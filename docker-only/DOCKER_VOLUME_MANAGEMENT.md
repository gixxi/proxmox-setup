# Docker Volume Management with ZFS

This document explains how Docker volumes are configured to use ZFS storage and how the backup system discovers and manages them.

## 🏗️ **Architecture Overview**

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Volume Architecture               │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Docker    │  │   ZFS Data  │  │   ZFS       │        │
│  │   Daemon    │  │    Pool     │  │  Backup     │        │
│  │             │  │             │  │   Pool      │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│         │                │                │               │
│         ▼                ▼                ▼               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │  /etc/docker│  │  /data/     │  │  /backup/   │        │
│  │ /daemon.json│  │  docker/    │  │ docker-back/│        │
│  │             │  │             │  │             │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│         │                │                │               │
│         ▼                ▼                ▼               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │  data-root  │  │  volumes/   │  │  *.tar.gz   │        │
│  │  configs/   │  │  configs/   │  │  backups    │        │
│  │             │  │             │  │             │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## 🔧 **Docker Daemon Configuration**

### **Key Configuration File: `/etc/docker/daemon.json`**

```json
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
```

### **Critical Setting: `data-root`**
- **Purpose**: Tells Docker where to store all its data
- **Location**: `/data/docker` (on ZFS pool)
- **Impact**: All Docker volumes, images, containers stored here

## 📁 **ZFS Dataset Structure**

### **Data Pool Structure**
```bash
data/
├── docker/
│   ├── volumes/          # Docker named volumes
│   ├── configs/          # Docker configurations
│   ├── overlay2/         # Docker storage driver data
│   └── containers/       # Container data
```

### **Backup Pool Structure**
```bash
backup/
├── docker-back/          # Docker volume backups
├── snapshots/            # ZFS snapshots
└── nfs-back/             # NFS data backups
```

## 🔍 **How Backup System Discovers Volumes**

### **1. Volume Discovery Methods**

#### **Method A: Docker Volume API**
```bash
# List all named volumes
docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Mountpoint}}"

# Example output:
# NAME                DRIVER    MOUNTPOINT
# myapp_data          local     /data/docker/volumes/myapp_data/_data
# postgres_data       local     /data/docker/volumes/postgres_data/_data
```

#### **Method B: Filesystem Scanning**
```bash
# Scan ZFS datasets
zfs list -o name,used,avail,refer,mountpoint data/docker/volumes

# Scan directories
find /data/docker/volumes -maxdepth 1 -type d -name "*"
```

#### **Method C: Container Inspection**
```bash
# Find volumes used by running containers
docker ps --format "{{.Names}}" | xargs -I {} docker inspect {} --format '{{range .Mounts}}{{.Name}} {{end}}'
```

### **2. Backup Discovery Script**

```bash
#!/bin/bash
# /opt/scripts/discover_docker_volumes.sh

VOLUMES_DIR="/data/docker/volumes"
BACKUP_DIR="/backup/docker-back"

# Discover all volumes
discover_volumes() {
    echo "=== Named Docker Volumes ==="
    docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Mountpoint}}"
    
    echo ""
    echo "=== ZFS Datasets ==="
    zfs list -o name,used,avail,refer,mountpoint data/docker/volumes
    
    echo ""
    echo "=== Bind-Mounted Volumes ==="
    find "$VOLUMES_DIR" -maxdepth 1 -type d -name "*" | while read -r dir; do
        VOLUME_NAME=$(basename "$dir")
        SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
        echo "  $VOLUME_NAME ($SIZE)"
    done
}

# Backup all discovered volumes
backup_all_volumes() {
    VOLUMES=$(docker volume ls -q)
    
    for volume in $VOLUMES; do
        echo "Backing up volume: $volume"
        /opt/scripts/manage_docker_volumes.sh backup "$volume"
    done
}
```

## 🗂️ **Volume Types and Storage**

### **1. Named Volumes**
```yaml
# docker-compose.yml
version: '3.8'
services:
  app:
    image: myapp:latest
    volumes:
      - app_data:/app/data  # Named volume
      - /data/docker/configs/app:/app/config  # Bind mount

volumes:
  app_data:  # This creates a named volume
```

**Storage Location**: `/data/docker/volumes/app_data/_data`

### **2. Bind Mounts**
```yaml
# docker-compose.yml
services:
  app:
    volumes:
      - /data/docker/volumes/myapp:/app/data  # Bind mount
      - /mnt/nas/shared:/app/shared  # NFS bind mount
```

**Storage Location**: Direct path mapping

### **3. Docker-Managed Volumes**
```bash
# Created via docker volume create
docker volume create my_volume

# Storage Location: /data/docker/volumes/my_volume/_data
```

## 🔄 **Backup Process Flow**

### **1. Volume Discovery**
```bash
# Step 1: Discover all volumes
VOLUMES=$(docker volume ls -q)

# Step 2: Get volume details
for volume in $VOLUMES; do
    MOUNTPOINT=$(docker volume inspect "$volume" --format '{{.Mountpoint}}')
    echo "Volume: $volume -> $MOUNTPOINT"
done
```

### **2. Backup Creation**
```bash
# Step 3: Create backup
for volume in $VOLUMES; do
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="/backup/docker-back/${volume}_${TIMESTAMP}.tar.gz"
    
    # Stop containers using this volume
    CONTAINERS=$(docker ps -q --filter volume="$volume")
    if [[ -n "$CONTAINERS" ]]; then
        docker stop $CONTAINERS
    fi
    
    # Create backup
    docker run --rm \
        -v "$volume:/data" \
        -v "/backup/docker-back:/backup" \
        alpine tar czf "/backup/${volume}_${TIMESTAMP}.tar.gz" /data
    
    # Restart containers
    if [[ -n "$CONTAINERS" ]]; then
        docker start $CONTAINERS
    fi
done
```

### **3. ZFS Snapshot Creation**
```bash
# Step 4: Create ZFS snapshot
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
zfs snapshot data/docker/volumes@backup_${TIMESTAMP}
```

## 📊 **Volume Management Scripts**

### **1. Volume Management Script**
```bash
# /opt/scripts/manage_docker_volumes.sh

# Usage examples:
./manage_docker_volumes.sh list                    # List all volumes
./manage_docker_volumes.sh create myapp_data       # Create volume
./manage_docker_volumes.sh backup myapp_data       # Backup volume
./manage_docker_volumes.sh restore myapp_data backup_file.tar.gz
./manage_docker_volumes.sh snapshot myapp_data     # Create ZFS snapshot
```

### **2. Backup Discovery Script**
```bash
# /opt/scripts/discover_docker_volumes.sh

# Usage examples:
./discover_docker_volumes.sh list-volumes          # List all volumes
./discover_docker_volumes.sh list-backups          # List existing backups
./discover_docker_volumes.sh backup-all            # Backup all volumes
./discover_docker_volumes.sh verify-backups        # Verify backup integrity
```

## 🔧 **Configuration Files**

### **1. Docker Daemon Configuration**
```bash
# /etc/docker/daemon.json
{
  "data-root": "/data/docker",
  "storage-driver": "overlay2"
}
```

### **2. Fstab Entries**
```bash
# /etc/fstab
# Docker ZFS mount points
data/docker /data/docker zfs defaults 0 0
data/docker/volumes /data/docker/volumes zfs defaults 0 0
data/docker/configs /data/docker/configs zfs defaults 0 0
backup/docker-back /backup/docker-back zfs defaults 0 0
```

### **3. ZFS Properties**
```bash
# Performance optimizations
zfs set compression=lz4 data/docker
zfs set recordsize=128K data/docker/volumes
zfs set atime=off data/docker
```

## 🔍 **Monitoring and Verification**

### **1. Volume Status Check**
```bash
# Check volume usage
docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Mountpoint}}"

# Check ZFS dataset usage
zfs list -o name,used,avail,refer,mountpoint data/docker/volumes

# Check backup directory
ls -la /backup/docker-back/
```

### **2. Backup Verification**
```bash
# Verify backup integrity
for backup in /backup/docker-back/*.tar.gz; do
    if tar -tzf "$backup" >/dev/null 2>&1; then
        echo "✓ $(basename "$backup") - OK"
    else
        echo "✗ $(basename "$backup") - CORRUPTED"
    fi
done
```

### **3. Storage Monitoring**
```bash
# Monitor ZFS pool usage
zpool status data
zpool status backup

# Monitor disk usage
df -h /data/docker/volumes
df -h /backup/docker-back
```

## 🚨 **Troubleshooting**

### **1. Volume Not Found**
```bash
# Check if volume exists
docker volume ls | grep volume_name

# Check ZFS dataset
zfs list data/docker/volumes

# Check mount point
ls -la /data/docker/volumes/
```

### **2. Backup Failures**
```bash
# Check backup directory permissions
ls -la /backup/docker-back/

# Check available space
df -h /backup/

# Check Docker daemon status
systemctl status docker
```

### **3. ZFS Issues**
```bash
# Check ZFS pool status
zpool status data
zpool status backup

# Check ZFS datasets
zfs list -o name,used,avail,refer,mountpoint

# Import pool if needed
zpool import -f data
```

## 📋 **Best Practices**

### **1. Volume Naming**
```bash
# Use descriptive names
docker volume create myapp_database_data
docker volume create myapp_uploads_data
docker volume create myapp_logs_data
```

### **2. Backup Scheduling**
```bash
# Daily backups at 2 AM
0 2 * * * root /opt/scripts/discover_docker_volumes.sh backup-all

# Weekly full backup
0 3 * * 0 root /opt/scripts/manage_docker_volumes.sh snapshot-all
```

### **3. Monitoring**
```bash
# Set up alerts for:
# - Low disk space
# - Failed backups
# - Corrupted volumes
# - ZFS pool errors
```

## 🎯 **Summary**

The Docker volume management system works by:

1. **Configuration**: Docker daemon configured to use `/data/docker` as data root
2. **ZFS Integration**: All Docker data stored on ZFS datasets
3. **Discovery**: Backup scripts discover volumes via Docker API and filesystem scanning
4. **Backup**: Volumes backed up to `/backup/docker-back/` with timestamps
5. **Snapshots**: ZFS snapshots provide point-in-time recovery
6. **Restore**: Full restore capabilities for all volume types

This ensures that all Docker volumes are automatically discovered, backed up, and can be restored when needed. 