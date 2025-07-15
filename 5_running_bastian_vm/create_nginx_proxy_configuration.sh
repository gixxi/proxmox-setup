#!/bin/bash

# Script to create Nginx reverse proxy configurations (vhost + location) on a remote Bastian VM.
# Usage: ./create_nginx_proxy_configuration.sh <bastian_vm_ip> <domain> <subdomain> <app_vm_ip> <app_http_port>

BASTIAN_IP=$1
DOMAIN=$2          # Base domain name (e.g., rocklog.ch)
SUBDOMAIN=$3       # Subdomain part (e.g., myapp)
APP_IP=$4          # IP of the backend application VM
APP_PORT=$5        # Port of the backend application
BASTIAN_USER="root" # User for SSH connection

# --- Parameter Validation ---
# Check for the correct number of arguments
if [ "$#" -ne 5 ]; then
  echo "Error: Incorrect number of arguments provided."
  echo "Usage: $0 <bastian_vm_ip> <domain> <subdomain> <app_vm_ip> <app_http_port>"
  exit 1
fi

# Validate parameters (basic checks)
if [ -z "$BASTIAN_IP" ] || [ -z "$DOMAIN" ] || [ -z "$SUBDOMAIN" ] || [ -z "$APP_IP" ] || [ -z "$APP_PORT" ]; then
  echo "Error: One or more mandatory parameters are empty."
  echo "Usage: $0 <bastian_vm_ip> <domain> <subdomain> <app_vm_ip> <app_http_port>"
  exit 1
fi

if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]] || [ "$APP_PORT" -lt 1 ] || [ "$APP_PORT" -gt 65535 ]; then
    echo "Error: Invalid application port number: $APP_PORT"
    exit 1
fi

# Construct the full server name
FULL_SERVER_NAME="${SUBDOMAIN}.${DOMAIN}"

# Define remote paths
REMOTE_SERVER_CONF="/etc/nginx/sites-enabled/${FULL_SERVER_NAME}.conf" # Use FQDN for server conf
REMOTE_SSL_CERT="/etc/nginx/ssl/proxmox.crt" # Assumes cert copied by copy_ssl_to_bastian.sh
REMOTE_SSL_KEY="/etc/nginx/ssl/proxmox.key"   # Assumes key copied by copy_ssl_to_bastian.sh

echo "--- Starting Nginx Proxy Configuration ---"
echo " Bastian VM IP: $BASTIAN_IP"
echo " Domain:        $DOMAIN"
echo " Subdomain:     $SUBDOMAIN"
echo " App VM IP:     $APP_IP"
echo " App Port:      $APP_PORT"
echo " Full Server:   $FULL_SERVER_NAME"
echo "-----------------------------------------"
# Acknowledging the location block use case:
echo "INFO: Will create server block for ${FULL_SERVER_NAME} and location block for /${SUBDOMAIN}/"
echo "      (Location block intended for potential direct access, e.g., bypassing Cloudflare for WebSockets)"
echo "-----------------------------------------"


# Use SSH to execute commands remotely on the Bastian VM
ssh ${BASTIAN_USER}@${BASTIAN_IP} "bash -s" -- << EOF
set -e # Exit immediately if a command exits with a non-zero status.

echo "INFO: Running commands remotely on ${BASTIAN_IP}..."

# --- Create Virtual Host Server Block ---
# Using FULL_SERVER_NAME in the filename for clarity
echo "INFO: Creating server block file: ${REMOTE_SERVER_CONF}"
# Ensure the sites-enabled directory exists (though it should)
mkdir -p /etc/nginx/sites-enabled

# Use cat and HERE document to write the config file
# Note: Variables like \${FULL_SERVER_NAME}, \${REMOTE_SSL_CERT} etc. inside VHOST_EOF
# will be expanded by the *remote* shell because the EOF marker is not quoted.
# This is desired here. Variables like \$host, \$request_uri need escaping (\$)
# so they are interpreted by Nginx, not the shell.
cat > "${REMOTE_SERVER_CONF}" << VHOST_EOF
# Configuration for ${FULL_SERVER_NAME}
# Managed by create_nginx_proxy_configuration.sh

# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${FULL_SERVER_NAME};

    # ACME challenge handler (optional, if using HTTP-01 challenge)
    # location ~ /.well-known/acme-challenge {
    #     allow all;
    #     root /var/www/html; # Or a dedicated ACME challenge directory
    # }

    # location / {
        return 301 https://\\\$host\\\$request_uri; # Escaped $ for Nginx variable
    # }
}

# HTTPS Server Block
server {
    listen 443 ssl http2; # Enable HTTP/2 if desired
    listen [::]:443 ssl http2;
    server_name ${FULL_SERVER_NAME};

    # disable any limits to avoid HTTP 413 for large image uploads
    client_max_body_size 0;

    # Default root (can be useful for ACME challenges if needed, otherwise less relevant for pure proxy)
    root /var/www/html;
    index index.html index.htm; # Add index.php if PHP is used directly here

    # SSL Configuration - IMPORTANT: Certificate must be valid for ${FULL_SERVER_NAME}
    ssl_certificate ${REMOTE_SSL_CERT};
    ssl_certificate_key ${REMOTE_SSL_KEY};
    # Include stronger SSL settings if not globally defined in nginx.conf
    # ssl_protocols TLSv1.2 TLSv1.3;
    # ssl_prefer_server_ciphers on;
    # ssl_ciphers 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH'; # Example cipher suite
    # ssl_session_cache shared:SSL:10m;
    # ssl_session_timeout 10m;
    # ssl_session_tickets off; # Consider security implications
    # add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"; # Enable HSTS if ready

    location / {
        proxy_pass http://${APP_IP}:${APP_PORT}/;
        proxy_set_header Host \\\$host; # Escaped $ for Nginx variable
        proxy_set_header X-Real-IP \\\$remote_addr; # Escaped $ for Nginx variable
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for; # Escaped $ for Nginx variable
        proxy_set_header X-Forwarded-Proto \\\$scheme; # Escaped $ for Nginx variable

        # WebSocket support (if needed by the application)
        proxy_set_header Upgrade \\\$http_upgrade; # Escaped $ for Nginx variable
        proxy_set_header Connection "upgrade";

        # Increase timeouts if needed for long-running requests
        proxy_connect_timeout 60s;
        proxy_send_timeout   60s;
        proxy_read_timeout   86400; # 24 hours for potentially very long operations

        proxy_http_version 1.1; # Recommended for keepalive, etc.
    }

    # Location block for /${SUBDOMAIN}/ (alternative access path)
    location /${SUBDOMAIN}/ {
        # Rewrite the request path before proxying (remove leading /<subdomain>)
        # Example: /subdomain/foo -> /foo
        rewrite ^/${SUBDOMAIN}(/.*)$ \\\$1 break; # Escaped $ for Nginx variable

        proxy_pass http://${APP_IP}:${APP_PORT}/; # Pass to the root of the app

        # Redirect Location headers from the backend app if they don't include the prefix
        # This helps fix redirects within the app when accessed via path
        proxy_redirect ~^/(.*)$ /${SUBDOMAIN}/\\\$1; # Escaped $ for Nginx variable

        proxy_set_header Host \\\$host; # Escaped $ for Nginx variable
        proxy_set_header X-Real-IP \\\$remote_addr; # Escaped $ for Nginx variable
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for; # Escaped $ for Nginx variable
        proxy_set_header X-Forwarded-Proto \\\$scheme; # Escaped $ for Nginx variable
        proxy_set_header X-Script-Name /${SUBDOMAIN}; # Inform app about base path

        # WebSocket support
        proxy_set_header Upgrade \\\$http_upgrade; # Escaped $ for Nginx variable
        proxy_set_header Connection "upgrade";

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout   60s;
        proxy_read_timeout   86400;

        proxy_http_version 1.1;
    }
}
VHOST_EOF
echo "INFO: Server block file created."

# Location block is now included directly in the server block above
echo "INFO: Location block for /${SUBDOMAIN}/ included in server block."

# --- Test and Reload Nginx ---
echo "INFO: Testing Nginx configuration..."
if nginx -t; then
    echo "INFO: Nginx configuration test successful."
    echo "INFO: Reloading Nginx service..."
    systemctl reload nginx
    echo "INFO: Nginx reloaded successfully."
else
    echo "ERROR: Nginx configuration test failed. Please check the file:"
    echo "  - ${REMOTE_SERVER_CONF}"
    echo "  Nginx was NOT reloaded."
    # Optional: remove the created file on failure?
    # rm -f "${REMOTE_SERVER_CONF}"
    exit 1 # Exit the remote script with an error
fi

echo "INFO: Remote configuration finished successfully."
EOF

# Check the exit status of the SSH command
SSH_EXIT_STATUS=$?
if [ $SSH_EXIT_STATUS -ne 0 ]; then
    echo "ERROR: SSH command failed with exit status $SSH_EXIT_STATUS."
    exit $SSH_EXIT_STATUS
fi

echo "--- Nginx Proxy Configuration Complete ---"
exit 0 