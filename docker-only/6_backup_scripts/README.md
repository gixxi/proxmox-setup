# Backup Scripts - ZFS Snapshots and Docker Volume Backups

This directory contains scripts for automated backup and restore operations for the Docker infrastructure.

## Backup Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Backup Strategy                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   ZFS       │  │   Docker    │  │   NFS       │        │
│  │ Snapshots   │  │   Volume    │  │   Data      │        │
│  │             │  │   Backups   │  │   Backup    │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│         │                │                │               │
│         ▼                ▼                ▼               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │  /backup/   │  │  /backup/   │  │  /backup/   │        │
│  │ snapshots/  │  │docker-back/ │  │   nfs-back/ │        │
│  │             │  │             │  │             │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Files

- `backup_zfs_snapshots.sh` - Create ZFS snapshots with timestamped names
- `backup_docker_volumes.sh` - Backup Docker volumes to backup pool
- `backup_nfs_data.sh` - Backup NFS data to backup pool
- `restore_zfs_snapshot.sh` - Restore from ZFS snapshot
- `restore_docker_volume.sh` - Restore Docker volume from backup
- `cleanup_old_backups.sh` - Clean up old backups based on retention policy
- `backup_all.sh` - Master script to run all backup operations

## Backup Strategy

### ZFS Snapshots
- **Frequency**: Daily at 2:00 AM
- **Retention**: 7 daily, 4 weekly, 12 monthly
- **Naming**: `data@daily_YYYYMMDD_HHMMSS`
- **Location**: Backup pool

### Docker Volume Backups
- **Frequency**: Before major updates, weekly
- **Method**: `docker run --rm -v source:/data -v backup:/backup alpine tar czf /backup/backup.tar.gz /data`
- **Retention**: 30 days
- **Location**: `/backup/docker-back/`

### NFS Data Backups
- **Frequency**: Daily
- **Method**: rsync with incremental backup
- **Retention**: 7 daily, 4 weekly
- **Location**: `/backup/nfs-back/`

## Backup Types

### 1. ZFS Snapshots
```bash
# Create snapshot
zfs snapshot data/docker@daily_$(date +%Y%m%d_%H%M%S)

# List snapshots
zfs list -t snapshot data/docker

# Clone snapshot for testing
zfs clone data/docker@daily_20231201_020000 data/docker-test
```

### 2. Docker Volume Backups
```bash
# Backup volume
docker run --rm \
  -v source_volume:/data \
  -v /backup/docker-back:/backup \
  alpine tar czf /backup/volume_backup_$(date +%Y%m%d_%H%M%S).tar.gz /data

# Restore volume
docker run --rm \
  -v target_volume:/data \
  -v /backup/docker-back:/backup \
  alpine tar xzf /backup/volume_backup_20231201_020000.tar.gz -C /data
```

### 3. NFS Data Backups
```bash
# Incremental backup
rsync -av --delete /mnt/nas/ /backup/nfs-back/daily/

# Full backup
rsync -av /mnt/nas/ /backup/nfs-back/full/$(date +%Y%m%d)/
```

## Cron Configuration

### Daily Backups
```bash
# /etc/cron.d/docker-backups
0 2 * * * root /opt/scripts/backup_all.sh daily
```

### Weekly Backups
```bash
# /etc/cron.d/docker-backups
0 3 * * 0 root /opt/scripts/backup_all.sh weekly
```

### Monthly Backups
```bash
# /etc/cron.d/docker-backups
0 4 1 * * root /opt/scripts/backup_all.sh monthly
```

## Backup Scripts

### 1. ZFS Snapshot Backup
```bash
#!/bin/bash
# backup_zfs_snapshots.sh

DATASET="data/docker"
SNAPSHOT_NAME="daily_$(date +%Y%m%d_%H%M%S)"

zfs snapshot $DATASET@$SNAPSHOT_NAME
echo "Created snapshot: $DATASET@$SNAPSHOT_NAME"
```

### 2. Docker Volume Backup
```bash
#!/bin/bash
# backup_docker_volumes.sh

VOLUME_NAME="$1"
BACKUP_DIR="/backup/docker-back"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

docker run --rm \
  -v $VOLUME_NAME:/data \
  -v $BACKUP_DIR:/backup \
  alpine tar czf /backup/${VOLUME_NAME}_${TIMESTAMP}.tar.gz /data
```

### 3. NFS Data Backup
```bash
#!/bin/bash
# backup_nfs_data.sh

SOURCE="/mnt/nas"
BACKUP_DIR="/backup/nfs-back/daily"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

rsync -av --delete --backup --backup-dir=$BACKUP_DIR/previous $SOURCE/ $BACKUP_DIR/current/
```

## Restore Procedures

### 1. Restore from ZFS Snapshot
```bash
#!/bin/bash
# restore_zfs_snapshot.sh

SNAPSHOT_NAME="$1"
DATASET="data/docker"

# Stop containers using the dataset
docker stop $(docker ps -q)

# Rollback to snapshot
zfs rollback $DATASET@$SNAPSHOT_NAME

# Start containers
docker start $(docker ps -aq)
```

### 2. Restore Docker Volume
```bash
#!/bin/bash
# restore_docker_volume.sh

VOLUME_NAME="$1"
BACKUP_FILE="$2"

# Stop container using the volume
docker stop $(docker ps -q --filter volume=$VOLUME_NAME)

# Remove volume
docker volume rm $VOLUME_NAME

# Create new volume
docker volume create $VOLUME_NAME

# Restore from backup
docker run --rm \
  -v $VOLUME_NAME:/data \
  -v /backup/docker-back:/backup \
  alpine tar xzf /backup/$BACKUP_FILE -C /data

# Start container
docker start $(docker ps -aq --filter volume=$VOLUME_NAME)
```

## Monitoring and Alerting

### Backup Status Monitoring
```bash
#!/bin/bash
# check_backup_status.sh

# Check if backups are recent
LAST_BACKUP=$(find /backup -name "*.tar.gz" -mtime -1 | wc -l)

if [ $LAST_BACKUP -eq 0 ]; then
    echo "WARNING: No recent backups found!"
    # Send alert
fi
```

### Log Monitoring
```bash
# Monitor backup logs
tail -f /var/log/backup.log | grep -E "(ERROR|WARNING|FAILED)"
```

## Performance Considerations

### Backup Performance
- **ZFS snapshots**: Near-instant, minimal performance impact
- **Docker volume backups**: Use compression, run during low-usage periods
- **NFS backups**: Use rsync with incremental backup

### Storage Optimization
```bash
# Enable compression on backup pool
zfs set compression=lz4 backup

# Set deduplication for backup datasets
zfs set dedup=on backup/docker-back
```

## Security Considerations

### Backup Security
- **Encryption**: Encrypt sensitive backup data
- **Access control**: Restrict access to backup directories
- **Offsite backup**: Consider offsite backup for critical data

### Backup Verification
```bash
# Verify backup integrity
tar -tzf backup_file.tar.gz > /dev/null && echo "Backup OK" || echo "Backup corrupted"
```

## Troubleshooting

### Common Issues
1. **Insufficient space**: Monitor backup pool usage
2. **Failed backups**: Check logs and permissions
3. **Restore failures**: Verify backup file integrity

### Debugging Commands
```bash
# Check backup status
ls -la /backup/

# Check ZFS snapshots
zfs list -t snapshot

# Check Docker volumes
docker volume ls

# Check backup logs
tail -f /var/log/backup.log
```

## Next Steps

After backup setup, proceed to:
1. `../7_operations/` - Day-to-day operational scripts
2. Test backup and restore procedures
3. Set up monitoring and alerting 