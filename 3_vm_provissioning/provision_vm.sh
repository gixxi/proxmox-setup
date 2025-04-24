#!/bin/bash
# VM Provisioning Script for Proxmox
# Usage: ./provision_vm.sh <customer_name> <ip_address> <ci_user> <ci_password> [memory in MB] [cpu] [disk in GB]
# Memory defaults to 2048 MB (2 GB), CPU to 2 cores, System Disk (DISK) to 10 GB.
# Creates only the primary system disk.

# --- Configuration ---
CUSTOMER=$1
IP_ADDRESS=$2
CI_USER=$3               # Cloud-init user (Mandatory)
CI_PASSWORD=$4           # Cloud-init password (Mandatory)
# Set default values for optional parameters
MEMORY=${5:-2048}         # Default system memory to 2 GB
CPU=${6:-2}               # Default CPU cores to 2
DISK=${7:-10}             # Default system disk size to 10 GB
# DATA_DISK_SIZE=20       # Removed - No additional data disk
STORAGE="proxmox_data"    # Proxmox storage ID
BRIDGE="vmbr0"            # Proxmox network bridge
GATEWAY="192.168.1.1"     # Network gateway
SSH_PUB_KEY_PATH="/root/.ssh/id_rsa.pub" # Path to SSH public key for cloud-init
TIMEZONE="Europe/Zurich"  # Timezone for the VM

# Specific Debian image URL and name
DEBIAN_IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/20250416-2084/debian-12-generic-amd64-20250416-2084.qcow2"
IMAGE_NAME="debian-12-generic-amd64-20250416-2084.qcow2"
DOWNLOAD_PATH="/tmp/${IMAGE_NAME}" # Local path to download the image

# --- Parameter Validation ---
if [ -z "$CUSTOMER" ] || [ -z "$IP_ADDRESS" ] || [ -z "$CI_USER" ] || [ -z "$CI_PASSWORD" ]; then
  echo "Error: Missing mandatory parameters"
  echo "Usage: $0 <customer_name> <ip_address> <ci_user> <ci_password> [memory in MB] [cpu] [disk in GB]"
  exit 1
fi

if ! [[ "$IP_ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Invalid IP address format: $IP_ADDRESS"
  exit 1
fi

if [ ! -f "$SSH_PUB_KEY_PATH" ]; then
    echo "Error: SSH public key not found at $SSH_PUB_KEY_PATH"
    exit 1
fi

VM_NAME="customer-$CUSTOMER"
SNIPPET_DIR="/var/lib/vz/snippets"
CUSTOM_SCRIPT_NAME="custom-$CUSTOMER.sh"
CUSTOM_SCRIPT_PATH="$SNIPPET_DIR/$CUSTOM_SCRIPT_NAME"

# --- Main Script ---

# 1. Get Next Available VM ID
echo "INFO: Getting next available VM ID..."
VM_ID=$(pvesh get /cluster/nextid)
if [ -z "$VM_ID" ]; then
    echo "ERROR: Could not get next VM ID from Proxmox."
    exit 1
fi
echo "INFO: Next available VM ID is $VM_ID."

# Check if VM already exists (optional, uncomment to prevent overwriting)
# if qm status $VM_ID > /dev/null 2>&1; then
#     echo "ERROR: VM ID $VM_ID already exists. Please choose a different ID or delete the existing VM."
#     exit 1
# fi

# 2. Download Debian Cloud Image if necessary
echo "INFO: Checking for Debian cloud image..."
if [ ! -f "${DOWNLOAD_PATH}" ]; then
  echo "INFO: Downloading Debian cloud image to ${DOWNLOAD_PATH}..."
  wget -q --show-progress -O "${DOWNLOAD_PATH}" "${DEBIAN_IMAGE_URL}"
  if [ $? -ne 0 ]; then
      echo "ERROR: Failed to download Debian image."
      exit 1
  fi
  echo "INFO: Download complete."
else
  echo "INFO: Debian cloud image already exists locally."
fi

# 3. Create the VM
echo "INFO: Creating VM $VM_ID (Name: $VM_NAME)..."
qm create $VM_ID --name "$VM_NAME" --memory $MEMORY --cores $CPU --net0 virtio,bridge=$BRIDGE
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create VM $VM_ID."
    # Optional: Clean up downloaded image if creation fails
    # rm -f "${DOWNLOAD_PATH}"
    exit 1
fi
echo "INFO: VM $VM_ID created."

# 4. Import the downloaded disk image to the VM's storage
echo "INFO: Importing disk image ${IMAGE_NAME} to storage '${STORAGE}' for VM $VM_ID..."
qm importdisk $VM_ID "${DOWNLOAD_PATH}" "${STORAGE}"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to import disk for VM $VM_ID."
    qm destroy $VM_ID --destroy-unreferenced-disks 1 --purge 1 # Clean up VM
    # rm -f "${DOWNLOAD_PATH}"
    exit 1
fi
# Note: importdisk creates a disk named 'vm-<VMID>-disk-<INDEX>' (e.g., vm-108-disk-0)
# The actual filename might include an extension like .raw or .qcow2 depending on storage/import options.
# We'll assume .raw based on common import behavior and your example. Adjust if needed.
IMPORTED_DISK_FILENAME="vm-${VM_ID}-disk-0.raw"
echo "INFO: Disk image imported. Assuming filename ${IMPORTED_DISK_FILENAME} in VM directory."

# 5. Attach the imported disk as the boot disk (scsi0 -> /dev/sda)
# Use the format that includes the VM ID subdirectory, matching your working example.
DISK_PATH_FOR_SET="${STORAGE}:${VM_ID}/${IMPORTED_DISK_FILENAME}"
echo "INFO: Attaching imported disk using path ${DISK_PATH_FOR_SET} as scsi0..."
# Using -scsi0 syntax as per your example, though --scsi0 should also work.
qm set $VM_ID --scsihw virtio-scsi-pci -scsi0 "${DISK_PATH_FOR_SET}"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to attach boot disk scsi0 for VM $VM_ID using path ${DISK_PATH_FOR_SET}."
    # Attempting fallback without extension, just in case
    DISK_PATH_FOR_SET_NOEXT="${STORAGE}:${VM_ID}/vm-${VM_ID}-disk-0"
    echo "INFO: Retrying attachment without .raw extension: ${DISK_PATH_FOR_SET_NOEXT}"
    qm set $VM_ID --scsihw virtio-scsi-pci -scsi0 "${DISK_PATH_FOR_SET_NOEXT}"
    if [ $? -ne 0 ]; then
        echo "ERROR: Fallback attachment also failed."
        qm destroy $VM_ID --destroy-unreferenced-disks 1 --purge 1 # Clean up VM
        # rm -f "${DOWNLOAD_PATH}"
        exit 1
    fi
fi

# 6. Set the boot order
echo "INFO: Setting boot disk to scsi0..."
qm set $VM_ID --boot c --bootdisk scsi0
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to set boot disk for VM $VM_ID."
    qm destroy $VM_ID --destroy-unreferenced-disks 1 --purge 1 # Clean up VM
    # rm -f "${DOWNLOAD_PATH}"
    exit 1
fi

# 7. Resize the boot disk
echo "INFO: Resizing system disk (scsi0) to ${DISK}G..."
qm resize $VM_ID scsi0 ${DISK}G
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to resize system disk scsi0 for VM $VM_ID."
    # Note: VM and disk still exist, resizing failed but might be recoverable or ignorable
fi

# 8. Create and attach the additional data disk (scsi1 -> /dev/sdb) - REMOVED
# echo "INFO: Creating and attaching additional data disk (scsi1) of ${DATA_DISK_SIZE}G..."
# qm set $VM_ID --scsi1 ${STORAGE}:${DATA_DISK_SIZE},format=raw
# if [ $? -ne 0 ]; then
#     echo "ERROR: Failed to create/attach data disk scsi1 for VM $VM_ID."
#     # Note: VM and boot disk still exist
# fi

# 9. Create and attach the cloud-init drive
echo "INFO: Creating and attaching cloud-init drive..."
qm set $VM_ID --ide2 ${STORAGE}:cloudinit
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to attach cloud-init drive for VM $VM_ID."
    qm destroy $VM_ID --destroy-unreferenced-disks 1 --purge 1 # Clean up VM
    # rm -f "${DOWNLOAD_PATH}"
    exit 1
else
    echo "INFO: Successfully attached cloud-init drive."
fi

# 10. Configure Cloud-Init
echo "INFO: Configuring Cloud-Init..."
qm set $VM_ID --citype nocloud
qm set $VM_ID --ipconfig0 "ip=${IP_ADDRESS}/24,gw=${GATEWAY}"
qm set $VM_ID --ciuser "${CI_USER}"
qm set $VM_ID --cipassword "${CI_PASSWORD}"
qm set $VM_ID --sshkeys "${SSH_PUB_KEY_PATH}"
# Add serial console for easier debugging if needed
qm set $VM_ID --serial0 socket --vga serial0

# 11. Create Cloud-Init User Data Script
echo "INFO: Creating Cloud-Init user data script at ${CUSTOM_SCRIPT_PATH}..."
mkdir -p "$SNIPPET_DIR"
cat > "${CUSTOM_SCRIPT_PATH}" << EOF
#!/bin/bash
# Cloud-Init User Data Script for ${VM_NAME} (VM ID: ${VM_ID})

export DEBIAN_FRONTEND=noninteractive

echo "--- Starting Cloud-Init User Data Script ---"

# Basic System Setup
echo "INFO: Updating package lists and upgrading packages..."
apt-get update -y && apt-get upgrade -y
if [ \$? -ne 0 ]; then echo "WARNING: apt update/upgrade failed."; fi

echo "INFO: Installing base packages..."
apt-get install -y docker.io supervisor emacs vim nano curl wget parted gdisk
if [ \$? -ne 0 ]; then echo "WARNING: apt install failed."; fi

echo "INFO: Enabling and starting Docker service..."
systemctl enable --now docker
if [ \$? -ne 0 ]; then echo "WARNING: Failed to enable/start docker."; fi

# Configure SSH settings
echo "INFO: Configuring SSH authentication settings..."
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
# Configure SSH to only allow connections from 192.168.1.0/24
echo "INFO: Restricting SSH access to 192.168.1.0/24..."
echo "sshd: 192.168.1.0/24" > /etc/hosts.allow
echo "sshd: ALL" > /etc/hosts.deny

# Restart SSH service to apply changes
systemctl restart sshd
if [ $? -ne 0 ]; then echo "WARNING: Failed to restart sshd service"; fi

# Timezone
echo "INFO: Setting timezone to ${TIMEZONE}..."
timedatectl set-timezone ${TIMEZONE}

# Setup additional data disk (scsi1 -> /dev/sdb or similar) - REMOVED
# echo "INFO: Setting up additional data disk..."
# ... (all the disk detection, formatting, mounting logic removed) ...

echo "--- Cloud-Init User Data Script Finished ---"
EOF

# 12. Attach the Cloud-Init Script to the VM
echo "INFO: Attaching Cloud-Init script ${CUSTOM_SCRIPT_NAME} to VM $VM_ID..."
# Use 'local' storage ID for snippets
qm set $VM_ID --cicustom "user=local:snippets/${CUSTOM_SCRIPT_NAME}"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to attach cloud-init script for VM $VM_ID."
    # Consider cleanup
    exit 1
fi

# 13. Start the VM
echo "INFO: Starting VM $VM_ID..."
qm start $VM_ID
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to start VM $VM_ID."
    exit 1
fi

# --- Completion ---
echo "=================================================="
echo " VM PROVISIONING COMPLETE"
echo "=================================================="
echo " VM ID:        $VM_ID"
echo " Name:         $VM_NAME"
echo " Customer:     $CUSTOMER"
echo " IP Address:   $IP_ADDRESS"
echo " Memory:       $MEMORY MB"
echo " CPU Cores:    $CPU"
echo " System Disk:  ${DISK}G (scsi0)"
# echo " Data Disk:    ${DATA_DISK_SIZE}G (scsi1)" # Removed
echo " SSH User:     $CI_USER (Password: $CI_PASSWORD)"
echo " SSH PubKey:   $SSH_PUB_KEY_PATH"
echo "=================================================="
echo "INFO: Waiting a bit for VM to boot and apply cloud-init..."
sleep 45 # Adjust as needed
echo "INFO: VM should now be accessible at ssh ${CI_USER}@${IP_ADDRESS}"
echo "INFO: Check cloud-init logs in /var/log/cloud-init-output.log inside the VM for details."

# Optional: Clean up the downloaded image if desired
# echo "INFO: Cleaning up downloaded image ${DOWNLOAD_PATH}..."
# rm -f "${DOWNLOAD_PATH}"

exit 0 