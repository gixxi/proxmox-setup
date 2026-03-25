#!/usr/bin/env bash
# Write /etc/nginx/sites-enabled/default as the default_server with TLS paths from certbot.
# Usage: sudo ./5_create_default_nginx_configuration.sh <full_server_name>

set -euo pipefail

usage() {
    echo "Usage: sudo $0 <full_server_name>" >&2
    echo "  full_server_name  FQDN for server_name and certbot -d (e.g. hub-zh-01.planet-rocklog.com)" >&2
    echo "Must be run as root." >&2
}

if [ "${EUID:-}" -ne 0 ]; then
    echo "ERROR: Run as root, e.g. sudo $0 <full_server_name>" >&2
    usage
    exit 1
fi

if [ "$#" -ne 1 ]; then
    echo "ERROR: Expected 1 argument, got $#" >&2
    usage
    exit 1
fi

FULL_SERVER_NAME="$1"
if [ -z "$FULL_SERVER_NAME" ]; then
    echo "ERROR: full_server_name must be non-empty." >&2
    usage
    exit 1
fi

SITES_ENABLED="/etc/nginx/sites-enabled"
SITES_BACKUP="/etc/nginx/sites-enabled.bak"
DEFAULT_CONF="${SITES_ENABLED}/default"

resolve_letsencrypt_paths() {
    local fqdn="$1"
    local out

    if ! command -v certbot >/dev/null 2>&1; then
        echo "ERROR: certbot not found in PATH." >&2
        exit 1
    fi

    if ! out=$(certbot certificates -d "$fqdn" 2>&1); then
        echo "ERROR: certbot certificates -d $fqdn failed:" >&2
        echo "$out" >&2
        exit 1
    fi

    SSL_CERT=$(echo "$out" | awk -F': ' '/Certificate Path:/{p=$2; gsub(/\r/, "", p); gsub(/^[ \t]+|[ \t]+$/, "", p); print p; exit}')
    SSL_KEY=$(echo "$out" | awk -F': ' '/Private Key Path:/{p=$2; gsub(/\r/, "", p); gsub(/^[ \t]+|[ \t]+$/, "", p); print p; exit}')

    if [ -z "${SSL_CERT:-}" ] || [ -z "${SSL_KEY:-}" ]; then
        echo "ERROR: Could not parse Certificate / Private Key paths from certbot for -d $fqdn" >&2
        echo "$out" >&2
        exit 1
    fi

    if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
        echo "ERROR: Certificate files missing:" >&2
        echo "  $SSL_CERT" >&2
        echo "  $SSL_KEY" >&2
        exit 1
    fi
}

echo "INFO: Resolving TLS paths via certbot for ${FULL_SERVER_NAME}..."
resolve_letsencrypt_paths "$FULL_SERVER_NAME"

if [ ! -d "$SITES_ENABLED" ]; then
    echo "ERROR: $SITES_ENABLED does not exist." >&2
    exit 1
fi

if [ ! -d "$SITES_BACKUP" ]; then
    echo "INFO: Creating one-time backup: $SITES_BACKUP"
    cp -a "$SITES_ENABLED" "$SITES_BACKUP"
else
    echo "INFO: Backup already exists ($SITES_BACKUP), skipping copy."
fi

mkdir -p "${SITES_ENABLED}/locations"
if ! compgen -G "${SITES_ENABLED}/locations/"*.conf > /dev/null 2>&1; then
    echo "INFO: No locations/*.conf yet; adding a no-op location so include succeeds."
    cat > "${SITES_ENABLED}/locations/00-placeholder.conf" << 'PLACEHOLDER'
# Remove after adding real *.conf fragments (valid inside server { }).
location = /_nginx_locations_placeholder_unused { return 404; }
PLACEHOLDER
fi

echo "INFO: Writing $DEFAULT_CONF"

cat > "$DEFAULT_CONF" << NGINX_DEFAULT
# Managed by 5_create_default_nginx_configuration.sh (${FULL_SERVER_NAME})

server {
        listen 80 default_server;
        listen [::]:80 default_server;

        listen 443 ssl default_server;
        listen [::]:443 ssl default_server;

        ssl_certificate ${SSL_CERT};
        ssl_certificate_key ${SSL_KEY};

        # disable any limits to avoid HTTP 413 for large image uploads
        client_max_body_size 0;

        root /var/www/html;

        # Add index.php to the list if you are using PHP
        index index.html index.htm index.nginx-debian.html;

        server_name ${FULL_SERVER_NAME};

        include ${SITES_ENABLED}/locations/*.conf;

        location / {
                # First attempt to serve request as file, then
                # as directory, then fall back to displaying a 404.
                try_files \$uri \$uri/ =404;
        }

        # Serve all files in /var/logs as plain text
        location /werner/status {
           root /tmp;
           default_type text/plain;
        }
}
NGINX_DEFAULT

echo "INFO: Testing nginx configuration..."
if nginx -t; then
    echo "INFO: Reloading nginx..."
    systemctl reload nginx
    echo "INFO: Done. Default server: ${FULL_SERVER_NAME}"
else
    echo "ERROR: nginx -t failed. Default config left at $DEFAULT_CONF" >&2
    exit 1
fi
