#!/bin/bash

# Cloud-Init Post-Install Script
# This script configures a Debian 12 system after manual installation
# Incorporates functionality from docker-only workflow

set -e

# Configuration
CONFIG_FILE=""
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[HEADER]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 -c <config_file> [options]"
    echo "Options:"
    echo "  -c, --config <file>    Configuration file (required)"
    echo "  -v, --verbose          Verbose output"
    echo "  -h, --help             Show this help"
    echo ""
    echo "Example:"
    echo "  $0 -c cloudinit_config.yaml"
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$CONFIG_FILE" ]]; then
        print_error "Configuration file is required"
        show_usage
        exit 1
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Function to install required packages
install_packages() {
    print_header "Installing required packages"
    
    # Update package list
    apt-get update
    
    # Install essential packages
    apt-get install -y \
        cloud-init \
        yq \
        zfsutils-linux \
        docker.io \
        docker-compose-plugin \
        nginx \
        certbot \
        python3-certbot-nginx \
        ufw \
        rsync \
        curl \
        wget \
        git \
        htop \
        iotop \
        nethogs \
        fail2ban \
        logwatch \
        cron \
        anacron
    
    print_status "Packages installed successfully"
}

# Function to harden SSH
harden_ssh() {
    print_header "Hardening SSH configuration"
    
    SSH_CONFIG="/etc/ssh/sshd_config"
    ALLOWED_USERS=$(yq e '.users[].name' "$CONFIG_FILE" | tr '\n' ' ')
    
    # Create backup
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="${SSH_CONFIG}.backup.${TIMESTAMP}"
    cp "${SSH_CONFIG}" "${BACKUP_FILE}"
    print_status "SSH config backed up to ${BACKUP_FILE}"
    
    # Create hardened SSH configuration
    cat > "${SSH_CONFIG}" << EOF
# SSH Configuration hardened on $(date)
# Original file backed up at ${BACKUP_FILE}

# Basic SSH settings
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication settings
LoginGraceTime 30
PermitRootLogin no
StrictModes yes
MaxAuthTries 3
MaxSessions 10

# Key-based authentication
PubkeyAuthentication yes
AuthorizedKeysFile %h/.ssh/authorized_keys

# Disable password authentication
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Disable legacy authentication methods
RhostsRSAAuthentication no
HostbasedAuthentication no

# User restrictions
AllowUsers ${ALLOWED_USERS}
DenyUsers root

# Connection settings
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive yes

# Logging
SyslogFacility AUTH
LogLevel INFO

# Security settings
X11Forwarding no
AllowTcpForwarding no
GatewayPorts no
PermitTunnel no
PrintMotd no
PrintLastLog yes
IgnoreRhosts yes
EOF
    
    # Validate and reload SSH
    if sshd -t; then
        systemctl reload ssh
        print_status "SSH configuration hardened successfully"
    else
        print_error "SSH configuration is invalid, restoring backup"
        cp "${BACKUP_FILE}" "${SSH_CONFIG}"
        systemctl reload ssh
        exit 1
    fi
}

# Function to create users
create_users() {
    print_header "Creating users"
    
    local user_count=$(yq e '.users | length' "$CONFIG_FILE")
    
    for ((i=0; i<$user_count; i++)); do
        local username=$(yq e ".users[$i].name" "$CONFIG_FILE")
        local sudo_access=$(yq e ".users[$i].sudo // false" "$CONFIG_FILE")
        local ssh_keys=$(yq e ".users[$i].ssh_authorized_keys // []" "$CONFIG_FILE")
        
        print_status "Creating user: $username"
        
        # Create user if it doesn't exist
        if ! id "$username" &>/dev/null; then
            useradd -m -s /bin/bash "$username"
            print_status "User $username created"
        else
            print_status "User $username already exists"
        fi
        
        # Add to workload group
        usermod -a -G workload "$username"
        
        # Add to docker group
        usermod -a -G docker "$username"
        
        # Configure sudo access
        if [[ "$sudo_access" == "true" ]]; then
            echo "$username ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$username"
            print_status "Sudo access granted to $username"
        fi
        
        # Configure SSH keys
        if [[ "$ssh_keys" != "[]" ]]; then
            mkdir -p "/home/$username/.ssh"
            chmod 700 "/home/$username/.ssh"
            
            # Add each SSH key
            local key_count=$(echo "$ssh_keys" | yq e 'length' -)
            for ((j=0; j<$key_count; j++)); do
                local key=$(echo "$ssh_keys" | yq e ".[$j]" -)
                echo "$key" >> "/home/$username/.ssh/authorized_keys"
            done
            
            chmod 600 "/home/$username/.ssh/authorized_keys"
            chown -R "$username:$username" "/home/$username/.ssh"
            print_status "SSH keys configured for $username"
        fi
    done
    
    # Create workload group if it doesn't exist
    if ! getent group workload >/dev/null 2>&1; then
        groupadd workload
        print_status "Created workload group"
    fi
    
    # Create docker group if it doesn't exist
    if ! getent group docker >/dev/null 2>&1; then
        groupadd docker
        print_status "Created docker group"
    fi
}

# Function to configure ZFS storage
configure_zfs() {
    print_header "Configuring ZFS storage"
    
    local pool_name=$(yq e '.zfs.pool_name' "$CONFIG_FILE")
    local mode=$(yq e '.zfs.mode' "$CONFIG_FILE")
    local devices=$(yq e '.zfs.devices[]' "$CONFIG_FILE")
    
    # Check if pool already exists
    if zpool list "$pool_name" >/dev/null 2>&1; then
        print_status "ZFS pool $pool_name already exists"
        return
    fi
    
    # Create ZFS pool
    local zpool_cmd="zpool create $pool_name $mode"
    for device in $devices; do
        zpool_cmd="$zpool_cmd $device"
    done
    
    print_status "Creating ZFS pool: $zpool_cmd"
    eval "$zpool_cmd"
    
    # Create datasets
    local datasets=("apps" "logs" "backup" "docker" "nginx" "supervisor")
    for dataset in "${datasets[@]}"; do
        if ! zfs list "$pool_name/$dataset" >/dev/null 2>&1; then
            zfs create "$pool_name/$dataset"
            print_status "Created dataset: $pool_name/$dataset"
        fi
    done
    
    # Configure ZFS properties
    zfs set compression=lz4 "$pool_name"
    zfs set atime=off "$pool_name"
    
    # Set specific properties for different datasets
    zfs set recordsize=128K "$pool_name/docker"
    zfs set recordsize=8K "$pool_name/nginx"
    zfs set recordsize=8K "$pool_name/supervisor"
    
    print_status "ZFS storage configured successfully"
}

# Function to configure networking
configure_networking() {
    print_header "Configuring networking"
    
    local interface_count=$(yq e '.network.interfaces | length' "$CONFIG_FILE")
    
    for ((i=0; i<$interface_count; i++)); do
        local name=$(yq e ".network.interfaces[$i].name" "$CONFIG_FILE")
        local dhcp=$(yq e ".network.interfaces[$i].dhcp // false" "$CONFIG_FILE")
        
        if [[ "$dhcp" == "true" ]]; then
            # DHCP configuration
            cat > "/etc/network/interfaces.d/$name" << EOF
auto $name
iface $name inet dhcp
EOF
            print_status "Configured $name for DHCP"
        else
            # Static configuration
            local address=$(yq e ".network.interfaces[$i].address" "$CONFIG_FILE")
            local gateway=$(yq e ".network.interfaces[$i].gateway" "$CONFIG_FILE")
            local dns_servers=$(yq e ".network.interfaces[$i].dns // []" "$CONFIG_FILE")
            
            cat > "/etc/network/interfaces.d/$name" << EOF
auto $name
iface $name inet static
    address $address
    gateway $gateway
EOF
            
            # Add DNS servers if specified
            if [[ "$dns_servers" != "[]" ]]; then
                local dns_count=$(echo "$dns_servers" | yq e 'length' -)
                for ((j=0; j<$dns_count; j++)); do
                    local dns=$(echo "$dns_servers" | yq e ".[$j]" -)
                    echo "    dns-nameservers $dns" >> "/etc/network/interfaces.d/$name"
                done
            fi
            
            print_status "Configured $name with static IP: $address"
        fi
    done
    
    # Restart networking
    systemctl restart networking
    print_status "Networking configured and restarted"
}

# Function to configure Docker
configure_docker() {
    print_header "Configuring Docker"
    
    # Start and enable Docker service
    systemctl enable docker
    systemctl start docker
    
    # Configure Docker daemon
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
  "storage-driver": "overlay2",
  "data-root": "/data/docker",
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
  },
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false,
  "metrics-addr": "127.0.0.1:9323"
}
EOF
    
    # Restart Docker to apply configuration
    systemctl restart docker
    
    print_status "Docker configured successfully"
}

# Function to setup backup scripts
setup_backup_scripts() {
    print_header "Setting up backup scripts"
    
    mkdir -p /opt/scripts/backup
    
    # Create ZFS snapshot backup script
    cat > /opt/scripts/backup/backup_zfs_snapshots.sh << 'EOF'
#!/bin/bash
# ZFS Snapshot Backup Script

set -e

DATASET="data"
SNAPSHOT_NAME="daily_$(date +%Y%m%d_%H%M%S)"

# Create snapshot
zfs snapshot $DATASET@$SNAPSHOT_NAME
echo "Created snapshot: $DATASET@$SNAPSHOT_NAME"

# Clean up old snapshots (keep last 7 daily, 4 weekly, 12 monthly)
zfs list -t snapshot -o name,creation | grep "$DATASET@daily_" | head -n -7 | awk '{print $1}' | xargs -r zfs destroy
zfs list -t snapshot -o name,creation | grep "$DATASET@weekly_" | head -n -4 | awk '{print $1}' | xargs -r zfs destroy
zfs list -t snapshot -o name,creation | grep "$DATASET@monthly_" | head -n -12 | awk '{print $1}' | xargs -r zfs destroy
EOF
    
    # Create Docker volume backup script
    cat > /opt/scripts/backup/backup_docker_volumes.sh << 'EOF'
#!/bin/bash
# Docker Volume Backup Script

set -e

VOLUME_NAME="$1"
BACKUP_DIR="/backup/docker-back"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [[ -z "$VOLUME_NAME" ]]; then
    echo "Usage: $0 <volume_name>"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup volume
docker run --rm \
  -v $VOLUME_NAME:/data \
  -v $BACKUP_DIR:/backup \
  alpine tar czf /backup/${VOLUME_NAME}_${TIMESTAMP}.tar.gz /data

echo "Backed up volume $VOLUME_NAME to ${VOLUME_NAME}_${TIMESTAMP}.tar.gz"

# Clean up old backups (keep last 30)
find "$BACKUP_DIR" -name "${VOLUME_NAME}_*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | head -n -30 | awk '{print $2}' | xargs -r rm -f
EOF
    
    # Create master backup script
    cat > /opt/scripts/backup/backup_all.sh << 'EOF'
#!/bin/bash
# Master Backup Script

set -e

BACKUP_TYPE="${1:-daily}"

case "$BACKUP_TYPE" in
    daily)
        /opt/scripts/backup/backup_zfs_snapshots.sh
        ;;
    weekly)
        /opt/scripts/backup/backup_zfs_snapshots.sh
        # Add weekly specific backups here
        ;;
    monthly)
        /opt/scripts/backup/backup_zfs_snapshots.sh
        # Add monthly specific backups here
        ;;
    *)
        echo "Usage: $0 [daily|weekly|monthly]"
        exit 1
        ;;
esac
EOF
    
    # Make scripts executable
    chmod +x /opt/scripts/backup/*.sh
    
    # Setup cron jobs
    cat > /etc/cron.d/backup-scripts << EOF
# Daily backups at 2:00 AM
0 2 * * * root /opt/scripts/backup/backup_all.sh daily

# Weekly backups at 3:00 AM on Sunday
0 3 * * 0 root /opt/scripts/backup/backup_all.sh weekly

# Monthly backups at 4:00 AM on 1st of month
0 4 1 * * root /opt/scripts/backup/backup_all.sh monthly
EOF
    
    print_status "Backup scripts configured successfully"
}

# Function to setup operations scripts
setup_operations_scripts() {
    print_header "Setting up operations scripts"
    
    mkdir -p /opt/scripts/operations
    
    # Create system health check script
    cat > /opt/scripts/operations/system_health_check.sh << 'EOF'
#!/bin/bash
# System Health Check Script

set -e

echo "=== System Health Report - $(date) ==="

# Check CPU usage
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
echo "CPU Usage: ${CPU_USAGE}%"

# Check memory usage
MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.2f", $3/$2 * 100.0)}')
echo "Memory Usage: ${MEMORY_USAGE}%"

# Check disk usage
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
echo "Disk Usage: ${DISK_USAGE}%"

# Check Docker status
DOCKER_STATUS=$(systemctl is-active docker)
echo "Docker Status: ${DOCKER_STATUS}"

# Check ZFS pool status
echo "ZFS Pool Status:"
zpool status

# Check running containers
echo "Running Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check system load
echo "System Load:"
uptime

# Check network interfaces
echo "Network Interfaces:"
ip addr show | grep -E "^[0-9]+:|inet " | grep -v "127.0.0.1"
EOF
    
    # Create Docker management script
    cat > /opt/scripts/operations/docker_management.sh << 'EOF'
#!/bin/bash
# Docker Management Script

set -e

ACTION="$1"

case "$ACTION" in
    list)
        echo "=== Docker Containers ==="
        docker ps -a
        echo ""
        echo "=== Docker Images ==="
        docker images
        echo ""
        echo "=== Docker Volumes ==="
        docker volume ls
        ;;
    update)
        echo "Updating Docker images..."
        docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>" | xargs -r docker pull
        ;;
    cleanup)
        echo "Cleaning up unused Docker resources..."
        docker system prune -f
        docker volume prune -f
        ;;
    restart)
        echo "Restarting Docker service..."
        systemctl restart docker
        ;;
    *)
        echo "Usage: $0 [list|update|cleanup|restart]"
        exit 1
        ;;
esac
EOF
    
    # Create storage management script
    cat > /opt/scripts/operations/storage_management.sh << 'EOF'
#!/bin/bash
# Storage Management Script

set -e

ACTION="$1"

case "$ACTION" in
    status)
        echo "=== ZFS Pool Status ==="
        zpool status
        echo ""
        echo "=== ZFS Dataset Usage ==="
        zfs list -o name,used,avail,refer,mountpoint
        ;;
    snapshot)
        echo "Creating ZFS snapshots..."
        zfs snapshot data@manual_$(date +%Y%m%d_%H%M%S)
        ;;
    cleanup-snapshots)
        echo "Cleaning up old snapshots..."
        zfs list -t snapshot -o name,creation | grep "data@daily_" | head -n -7 | awk '{print $1}' | xargs -r zfs destroy
        ;;
    *)
        echo "Usage: $0 [status|snapshot|cleanup-snapshots]"
        exit 1
        ;;
esac
EOF
    
    # Make scripts executable
    chmod +x /opt/scripts/operations/*.sh
    
    print_status "Operations scripts configured successfully"
}

# Function to configure firewall
configure_firewall() {
    print_header "Configuring firewall"
    
    # Reset UFW to defaults
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow ssh
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Enable UFW
    ufw --force enable
    
    print_status "Firewall configured successfully"
}

# Function to setup monitoring
setup_monitoring() {
    print_header "Setting up monitoring"
    
    # Configure fail2ban
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF
    
    # Enable and start fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
    
    # Setup logwatch
    cat > /etc/logwatch/conf/logwatch.conf << EOF
LogDir = /var/log
TmpDir = /var/cache/logwatch
Output = mail
Format = html
MailTo = root
Range = yesterday
Detail = Low
Service = All
EOF
    
    print_status "Monitoring configured successfully"
}

# Function to create symlinks for configs
create_config_symlinks() {
    print_header "Creating config symlinks"
    
    # Create symlinks for nginx and supervisor configs
    if [[ -d "/etc/nginx" ]] && [[ ! -L "/etc/nginx" ]]; then
        # Backup existing config
        mv /etc/nginx /etc/nginx.backup
        ln -s /data/nginx /etc/nginx
        # Copy configs if backup exists
        if [[ -d "/etc/nginx.backup" ]]; then
            cp -r /etc/nginx.backup/* /data/nginx/
        fi
        print_status "Nginx config symlinked to /data/nginx"
    fi
    
    if [[ -d "/etc/supervisor" ]] && [[ ! -L "/etc/supervisor" ]]; then
        # Backup existing config
        mv /etc/supervisor /etc/supervisor.backup
        ln -s /data/supervisor /etc/supervisor
        # Copy configs if backup exists
        if [[ -d "/etc/supervisor.backup" ]]; then
            cp -r /etc/supervisor.backup/* /data/supervisor/
        fi
        print_status "Supervisor config symlinked to /data/supervisor"
    fi
}

# Function to setup sudoers for workload group
setup_sudoers() {
    print_header "Setting up sudoers for workload group"
    
    cat > /etc/sudoers.d/workload << 'EOF'
# Allow workload group to use supervisorctl and nginx without password
%workload ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl
%workload ALL=(ALL) NOPASSWD: /bin/systemctl reload nginx
%workload ALL=(ALL) NOPASSWD: /bin/systemctl restart nginx
%workload ALL=(ALL) NOPASSWD: /bin/systemctl status nginx
%workload ALL=(ALL) NOPASSWD: /usr/bin/docker
%workload ALL=(ALL) NOPASSWD: /usr/local/bin/docker-compose
EOF
    
    print_status "Sudoers configured for workload group"
}

# Function to apply cloud-init config
apply_cloud_init_config() {
    print_header "Applying cloud-init configuration"
    
    # Check if cloud-init config section exists
    if yq e '.cloud_init' "$CONFIG_FILE" >/dev/null 2>&1; then
        local cloud_init_config=$(yq e '.cloud_init' "$CONFIG_FILE")
        echo "$cloud_init_config" > /etc/cloud/cloud.cfg.d/99-custom.cfg
        print_status "Cloud-init configuration applied"
    else
        print_status "No cloud-init configuration found, skipping"
    fi
}

# Function to finalize setup
finalize_setup() {
    print_header "Finalizing setup"
    
    # Update system
    apt-get update && apt-get upgrade -y
    
    # Clean up
    apt-get autoremove -y
    apt-get autoclean
    
    # Set proper permissions on ZFS datasets
    chown -R root:workload /data/apps
    chown -R root:workload /data/logs
    chown -R root:workload /data/backup
    chown -R root:docker /data/docker
    chown -R root:workload /data/nginx
    chown -R root:workload /data/supervisor
    
    chmod 775 /data/apps
    chmod 775 /data/logs
    chmod 775 /data/backup
    chmod 775 /data/docker
    chmod 775 /data/nginx
    chmod 775 /data/supervisor
    
    print_status "Setup finalized successfully"
}

# Main execution
main() {
    print_header "Starting Cloud-Init Post-Install Configuration"
    
    # Parse arguments
    parse_args "$@"
    
    # Check if running as root
    check_root
    
    # Install required packages
    install_packages
    
    # Create users
    create_users
    
    # Configure ZFS storage
    configure_zfs
    
    # Configure networking
    configure_networking
    
    # Configure Docker
    configure_docker
    
    # Setup backup scripts
    setup_backup_scripts
    
    # Setup operations scripts
    setup_operations_scripts
    
    # Configure firewall
    configure_firewall
    
    # Setup monitoring
    setup_monitoring
    
    # Create config symlinks
    create_config_symlinks
    
    # Setup sudoers
    setup_sudoers
    
    # Harden SSH (do this last to avoid locking out)
    harden_ssh
    
    # Apply cloud-init config
    apply_cloud_init_config
    
    # Finalize setup
    finalize_setup
    
    print_header "Cloud-Init Post-Install Configuration Complete!"
    print_status "System is now ready for Docker-based workloads"
    print_status "Users can now SSH in and use Docker without sudo"
    print_status "Backup scripts are configured and scheduled"
    print_status "Operations scripts are available in /opt/scripts/operations/"
    
    echo ""
    print_warning "IMPORTANT: Test SSH access from another terminal before logging out!"
    print_warning "SSH is now hardened - only key-based authentication is allowed"
}

# Run main function with all arguments
main "$@" 