#!/bin/bash
# Diagnose VM Cloud-Init Configuration Issues
# Usage: ./diagnose_vm_cloudinit.sh <VM_ID>
# Example: ./diagnose_vm_cloudinit.sh 108

# Check if VM ID is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <VM_ID>"
    echo "Example: $0 108"
    echo ""
    echo "This script diagnoses cloud-init configuration issues for a VM."
    exit 1
fi

VM_ID="$1"

echo "=================================================="
echo " CLOUD-INIT DIAGNOSIS FOR VM $VM_ID"
echo "=================================================="

# Check if VM exists
if ! qm status $VM_ID > /dev/null 2>&1; then
    echo "ERROR: VM $VM_ID does not exist or is not accessible."
    exit 1
fi

# Get VM status
VM_STATUS=$(qm status $VM_ID)
echo "VM Status: $VM_STATUS"
echo ""

# Get full VM configuration
echo "=== FULL VM CONFIGURATION ==="
qm config $VM_ID
echo ""

# Focus on storage-related configuration
echo "=== STORAGE DEVICES ==="
qm config $VM_ID | grep -E "^(ide|scsi|sata|virtio)[0-9]:"
echo ""

# Check specifically for cloud-init drives
echo "=== CLOUD-INIT DRIVE ANALYSIS ==="
CLOUDINIT_DRIVES=$(qm config $VM_ID | grep "cloudinit")
if [ -z "$CLOUDINIT_DRIVES" ]; then
    echo "❌ No cloud-init drives found in VM configuration"
else
    echo "✅ Cloud-init drives found:"
    echo "$CLOUDINIT_DRIVES"
fi
echo ""

# Check each IDE interface
echo "=== IDE INTERFACE ANALYSIS ==="
for i in {0..3}; do
    IDE_CONFIG=$(qm config $VM_ID | grep "^ide${i}:")
    if [ -n "$IDE_CONFIG" ]; then
        echo "ide${i}: $IDE_CONFIG"
        if echo "$IDE_CONFIG" | grep -q "cloudinit"; then
            echo "  ↳ 🔍 This is a cloud-init drive"
            if [ "$i" -eq 2 ]; then
                echo "  ↳ ✅ Correctly positioned on ide2"
            else
                echo "  ↳ ⚠️  Incorrectly positioned (should be on ide2)"
            fi
        fi
    else
        echo "ide${i}: (not configured)"
    fi
done
echo ""

# Check cloud-init configuration
echo "=== CLOUD-INIT CONFIGURATION ==="
CI_CONFIG=$(qm config $VM_ID | grep -E "^(ciuser|cipassword|sshkeys|nameserver|searchdomain|citype|cicustom|ipconfig):")
if [ -z "$CI_CONFIG" ]; then
    echo "❌ No cloud-init configuration found"
else
    echo "✅ Cloud-init configuration found:"
    echo "$CI_CONFIG"
fi
echo ""

# Check for cloud-init custom scripts
echo "=== CLOUD-INIT CUSTOM SCRIPTS ==="
CICUSTOM=$(qm config $VM_ID | grep "^cicustom:")
if [ -n "$CICUSTOM" ]; then
    echo "Custom cloud-init script configuration:"
    echo "$CICUSTOM"
    
    # Extract script path and check if it exists
    SCRIPT_PATH=$(echo "$CICUSTOM" | sed 's/.*user=local:snippets\///g' | cut -d, -f1)
    if [ -n "$SCRIPT_PATH" ]; then
        FULL_SCRIPT_PATH="/var/lib/vz/snippets/$SCRIPT_PATH"
        echo ""
        echo "Checking script file: $FULL_SCRIPT_PATH"
        if [ -f "$FULL_SCRIPT_PATH" ]; then
            echo "✅ Script file exists"
            echo "  Size: $(stat -c%s "$FULL_SCRIPT_PATH") bytes"
            echo "  Modified: $(stat -c%y "$FULL_SCRIPT_PATH")"
        else
            echo "❌ Script file not found!"
        fi
    fi
else
    echo "No custom cloud-init scripts configured"
fi
echo ""

# Recommendations
echo "=== RECOMMENDATIONS ==="
CLOUDINIT_ON_IDE2=$(qm config $VM_ID | grep "^ide2:" | grep -c "cloudinit")
CLOUDINIT_ON_OTHER=$(qm config $VM_ID | grep -E "^ide[013]:" | grep -c "cloudinit")

if [ "$CLOUDINIT_ON_IDE2" -eq 1 ]; then
    echo "✅ Cloud-init drive is correctly attached to ide2"
    echo "   If Proxmox UI still shows 'No CloudInit Drive found':"
    echo "   1. Try refreshing the browser (Ctrl+F5)"
    echo "   2. Check the Hardware tab in VM configuration"
    echo "   3. Restart the Proxmox web service: systemctl restart pveproxy"
elif [ "$CLOUDINIT_ON_OTHER" -gt 0 ]; then
    echo "⚠️  Cloud-init drive found on wrong IDE interface"
    echo "   Run: ./fix_cloudinit_drive.sh $VM_ID"
    echo "   This will move the cloud-init drive to ide2"
else
    echo "❌ No cloud-init drive found"
    echo "   Run: ./fix_cloudinit_drive.sh $VM_ID"
    echo "   This will create a new cloud-init drive on ide2"
fi

echo ""
echo "=== ADDITIONAL CHECKS ==="
echo "Proxmox version:"
pveversion --verbose | head -1

echo ""
echo "Available storage pools:"
pvesm status | grep -E "(Type|cloudinit|snippets)"

echo "==================================================" 