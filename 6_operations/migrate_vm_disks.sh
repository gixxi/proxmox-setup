#!/bin/bash

# Check if the correct number of arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <vm_id> <target_storage>"
    exit 1
fi

vm_id=$1
target_storage=$2

# Function to check if VM exists
check_vm_exists() {
    if ! qm config "$vm_id" >/dev/null 2>&1; then
        echo "Error: VM with ID $vm_id does not exist"
        exit 1
    fi
}

# Function to check if target storage exists
check_storage_exists() {
    if ! pvesm status --storage "$target_storage" >/dev/null 2>&1; then
        echo "Error: Target storage '$target_storage' does not exist or is not accessible"
        exit 1
    fi
}

# Function to extract disk information from VM config
get_disk_info() {
    local config_output
    config_output=$(qm config "$vm_id")
    
    # Extract disk lines (scsi*, ide*, virtio*, sata*)
    echo "$config_output" | grep -E '^(scsi|ide|virtio|sata)[0-9]+:' | while read -r line; do
        local disk_id=$(echo "$line" | cut -d: -f1)
        local disk_info=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//')
        
        # Extract storage and filename from disk info
        local storage=$(echo "$disk_info" | cut -d: -f1)
        local filename=$(echo "$disk_info" | cut -d: -f2 | cut -d, -f1)
        local size=$(echo "$disk_info" | grep -o 'size=[0-9]*[A-Z]*' | cut -d= -f2)
        
        echo "$disk_id|$storage|$filename|$size"
    done
}

# Function to migrate disk
migrate_disk() {
    local disk_id=$1
    local current_storage=$2
    local filename=$3
    
    echo "Migrating $disk_id from $current_storage to $target_storage..."
    
    if qm move disk "$vm_id" "$disk_id" "$target_storage" --delete 1; then
        echo "Successfully migrated $disk_id to $target_storage"
    else
        echo "Error: Failed to migrate $disk_id"
        return 1
    fi
}

# Main script execution
echo "VM Disk Migration Tool"
echo "======================"

# Check if VM exists
check_vm_exists

# Check if target storage exists
check_storage_exists

echo "VM ID: $vm_id"
echo "Target Storage: $target_storage"
echo ""

# Get disk information
echo "Found disks in VM configuration:"
echo "--------------------------------"

disks_found=false
while IFS='|' read -r disk_id storage filename size; do
    if [ -n "$disk_id" ]; then
        disks_found=true
        echo "  $disk_id: $storage:$filename (${size:-unknown size})"
    fi
done < <(get_disk_info)

if [ "$disks_found" = false ]; then
    echo "No disks found in VM configuration"
    exit 0
fi

echo ""
echo "This will migrate ALL disks from their current storage to '$target_storage'"
echo "The VM will be suspended during migration if it's running."
echo ""

# Ask for confirmation
read -p "Do you want to proceed with the migration? (y/N): " -r confirm
echo

if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "Migration cancelled."
    exit 0
fi

# Suspend VM if running
vm_status=$(qm status "$vm_id" 2>/dev/null | grep -o 'status:.*' | cut -d: -f2 | tr -d ' ')
if [ "$vm_status" = "running" ]; then
    echo "Suspending VM $vm_id..."
    qm suspend "$vm_id"
    echo "Waiting for VM to suspend..."
    while [ "$(qm status "$vm_id" 2>/dev/null | grep -o 'status:.*' | cut -d: -f2 | tr -d ' ')" = "running" ]; do
        sleep 1
    done
fi

# Migrate all disks
echo ""
echo "Starting disk migration..."
echo "-------------------------"

migration_success=true
while IFS='|' read -r disk_id storage filename size; do
    if [ -n "$disk_id" ]; then
        if ! migrate_disk "$disk_id" "$storage" "$filename"; then
            migration_success=false
        fi
        echo ""
    fi
done < <(get_disk_info)

if [ "$migration_success" = true ]; then
    echo "All disks migrated successfully!"
    echo "You can now resume the VM with: qm resume $vm_id"
else
    echo "Some disks failed to migrate. Please check the errors above."
    exit 1
fi

