# SSL Setup - Nginx and Let's Encrypt

This directory contains scripts for setting up SSL/TLS certificates using Let's Encrypt and Nginx as a reverse proxy.

## SSL Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SSL/TLS Setup                            │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Internet  │  │    Nginx    │  │   Docker    │        │
│  │   Traffic   │  │  (Reverse   │  │  Containers │        │
│  │             │  │   Proxy)    │  │             │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│         │                │                │               │
│         ▼                ▼                ▼               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Port 80   │  │   Port 443  │  │   Internal  │        │
│  │ (HTTP)      │  │   (HTTPS)   │  │   Ports     │        │
│  │ Redirect    │  │   SSL/TLS   │  │             │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Files

- `install_nginx.sh` - Install and configure Nginx
- `install_certbot.sh` - Install Certbot for Let's Encrypt
- `create_ssl_certificate.sh` - Create SSL certificate for domain
- `setup_auto_renewal.sh` - Setup automatic certificate renewal
- `configure_nginx_proxy.sh` - Configure Nginx as reverse proxy
- `test_ssl.sh` - Test SSL configuration

## Domain Configuration

### Domain Pattern
- **Pattern**: `{hostname}.planet-rocklog.com`
- **Example**: `docker-host-01.planet-rocklog.com`
- **DNS**: A record pointing to host IP address

### SSL Certificate
- **Provider**: Let's Encrypt
- **Challenge**: HTTP-01 (port 80)
- **Validity**: 90 days
- **Auto-renewal**: Every 60 days

## Nginx Configuration

### Main Configuration
```nginx
# /etc/nginx/nginx.conf
http {
    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
    ssl_prefer_server_ciphers off;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    # Include site configurations
    include /etc/nginx/sites-enabled/*;
}
```

### Site Configuration
```nginx
# /etc/nginx/sites-available/docker-host-01.planet-rocklog.com
server {
    listen 80;
    server_name docker-host-01.planet-rocklog.com;
    
    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name docker-host-01.planet-rocklog.com;
    
    # SSL certificate
    ssl_certificate /etc/letsencrypt/live/docker-host-01.planet-rocklog.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/docker-host-01.planet-rocklog.com/privkey.pem;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Proxy to Docker containers
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Installation Steps

### 1. Install Nginx
```bash
# Install Nginx
apt update
apt install -y nginx

# Start and enable Nginx
systemctl start nginx
systemctl enable nginx
```

### 2. Install Certbot
```bash
# Install Certbot
apt install -y certbot python3-certbot-nginx

# Verify installation
certbot --version
```

### 3. Create SSL Certificate
```bash
# Create certificate
certbot --nginx -d docker-host-01.planet-rocklog.com

# Test renewal
certbot renew --dry-run
```

## Automated Setup

### 1. Install Nginx and Certbot
```bash
./install_nginx.sh
./install_certbot.sh
```

### 2. Create SSL Certificate
```bash
./create_ssl_certificate.sh docker-host-01.planet-rocklog.com
```

### 3. Setup Auto-renewal
```bash
./setup_auto_renewal.sh
```

### 4. Configure Reverse Proxy
```bash
./configure_nginx_proxy.sh
```

## Certificate Management

### Manual Certificate Creation
```bash
# Create certificate with HTTP challenge
certbot certonly --standalone -d docker-host-01.planet-rocklog.com

# Create certificate with webroot challenge
certbot certonly --webroot -w /var/www/html -d docker-host-01.planet-rocklog.com
```

### Certificate Renewal
```bash
# Manual renewal
certbot renew

# Test renewal
certbot renew --dry-run

# Check certificate status
certbot certificates
```

### Certificate Information
```bash
# View certificate details
openssl x509 -in /etc/letsencrypt/live/docker-host-01.planet-rocklog.com/cert.pem -text -noout

# Check certificate expiration
openssl x509 -in /etc/letsencrypt/live/docker-host-01.planet-rocklog.com/cert.pem -noout -dates
```

## Nginx Proxy Configuration

### Docker Container Proxy
```nginx
# Proxy to Docker container
location /app/ {
    proxy_pass http://127.0.0.1:8080/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

### Load Balancing
```nginx
# Load balancing between multiple containers
upstream docker_apps {
    server 127.0.0.1:8080;
    server 127.0.0.1:8081;
    server 127.0.0.1:8082;
}

location / {
    proxy_pass http://docker_apps;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## Security Configuration

### SSL Security
```nginx
# Strong SSL configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
ssl_prefer_server_ciphers off;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
```

### Security Headers
```nginx
# Security headers
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
add_header Referrer-Policy "strict-origin-when-cross-origin";
```

## Monitoring and Maintenance

### Certificate Monitoring
```bash
#!/bin/bash
# check_certificate_expiry.sh

DOMAIN="docker-host-01.planet-rocklog.com"
CERT_FILE="/etc/letsencrypt/live/$DOMAIN/cert.pem"

# Check certificate expiration
EXPIRY=$(openssl x509 -in $CERT_FILE -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
CURRENT_EPOCH=$(date +%s)
DAYS_LEFT=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))

if [ $DAYS_LEFT -lt 30 ]; then
    echo "WARNING: Certificate expires in $DAYS_LEFT days"
    # Send alert
fi
```

### Nginx Status Monitoring
```bash
# Check Nginx status
systemctl status nginx

# Check Nginx configuration
nginx -t

# Check Nginx logs
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

## Troubleshooting

### Common Issues
1. **Certificate creation fails**: Check DNS resolution and port 80 availability
2. **Nginx configuration errors**: Check syntax with `nginx -t`
3. **SSL handshake failures**: Check certificate validity and configuration

### Debugging Commands
```bash
# Test SSL configuration
openssl s_client -connect docker-host-01.planet-rocklog.com:443 -servername docker-host-01.planet-rocklog.com

# Check certificate chain
openssl s_client -connect docker-host-01.planet-rocklog.com:443 -showcerts

# Test HTTP to HTTPS redirect
curl -I http://docker-host-01.planet-rocklog.com

# Check Nginx configuration
nginx -T | grep -A 10 -B 10 "server_name"
```

## Performance Optimization

### Nginx Optimization
```nginx
# Enable gzip compression
gzip on;
gzip_vary on;
gzip_min_length 1024;
gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;

# Enable HTTP/2
listen 443 ssl http2;

# Enable keepalive
keepalive_timeout 65;
keepalive_requests 100;
```

### SSL Optimization
```nginx
# SSL session cache
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;

# OCSP stapling
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
```

## Next Steps

After SSL setup, proceed to:
1. `../6_backup_scripts/` - Setup backup automation
2. `../7_operations/` - Day-to-day operational scripts
3. Test SSL configuration and certificate renewal 