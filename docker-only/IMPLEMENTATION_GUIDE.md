# Docker-Only Infrastructure Implementation Guide

This guide provides a step-by-step implementation plan for setting up a Docker-based infrastructure on Debian 12, as an alternative to Proxmox virtualization.

## Quick Start

### Prerequisites
- Debian 12 minimal installation
- At least 2 network interfaces
- 4+ additional disks for ZFS pools
- Synology NAS with NFS export
- Domain DNS configuration

### Implementation Order
1. **Host Setup** → 2. **Network Config** → 3. **Docker Install** → 4. **Storage Setup** → 5. **SSL Setup** → 6. **Backup Scripts** → 7. **Operations**

## Phase 1: Host Setup

### 1.1 Install Debian 12
```bash
# Download Debian 12 netinst ISO
# Boot from USB and install with minimal configuration
# Choose: LVM partitioning, minimal installation
```

### 1.2 Create Non-Root User
```bash
# Run as root
./1_host_setup/create_non_root_user.sh gix "Your Full Name" "ssh-rsa YOUR_PUBLIC_KEY"
```

### 1.3 Harden SSH Access
```bash
# Run as root
./1_host_setup/harden_ssh.sh gix
```

### 1.4 Test Setup
```bash
# Log out and test SSH access
ssh gix@hostname
# Test Docker access
docker run hello-world
```

## Phase 2: Network Configuration

### 2.1 Detect Network Interfaces
```bash
./2_network_config/detect_interfaces.sh
```

### 2.2 Configure Dual NIC Setup
```bash
# Edit network configuration based on detected interfaces
# Configure Internet NIC (DHCP) and 10Gbit NIC (static IP)
```

### 2.3 Setup NFS Mount
```bash
./2_network_config/setup_nfs_mount.sh
```

### 2.4 Test Network
```bash
./2_network_config/test_network.sh
```

## Phase 3: Docker Installation

### 3.1 Install Docker (if not already done)
```bash
# Docker should already be installed from user setup
# Verify installation
docker --version
docker-compose --version
```

### 3.2 Configure Docker Storage
```bash
# Configure Docker to use ZFS storage
# This will be done in Phase 4
```

## Phase 4: Storage Setup

### 4.1 Detect Available Disks
```bash
./5_storage_setup/detect_disks.sh
```

### 4.2 Create ZFS Pools
```bash
# Create data pool (mirror)
zpool create data mirror /dev/sdb /dev/sdc

# Create backup pool (mirror)
zpool create backup mirror /dev/sdd /dev/sde
```

### 4.3 Setup Mount Points
```bash
./5_storage_setup/setup_mount_points.sh
```

### 4.4 Configure Docker Storage
```bash
./5_storage_setup/configure_docker_storage.sh
```

## Phase 5: SSL Setup

### 5.1 Install Nginx and Certbot
```bash
./4_ssl_setup/install_nginx.sh
./4_ssl_setup/install_certbot.sh
```

### 5.2 Create SSL Certificate
```bash
# Replace with your hostname
./4_ssl_setup/create_ssl_certificate.sh your-hostname.planet-rocklog.com
```

### 5.3 Setup Auto-Renewal
```bash
./4_ssl_setup/setup_auto_renewal.sh
```

### 5.4 Configure Nginx Proxy
```bash
./4_ssl_setup/configure_nginx_proxy.sh
```

## Phase 6: Backup Scripts

### 6.1 Setup Backup Directories
```bash
mkdir -p /backup/{snapshots,docker-back,nfs-back}
```

### 6.2 Configure Backup Scripts
```bash
# Edit backup scripts with your specific paths
# Configure retention policies
```

### 6.3 Setup Cron Jobs
```bash
# Add to /etc/cron.d/docker-backups
0 2 * * * root /opt/scripts/backup_all.sh daily
0 3 * * 0 root /opt/scripts/backup_all.sh weekly
```

## Phase 7: Operations

### 7.1 Setup Monitoring Scripts
```bash
# Copy operation scripts to /opt/scripts/
sudo cp 7_operations/*.sh /opt/scripts/
sudo chmod +x /opt/scripts/*.sh
```

### 7.2 Configure Systemd Services
```bash
# Setup monitoring services
sudo systemctl enable docker-monitor.service
```

### 7.3 Test Operations
```bash
# Test health check
/opt/scripts/system_health_check.sh

# Test Docker management
/opt/scripts/docker_management.sh list
```

## Configuration Examples

### Docker Compose Example
```yaml
# docker-compose.yml
version: '3.8'

services:
  app:
    image: your-app:latest
    container_name: your-app
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - /data/docker/volumes/app-data:/app/data
      - /mnt/nas/shared-data:/app/shared
    environment:
      - NODE_ENV=production
    networks:
      - app-network

  nginx:
    image: nginx:alpine
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /data/docker/configs/nginx:/etc/nginx/conf.d
      - /etc/letsencrypt:/etc/letsencrypt:ro
    depends_on:
      - app

networks:
  app-network:
    driver: bridge
```

### Nginx Configuration Example
```nginx
# /data/docker/configs/nginx/app.conf
server {
    listen 80;
    server_name your-hostname.planet-rocklog.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-hostname.planet-rocklog.com;
    
    ssl_certificate /etc/letsencrypt/live/your-hostname.planet-rocklog.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-hostname.planet-rocklog.com/privkey.pem;
    
    location / {
        proxy_pass http://app:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Monitoring and Maintenance

### Daily Tasks
- Check system health: `/opt/scripts/system_health_check.sh`
- Monitor logs: `tail -f /var/log/syslog`
- Check Docker status: `docker ps`

### Weekly Tasks
- Update system: `/opt/scripts/update_system.sh --weekly`
- Verify backups: `/opt/scripts/verify_backups.sh`
- Clean up old snapshots: `/opt/scripts/cleanup_old_backups.sh`

### Monthly Tasks
- Security audit: `/opt/scripts/security_audit.sh`
- Performance analysis: `/opt/scripts/performance_analysis.sh`
- Capacity planning: `/opt/scripts/capacity_planning.sh`

## Troubleshooting

### Common Issues

#### 1. Docker Container Won't Start
```bash
# Check container logs
docker logs container_name

# Check resource limits
docker stats

# Check volume permissions
ls -la /data/docker/volumes/
```

#### 2. SSL Certificate Issues
```bash
# Check certificate status
certbot certificates

# Test renewal
certbot renew --dry-run

# Check Nginx configuration
nginx -t
```

#### 3. ZFS Pool Issues
```bash
# Check pool status
zpool status

# Check dataset usage
zfs list

# Import pool if needed
zpool import -f data
```

#### 4. NFS Mount Issues
```bash
# Check NFS mount
mount | grep nfs

# Test NFS connectivity
showmount -e nas_ip

# Remount if needed
sudo mount -a
```

### Emergency Procedures

#### 1. Emergency Restore
```bash
# Restore from latest backup
/opt/scripts/emergency_restore.sh --latest

# Restore specific backup
/opt/scripts/emergency_restore.sh --backup 20231201_020000
```

#### 2. Maintenance Mode
```bash
# Enable maintenance mode
/opt/scripts/maintenance_mode.sh --enable

# Disable maintenance mode
/opt/scripts/maintenance_mode.sh --disable
```

## Performance Optimization

### Docker Optimization
```bash
# Optimize Docker daemon
cat > /etc/docker/daemon.json << EOF
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Hard": 64000,
      "Name": "nofile",
      "Soft": 64000
    }
  }
}
EOF
```

### ZFS Optimization
```bash
# Enable compression
zfs set compression=lz4 data
zfs set compression=lz4 backup

# Set ashift for SSD
zpool create -o ashift=12 data mirror /dev/sdb /dev/sdc
```

### System Optimization
```bash
# Optimize system settings
echo 'vm.swappiness=10' >> /etc/sysctl.conf
echo 'net.core.rmem_max=16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_max=16777216' >> /etc/sysctl.conf
sysctl -p
```

## Security Considerations

### Access Control
- Use SSH keys only (no password authentication)
- Restrict sudo access to necessary commands
- Regular security updates
- Monitor access logs

### Network Security
- Separate networks for different purposes
- Firewall rules for Docker containers
- SSL/TLS for all external communication
- Regular security audits

### Data Security
- Encrypt sensitive data
- Regular backups with verification
- Access control on backup data
- Offsite backup for critical data

## Migration from Proxmox

### Benefits of Docker-Only Approach
- **Lower overhead**: Near-native performance
- **Resource efficiency**: Better utilization
- **Simpler management**: Docker Compose orchestration
- **Cost effective**: Reduced hardware requirements
- **Rapid deployment**: Container-based applications

### Migration Steps
1. **Assessment**: Identify containerizable workloads
2. **Testing**: Test Docker versions of applications
3. **Data migration**: Migrate data to ZFS/NFS storage
4. **Application deployment**: Deploy with Docker Compose
5. **Validation**: Test functionality and performance
6. **Cutover**: Switch from Proxmox to Docker

## Next Steps

After implementation:
1. **Monitoring**: Set up comprehensive monitoring
2. **Alerting**: Configure alerts for critical issues
3. **Documentation**: Create runbooks for common tasks
4. **Testing**: Regular backup and restore testing
5. **Optimization**: Continuous performance tuning

## Support and Resources

### Documentation
- [Docker Documentation](https://docs.docker.com/)
- [ZFS Documentation](https://openzfs.github.io/openzfs-docs/)
- [Nginx Documentation](https://nginx.org/en/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)

### Community
- Docker Community Forums
- ZFS Community
- Debian Community

### Tools
- Docker Compose
- ZFS utilities
- Nginx
- Certbot
- Monitoring tools (Prometheus, Grafana) 