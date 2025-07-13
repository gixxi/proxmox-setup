# Storage Setup - ZFS Pools and NFS

This directory contains scripts for setting up ZFS storage pools and NFS mounting for Docker infrastructure.

## Storage Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Debian 12 Host                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   ZFS Data  │  │  ZFS Backup │  │   NFS Mount │        │
│  │    Pool     │  │    Pool     │  │  (Synology) │        │
│  │  (Mirror)   │  │  (Mirror)   │  │             │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│         │                │                │               │
│         ▼                ▼                ▼               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │  /data      │  │  /backup    │  │  /mnt/nas   │        │
│  │  (Docker    │  │  (Backups)  │  │  (Shared    │        │
│  │   volumes)  │  │             │  │   storage)  │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Files

- `detect_disks.sh` - Detect available disks for ZFS pools
- `create_zfs_pools.sh` - Create ZFS data and backup pools
- `setup_mount_points.sh` - Configure mount points for Docker volumes
- `setup_nfs_mount.sh` - Mount NFS share from Synology NAS
- `configure_docker_storage.sh` - Configure Docker to use ZFS/NFS storage

## Storage Strategy

### ZFS Data Pool
- **Purpose**: Docker volumes and application data
- **Configuration**: Mirror (RAID 1) for redundancy
- **Mount point**: `/data`
- **Use case**: Persistent Docker volumes, application data

### ZFS Backup Pool
- **Purpose**: Backup storage and snapshots
- **Configuration**: Mirror (RAID 1) for redundancy
- **Mount point**: `/backup`
- **Use case**: ZFS snapshots, Docker volume backups

### NFS Mount
- **Purpose**: Additional shared storage
- **Source**: Synology NAS
- **Mount point**: `/mnt/nas`
- **Use case**: Shared data, additional Docker volumes

## ZFS Configuration

### Pool Configuration
```bash
# Data pool (mirror)
zpool create data mirror /dev/sdb /dev/sdc

# Backup pool (mirror)
zpool create backup mirror /dev/sdd /dev/sde
```

### Dataset Structure
```
data/
├── docker/
│   ├── volumes/
│   └── configs/
└── applications/
    └── rocklog/

backup/
├── snapshots/
├── docker-backups/
└── system-backups/
```

## Docker Volume Configuration

### Bind Mounts
```yaml
# docker-compose.yml example
volumes:
  - /data/docker/volumes/app-data:/app/data
  - /mnt/nas/shared-data:/app/shared
  - /data/docker/configs/app-config:/app/config
```

### Named Volumes
```yaml
# docker-compose.yml example
volumes:
  app-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /data/docker/volumes/app-data
```

## Prerequisites

- At least 4 additional disks (2 for data pool, 2 for backup pool)
- Synology NAS with NFS export configured
- ZFS kernel module installed
- Network connectivity to NAS

## Configuration Steps

1. **Detect Available Disks**
   ```bash
   ./detect_disks.sh
   ```

2. **Create ZFS Pools**
   ```bash
   ./create_zfs_pools.sh
   ```

3. **Setup Mount Points**
   ```bash
   ./setup_mount_points.sh
   ```

4. **Configure NFS Mount**
   ```bash
   ./setup_nfs_mount.sh
   ```

5. **Configure Docker Storage**
   ```bash
   ./configure_docker_storage.sh
   ```

## ZFS Commands Reference

### Pool Management
```bash
# List pools
zpool list

# Pool status
zpool status

# Create pool
zpool create poolname mirror disk1 disk2

# Destroy pool
zpool destroy poolname
```

### Dataset Management
```bash
# Create dataset
zfs create poolname/dataset

# List datasets
zfs list

# Set properties
zfs set compression=lz4 poolname/dataset

# Create snapshot
zfs snapshot poolname/dataset@snapshot-name
```

### Snapshot Management
```bash
# Create snapshot
zfs snapshot data/docker@$(date +%Y%m%d_%H%M%S)

# List snapshots
zfs list -t snapshot

# Clone snapshot
zfs clone data/docker@snapshot-name data/docker-clone

# Rollback to snapshot
zfs rollback data/docker@snapshot-name
```

## Backup Strategy

### ZFS Snapshots
- **Frequency**: Daily snapshots of data pool
- **Retention**: 7 daily, 4 weekly, 12 monthly
- **Location**: Backup pool

### Docker Volume Backups
- **Method**: `docker run --rm -v source:/data -v backup:/backup alpine tar czf /backup/backup.tar.gz /data`
- **Frequency**: Before major updates
- **Location**: Backup pool

### NFS Data Backup
- **Method**: rsync to backup pool
- **Frequency**: Daily
- **Location**: Backup pool

## Performance Considerations

### ZFS Optimization
```bash
# Set ashift for SSD
zpool create -o ashift=12 data mirror /dev/sdb /dev/sdc

# Enable compression
zfs set compression=lz4 data

# Set recordsize for database workloads
zfs set recordsize=8K data/docker/volumes/database
```

### NFS Optimization
```bash
# Mount options for performance
mount -t nfs -o rw,hard,intr,rsize=32768,wsize=32768,timeo=600,retrans=2 nas:/share /mnt/nas
```

## Troubleshooting

### Common Issues
1. **ZFS module not loaded**: `modprobe zfs`
2. **Pool import issues**: `zpool import -f poolname`
3. **NFS mount fails**: Check network and export permissions
4. **Permission issues**: Check ownership and ACLs

### Debugging Commands
```bash
# Check ZFS status
zpool status
zfs list

# Check mount points
mount | grep zfs
mount | grep nfs

# Check disk usage
df -h

# Check ZFS properties
zfs get all data
```

## Next Steps

After storage setup, proceed to:
1. `../4_ssl_setup/` - Configure SSL certificates
2. `../6_backup_scripts/` - Setup backup automation 

##  **Important: Don't Use XFS for Root Partition**

### **Why Not XFS for Root?**
- **ZFS dependency**: Your Docker volumes and data will be on ZFS pools
- **Boot complexity**: XFS + ZFS can create boot dependencies
- **Snapshot limitations**: XFS doesn't support snapshots like ZFS
- **Consistency**: Better to have a unified storage approach

## ✅ **Recommended Root Partition Strategy**

### **Option 1: ext4 for Root (Recommended)**
```bash
# During Debian installation
Partitioning: Manual
Root partition: ext4 on /dev/sda1
Boot partition: ext4 on /dev/sda2 (if UEFI)
Swap: on /dev/sda3 (if needed)
```

**Benefits:**
- **Stable and proven**: ext4 is rock-solid for root
- **No conflicts**: Won't interfere with ZFS pools
- **Simple boot**: Standard boot process
- **Easy recovery**: Well-documented recovery procedures

### **Option 2: ZFS for Root (Advanced)**
```bash
# Only if you're experienced with ZFS boot
Root pool: zpool create rpool mirror /dev/sda /dev/sdb
Root dataset: zfs create rpool/ROOT/debian
Boot dataset: zfs create rpool/boot
```

**Considerations:**
- **Complex setup**: Requires ZFS boot configuration
- **Recovery complexity**: More complex recovery procedures
- **Boot dependencies**: Need ZFS kernel modules at boot
- **Advanced users only**: Not recommended for most users

## 🎯 **Recommended Installation Steps**

### **1. Debian Installation**
```bash
# Download Debian 12 netinst ISO
# Boot from USB

# Installation options:
- Language: English
- Location: Your timezone
- Keyboard: Your layout
- Network: Configure both NICs
- Hostname: Choose meaningful name
- Domain: Leave empty or set to planet-rocklog.com
- Root password: Set strong password
- User account: Create initial user (will be replaced)
```

### **2. Partitioning (Manual)**
```bash
# Choose "Manual" partitioning
# Recommended layout:

/dev/sda1  -  ext4  -  /boot     -  512MB
/dev/sda2  -  ext4  -  /         -  Rest of disk
/dev/sda3  -  swap  -  swap      -  8GB (if needed)

# For ZFS pools (separate disks):
/dev/sdb   -  Available for ZFS data pool
/dev/sdc   -  Available for ZFS data pool
/dev/sdd   -  Available for ZFS backup pool
/dev/sde   -  Available for ZFS backup pool
```

### **3. Software Selection**
```bash
# Choose "Minimal installation" only
# Don't install additional software during installation
# We'll install Docker and other tools via scripts
```

## 🔧 **Post-Installation ZFS Setup**

After Debian installation, you'll create ZFS pools on the additional disks:

```bash
<code_block_to_apply_changes_from>
```

## 📋 **Installation Checklist**

### **During Installation**
- [ ] **Partitioning**: Manual with ext4 for root
- [ ] **Network**: Configure both NICs
- [ ] **Software**: Minimal installation only
- [ ] **User**: Create initial user account

### **After Installation**
- [ ] **Update system**: `apt update && apt upgrade`
- [ ] **Install ZFS**: `apt install zfsutils-linux`
- [ ] **Create ZFS pools**: On additional disks
- [ ] **Run setup scripts**: From the docker-only directory

## 🚨 **Common Pitfalls to Avoid**

### **1. Don't Mix Filesystems Unnecessarily**
```bash
# Avoid this:
Root: XFS
Docker volumes: ZFS
NFS: ext4

# Use this instead:
Root: ext4
Docker volumes: ZFS
NFS: ZFS (if possible)
```

### **2. Don't Use LVM for Root**
```bash
# Avoid LVM for root partition
# It adds complexity without benefits for this setup
# Use simple ext4 partition instead
```

### **3. Don't Install Unnecessary Software**
```bash
# During installation, choose "Minimal"
# Don't install:
- Desktop environment
- Web server
- Database server
- Print server
```

## 🎯 **Final Recommendation**

**Use ext4 for root partition** because:

1. **Simplicity**: Standard, well-tested filesystem
2. **Compatibility**: Works with all tools and recovery procedures
3. **Performance**: Good performance for root filesystem
4. **No conflicts**: Won't interfere with ZFS pools
5. **Easy maintenance**: Standard Linux administration

The ZFS pools will be created on your additional disks after installation, giving you the benefits of ZFS for your Docker data while keeping the root filesystem simple and reliable.

Would you like me to create a specific installation guide for the Debian setup, or do you have questions about the partitioning strategy? 