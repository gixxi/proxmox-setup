#!/bin/bash

# Create Workload User Script
# This script creates a dedicated user for workload management with controlled access

set -e

# parameters
username=$1
if [ -z "$username" ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

# Configuration
WORKLOAD_USER="$username"
WORKLOAD_GROUP="$username"
DATA_DIR="/data"
WORKLOAD_HOME="/home/$WORKLOAD_USER"

echo "Creating workload user and group..."

# Create workload group
groupadd -f $WORKLOAD_GROUP

# Create workload user
useradd -m -d $WORKLOAD_HOME -s /bin/bash -g $WORKLOAD_GROUP $WORKLOAD_USER || true

# Add user to docker group for Docker access
usermod -a -G docker $WORKLOAD_USER

# Set up SSH directory for workload user
mkdir -p $WORKLOAD_HOME/.ssh
chmod 700 $WORKLOAD_HOME/.ssh
touch $WORKLOAD_HOME/.ssh/authorized_keys
chmod 600 $WORKLOAD_HOME/.ssh/authorized_keys
chown -R $WORKLOAD_USER:$WORKLOAD_GROUP $WORKLOAD_HOME

# Set up data directory permissions
echo "Setting up data directory permissions..."

# Create data subdirectories if they don't exist
mkdir -p $DATA_DIR/{docker,apps,backup,logs}

# Set ownership to root:workload for security
chown root:$WORKLOAD_GROUP $DATA_DIR

# Set permissions: root can read/write, workload group can read/write
chmod 775 $DATA_DIR

# Set up subdirectories with appropriate permissions
chown root:$WORKLOAD_GROUP $DATA_DIR/docker
chmod 775 $DATA_DIR/docker

chown root:$WORKLOAD_GROUP $DATA_DIR/apps
chmod 775 $DATA_DIR/apps

chown root:$WORKLOAD_GROUP $DATA_DIR/backup
chmod 775 $DATA_DIR/backup

chown root:$WORKLOAD_GROUP $DATA_DIR/logs
chmod 775 $DATA_DIR/logs

# Create a .profile for the workload user with helpful aliases
cat > $WORKLOAD_HOME/.profile << 'EOF'
# Workload User Profile
export PATH=$PATH:/usr/local/bin

# Aliases for common operations
alias ll='ls -la'
alias data='cd /data'
alias apps='cd /data/apps'
alias logs='cd /data/logs'
alias backup='cd /data/backup'

# Docker shortcuts
alias d='docker'
alias dc='docker-compose'
alias dps='docker ps'
alias dpsa='docker ps -a'

# ZFS shortcuts
alias zfs='sudo zfs'
alias zpool='sudo zpool'

echo "Welcome to the workload environment!"
echo "Useful directories: /data/apps, /data/logs, /data/backup"
echo "Use 'sudo' for system operations, regular commands for data access"
EOF

chown $WORKLOAD_USER:$WORKLOAD_GROUP $WORKLOAD_HOME/.profile

# Create a README for the workload user
cat > $WORKLOAD_HOME/README.md << 'EOF'
# Workload User Guide

## Overview
This user account is dedicated to managing workloads and applications on this server.

## Access
- **SSH**: Use your SSH key to connect
- **Data Directory**: Full read/write access to `/data` and subdirectories
- **System Operations**: Use `sudo` for system-level operations

## Important Directories
- `/data/apps` - Application data and configurations
- `/data/logs` - Application and system logs
- `/data/backup` - Backup files and archives
- `/data/docker` - Docker volumes and data

## Security Notes
- This user has limited system access for security
- Use `sudo` for system administration tasks
- All data operations are logged
- Regular backups are stored in `/data/backup`

## Useful Commands
```bash
# Check system status
sudo systemctl status

# View logs
tail -f /data/logs/*

# Manage Docker containers
docker ps
docker-compose up -d

# Check ZFS pools
sudo zpool status
```

## Support
For system administration, contact the admin user.
EOF

chown $WORKLOAD_USER:$WORKLOAD_GROUP $WORKLOAD_HOME/README.md

# Set up sudo access for workload user (limited)
cat > /etc/sudoers.d/$WORKLOAD_USER << EOF
# $WORKLOAD_USER sudo access
$WORKLOAD_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl status *, /usr/bin/journalctl *, /usr/bin/docker *, /usr/bin/docker-compose *, /usr/bin/zfs *, /usr/bin/zpool *, /usr/bin/ufw status, /usr/bin/supervisorctl status, /usr/bin/supervisorctl restart *, /usr/bin/supervisorctl stop *, /usr/bin/supervisorctl start *
EOF

chmod 440 /etc/sudoers.d/$WORKLOAD_USER

echo "Workload user setup completed successfully!"
echo "User: $WORKLOAD_USER"
echo "Group: $WORKLOAD_GROUP"
echo "Data directory: $DATA_DIR"
echo "Home directory: $WORKLOAD_HOME"
echo "Docker access: User added to docker group"
echo "Usage: $0 <username>" 