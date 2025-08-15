#!/bin/bash

# Docker Container Memory and Swap Monitor
# Usage: ./monitor_container_memory.sh <container_name_or_id> [interval_seconds]

if [ $# -lt 1 ]; then
    echo "Usage: $0 <container_name_or_id> [interval_seconds]"
    echo "  container_name_or_id - Name or ID of the container to monitor"
    echo "  interval_seconds     - Refresh interval (default: 5 seconds)"
    exit 1
fi

CONTAINER=$1
INTERVAL=${2:-5}

# Function to convert bytes to human readable format
bytes_to_human() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then
        echo "${bytes}B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$(( bytes / 1024 ))KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$(( bytes / 1048576 ))MB"
    else
        echo "$(( bytes / 1073741824 ))GB"
    fi
}

# Function to get container memory stats
get_memory_stats() {
    local container=$1
    
    # Check if container exists and is running
    if ! docker ps --format "{{.Names}}" | grep -q "^${container}$" && \
       ! docker ps --format "{{.ID}}" | grep -q "^${container}"; then
        echo "ERROR: Container '${container}' not found or not running"
        return 1
    fi
    
    # Get container ID if name was provided
    local container_id=$(docker ps --format "{{.ID}} {{.Names}}" | grep "${container}" | awk '{print $1}' | head -n1)
    
    if [ -z "$container_id" ]; then
        container_id=$container
    fi
    
    echo "=== Container Memory Analysis: $container (ID: $container_id) ==="
    echo "Timestamp: $(date)"
    echo ""
    
    # Docker stats
    echo "--- Docker Stats ---"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" $container_id
    echo ""
    
    # Detailed memory breakdown from cgroup
    echo "--- Detailed Memory Stats (cgroup) ---"
    
    # Check for cgroup v2 first (newer systems)
    if docker exec $container_id test -f /sys/fs/cgroup/memory.stat 2>/dev/null; then
        echo "Using cgroup v2 format"
        
        # Get current memory and swap usage
        local current_memory=$(docker exec $container_id cat /sys/fs/cgroup/memory.current 2>/dev/null || echo "0")
        local current_swap=$(docker exec $container_id cat /sys/fs/cgroup/memory.swap.current 2>/dev/null || echo "0")
        local peak_memory=$(docker exec $container_id cat /sys/fs/cgroup/memory.peak 2>/dev/null || echo "0")
        
        # Get detailed memory breakdown
        local mem_stat=$(docker exec $container_id cat /sys/fs/cgroup/memory.stat 2>/dev/null)
        local anon=$(echo "$mem_stat" | grep "^anon " | awk '{print $2}' || echo "0")
        local file=$(echo "$mem_stat" | grep "^file " | awk '{print $2}' || echo "0")
        local kernel_stack=$(echo "$mem_stat" | grep "^kernel_stack " | awk '{print $2}' || echo "0")
        local slab=$(echo "$mem_stat" | grep "^slab " | awk '{print $2}' || echo "0")
        
        echo "Current Memory:   $(bytes_to_human ${current_memory:-0})"
        echo "Peak Memory:      $(bytes_to_human ${peak_memory:-0})"
        echo "Anonymous Pages:  $(bytes_to_human ${anon:-0})"
        echo "File Cache:       $(bytes_to_human ${file:-0})"
        echo "Kernel Stack:     $(bytes_to_human ${kernel_stack:-0})"
        echo "Slab Memory:      $(bytes_to_human ${slab:-0})"
        echo "Current Swap:     $(bytes_to_human ${current_swap:-0})"
        
        # Highlight swap usage
        if [ "${current_swap:-0}" -gt 0 ]; then
            echo ""
            echo "⚠️  SWAP DETECTED: Container is using $(bytes_to_human $current_swap) of swap memory"
        else
            echo ""
            echo "✅ No swap usage detected"
        fi
        
    # Fall back to cgroup v1 (older systems)
    elif docker exec $container_id test -f /sys/fs/cgroup/memory/memory.stat 2>/dev/null; then
        echo "Using cgroup v1 format"
        local mem_stat=$(docker exec $container_id cat /sys/fs/cgroup/memory/memory.stat 2>/dev/null)
        
        # Extract key metrics
        local cache=$(echo "$mem_stat" | grep "^cache " | awk '{print $2}')
        local rss=$(echo "$mem_stat" | grep "^rss " | awk '{print $2}')
        local swap=$(echo "$mem_stat" | grep "^swap " | awk '{print $2}')
        local total_cache=$(echo "$mem_stat" | grep "^total_cache " | awk '{print $2}')
        local total_rss=$(echo "$mem_stat" | grep "^total_rss " | awk '{print $2}')
        local total_swap=$(echo "$mem_stat" | grep "^total_swap " | awk '{print $2}')
        
        echo "Cache Memory:     $(bytes_to_human ${cache:-0})"
        echo "RSS (Real RAM):   $(bytes_to_human ${rss:-0})"
        echo "Swap Usage:       $(bytes_to_human ${swap:-0})"
        echo "Total Cache:      $(bytes_to_human ${total_cache:-0})"
        echo "Total RSS:        $(bytes_to_human ${total_rss:-0})"
        echo "Total Swap:       $(bytes_to_human ${total_swap:-0})"
        
        # Calculate total memory usage
        local total_mem=$((${total_rss:-0} + ${total_cache:-0}))
        echo "Total Memory:     $(bytes_to_human $total_mem)"
        
        # Highlight swap usage
        if [ "${total_swap:-0}" -gt 0 ]; then
            echo ""
            echo "⚠️  SWAP DETECTED: Container is using $(bytes_to_human $total_swap) of swap memory"
        else
            echo ""
            echo "✅ No swap usage detected"
        fi
    else
        echo "Cannot access cgroup memory stats - unknown cgroup version or permissions issue"
    fi
    
    echo ""
    
    # Memory limits
    echo "--- Memory Limits ---"
    local limit=$(docker inspect $container_id --format='{{.HostConfig.Memory}}' 2>/dev/null)
    local swap_limit=$(docker inspect $container_id --format='{{.HostConfig.MemorySwap}}' 2>/dev/null)
    
    if [ "$limit" != "0" ] && [ -n "$limit" ]; then
        echo "Memory Limit:     $(bytes_to_human $limit)"
    else
        echo "Memory Limit:     No limit set"
    fi
    
    if [ "$swap_limit" != "0" ] && [ -n "$swap_limit" ]; then
        if [ "$swap_limit" = "-1" ]; then
            echo "Swap Limit:       Unlimited"
        else
            echo "Swap Limit:       $(bytes_to_human $swap_limit)"
        fi
    else
        echo "Swap Limit:       Same as memory limit (no additional swap)"
    fi
}

# Function for continuous monitoring
monitor_continuous() {
    while true; do
        clear
        get_memory_stats "$CONTAINER"
        echo ""
        echo "--- Host System Memory ---"
        free -h
        echo ""
        echo "Refreshing every ${INTERVAL} seconds... (Press Ctrl+C to stop)"
        sleep $INTERVAL
    done
}

# Main execution
echo "Starting memory monitoring for container: $CONTAINER"
echo "Refresh interval: ${INTERVAL} seconds"
echo ""

if [ "$INTERVAL" = "0" ]; then
    # Single run
    get_memory_stats "$CONTAINER"
else
    # Continuous monitoring
    monitor_continuous
fi 