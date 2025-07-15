#!/bin/bash
# Script to copy Proxmox SSL certificate to bastian VM
# Usage: ./copy_ssl_to_bastian.sh <bastian_vm_ip>

BASTIAN_IP=$1
BASTIAN_USER="root"
# Get hostname or exit with error
if ! NODE_NAME=$(hostname); then
    echo "Error: Failed to get hostname" 
    exit 1
fi

CERT_PATH="/etc/pve/nodes/${NODE_NAME}/pveproxy-ssl.pem"
KEY_PATH="/etc/pve/nodes/${NODE_NAME}/pveproxy-ssl.key"
REMOTE_CERT_PATH="/etc/nginx/ssl/proxmox.crt"
REMOTE_KEY_PATH="/etc/nginx/ssl/proxmox.key"

# Check if IP is provided
if [ -z "$BASTIAN_IP" ]; then
  echo "Error: Bastian VM IP address not provided"
  echo "Usage: $0 <bastian_vm_ip>"
  exit 1
fi

# Check if certificate and key exist
if [ ! -f "$CERT_PATH" ]; then
  echo "Error: Certificate file not found at $CERT_PATH"
  exit 1
fi

if [ ! -f "$KEY_PATH" ]; then
  echo "Error: Key file not found at $KEY_PATH"
  exit 1
fi

# Create directory on bastian VM
echo "Creating SSL directory on bastian VM..."
ssh $BASTIAN_USER@$BASTIAN_IP "mkdir -p /etc/nginx/ssl && chmod 700 /etc/nginx/ssl"

# Copy files to bastian VM
# The .pem file contains the full chain, which is suitable for nginx's ssl_certificate
echo "Copying certificate and key to bastian VM..."
scp "$CERT_PATH" $BASTIAN_USER@$BASTIAN_IP:$REMOTE_CERT_PATH
scp "$KEY_PATH" $BASTIAN_USER@$BASTIAN_IP:$REMOTE_KEY_PATH

# Set proper permissions on bastian VM
echo "Setting proper permissions..."
ssh $BASTIAN_USER@$BASTIAN_IP "chmod 600 $REMOTE_CERT_PATH $REMOTE_KEY_PATH && chown www-data:www-data $REMOTE_CERT_PATH $REMOTE_KEY_PATH"

# Configure NGINX on bastian VM (Optional - only if you want this script to manage it)
# echo "Configuring NGINX on bastian VM..."
# Configure NGINX on bastian VM
echo "Configuring NGINX on bastian VM..."
# Create SSL configuration for NGINX

ssh $BASTIAN_USER@$BASTIAN_IP "cat > /etc/nginx/conf.d/ssl.conf << 'EOF'
server {
    listen 443 ssl;
    server_name _; # Or your specific domain(s)
    
    ssl_certificate $REMOTE_CERT_PATH;
    ssl_certificate_key $REMOTE_KEY_PATH;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
    
    include /etc/nginx/sites-enabled/locations/*.conf;

    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF"

# Restart NGINX on bastian VM (Optional - only if you want this script to manage it)
# echo "Restarting NGINX on bastian VM..."
# ssh $BASTIAN_USER@$BASTIAN_IP "systemctl restart nginx"

echo "Certificate successfully copied to $BASTIAN_IP" 