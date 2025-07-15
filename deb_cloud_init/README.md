# Debian Post-Install Cloud-Init Style Configuration

This approach lets you install Debian 12 manually (using the official installer), then run a single script to configure a complete Docker-based infrastructure with:
- SSH hardening and user management
- Docker and Docker Compose installation
- ZFS storage configuration with datasets
- Network configuration (static or DHCP)
- Backup automation with ZFS snapshots
- Operations and monitoring scripts
- Firewall and security hardening
- Nginx and SSL setup preparation

## Quick Start

1. **Install Debian 12 manually** (set up root password, boot drive, etc.)
2. **Copy the following files to your new system:**
   - `cloudinit_postinstall.sh` (main script)
   - `cloudinit_config.yaml` (your configuration)
3. **Install yq if needed:**
   ```bash
   sudo apt-get install -y yq
   ```
4. **Run the script as root:**
   ```bash
   sudo bash cloudinit_postinstall.sh -c cloudinit_config.yaml
   ```

## Configuration File Example (`cloudinit_config.yaml`)

```yaml
# User management
users:
  - name: myapp
    ssh_authorized_keys:
      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@host"
    sudo: true
  - name: anotheruser
    ssh_authorized_keys:
      - "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user2@host"
    sudo: false

# ZFS storage configuration
zfs:
  pool_name: data
  mode: mirror
  devices:
    - /dev/nvme0n1
    - /dev/nvme1n1

# Network configuration
network:
  interfaces:
    - name: enp1s0
      address: 192.168.1.100/24
      gateway: 192.168.1.1
      dns:
        - 1.1.1.1
        - 8.8.8.8
    - name: enp2s0
      dhcp: true

# Docker configuration
docker:
  data_root: /data/docker
  storage_driver: overlay2
  log_max_size: 10m
  log_max_files: 3

# Backup configuration
backup:
  zfs_snapshots:
    daily_retention: 7
    weekly_retention: 4
    monthly_retention: 12
  docker_volumes:
    retention_days: 30
  schedule:
    daily_time: "02:00"
    weekly_time: "03:00"
    monthly_time: "04:00"

# Monitoring configuration
monitoring:
  fail2ban:
    enabled: true
    bantime: 3600
    findtime: 600
    maxretry: 3
  logwatch:
    enabled: true
    output: mail
    detail: Low

# Firewall configuration
firewall:
  allow_ports:
    - 22    # SSH
    - 80    # HTTP
    - 443   # HTTPS
  default_policy: deny_incoming
```

## What the Script Does

### 1. Package Installation
- Installs `cloud-init`, `yq`, `zfsutils-linux`, `docker.io`, `docker-compose-plugin`
- Installs `nginx`, `certbot`, `ufw`, `fail2ban`, `logwatch`, and other utilities
- Updates system packages

### 2. User Management
- Creates specified users with SSH keys
- Adds users to `workload` and `docker` groups
- Configures sudo access as specified
- Updates `/etc/ssh/sshd_config` with `AllowUsers`

### 3. SSH Hardening
- Disables root login and password authentication
- Enables key-based authentication only
- Sets secure connection timeouts
- Disables X11 forwarding and port forwarding
- Creates backup of original SSH config

### 4. ZFS Storage Setup
- Creates ZFS pool with specified devices and mode
- Creates datasets: `/data/apps`, `/data/logs`, `/data/backup`, `/data/docker`, `/data/nginx`, `/data/supervisor`
- Configures ZFS properties for performance (compression, recordsize, atime)
- Sets proper ownership and permissions

### 5. Docker Configuration
- Installs Docker Engine and Docker Compose plugin
- Configures Docker daemon to use ZFS storage
- Sets up proper permissions for non-root Docker usage
- Configures log rotation and resource limits

### 6. Network Configuration
- Configures network interfaces via `/etc/network/interfaces.d/`
- Supports both static IP and DHCP configurations
- Restarts networking service

### 7. Backup Automation
- Creates ZFS snapshot backup scripts
- Creates Docker volume backup scripts
- Sets up cron jobs for daily/weekly/monthly backups
- Implements retention policies

### 8. Operations Scripts
- System health monitoring script
- Docker management script (list, update, cleanup, restart)
- Storage management script (status, snapshot, cleanup)
- All scripts located in `/opt/scripts/operations/`

### 9. Security Hardening
- Configures UFW firewall with default deny incoming
- Sets up fail2ban for SSH protection
- Configures logwatch for system monitoring
- Creates sudoers rules for workload group

### 10. Configuration Symlinks
- Symlinks `/etc/nginx` to `/data/nginx`
- Symlinks `/etc/supervisor` to `/data/supervisor`
- Preserves existing configs if present

## Directory Structure After Installation

```
/data/
├── apps/          # Application data
├── logs/          # Log files
├── backup/        # Backup data
├── docker/        # Docker data root
│   ├── volumes/   # Docker volumes
│   └── configs/   # Docker configs
├── nginx/         # Nginx configuration
└── supervisor/    # Supervisor configuration

/opt/scripts/
├── backup/        # Backup scripts
│   ├── backup_zfs_snapshots.sh
│   ├── backup_docker_volumes.sh
│   └── backup_all.sh
└── operations/    # Operations scripts
    ├── system_health_check.sh
    ├── docker_management.sh
    └── storage_management.sh
```

## Usage Examples

### Basic Usage
```bash
# Run with default configuration
sudo bash cloudinit_postinstall.sh -c cloudinit_config.yaml

# Run with verbose output
sudo bash cloudinit_postinstall.sh -c cloudinit_config.yaml -v
```

### Post-Installation Operations

#### System Health Check
```bash
/opt/scripts/operations/system_health_check.sh
```

#### Docker Management
```bash
# List all containers, images, and volumes
/opt/scripts/operations/docker_management.sh list

# Update all Docker images
/opt/scripts/operations/docker_management.sh update

# Clean up unused Docker resources
/opt/scripts/operations/docker_management.sh cleanup
```

#### Storage Management
```bash
# Check ZFS pool and dataset status
/opt/scripts/operations/storage_management.sh status

# Create manual ZFS snapshot
/opt/scripts/operations/storage_management.sh snapshot

# Clean up old snapshots
/opt/scripts/operations/storage_management.sh cleanup-snapshots
```

#### Backup Operations
```bash
# Run daily backup
/opt/scripts/backup/backup_all.sh daily

# Backup specific Docker volume
/opt/scripts/backup/backup_docker_volumes.sh myapp_data
```

## Security Features

### SSH Security
- Key-based authentication only
- Root login disabled
- Connection timeouts and limits
- User restrictions via `AllowUsers`

### Firewall Configuration
- Default deny incoming policy
- Only essential ports open (SSH, HTTP, HTTPS)
- UFW-based configuration

### User Permissions
- Non-root users can use Docker without sudo
- Workload group has limited sudo access
- Proper file permissions on ZFS datasets

### Monitoring
- fail2ban protection against brute force attacks
- logwatch for system monitoring
- Automated backup verification

## Backup Strategy

### ZFS Snapshots
- **Daily**: 7 snapshots retained
- **Weekly**: 4 snapshots retained  
- **Monthly**: 12 snapshots retained
- **Location**: Backup pool with timestamped names

### Docker Volume Backups
- **Frequency**: Before major updates, weekly
- **Method**: tar.gz archives
- **Retention**: 30 days
- **Location**: `/backup/docker-back/`

### Automated Scheduling
- Daily backups at 2:00 AM
- Weekly backups at 3:00 AM on Sunday
- Monthly backups at 4:00 AM on 1st of month

## Troubleshooting

### SSH Access Issues
```bash
# Check SSH configuration
sshd -t

# View SSH logs
tail -f /var/log/auth.log

# Restore SSH backup if needed
cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config
systemctl reload ssh
```

### Docker Issues
```bash
# Check Docker status
systemctl status docker

# Check Docker daemon configuration
cat /etc/docker/daemon.json

# Restart Docker
systemctl restart docker
```

### ZFS Issues
```bash
# Check ZFS pool status
zpool status

# Check ZFS datasets
zfs list

# Check ZFS mount points
zfs get mountpoint
```

### Network Issues
```bash
# Check network interfaces
ip addr show

# Check network configuration
cat /etc/network/interfaces.d/*

# Restart networking
systemctl restart networking
```

## Extending the Configuration

### Adding More Users
```yaml
users:
  - name: existinguser
    ssh_authorized_keys:
      - "ssh-key..."
    sudo: true
  - name: newuser
    ssh_authorized_keys:
      - "ssh-key..."
    sudo: false
```

### Adding More ZFS Pools
```yaml
zfs:
  pool_name: data
  mode: mirror
  devices:
    - /dev/nvme0n1
    - /dev/nvme1n1
  # Add additional pools as needed
```

### Custom Backup Retention
```yaml
backup:
  zfs_snapshots:
    daily_retention: 14    # Keep 14 daily snapshots
    weekly_retention: 8    # Keep 8 weekly snapshots
    monthly_retention: 24  # Keep 24 monthly snapshots
```

## Requirements

### Hardware Requirements
- **CPU**: x86_64 architecture
- **RAM**: Minimum 4GB (8GB recommended)
- **Storage**: At least 2 drives for ZFS mirror
- **Network**: At least 1 network interface

### Software Requirements
- **OS**: Debian 12 (Bookworm)
- **Boot**: UEFI or legacy BIOS
- **Network**: Internet connectivity for package installation

### Prerequisites
- Manual Debian 12 installation completed
- Root access to the system
- SSH keys for user authentication
- Knowledge of network configuration

## Support

For issues and questions:
1. Check the script output for error messages
2. Review system logs: `/var/log/syslog`, `/var/log/auth.log`
3. Verify configuration file syntax with `yq eval` command
4. Test with minimal configuration first
5. Ensure SSH key access before running SSH hardening

## License

This project is provided as-is for educational and deployment purposes. 