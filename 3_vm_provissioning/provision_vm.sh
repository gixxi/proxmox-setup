#!/bin/bash
# VM Provisioning Script for Proxmox
# Usage: ./provision_vm.sh <vm_name> <ip_address> <ci_user> <ci_password> [memory in MB] [cpu] [disk in GB] [vm_id]
# Memory defaults to 2048 MB (2 GB), CPU to 2 cores, System Disk (DISK) to 10 GB.
# Creates only the primary system disk.

# --- Configuration ---
VM_NAME=$1
IP_ADDRESS=$2
CI_USER=$3               # Cloud-init user (Mandatory)
CI_PASSWORD=$4           # Cloud-init password (Mandatory)
# Set default values for optional parameters
MEMORY=${5:-2048}         # Default system memory to 2 GB
CPU=${6:-2}               # Default CPU cores to 2
DISK=${7:-10}             # Default system disk size to 10 GB
VM_ID=${8:-}              # VM ID (optional)
STORAGE=${9:-proxmox_data}    # Proxmox storage ID
BRIDGE="vmbr0"            # Proxmox network bridge
# Use GATEWAY from environment if set, otherwise use default
GATEWAY="${GATEWAY:-192.168.3.1}"    # Network gateway (matches Proxmox host network)
SSH_PUB_KEY_PATH="/root/.ssh/id_rsa.pub" # Path to SSH public key for cloud-init
TIMEZONE="Europe/Zurich"  # Timezone for the VM

# Specific Debian image URL and name
DEBIAN_IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/20250416-2084/debian-12-generic-amd64-20250416-2084.qcow2"
IMAGE_NAME="debian-12-generic-amd64-20250416-2084.qcow2"
DOWNLOAD_PATH="/tmp/${IMAGE_NAME}" # Local path to download the image

# --- Parameter Validation ---
if [ -z "$VM_NAME" ] || [ -z "$IP_ADDRESS" ] || [ -z "$CI_USER" ] || [ -z "$CI_PASSWORD" ]; then
  echo "Error: Missing mandatory parameters"
  echo "Usage: $0 <VM_NAME> <ip_address> <ci_user> <ci_password> [memory in MB] [cpu] [disk in GB] [vm_id] [storage]"
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
# Set DNS servers (primary: router, secondary: Google DNS, tertiary: Cloudflare)
qm set $VM_ID --nameserver "192.168.3.1 8.8.8.8 1.1.1.1"
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
cat > /etc/resolv.conf << 'RESOLV_EOF'
# DNS configuration for ${VM_NAME}
# Primary: Router (matches Proxmox host network)
nameserver 192.168.3.1
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
ufw allow from 192.168.3.0/24 to any port 22 proto tcp # Local network access
ufw allow from 5.161.184.133 to any port 22 proto tcp

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
echo " VM ID:        $VM_ID"
echo " Name:         $VM_NAME"
echo " VM_NAME:      $VM_NAME"
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