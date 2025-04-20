#!/bin/bash
# VM Provisioning Script for Proxmox
# Usage: ./provision_vm.sh <customer_name> <ip_address> [memory in MB] [cpu] [disk in GB]
# Memory defaults to 2048 MB (2 GB), CPU to 2 cores, DISK to 10 GB

# Check for mandatory parameters
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Error: Missing mandatory parameters"
  echo "Usage: ./provision_vm.sh <customer_name> <ip_address> [memory in MB] [cpu] [disk in GB]"
  exit 1
fi

CUSTOMER=$1
IP_ADDRESS=$2
# Set default values if parameters are not provided
MEMORY=${3:-2048}  # Default to 2 GB
CPU=${4:-2}        # Default to 2 cores
DISK=${5:-10}      # Default to 10 GB
DATA_DISK_SIZE=20  # Size of additional data disk in GB
TEMPLATE="debian-12-custom"
STORAGE="proxmox_data"
VM_NAME="customer-$CUSTOMER"

# Create VM
VM_ID=$(pvesh get /cluster/nextid)
echo "Creating VM with ID $VM_ID"

# Stop the VM if it is already running (this will only be relevant for updates to existing VMs)
if qm status $VM_ID 2>/dev/null | grep -q "running"; then
  echo "Stopping VM $VM_ID"
  qm stop $VM_ID
fi

# Specific Debian image URL
DEBIAN_IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/20250416-2084/debian-12-generic-amd64-20250416-2084.qcow2"
IMAGE_NAME="debian-12-generic-amd64-20250416-2084.qcow2"
DOWNLOAD_PATH="/tmp/${IMAGE_NAME}"

# Download the specific Debian cloud image if not already present
if [ ! -f "${DOWNLOAD_PATH}" ]; then
  echo "Downloading Debian cloud image..."
  wget -O "${DOWNLOAD_PATH}" "${DEBIAN_IMAGE_URL}"
fi

# Create VM
qm create $VM_ID --name "customer-$CUSTOMER" --memory $MEMORY --cores $CPU --net0 virtio,bridge=vmbr0

# Import disk from the custom image
echo "Importing disk $IMAGE_NAME from the custom image"
qm importdisk $VM_ID "${DOWNLOAD_PATH}" "${STORAGE}"

# Configure disk and boot
# scsi0 will be mapped to /dev/sda inside the VM
qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 "${STORAGE}:vm-$VM_ID-disk-0"
qm set $VM_ID --boot c --bootdisk scsi0

# Resize the system disk to the requested size
echo "Resizing system disk to ${DISK}GB"
qm resize $VM_ID scsi0 ${DISK}G

# Create and add an additional data disk
# scsi1 will be mapped to /dev/sdb inside the VM
echo "Creating additional data disk of ${DATA_DISK_SIZE}GB"
qm disk create $VM_ID --disk scsi1 --storage "${STORAGE}" --size ${DATA_DISK_SIZE}G

# Ensure the secondary disk is attached properly
echo "Ensuring secondary disk is properly attached"
# Display disk configuration for debugging
qm config $VM_ID | grep -E "scsi[0-9]+"

# Set cloud-init
qm set $VM_ID --citype nocloud
qm set $VM_ID --ipconfig0 "ip=$IP_ADDRESS/24,gw=192.168.1.1"
qm set $VM_ID --ciuser admin
qm set $VM_ID --cipassword "initial-password"
qm set $VM_ID --sshkeys /root/.ssh/id_rsa.pub

# Create cloud-init customization script with improved disk detection
mkdir -p /var/lib/vz/snippets
cat > /var/lib/vz/snippets/custom-$CUSTOMER.sh << 'EOF'
#!/bin/bash
apt-get update && apt-get upgrade -y
apt-get install -y docker.io supervisor emacs vim nano curl wget
systemctl enable --now docker
echo 'AllowUsers root@192.168.1.0/24' >> /etc/ssh/sshd_config
systemctl restart sshd
timedatectl set-timezone Europe/Zurich

# Setup additional data disk - look for all additional disks
echo "Setting up additional data disks"
# First check for standard device path
if [ -e /dev/sdb ]; then
  DATA_DISK="/dev/sdb"
  echo "Found data disk at /dev/sdb"
# If not found, try to detect from available disks
elif [ -e /dev/vdb ]; then
  DATA_DISK="/dev/vdb"
  echo "Found data disk at /dev/vdb"
else
  # List all block devices for troubleshooting
  echo "Available block devices:"
  lsblk
  # Try to find a disk that's not the boot disk
  DATA_DISK=$(lsblk -dpno NAME | grep -v "$(findmnt -n -o SOURCE /)" | head -1)
  if [ -n "$DATA_DISK" ]; then
    echo "Using detected data disk: $DATA_DISK"
  else
    echo "No secondary disk found"
    exit 0
  fi
fi

# If we found a disk to use, format and mount it
if [ -n "$DATA_DISK" ]; then
  echo "Setting up data disk $DATA_DISK"
  parted $DATA_DISK mklabel gpt
  parted $DATA_DISK mkpart primary 0% 100%
  PART="${DATA_DISK}1"
  mkfs.ext4 $PART
  mkdir -p /data
  echo "$PART /data ext4 defaults 0 0" >> /etc/fstab
  mount /data
  chmod 777 /data
  echo "Data disk setup complete"
fi
EOF

qm set $VM_ID --cicustom "user=local:snippets/custom-$CUSTOMER.sh"

# Start VM
qm start $VM_ID

echo "VM customer-$CUSTOMER created with ID $VM_ID and IP $IP_ADDRESS"
echo "Waiting for VM to boot and apply cloud-init configuration..."
sleep 30
echo "VM should be configuring the additional disk now"

# Optional: Clean up the download if desired
# rm -f "${DOWNLOAD_PATH}" 