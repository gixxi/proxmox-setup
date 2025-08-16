#!/bin/bash
# Fix Cloud-Init Drive Configuration After VM Backup Restoration
# Usage: ./fix_cloudinit_drive.sh <VM_ID> [storage_id]
# Example: ./fix_cloudinit_drive.sh 108 proxmox_data

# Check if VM ID is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <VM_ID> [storage_id]"
    echo "Example: $0 108 proxmox_data"
    echo ""
    echo "This script fixes cloud-init drive configuration after VM backup restoration."
    echo "It detaches the cloud-init drive from the wrong IDE interface and reattaches it to ide2."
    exit 1
fi

VM_ID="$1"
STORAGE="${2:-proxmox_data}"  # Default storage if not provided

echo "=================================================="
echo " FIXING CLOUD-INIT DRIVE FOR VM $VM_ID"
echo "=================================================="

# Check if VM exists
if ! qm status $VM_ID > /dev/null 2>&1; then
    echo "ERROR: VM $VM_ID does not exist or is not accessible."
    exit 1
fi

# Get VM configuration
echo "INFO: Getting current VM configuration..."
VM_CONFIG=$(qm config $VM_ID)

echo "Current VM configuration:"
echo "$VM_CONFIG" | grep -E "^(ide|scsi|sata)[0-9]:"

# Check current cloud-init drive location
CLOUDINIT_ON_IDE1=$(echo "$VM_CONFIG" | grep "^ide1:" | grep -c "cloudinit")
CLOUDINIT_ON_IDE2=$(echo "$VM_CONFIG" | grep "^ide2:" | grep -c "cloudinit")

echo ""
echo "Cloud-init drive detection:"
echo "  On ide1: $CLOUDINIT_ON_IDE1"
echo "  On ide2: $CLOUDINIT_ON_IDE2"

if [ "$CLOUDINIT_ON_IDE2" -eq 1 ]; then
    echo "INFO: Cloud-init drive is already correctly attached to ide2."
    echo "INFO: If Proxmox UI still shows 'No CloudInit Drive found', try:"
    echo "  1. Stop the VM if running"
    echo "  2. Refresh the browser"
    echo "  3. Check Hardware tab in VM configuration"
    exit 0
fi

if [ "$CLOUDINIT_ON_IDE1" -eq 1 ]; then
    echo "INFO: Found cloud-init drive on ide1. Moving to ide2..."
    
    # Check if VM is running
    VM_STATUS=$(qm status $VM_ID | awk '{print $2}')
    if [ "$VM_STATUS" = "running" ]; then
        echo "WARNING: VM $VM_ID is currently running."
        read -p "Do you want to stop the VM to fix the cloud-init drive? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "INFO: Stopping VM $VM_ID..."
            qm stop $VM_ID
            # Wait for VM to stop
            sleep 5
        else
            echo "ERROR: Cannot modify VM configuration while it's running."
            exit 1
        fi
    fi
    
    # Remove cloud-init drive from ide1
    echo "INFO: Removing cloud-init drive from ide1..."
    qm set $VM_ID --delete ide1
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to remove cloud-init drive from ide1."
        exit 1
    fi
    
    # Add cloud-init drive to ide2
    echo "INFO: Adding cloud-init drive to ide2..."
    qm set $VM_ID --ide2 ${STORAGE}:cloudinit
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to add cloud-init drive to ide2."
        echo "INFO: Attempting to restore cloud-init drive to ide1..."
        qm set $VM_ID --ide1 ${STORAGE}:cloudinit
        exit 1
    fi
    
    echo "SUCCESS: Cloud-init drive moved from ide1 to ide2."
    
elif [ "$CLOUDINIT_ON_IDE1" -eq 0 ] && [ "$CLOUDINIT_ON_IDE2" -eq 0 ]; then
    echo "INFO: No cloud-init drive found. Creating new one on ide2..."
    
    # Check if VM is running
    VM_STATUS=$(qm status $VM_ID | awk '{print $2}')
    if [ "$VM_STATUS" = "running" ]; then
        echo "WARNING: VM $VM_ID is currently running."
        read -p "Do you want to stop the VM to add the cloud-init drive? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "INFO: Stopping VM $VM_ID..."
            qm stop $VM_ID
            # Wait for VM to stop
            sleep 5
        else
            echo "ERROR: Cannot modify VM configuration while it's running."
            exit 1
        fi
    fi
    
    # Create cloud-init drive on ide2
    qm set $VM_ID --ide2 ${STORAGE}:cloudinit
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create cloud-init drive on ide2."
        exit 1
    fi
    
    echo "SUCCESS: Cloud-init drive created on ide2."
fi

# Verify the fix
echo ""
echo "INFO: Verifying cloud-init drive configuration..."
UPDATED_CONFIG=$(qm config $VM_ID)
echo "Updated VM configuration:"
echo "$UPDATED_CONFIG" | grep -E "^(ide|scsi|sata)[0-9]:"

CLOUDINIT_ON_IDE2_AFTER=$(echo "$UPDATED_CONFIG" | grep "^ide2:" | grep -c "cloudinit")
if [ "$CLOUDINIT_ON_IDE2_AFTER" -eq 1 ]; then
    echo ""
    echo "SUCCESS: Cloud-init drive is now properly configured on ide2."
    echo ""
    echo "NEXT STEPS:"
    echo "1. Refresh your Proxmox web interface"
    echo "2. Go to VM $VM_ID > Hardware tab"
    echo "3. You should now see 'CloudInit Drive (ide2)' listed"
    echo "4. Go to VM $VM_ID > Cloud-Init tab to configure settings"
    echo "5. Start the VM when ready"
else
    echo "ERROR: Cloud-init drive configuration verification failed."
    exit 1
fi

echo "==================================================" 