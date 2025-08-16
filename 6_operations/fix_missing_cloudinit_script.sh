#!/bin/bash
# Fix Missing Cloud-Init Custom Script Reference
# Usage: ./fix_missing_cloudinit_script.sh <VM_ID>
# Example: ./fix_missing_cloudinit_script.sh 108

# Check if VM ID is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <VM_ID>"
    echo "Example: $0 108"
    echo ""
    echo "This script fixes missing cloud-init custom script references."
    exit 1
fi

VM_ID="$1"

echo "=================================================="
echo " FIXING MISSING CLOUD-INIT SCRIPT FOR VM $VM_ID"
echo "=================================================="

# Check if VM exists
if ! qm status $VM_ID > /dev/null 2>&1; then
    echo "ERROR: VM $VM_ID does not exist or is not accessible."
    exit 1
fi

# Get VM configuration
echo "INFO: Checking VM configuration for custom script references..."
CICUSTOM_REF=$(qm config $VM_ID | grep "^cicustom:")

if [ -z "$CICUSTOM_REF" ]; then
    echo "INFO: No custom cloud-init script reference found."
    exit 0
fi

echo "Found custom script reference: $CICUSTOM_REF"

# Extract script name
SCRIPT_NAME=$(echo "$CICUSTOM_REF" | sed 's/.*user=local:snippets\///g' | cut -d, -f1)
if [ -z "$SCRIPT_NAME" ]; then
    echo "ERROR: Could not extract script name from cicustom reference."
    exit 1
fi

SCRIPT_PATH="/var/lib/vz/snippets/$SCRIPT_NAME"
echo "Script path: $SCRIPT_PATH"

# Check if script exists
if [ -f "$SCRIPT_PATH" ]; then
    echo "✅ Script file exists. No action needed."
    exit 0
fi

echo "❌ Script file does not exist!"
echo ""
echo "You have two options:"
echo "1. Remove the custom script reference (recommended for quick fix)"
echo "2. Create a basic cloud-init script"
echo ""

read -p "Choose option (1 or 2): " -n 1 -r
echo

case $REPLY in
    1)
        echo "INFO: Removing custom script reference..."
        
        # Check if VM is running
        VM_STATUS=$(qm status $VM_ID | awk '{print $2}')
        if [ "$VM_STATUS" = "running" ]; then
            echo "WARNING: VM $VM_ID is currently running."
            read -p "Do you want to stop the VM to modify configuration? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "INFO: Stopping VM $VM_ID..."
                qm stop $VM_ID
                sleep 5
            else
                echo "ERROR: Cannot modify VM configuration while it's running."
                exit 1
            fi
        fi
        
        qm set $VM_ID --delete cicustom
        if [ $? -eq 0 ]; then
            echo "✅ Custom script reference removed successfully."
            echo "INFO: You can now use standard cloud-init configuration via Proxmox UI."
        else
            echo "❌ Failed to remove custom script reference."
            exit 1
        fi
        ;;
    2)
        echo "INFO: Creating basic cloud-init script..."
        
        # Ensure snippets directory exists
        mkdir -p /var/lib/vz/snippets
        
        # Create a basic cloud-init script
        cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash
# Basic Cloud-Init script generated automatically
# This script was created to replace a missing custom script reference

export DEBIAN_FRONTEND=noninteractive

echo "--- Starting Basic Cloud-Init Script ---"

# Update package lists
echo "INFO: Updating package lists..."
apt-get update -y

# Install basic packages
echo "INFO: Installing basic packages..."
apt-get install -y curl wget vim nano

# Ensure SSH service is running
echo "INFO: Ensuring SSH service is running..."
systemctl enable --now ssh

echo "--- Basic Cloud-Init Script Finished ---"
EOF

        chmod +x "$SCRIPT_PATH"
        echo "✅ Basic cloud-init script created at $SCRIPT_PATH"
        echo "INFO: You can edit this script to customize VM initialization."
        ;;
    *)
        echo "Invalid option. Exiting."
        exit 1
        ;;
esac

echo ""
echo "NEXT STEPS:"
echo "1. Try creating the cloud-init drive again"
echo "2. Check the Hardware tab in Proxmox UI"
echo "3. Go to Cloud-Init tab to configure settings"
echo "==================================================" 