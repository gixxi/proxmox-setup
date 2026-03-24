#!/usr/bin/env bash
# Nginx reverse proxy (vhost + location) on the local machine (Docker app on localhost).
#
# Service FQDN (nginx server_name, config filenames): <subdomain>.<domain>  e.g. customer-xy.rocklog.ch
# Certificate FQDN (Let's Encrypt name):              <server>.<domain>       e.g. hub-zh-01.rocklog.ch
#
# TLS paths from: certbot certificates -d <server>.<domain>
# Usage: sudo ./4_create_nginx_proxy_configuration.sh <domain> <subdomain> <server> <app_http_port>

set -euo pipefail

usage() {
    echo "Usage: sudo $0 <domain> <subdomain> <server> <app_http_port>" >&2
    echo "  domain          Base domain (e.g. rocklog.ch)" >&2
    echo "  subdomain       Service hostname label — nginx uses <subdomain>.<domain> (e.g. customer-xy)" >&2
    echo "  server          Hostname label for the existing Let's Encrypt cert (e.g. hub-zh-01)" >&2
    echo "  app_http_port   Local port where the app listens (Docker on this host)" >&2
    echo "Must be run as root (writes under /etc/nginx and reads /etc/letsencrypt)." >&2
}

if [ "${EUID:-}" -ne 0 ]; then
    echo "ERROR: Run as root, e.g. sudo $0 <domain> <subdomain> <server> <app_http_port>" >&2
    usage
    exit 1
fi

if [ "$#" -ne 4 ]; then
    echo "ERROR: Expected 4 arguments, got $#" >&2
    usage
    exit 1
fi

DOMAIN=$1
SUBDOMAIN=$2
SERVER=$3
APP_PORT=$4
APP_HOST="127.0.0.1"

if [ -z "$DOMAIN" ] || [ -z "$SUBDOMAIN" ] || [ -z "$SERVER" ] || [ -z "$APP_PORT" ]; then
    echo "ERROR: domain, subdomain, server, and app_http_port must be non-empty." >&2
    usage
    exit 1
fi

if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]] || [ "$APP_PORT" -lt 1 ] || [ "$APP_PORT" -gt 65535 ]; then
    echo "ERROR: Invalid application port number: $APP_PORT" >&2
    exit 1
fi

# Nginx vhost / paths: service domain
FULL_SERVER_NAME="${SUBDOMAIN}.${DOMAIN}"
# Certbot: certificate issued for this FQDN (often the host name, not the customer-facing name)
CERT_FQDN="${SERVER}.${DOMAIN}"

VHOST_CONF="/etc/nginx/sites-enabled/${FULL_SERVER_NAME}.conf"
LOCATION_DIR="/etc/nginx/sites-enabled/locations"
LOCATION_CONF="${LOCATION_DIR}/${SUBDOMAIN}.location.conf"

# Parse certbot output for Let's Encrypt paths (Certificate Name / live dir from -d <fqdn>).
resolve_letsencrypt_paths() {
    local fqdn="$1"
    local out

    if ! command -v certbot >/dev/null 2>&1; then
        echo "ERROR: certbot not found in PATH. Install certbot (e.g. apt install certbot)." >&2
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
        echo "ERROR: Could not parse Certificate Path / Private Key Path from certbot output for -d $fqdn" >&2
        echo "Ensure a certificate exists. Example:" >&2
        echo "  certbot certificates -d $fqdn" >&2
        echo "$out" >&2
        exit 1
    fi

    if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
        echo "ERROR: Resolved cert files are missing on disk:" >&2
        echo "  $SSL_CERT" >&2
        echo "  $SSL_KEY" >&2
        exit 1
    fi
}

resolve_letsencrypt_paths "$CERT_FQDN"

echo "--- Starting Nginx proxy configuration (local) ---"
echo " Domain:           $DOMAIN"
echo " Service (nginx):  $FULL_SERVER_NAME  (subdomain + domain)"
echo " Cert lookup:      $CERT_FQDN  (server + domain)"
echo " Server label:     $SERVER"
echo " App (local):      $APP_HOST:$APP_PORT"
echo " TLS cert file:    $SSL_CERT"
echo " TLS key file:     $SSL_KEY"
echo "-----------------------------------------"
echo "INFO: Server block for ${FULL_SERVER_NAME}; location /${SUBDOMAIN}/ for path-prefixed access"
echo "-----------------------------------------"

mkdir -p /etc/nginx/sites-enabled
mkdir -p "${LOCATION_DIR}"

cat > "${VHOST_CONF}" << VHOST_EOF
# Configuration for ${FULL_SERVER_NAME}
# Managed by 4_create_nginx_proxy_configuration.sh

# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${FULL_SERVER_NAME};
    return 301 https://\$host\$request_uri;
}

# HTTPS Server Block
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${FULL_SERVER_NAME};

    client_max_body_size 0;

    root /var/www/html;
    index index.html index.htm;

    # Certificate files are for ${CERT_FQDN}; server_name is the service host ${FULL_SERVER_NAME}
    ssl_certificate ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};

    location / {
        proxy_pass http://${APP_HOST}:${APP_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_connect_timeout 60s;
        proxy_send_timeout   60s;
        proxy_read_timeout   86400;

        proxy_http_version 1.1;
    }

    location /${SUBDOMAIN}/ {
        rewrite ^/${SUBDOMAIN}(/.*)$ \$1 break;

        proxy_pass http://${APP_HOST}:${APP_PORT}/;

        proxy_redirect ~^/(.*)$ /${SUBDOMAIN}/\$1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Script-Name /${SUBDOMAIN};

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_connect_timeout 60s;
        proxy_send_timeout   60s;
        proxy_read_timeout   86400;

        proxy_http_version 1.1;
    }
}
VHOST_EOF

cat > "${LOCATION_CONF}" << LOCATION_EOF
# Location block for /${SUBDOMAIN}/
# Managed by 4_create_nginx_proxy_configuration.sh

location /${SUBDOMAIN}/ {
    rewrite ^/${SUBDOMAIN}(/.*)$ \$1 break;

    proxy_pass http://${APP_HOST}:${APP_PORT}/;

    proxy_redirect ~^/(.*)$ /${SUBDOMAIN}/\$1;

    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Script-Name /${SUBDOMAIN};

    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";

    proxy_connect_timeout 60s;
    proxy_send_timeout   60s;
    proxy_read_timeout   86400;

    proxy_http_version 1.1;
}
LOCATION_EOF

echo "INFO: Wrote ${VHOST_CONF}"
echo "INFO: Wrote ${LOCATION_CONF}"

echo "INFO: Testing Nginx configuration..."
if nginx -t; then
    echo "INFO: Nginx configuration test successful."
    echo "INFO: Reloading Nginx..."
    systemctl reload nginx
    echo "INFO: Nginx reloaded successfully."
else
    echo "ERROR: nginx -t failed. Files left in place for inspection:" >&2
    echo "  - ${VHOST_CONF}" >&2
    echo "  - ${LOCATION_CONF}" >&2
    exit 1
fi

echo "--- Nginx proxy configuration complete ---"
