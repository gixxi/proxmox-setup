#!/bin/bash
# Network Diagnostics Script for Proxmox and VMs
# This script helps diagnose DNS and internet connectivity issues

echo "=================================================="
echo " NETWORK DIAGNOSTICS FOR PROXMOX AND VMs"
echo "=================================================="

# Function to test DNS resolution
test_dns() {
    local hostname=$1
    echo "Testing DNS resolution for: $hostname"
    
    # Test with nslookup
    echo "nslookup $hostname:"
    nslookup $hostname 2>/dev/null || echo "nslookup failed"
    
    # Test with dig
    echo "dig $hostname:"
    dig $hostname +short 2>/dev/null || echo "dig failed"
    
    # Test with getent
    echo "getent hosts $hostname:"
    getent hosts $hostname 2>/dev/null || echo "getent failed"
    
    echo "---"
}

# Function to test internet connectivity
test_connectivity() {
    local target=$1
    local description=$2
    echo "Testing connectivity to $description ($target):"
    
    # Test ping
    echo "ping -c 3 $target:"
    ping -c 3 $target 2>/dev/null || echo "ping failed"
    
    # Test HTTP connectivity
    if [[ $target == *"http"* ]]; then
        echo "curl -I $target (timeout 10s):"
        curl -I --connect-timeout 10 $target 2>/dev/null || echo "curl failed"
    fi
    
    echo "---"
}

# Function to show network configuration
show_network_config() {
    local interface=$1
    echo "Network configuration for $interface:"
    
    # Show IP configuration
    echo "IP configuration:"
    ip addr show $interface 2>/dev/null || echo "Interface $interface not found"
    
    # Show routing
    echo "Routing table:"
    ip route show 2>/dev/null || echo "Failed to show routing"
    
    # Show DNS configuration
    echo "DNS configuration (/etc/resolv.conf):"
    cat /etc/resolv.conf 2>/dev/null || echo "Failed to read resolv.conf"
    
    # Show systemd-resolved status if available
    if command -v systemd-resolve >/dev/null 2>&1; then
        echo "systemd-resolved status:"
        systemd-resolve --status 2>/dev/null || echo "systemd-resolve failed"
    fi
    
    echo "---"
}

echo "1. PROXMOX HOST NETWORK DIAGNOSTICS"
echo "=================================="

# Show Proxmox host network interfaces
echo "Available network interfaces:"
ip link show | grep -E "^[0-9]+:" | awk '{print $2}' | sed 's/://'

echo ""
echo "Proxmox bridge configuration:"
echo "vmbr0 configuration:"
ip addr show vmbr0 2>/dev/null || echo "vmbr0 not found"

echo ""
echo "Proxmox host DNS configuration:"
cat /etc/resolv.conf 2>/dev/null || echo "Failed to read resolv.conf"

echo ""
echo "Testing Proxmox host internet connectivity:"
test_connectivity "8.8.8.8" "Google DNS"
test_connectivity "1.1.1.1" "Cloudflare DNS"
test_connectivity "https://www.google.com" "Google HTTPS"

echo ""
echo "Testing Proxmox host DNS resolution:"
test_dns "www.google.com"
test_dns "www.debian.org"
test_dns "cloud.debian.org"

echo ""
echo "2. PROXMOX NETWORK BRIDGE DIAGNOSTICS"
echo "===================================="

# Check if vmbr0 exists and show its configuration
if ip link show vmbr0 >/dev/null 2>&1; then
    echo "vmbr0 bridge exists and is configured:"
    brctl show vmbr0 2>/dev/null || echo "brctl not available or vmbr0 not a bridge"
    
    echo ""
    echo "vmbr0 IP configuration:"
    ip addr show vmbr0
    
    echo ""
    echo "vmbr0 routing:"
    ip route show dev vmbr0 2>/dev/null || echo "No routes for vmbr0"
else
    echo "vmbr0 bridge does not exist!"
fi

echo ""
echo "3. VM NETWORK DIAGNOSTICS"
echo "========================="

# List running VMs
echo "Running VMs:"
qm list | grep running || echo "No running VMs found"

echo ""
echo "4. TROUBLESHOOTING COMMANDS"
echo "==========================="
echo "To test a specific VM's connectivity, SSH into it and run:"
echo ""
echo "  # Test DNS resolution"
echo "  nslookup google.com"
echo "  dig google.com"
echo ""
echo "  # Test internet connectivity"
echo "  ping -c 3 8.8.8.8"
echo "  curl -I https://www.google.com"
echo ""
echo "  # Check VM network configuration"
echo "  ip addr show"
echo "  ip route show"
echo "  cat /etc/resolv.conf"
echo ""
echo "  # Check if DNS servers are reachable"
echo "  ping -c 3 192.168.1.1  # Your gateway"
echo "  ping -c 3 8.8.8.8      # Google DNS"
echo "  ping -c 3 1.1.1.1      # Cloudflare DNS"
echo ""
echo "5. COMMON FIXES"
echo "==============="
echo "If VMs can't access internet:"
echo "1. Check if Proxmox host can access internet"
echo "2. Verify vmbr0 bridge configuration"
echo "3. Ensure VMs have correct DNS servers configured"
echo "4. Check Unifi router DNS settings"
echo "5. Verify firewall rules on Proxmox host"
echo ""
echo "To fix DNS in VMs, add to /etc/resolv.conf:"
echo "  nameserver 8.8.8.8"
echo "  nameserver 1.1.1.1"
echo "  nameserver 192.168.1.1  # Your router"
echo ""
echo "==================================================" 