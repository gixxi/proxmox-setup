#!/bin/bash

# Docker Storage Configuration Script
# This script configures Docker to use ZFS storage for volumes and data

set -e

# Configuration
DOCKER_DATA_DIR="/data/docker"
DOCKER_CONFIG_DIR="/data/docker/configs"
DOCKER_VOLUMES_DIR="/data/docker/volumes"
BACKUP_DIR="/backup/docker-back"
DOCKER_DAEMON_CONFIG="/etc/docker/daemon.json"

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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

print_header "Configuring Docker Storage with ZFS"

# Check if ZFS pools exist
if ! zpool list data >/dev/null 2>&1; then
    print_error "ZFS data pool not found. Please create it first:"
    echo "zpool create data mirror /dev/sdb /dev/sdc"
    exit 1
fi

if ! zpool list backup >/dev/null 2>&1; then
    print_error "ZFS backup pool not found. Please create it first:"
    echo "zpool create backup mirror /dev/sdd /dev/sde"
    exit 1
fi

print_status "ZFS pools verified"

# Create Docker directories on ZFS
print_status "Creating Docker directories on ZFS..."

# Create datasets if they don't exist
if ! zfs list data/docker >/dev/null 2>&1; then
    zfs create data/docker
    print_status "Created data/docker dataset"
fi

if ! zfs list data/docker/volumes >/dev/null 2>&1; then
    zfs create data/docker/volumes
    print_status "Created data/docker/volumes dataset"
fi

if ! zfs list data/docker/configs >/dev/null 2>&1; then
    zfs create data/docker/configs
    print_status "Created data/docker/configs dataset"
fi

if ! zfs list backup/docker-back >/dev/null 2>&1; then
    zfs create backup/docker-back
    print_status "Created backup/docker-back dataset"
fi

# Set ZFS properties for performance
print_status "Configuring ZFS properties..."

# Enable compression
zfs set compression=lz4 data/docker
zfs set compression=lz4 data/docker/volumes
zfs set compression=lz4 data/docker/configs
zfs set compression=lz4 backup/docker-back

# Set recordsize for different workloads
zfs set recordsize=128K data/docker/volumes  # Good for general workloads
zfs set recordsize=8K data/docker/configs    # Good for small files

# Enable atime=off for better performance
zfs set atime=off data/docker
zfs set atime=off data/docker/volumes
zfs set atime=off data/docker/configs

print_status "ZFS properties configured"

# Create mount points
print_status "Creating mount points..."

mkdir -p "$DOCKER_DATA_DIR"
mkdir -p "$DOCKER_CONFIG_DIR"
mkdir -p "$DOCKER_VOLUMES_DIR"
mkdir -p "$BACKUP_DIR"

# Set permissions
chown -R root:root "$DOCKER_DATA_DIR"
chmod 755 "$DOCKER_DATA_DIR"

chown -R root:root "$DOCKER_CONFIG_DIR"
chmod 755 "$DOCKER_CONFIG_DIR"

chown -R root:root "$DOCKER_VOLUMES_DIR"
chmod 755 "$DOCKER_VOLUMES_DIR"

chown -R root:root "$BACKUP_DIR"
chmod 755 "$BACKUP_DIR"

print_status "Mount points created and permissions set"

# Configure Docker daemon
print_status "Configuring Docker daemon..."

# Create backup of existing config
if [[ -f "$DOCKER_DAEMON_CONFIG" ]]; then
    cp "$DOCKER_DAEMON_CONFIG" "${DOCKER_DAEMON_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    print_status "Backup created: ${DOCKER_DAEMON_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Create Docker daemon configuration
cat > "$DOCKER_DAEMON_CONFIG" << EOF
{
  "storage-driver": "overlay2",
  "data-root": "$DOCKER_DATA_DIR",
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
  "metrics-addr": "127.0.0.1:9323",
  "insecure-registries": [],
  "registry-mirrors": []
}
EOF

chmod 644 "$DOCKER_DAEMON_CONFIG"
print_status "Docker daemon configuration created"

# Create volume management script
print_status "Creating volume management script..."

VOLUME_MANAGEMENT_SCRIPT="/opt/scripts/manage_docker_volumes.sh"

mkdir -p /opt/scripts

cat > "$VOLUME_MANAGEMENT_SCRIPT" << 'EOF'
#!/bin/bash

# Docker Volume Management Script
# This script manages Docker volumes on ZFS

set -e

VOLUMES_DIR="/data/docker/volumes"
BACKUP_DIR="/backup/docker-back"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

ACTION="$1"
VOLUME_NAME="$2"

case $ACTION in
    "list")
        print_status "Docker volumes on ZFS:"
        echo ""
        echo "Named volumes:"
        docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Mountpoint}}"
        echo ""
        echo "ZFS datasets:"
        zfs list -o name,used,avail,refer,mountpoint data/docker/volumes
        ;;
    "create")
        if [[ -z "$VOLUME_NAME" ]]; then
            print_error "Volume name required"
            echo "Usage: $0 create <volume_name>"
            exit 1
        fi
        
        print_status "Creating volume: $VOLUME_NAME"
        docker volume create "$VOLUME_NAME"
        
        # Create ZFS dataset for the volume
        VOLUME_PATH="$VOLUMES_DIR/$VOLUME_NAME"
        if [[ ! -d "$VOLUME_PATH" ]]; then
            mkdir -p "$VOLUME_PATH"
            print_status "Created directory: $VOLUME_PATH"
        fi
        ;;
    "backup")
        if [[ -z "$VOLUME_NAME" ]]; then
            print_error "Volume name required"
            echo "Usage: $0 backup <volume_name>"
            exit 1
        fi
        
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        BACKUP_FILE="$BACKUP_DIR/${VOLUME_NAME}_${TIMESTAMP}.tar.gz"
        
        print_status "Backing up volume: $VOLUME_NAME"
        
        # Stop containers using this volume
        CONTAINERS=$(docker ps -q --filter volume="$VOLUME_NAME")
        if [[ -n "$CONTAINERS" ]]; then
            print_warning "Stopping containers using volume $VOLUME_NAME"
            docker stop $CONTAINERS
        fi
        
        # Create backup
        docker run --rm \
            -v "$VOLUME_NAME:/data" \
            -v "$BACKUP_DIR:/backup" \
            alpine tar czf "/backup/${VOLUME_NAME}_${TIMESTAMP}.tar.gz" /data
        
        # Start containers
        if [[ -n "$CONTAINERS" ]]; then
            print_status "Starting containers"
            docker start $CONTAINERS
        fi
        
        print_status "Backup created: $BACKUP_FILE"
        ;;
    "restore")
        if [[ -z "$VOLUME_NAME" ]] || [[ -z "$3" ]]; then
            print_error "Volume name and backup file required"
            echo "Usage: $0 restore <volume_name> <backup_file>"
            exit 1
        fi
        
        BACKUP_FILE="$3"
        
        if [[ ! -f "$BACKUP_FILE" ]]; then
            print_error "Backup file not found: $BACKUP_FILE"
            exit 1
        fi
        
        print_status "Restoring volume: $VOLUME_NAME from $BACKUP_FILE"
        
        # Stop containers using this volume
        CONTAINERS=$(docker ps -q --filter volume="$VOLUME_NAME")
        if [[ -n "$CONTAINERS" ]]; then
            print_warning "Stopping containers using volume $VOLUME_NAME"
            docker stop $CONTAINERS
        fi
        
        # Remove existing volume
        docker volume rm "$VOLUME_NAME" 2>/dev/null || true
        
        # Create new volume
        docker volume create "$VOLUME_NAME"
        
        # Restore from backup
        docker run --rm \
            -v "$VOLUME_NAME:/data" \
            -v "$(dirname "$BACKUP_FILE"):/backup" \
            alpine tar xzf "/backup/$(basename "$BACKUP_FILE")" -C /data
        
        # Start containers
        if [[ -n "$CONTAINERS" ]]; then
            print_status "Starting containers"
            docker start $CONTAINERS
        fi
        
        print_status "Volume restored successfully"
        ;;
    "snapshot")
        if [[ -z "$VOLUME_NAME" ]]; then
            print_error "Volume name required"
            echo "Usage: $0 snapshot <volume_name>"
            exit 1
        fi
        
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        SNAPSHOT_NAME="data/docker/volumes@${VOLUME_NAME}_${TIMESTAMP}"
        
        print_status "Creating ZFS snapshot: $SNAPSHOT_NAME"
        zfs snapshot "$SNAPSHOT_NAME"
        print_status "Snapshot created: $SNAPSHOT_NAME"
        ;;
    "cleanup")
        print_status "Cleaning up old backups (older than 30 days)"
        find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete
        print_status "Cleanup completed"
        ;;
    *)
        echo "Usage: $0 {list|create|backup|restore|snapshot|cleanup} [volume_name] [backup_file]"
        echo ""
        echo "Commands:"
        echo "  list                    - List all volumes and ZFS datasets"
        echo "  create <volume_name>    - Create a new volume"
        echo "  backup <volume_name>    - Backup a volume to backup pool"
        echo "  restore <volume_name> <backup_file> - Restore volume from backup"
        echo "  snapshot <volume_name>  - Create ZFS snapshot of volume"
        echo "  cleanup                 - Clean up old backups"
        exit 1
        ;;
esac
EOF

chmod +x "$VOLUME_MANAGEMENT_SCRIPT"
print_status "Volume management script created: $VOLUME_MANAGEMENT_SCRIPT"

# Create backup discovery script
print_status "Creating backup discovery script..."

BACKUP_DISCOVERY_SCRIPT="/opt/scripts/discover_docker_volumes.sh"

cat > "$BACKUP_DISCOVERY_SCRIPT" << 'EOF'
#!/bin/bash

# Docker Volume Discovery Script
# This script discovers Docker volumes for backup procedures

set -e

VOLUMES_DIR="/data/docker/volumes"
BACKUP_DIR="/backup/docker-back"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

ACTION="$1"

case $ACTION in
    "list-volumes")
        print_status "Discovering Docker volumes..."
        echo ""
        
        # List named volumes
        echo "Named Docker volumes:"
        docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Mountpoint}}" | grep -v "DRIVER"
        echo ""
        
        # List bind-mounted volumes
        echo "Bind-mounted volumes in $VOLUMES_DIR:"
        if [[ -d "$VOLUMES_DIR" ]]; then
            find "$VOLUMES_DIR" -maxdepth 1 -type d -name "*" | grep -v "^$VOLUMES_DIR$" | while read -r dir; do
                VOLUME_NAME=$(basename "$dir")
                SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
                echo "  $VOLUME_NAME ($SIZE)"
            done
        fi
        ;;
    "list-backups")
        print_status "Discovering existing backups..."
        echo ""
        
        if [[ -d "$BACKUP_DIR" ]]; then
            echo "Backup files in $BACKUP_DIR:"
            find "$BACKUP_DIR" -name "*.tar.gz" -type f | while read -r backup; do
                SIZE=$(du -sh "$backup" 2>/dev/null | cut -f1)
                DATE=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1)
                echo "  $(basename "$backup") ($SIZE, $DATE)"
            done
        else
            print_warning "Backup directory not found: $BACKUP_DIR"
        fi
        ;;
    "backup-all")
        print_status "Backing up all Docker volumes..."
        echo ""
        
        # Get all named volumes
        VOLUMES=$(docker volume ls -q)
        
        if [[ -z "$VOLUMES" ]]; then
            print_warning "No Docker volumes found"
            exit 0
        fi
        
        for volume in $VOLUMES; do
            print_status "Backing up volume: $volume"
            /opt/scripts/manage_docker_volumes.sh backup "$volume"
        done
        
        print_status "All volumes backed up successfully"
        ;;
    "verify-backups")
        print_status "Verifying backup integrity..."
        echo ""
        
        if [[ -d "$BACKUP_DIR" ]]; then
            find "$BACKUP_DIR" -name "*.tar.gz" -type f | while read -r backup; do
                print_status "Verifying: $(basename "$backup")"
                if tar -tzf "$backup" >/dev/null 2>&1; then
                    echo "  ✓ OK"
                else
                    echo "  ✗ CORRUPTED"
                fi
            done
        fi
        ;;
    *)
        echo "Usage: $0 {list-volumes|list-backups|backup-all|verify-backups}"
        echo ""
        echo "Commands:"
        echo "  list-volumes    - List all Docker volumes"
        echo "  list-backups    - List existing backups"
        echo "  backup-all      - Backup all Docker volumes"
        echo "  verify-backups  - Verify backup integrity"
        exit 1
        ;;
esac
EOF

chmod +x "$BACKUP_DISCOVERY_SCRIPT"
print_status "Backup discovery script created: $BACKUP_DISCOVERY_SCRIPT"

# Create fstab entries for persistence
print_status "Adding mount points to /etc/fstab..."

# Check if entries already exist
if ! grep -q "$DOCKER_DATA_DIR" /etc/fstab; then
    echo "# Docker ZFS mount points" >> /etc/fstab
    echo "data/docker $DOCKER_DATA_DIR zfs defaults 0 0" >> /etc/fstab
    echo "data/docker/volumes $DOCKER_VOLUMES_DIR zfs defaults 0 0" >> /etc/fstab
    echo "data/docker/configs $DOCKER_CONFIG_DIR zfs defaults 0 0" >> /etc/fstab
    echo "backup/docker-back $BACKUP_DIR zfs defaults 0 0" >> /etc/fstab
    print_status "Added ZFS mount points to /etc/fstab"
else
    print_warning "ZFS mount points already exist in /etc/fstab"
fi

# Mount the datasets
print_status "Mounting ZFS datasets..."

zfs mount data/docker || true
zfs mount data/docker/volumes || true
zfs mount data/docker/configs || true
zfs mount backup/docker-back || true

print_status "ZFS datasets mounted"

# Restart Docker daemon
print_status "Restarting Docker daemon..."

systemctl daemon-reload
systemctl restart docker

# Wait for Docker to start
sleep 5

# Verify Docker is running
if systemctl is-active --quiet docker; then
    print_status "Docker daemon restarted successfully"
else
    print_error "Docker daemon failed to start"
    exit 1
fi

# Test Docker volume creation
print_status "Testing Docker volume creation..."

TEST_VOLUME="test_volume_$(date +%s)"
if docker volume create "$TEST_VOLUME" >/dev/null 2>&1; then
    print_status "Docker volume creation test successful"
    docker volume rm "$TEST_VOLUME" >/dev/null 2>&1
else
    print_error "Docker volume creation test failed"
    exit 1
fi

print_header "Docker Storage Configuration Complete!"

echo ""
print_status "Configuration Summary:"
echo "  Docker data root: $DOCKER_DATA_DIR"
echo "  Docker volumes: $DOCKER_VOLUMES_DIR"
echo "  Docker configs: $DOCKER_CONFIG_DIR"
echo "  Backup directory: $BACKUP_DIR"
echo ""
print_status "Management Scripts:"
echo "  Volume management: $VOLUME_MANAGEMENT_SCRIPT"
echo "  Backup discovery: $BACKUP_DISCOVERY_SCRIPT"
echo ""
print_status "Usage Examples:"
echo "  List volumes: $VOLUME_MANAGEMENT_SCRIPT list"
echo "  Create volume: $VOLUME_MANAGEMENT_SCRIPT create myapp_data"
echo "  Backup volume: $VOLUME_MANAGEMENT_SCRIPT backup myapp_data"
echo "  Discover volumes: $BACKUP_DISCOVERY_SCRIPT list-volumes"
echo "  Backup all: $BACKUP_DISCOVERY_SCRIPT backup-all"
echo ""
print_status "Next steps:"
echo "1. Test volume creation and backup procedures"
echo "2. Configure your applications to use the new volume locations"
echo "3. Set up automated backup schedules"
echo "4. Test restore procedures" 