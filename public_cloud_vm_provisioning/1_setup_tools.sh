#!/usr/bin/env bash
# Configure Nginx (same layout as 3_vm_provissioning/provision_vm.sh) and verify Docker.
# Intended for Debian/Ubuntu on a single local or public-cloud VM. Run as root (see README).

set -euo pipefail

if [ "${EUID:-}" -ne 0 ]; then
    echo "ERROR: Run this script as root, e.g. sudo $0" >&2
    exit 1
fi

echo "INFO: Installing nginx and docker.io (if needed)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx docker.io

# --- Configure Nginx ---
echo "INFO: Configuring Nginx..."
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_CONF_BAK="/etc/nginx/nginx.conf.bak"

if [ -f "$NGINX_CONF" ]; then
    echo "Backing up default Nginx config to $NGINX_CONF_BAK"
    cp "$NGINX_CONF" "$NGINX_CONF_BAK"
fi

cat > "$NGINX_CONF" << 'NGINX_EOF'
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

echo "INFO: New Nginx configuration written to $NGINX_CONF"

if ! nginx -t; then
    echo "ERROR: Nginx configuration test failed. Restoring backup."
    if [ -f "$NGINX_CONF_BAK" ]; then
        cp "$NGINX_CONF_BAK" "$NGINX_CONF"
    fi
else
    echo "INFO: Nginx configuration test successful."
fi

echo "INFO: Restarting Nginx service..."
if ! systemctl restart nginx; then
    echo "WARNING: Failed to restart Nginx service. Check config and logs."
fi
# --- End Nginx Configuration ---

echo "INFO: Enabling and starting Docker service..."
if ! systemctl enable --now docker; then
    echo "WARNING: Failed to enable/start docker."
    exit 1
fi

echo "INFO: Testing Docker service..."
if ! systemctl is-active --quiet docker; then
    echo "ERROR: Docker service is not active." >&2
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: docker info failed. Check Docker daemon and permissions." >&2
    exit 1
fi
echo "INFO: Docker is running (docker info OK)."
