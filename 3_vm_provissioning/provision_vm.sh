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
TEMPLATE="debian-12-custom"
STORAGE="proxmox_data"
VM_NAME="customer-$CUSTOMER"

# Specific Debian image URL
DEBIAN_IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/20250416-2084/debian-12-generic-amd64-20250416-2084.qcow2"
IMAGE_NAME="debian-12-generic-amd64-20250416-2084.qcow2"
DOWNLOAD_PATH="/tmp/${IMAGE_NAME}"

# Download the specific Debian cloud image if not already present
if [ ! -f "${DOWNLOAD_PATH}" ]; then
  echo "Downloading Debian cloud image..."
  wget -O "${DOWNLOAD_PATH}" "${DEBIAN_IMAGE_URL}"
fi

# Check if image exists in proxmox_data storage
if ! pvesm list proxmox_data | grep -q "${IMAGE_NAME}"; then
  echo "Importing image to proxmox_data storage..."
  # Upload the image to proxmox_data storage
  pvesm upload "${STORAGE}" "${DOWNLOAD_PATH}" -content vztmpl
fi

# Create VM
VM_ID=$(pvesh get /cluster/nextid)
qm create $VM_ID --name "customer-$CUSTOMER" --memory $MEMORY --cores $CPU --net0 virtio,bridge=vmbr0

# Import disk from the custom image in proxmox_data
qm importdisk $VM_ID "${STORAGE}:vztmpl/${IMAGE_NAME}" "${STORAGE}"

# Configure disk and boot
qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 proxmox_data:vm-$VM_ID-disk-0
qm set $VM_ID --boot c --bootdisk scsi0

# Set cloud-init
qm set $VM_ID --citype nocloud
qm set $VM_ID --ipconfig0 "ip=$IP_ADDRESS/24,gw=192.168.1.1"
qm set $VM_ID --ciuser admin
qm set $VM_ID --cipassword "initial-password"
qm set $VM_ID --sshkeys /root/.ssh/id_rsa.pub

# Create cloud-init customization script
cat > /var/lib/vz/snippets/custom-$CUSTOMER.sh << 'EOF'
#!/bin/bash
apt-get update && apt-get upgrade -y
apt-get install -y docker.io supervisor emacs vim nano curl wget
systemctl enable --now docker
echo 'AllowUsers root@192.168.1.0/24' >> /etc/ssh/sshd_config
systemctl restart sshd
timedatectl set-timezone Europe/Zurich
EOF

qm set $VM_ID --cicustom "user=local:snippets/custom-$CUSTOMER.sh"

# Start VM
qm start $VM_ID

echo "VM customer-$CUSTOMER created with ID $VM_ID and IP $IP_ADDRESS"
# Optional: Clean up the download if desired
# rm -f "${DOWNLOAD_PATH}" 