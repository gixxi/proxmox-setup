#!/bin/bash
# VM Provisioning Script for Proxmox
# Usage: ./provision_vm.sh --vm-name <name> --ip <address> --user <user> --password <password> [options]
# Example: ./provision_vm.sh --vm-name myvm --ip 192.168.3.100 --user admin --password mypass --memory 4096 --cpu 4
#
# Mandatory parameters:
#   --vm-name, -n     : VM name
#   --ip, -i          : IP address
#   --user, -u        : Cloud-init user
#   --password, -p    : Cloud-init password
#
# Optional parameters:
#   --memory, -m      : Memory in MB (default: 2048)
#   --cpu, -c         : CPU cores (default: 2)
#   --disk, -d        : Disk size in GB (default: 10)
#   --vm-id           : VM ID (default: auto-assigned)
#   --storage, -s     : Proxmox storage ID (default: proxmox_data)
#   --bridge, -b      : Network bridge (default: vmbr0)
#   --gateway, -g     : Network gateway (default: 192.168.3.1)
#   --ssh-key         : SSH public key path (default: /root/.ssh/id_rsa.pub)
#   --timezone, -t    : Timezone (default: Europe/Zurich)
#   --help, -h        : Show this help message

# --- Default Configuration ---
# Set default values
MEMORY=2048
CPU=2
DISK=10
VM_ID=""
STORAGE="proxmox_data"
BRIDGE="vmbr0"
GATEWAY="192.168.3.1"
LOCAL_SUBNET="192.168.3.0/24"
SSH_PUB_KEY_PATH="/root/.ssh/id_rsa.pub"
TIMEZONE="Europe/Zurich"

# Mandatory parameters (will be validated)
VM_NAME=""
IP_ADDRESS=""
CI_USER=""
CI_PASSWORD=""

# Function to show usage
show_usage() {
    echo "Usage: $0 --vm-name <name> --ip <address> --user <user> --password <password> [options]"
    echo ""
    echo "Mandatory parameters:"
    echo "  --vm-name, -n     VM name"
    echo "  --ip, -i          IP address"
    echo "  --user, -u        Cloud-init user"
    echo "  --password, -p    Cloud-init password"
    echo ""
    echo "Optional parameters:"
    echo "  --memory, -m      Memory in MB (default: $MEMORY)"
    echo "  --cpu, -c         CPU cores (default: $CPU)"
    echo "  --disk, -d        Disk size in GB (default: $DISK)"
    echo "  --vm-id           VM ID (default: auto-assigned)"
    echo "  --storage, -s     Proxmox storage ID (default: $STORAGE)"
    echo "  --bridge, -b      Network bridge (default: $BRIDGE)"
    echo "  --gateway, -g     Network gateway (default: $GATEWAY)"
    echo "  --subnet          Local subnet for SSH access (default: $LOCAL_SUBNET)"
    echo "  --ssh-key         SSH public key path (default: $SSH_PUB_KEY_PATH)"
    echo "  --timezone, -t    Timezone (default: $TIMEZONE)"
    echo "  --help, -h        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --vm-name web01 --ip 192.168.3.100 --user admin --password mypass"
    echo "  $0 -n db01 -i 192.168.3.101 -u dbuser -p dbpass -m 4096 -c 4 -d 20"
    echo "  $0 --vm-name app01 --ip 192.168.3.102 --user appuser --password apppass --gateway 192.168.3.254"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vm-name|-n)
            VM_NAME="$2"
            shift 2
            ;;
        --ip|-i)
            IP_ADDRESS="$2"
            shift 2
            ;;
        --user|-u)
            CI_USER="$2"
            shift 2
            ;;
        --password|-p)
            CI_PASSWORD="$2"
            shift 2
            ;;
        --memory|-m)
            MEMORY="$2"
            shift 2
            ;;
        --cpu|-c)
            CPU="$2"
            shift 2
            ;;
        --disk|-d)
            DISK="$2"
            shift 2
            ;;
        --vm-id)
            VM_ID="$2"
            shift 2
            ;;
        --storage|-s)
            STORAGE="$2"
            shift 2
            ;;
        --bridge|-b)
            BRIDGE="$2"
            shift 2
            ;;
        --gateway|-g)
            GATEWAY="$2"
            shift 2
            ;;
        --subnet)
            LOCAL_SUBNET="$2"
            shift 2
            ;;
        --ssh-key)
            SSH_PUB_KEY_PATH="$2"
            shift 2
            ;;
        --timezone|-t)
            TIMEZONE="$2"
            shift 2
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown parameter '$1'"
            echo "Use --help or -h for usage information"
            exit 1
            ;;
    esac
done

# Override with environment variables if they exist
GATEWAY="${GATEWAY_ENV:-$GATEWAY}"    # Allow environment override

# Specific Debian image URL and name
DEBIAN_IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/20250416-2084/debian-12-generic-amd64-20250416-2084.qcow2"
IMAGE_NAME="debian-12-generic-amd64-20250416-2084.qcow2"
DOWNLOAD_PATH="/tmp/${IMAGE_NAME}" # Local path to download the image

# --- Parameter Validation ---
# Check for mandatory parameters
if [ -z "$VM_NAME" ] || [ -z "$IP_ADDRESS" ] || [ -z "$CI_USER" ] || [ -z "$CI_PASSWORD" ]; then
  echo "Error: Missing mandatory parameters"
  echo ""
  if [ -z "$VM_NAME" ]; then echo "  Missing: --vm-name"; fi
  if [ -z "$IP_ADDRESS" ]; then echo "  Missing: --ip"; fi
  if [ -z "$CI_USER" ]; then echo "  Missing: --user"; fi
  if [ -z "$CI_PASSWORD" ]; then echo "  Missing: --password"; fi
  echo ""
  echo "Use --help or -h for usage information"
  exit 1
fi

# Validate numeric parameters
if ! [[ "$MEMORY" =~ ^[0-9]+$ ]]; then
  echo "Error: Memory must be a positive integer (MB): $MEMORY"
  exit 1
fi

if ! [[ "$CPU" =~ ^[0-9]+$ ]]; then
  echo "Error: CPU must be a positive integer: $CPU"
  exit 1
fi

if ! [[ "$DISK" =~ ^[0-9]+$ ]]; then
  echo "Error: Disk size must be a positive integer (GB): $DISK"
  exit 1
fi

if [ -n "$VM_ID" ] && ! [[ "$VM_ID" =~ ^[0-9]+$ ]]; then
  echo "Error: VM ID must be a positive integer: $VM_ID"
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

# Display parsed configuration
echo "=================================================="
echo " VM PROVISIONING CONFIGURATION"
echo "=================================================="
echo " VM Name:        $VM_NAME"
echo " IP Address:     $IP_ADDRESS"
echo " Gateway:        $GATEWAY"
echo " Local Subnet:   $LOCAL_SUBNET"
echo " Memory:         $MEMORY MB"
echo " CPU Cores:      $CPU"
echo " Disk Size:      ${DISK}GB"
echo " VM ID:          ${VM_ID:-auto-assigned}"
echo " Storage:        $STORAGE"
echo " Bridge:         $BRIDGE"
echo " Timezone:       $TIMEZONE"
echo " SSH User:       $CI_USER"
echo " SSH Key Path:   $SSH_PUB_KEY_PATH"
echo "=================================================="
echo ""

# Validate and sanitize VM name for Proxmox DNS compatibility
# Proxmox requires VM names to be valid DNS names (letters, numbers, hyphens only)
ORIGINAL_VM_NAME="$VM_NAME"
VM_NAME=$(echo "$VM_NAME" | sed 's/_/-/g')  # Replace underscores with hyphens

# Additional validation: ensure name only contains valid DNS characters
if ! [[ "$VM_NAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
  echo "Error: VM name contains invalid characters. Only letters, numbers, and hyphens are allowed."
  echo "Original name: $ORIGINAL_VM_NAME"
  echo "Sanitized name: $VM_NAME"
  exit 1
fi

# Check if name starts or ends with hyphen (invalid DNS name)
if [[ "$VM_NAME" =~ ^- ]] || [[ "$VM_NAME" =~ -$ ]]; then
  echo "Error: VM name cannot start or end with a hyphen."
  echo "Original name: $ORIGINAL_VM_NAME"
  echo "Sanitized name: $VM_NAME"
  exit 1
fi

# Inform user if name was modified
if [ "$ORIGINAL_VM_NAME" != "$VM_NAME" ]; then
  echo "INFO: VM name sanitized from '$ORIGINAL_VM_NAME' to '$VM_NAME' for Proxmox compatibility"
fi
SNIPPET_DIR="/var/lib/vz/snippets"
CUSTOM_SCRIPT_NAME="custom-$VM_NAME.sh"
CUSTOM_SCRIPT_PATH="$SNIPPET_DIR/$CUSTOM_SCRIPT_NAME"

# --- Main Script ---

# 1. Get Next Available VM ID if not provided
if [ -z "$VM_ID" ]; then
  echo "INFO: Getting next available VM ID..."
  VM_ID=$(pvesh get /cluster/nextid)
  if [ -z "$VM_ID" ]; then
    echo "ERROR: Could not get next VM ID from Proxmox."
    exit 1
  fi
  echo "INFO: Next available VM ID is $VM_ID."
fi

# Check if VM already exists (optional, uncomment to prevent overwriting)
# if qm status $VM_ID > /dev/null 2>&1; then
#     echo "ERROR: VM ID $VM_ID already exists. Please choose a different ID or delete the existing VM."
#     exit 1
# fi

# 2. Download Debian Cloud Image if necessary
echo "INFO: Checking for Debian cloud image..."
if [ ! -f "${DOWNLOAD_PATH}" ]; then
  echo "INFO: Debian cloud image not found locally. Downloading to ${DOWNLOAD_PATH}..."
  wget -q --show-progress -O "${DOWNLOAD_PATH}" "${DEBIAN_IMAGE_URL}"
  if [ $? -ne 0 ]; then
      echo "ERROR: Failed to download Debian image."
      exit 1
  fi
  echo "INFO: Download complete."
else
  echo "INFO: Debian cloud image already exists locally at ${DOWNLOAD_PATH}"
  echo "INFO: Skipping download to save time and bandwidth."
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
# Detect if storage is ZFS (by name or by checking storage type, here we use name as a quick fix)
if [[ "$STORAGE" == *zfs* || "$STORAGE" == *local_data* ]]; then
    IMPORTED_DISK_FILENAME="vm-${VM_ID}-disk-0"
    DISK_PATH_FOR_SET="${STORAGE}:${IMPORTED_DISK_FILENAME}"
else
    IMPORTED_DISK_FILENAME="vm-${VM_ID}-disk-0.raw"
    DISK_PATH_FOR_SET="${STORAGE}:${VM_ID}/${IMPORTED_DISK_FILENAME}"
fi
echo "INFO: Disk image imported. Assuming filename ${IMPORTED_DISK_FILENAME} in VM directory."

# 5. Attach the imported disk as the boot disk (scsi0 -> /dev/sda)
# Use the format that includes the VM ID subdirectory, matching your working example.
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
# Configure IP, gateway, and DNS servers
qm set $VM_ID --ipconfig0 "ip=${IP_ADDRESS}/24,gw=${GATEWAY},ip6=auto"
# Set DNS servers (primary: Google DNS, secondary: Cloudflare)
qm set $VM_ID --nameserver "8.8.8.8 1.1.1.1"
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

# Set the hostname
echo "INFO: Setting hostname to ${VM_NAME}..."
hostnamectl set-hostname ${VM_NAME}
if [ \$? -ne 0 ]; then echo "WARNING: Failed to set hostname."; fi

# Force set root password directly
echo 'root:${CI_PASSWORD}' | chpasswd
echo "INFO: Root password has been explicitly set to the provided cloud-init password"

# Ensure SSH directory exists with proper permissions
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Simply create the authorized_keys file with the SSH key
echo "$(cat ${SSH_PUB_KEY_PATH})" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
echo "INFO: SSH key added to authorized_keys"

# Basic System Setup
echo "INFO: Updating package lists and upgrading packages..."
apt-get update -y && apt-get upgrade -y
if [ \$? -ne 0 ]; then echo "WARNING: apt update/upgrade failed."; fi

echo "INFO: Installing base packages including nginx and ufw..."
apt-get install -y docker.io supervisor emacs vim nano curl wget parted gdisk mosh nginx ufw zsh tmux make
if [ \$? -ne 0 ]; then echo "WARNING: apt install failed."; fi

# Mask systemd-networkd-wait-online.service to prevent network wait delays
systemctl mask systemd-networkd-wait-online.service || true

# Restart Docker to apply new configuration
systemctl restart docker
if [ \$? -ne 0 ]; then echo "WARNING: Failed to restart Docker service"; fi

# --- Configure Nginx ---
echo "INFO: Configuring Nginx..."
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_CONF_BAK="/etc/nginx/nginx.conf.bak"

# Backup the original config
if [ -f "\$NGINX_CONF" ]; then
    echo "Backing up default Nginx config to \$NGINX_CONF_BAK"
    cp "\$NGINX_CONF" "\$NGINX_CONF_BAK"
fi

# Create the new nginx.conf with desired settings
cat > "\$NGINX_CONF" << 'NGINX_EOF'
user www-data;
worker_processes auto; # Adjust based on CPU cores if needed
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    # Support large number of connections
    worker_connections 20000;
    # multi_accept on; # Uncomment if needed for high connection rates
}

http {
    # Handle large file uploads
    client_max_body_size 10M;

    ##
    # Basic Settings
    ##
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on; # Often used with tcp_nopush and sendfile
    keepalive_timeout 65;
    types_hash_max_size 2048;
    # server_tokens off; # Uncomment to hide Nginx version

    # server_names_hash_bucket_size 64; # Uncomment if long server names are used
    # server_name_in_redirect off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ##
    # SSL Settings (Sensible defaults, customize further in vhosts)
    ##
    ssl_protocols TLSv1.2 TLSv1.3; # Modern protocols
    ssl_prefer_server_ciphers on;
    # Add recommended ciphers here or in vhost configs if needed
    # ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:...';

    ##
    # Logging Settings
    ##
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    ##
    # Gzip Settings
    ##
    gzip on;
    gzip_disable "msie6"; # Disable for old IE versions
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6; # Balance between CPU and compression ratio
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_min_length 256; # Don't gzip very small files
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;

    ##
    # Virtual Host Configs
    ##
    include /etc/nginx/conf.d/*.conf;
    # Include individual .conf files from sites-enabled
    include /etc/nginx/sites-enabled/*.conf;
    # Explicitly include the standard default site if it exists
    include /etc/nginx/sites-enabled/default;
}
NGINX_EOF

echo "INFO: New Nginx configuration written to \$NGINX_CONF"

# Check Nginx configuration syntax
nginx -t
if [ \$? -ne 0 ]; then
    echo "ERROR: Nginx configuration test failed. Restoring backup."
    if [ -f "\$NGINX_CONF_BAK" ]; then
        cp "\$NGINX_CONF_BAK" "\$NGINX_CONF"
    fi
    # Decide how to handle this - maybe exit or just warn?
    # For now, we'll proceed but Nginx might fail to start/reload
else
    echo "INFO: Nginx configuration test successful."
fi

# Restart Nginx to apply changes
echo "INFO: Restarting Nginx service..."
systemctl restart nginx
if [ \$? -ne 0 ]; then
    echo "WARNING: Failed to restart Nginx service. Check config and logs."
fi
# --- End Nginx Configuration ---

echo "INFO: Enabling and starting Docker service..."
systemctl enable --now docker
if [ \$? -ne 0 ]; then echo "WARNING: Failed to enable/start docker."; fi

# Configure SSH settings (Allowing root login and password auth - adjust if needed)
echo "INFO: Configuring SSH authentication settings..."
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Restart SSH service to apply changes
systemctl restart sshd
if [ \$? -ne 0 ]; then echo "WARNING: Failed to restart sshd service"; fi

# Timezone
echo "INFO: Setting timezone to ${TIMEZONE}..."
timedatectl set-timezone ${TIMEZONE}

# --- Configure DNS ---
echo "INFO: Configuring DNS servers..."
# Backup original resolv.conf
cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null || echo "No backup needed"

# Create new resolv.conf with proper DNS servers
cat > /etc/resolv.conf << RESOLV_EOF
# DNS configuration for ${VM_NAME}
# Primary: Router/Gateway (matches Proxmox host network)
nameserver ${GATEWAY}
# Secondary: Google DNS
nameserver 8.8.8.8
# Tertiary: Cloudflare DNS
nameserver 1.1.1.1
# Search domain (optional)
search local
RESOLV_EOF

echo "INFO: DNS configuration written to /etc/resolv.conf"
echo "INFO: Testing DNS resolution..."
nslookup google.com 2>/dev/null && echo "DNS resolution working" || echo "WARNING: DNS resolution failed"

# Test internet connectivity
echo "INFO: Testing internet connectivity..."
ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo "Internet connectivity working" || echo "WARNING: Internet connectivity failed"

# --- Configure UFW (Uncomplicated Firewall) ---
echo "INFO: Configuring UFW firewall rules..."

# Allow SSH (port 22) from specific IPs
echo "Allowing SSH from specific IPs..."
ufw allow from 172.105.94.119 to any port 22 proto tcp
ufw allow from 116.203.216.1 to any port 22 proto tcp
ufw allow from 5.161.184.133 to any port 22 proto tcp

# Allow SSH from local subnet
echo "Allowing SSH from local subnet: ${LOCAL_SUBNET}..."
ufw allow from ${LOCAL_SUBNET} to any port 22 proto tcp

# Explicitly deny SSH from other sources (IPv4 and IPv6)
echo "Denying SSH from other sources..."
ufw deny 22/tcp comment 'Deny all other SSH access'

# Allow HTTP (port 80)
echo "Allowing HTTP (port 80)..."
ufw allow 80/tcp

# Allow HTTPS (port 443)
echo "Allowing HTTPS (port 443)..."
ufw allow 443/tcp

# Allow custom TCP ports (8080, 8443)
echo "Allowing custom TCP ports 8080 and 8443..."
ufw allow 8080/tcp
ufw allow 8443/tcp

# Allow Mosh UDP ports (60000:61000)
echo "Allowing Mosh UDP ports (60000:61000)..."
ufw allow 60000:61000/udp

# Enable UFW
echo "Enabling UFW..."
# Use --force to enable without interactive prompt
ufw --force enable

echo "INFO: UFW enabled."
# --- End UFW Configuration ---

# Setup additional data disk (scsi1 -> /dev/sdb or similar) - REMOVED
# echo "INFO: Setting up additional data disk..."
# ... (all the disk detection, formatting, mounting logic removed) ...

echo "--- Cloud-Init User Data Script Finished ---"

# Optional: Print final UFW status to cloud-init log
echo "Final UFW status:"
ufw status verbose

# Optional: Print Nginx status
echo "Nginx service status:"
systemctl status nginx --no-pager || echo "Could not get Nginx status."

cat /etc/ssh/sshd_config

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
echo " VM ID:          $VM_ID"
echo " Name:           $VM_NAME"
echo " IP Address:     $IP_ADDRESS"
echo " Gateway:        $GATEWAY"
echo " Memory:         $MEMORY MB"
echo " CPU Cores:      $CPU"
echo " System Disk:    ${DISK}G (scsi0)"
echo " Storage:        $STORAGE"
echo " Bridge:         $BRIDGE"
echo " Timezone:       $TIMEZONE"
echo " SSH User:       $CI_USER"
echo " SSH Password:   $CI_PASSWORD"
echo " SSH PubKey:     $SSH_PUB_KEY_PATH"
echo "=================================================="
echo ""
echo "INFO: Waiting a bit for VM to boot and apply cloud-init..."
sleep 45 # Adjust as needed
echo ""
echo "CONNECTION INFO:"
echo "  SSH:    ssh ${CI_USER}@${IP_ADDRESS}"
echo "  Root:   ssh root@${IP_ADDRESS}  (password: *****)"
echo "  HTTP:   http://${IP_ADDRESS}"
echo "  HTTPS:  https://${IP_ADDRESS}"
echo ""
echo "NEXT STEPS:"
echo "  1. Check cloud-init logs: /var/log/cloud-init-output.log"
echo "  2. Verify services: systemctl status nginx docker"
echo "  3. Check firewall: ufw status verbose"
echo "=================================================="

# Optional: Clean up the downloaded image if desired
# echo "INFO: Cleaning up downloaded image ${DOWNLOAD_PATH}..."
# rm -f "${DOWNLOAD_PATH}"

exit 0 