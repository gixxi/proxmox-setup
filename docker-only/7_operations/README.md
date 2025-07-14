# Operations - Day-to-Day Management

This directory contains scripts for day-to-day operational tasks and maintenance of the Docker infrastructure.

## Operations Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Operations Tasks                         │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   System    │  │   Docker    │  │   Storage   │        │
│  │ Monitoring  │  │ Management  │  │ Management  │        │
│  │             │  │             │  │             │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│         │                │                │               │
│         ▼                ▼                ▼               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Health    │  │   Container │  │   ZFS Pool  │        │
│  │   Checks    │  │   Updates   │  │   Status    │        │
│  │             │  │             │  │             │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Files

- `system_health_check.sh` - Comprehensive system health monitoring
- `docker_management.sh` - Docker container and volume management
- `storage_management.sh` - ZFS pool and NFS management
- `update_system.sh` - System and Docker updates
- `monitor_logs.sh` - Log monitoring and analysis
- `emergency_restore.sh` - Emergency restore procedures
- `maintenance_mode.sh` - Enable/disable maintenance mode

## Daily Operations

### 1. System Health Check
```bash
# Run daily health check
./system_health_check.sh

# Check specific components
./system_health_check.sh --component docker
./system_health_check.sh --component storage
./system_health_check.sh --component network
```

### 2. Docker Management
```bash
# List all containers
./docker_management.sh list

# Update containers
./docker_management.sh update

# Clean up unused resources
./docker_management.sh cleanup
```

### 3. Storage Management
```bash
# Check ZFS pool status
./storage_management.sh status

# Create snapshots
./storage_management.sh snapshot

# Clean up old snapshots
./storage_management.sh cleanup-snapshots
```

## Weekly Operations

### 1. System Updates
```bash
# Update system packages
./update_system.sh --packages

# Update Docker images
./update_system.sh --docker

# Full system update
./update_system.sh --full
```

### 2. Backup Verification
```bash
# Verify backup integrity
./verify_backups.sh

# Test restore procedures
./test_restore.sh
```

### 3. Log Analysis
```bash
# Analyze system logs
./monitor_logs.sh --analyze

# Check for errors
./monitor_logs.sh --errors

# Generate report
./monitor_logs.sh --report
```

## Monthly Operations

### 1. Security Audit
```bash
# Check for security updates
./security_audit.sh

# Verify SSL certificates
./security_audit.sh --ssl

# Check user permissions
./security_audit.sh --users
```

### 2. Performance Analysis
```bash
# Analyze system performance
./performance_analysis.sh

# Generate performance report
./performance_analysis.sh --report
```

### 3. Capacity Planning
```bash
# Check storage usage
./capacity_planning.sh --storage

# Check resource usage
./capacity_planning.sh --resources
```

## Emergency Procedures

### 1. Emergency Restore
```bash
# Emergency restore from backup
./emergency_restore.sh --latest

# Restore specific backup
./emergency_restore.sh --backup 20231201_020000
```

### 2. Maintenance Mode
```bash
# Enable maintenance mode
./maintenance_mode.sh --enable

# Disable maintenance mode
./maintenance_mode.sh --disable
```

### 3. Emergency Shutdown
```bash
# Graceful shutdown
./emergency_shutdown.sh --graceful

# Force shutdown
./emergency_shutdown.sh --force
```

## Monitoring Scripts

### 1. System Health Check
```bash
#!/bin/bash
# system_health_check.sh

# Check CPU usage
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)

# Check memory usage
MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.2f", $3/$2 * 100.0)}')

# Check disk usage
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1)

# Check Docker status
DOCKER_STATUS=$(systemctl is-active docker)

# Generate report
echo "System Health Report - $(date)"
echo "CPU Usage: ${CPU_USAGE}%"
echo "Memory Usage: ${MEMORY_USAGE}%"
echo "Disk Usage: ${DISK_USAGE}%"
echo "Docker Status: ${DOCKER_STATUS}"
```

### 2. Docker Management
```bash
#!/bin/bash
# docker_management.sh

ACTION="$1"

case $ACTION in
    "list")
        echo "Running containers:"
        docker ps
        echo ""
        echo "All containers:"
        docker ps -a
        ;;
    "update")
        echo "Updating containers..."
        docker-compose pull
        docker-compose up -d
        ;;
    "cleanup")
        echo "Cleaning up Docker resources..."
        docker system prune -f
        docker volume prune -f
        ;;
    *)
        echo "Usage: $0 {list|update|cleanup}"
        exit 1
        ;;
esac
```

### 3. Storage Management
```bash
#!/bin/bash
# storage_management.sh

ACTION="$1"

case $ACTION in
    "status")
        echo "ZFS Pool Status:"
        zpool status
        echo ""
        echo "ZFS Dataset Usage:"
        zfs list -o name,used,avail,refer,mountpoint
        ;;
    "snapshot")
        echo "Creating ZFS snapshots..."
        zfs snapshot data/docker@daily_$(date +%Y%m%d_%H%M%S)
        ;;
    "cleanup-snapshots")
        echo "Cleaning up old snapshots..."
        # Keep only last 7 daily snapshots
        zfs list -t snapshot data/docker | grep daily | tail -n +8 | awk '{print $1}' | xargs -r zfs destroy
        ;;
    *)
        echo "Usage: $0 {status|snapshot|cleanup-snapshots}"
        exit 1
        ;;
esac
```

## Log Management

### 1. Log Monitoring
```bash
#!/bin/bash
# monitor_logs.sh

# Monitor Docker logs
docker logs -f container_name

# Monitor system logs
tail -f /var/log/syslog

# Monitor Nginx logs
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

### 2. Log Analysis
```bash
#!/bin/bash
# analyze_logs.sh

# Analyze error patterns
grep -i error /var/log/syslog | tail -100

# Check for failed login attempts
grep "Failed password" /var/log/auth.log

# Check Docker container restarts
docker ps -a | grep -E "(Exit|Restarting)"
```

## Automation

### 1. Cron Jobs
```bash
# /etc/cron.d/docker-operations

# Daily health check at 6 AM
0 6 * * * root /opt/scripts/system_health_check.sh

# Weekly updates on Sunday at 2 AM
0 2 * * 0 root /opt/scripts/update_system.sh --weekly

# Monthly maintenance on 1st at 3 AM
0 3 1 * * root /opt/scripts/maintenance.sh --monthly
```

### 2. Systemd Services
```bash
# /etc/systemd/system/docker-monitor.service
[Unit]
Description=Docker Monitoring Service
After=docker.service

[Service]
Type=simple
ExecStart=/opt/scripts/monitor_docker.sh
Restart=always

[Install]
WantedBy=multi-user.target
```

## Troubleshooting

### 1. Common Issues
- **Container won't start**: Check logs and resource limits
- **Storage full**: Clean up old snapshots and backups
- **Network issues**: Check Docker network configuration
- **SSL certificate expired**: Renew certificates manually

### 2. Debugging Commands
```bash
# Check Docker daemon logs
journalctl -u docker.service

# Check container resource usage
docker stats

# Check ZFS pool health
zpool status -v

# Check network connectivity
docker network ls
docker network inspect bridge
```

## Performance Optimization

### 1. Docker Optimization
```bash
# Optimize Docker daemon
cat > /etc/docker/daemon.json << EOF
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
```

### 2. System Optimization
```bash
# Optimize system settings
echo 'vm.swappiness=10' >> /etc/sysctl.conf
echo 'net.core.rmem_max=16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_max=16777216' >> /etc/sysctl.conf
```

## Security

### 1. Security Checks
```bash
# Check for security updates
apt list --upgradable | grep security

# Check Docker image vulnerabilities
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image image_name

# Check file permissions
find /data -type f -perm /o+w
```

### 2. Access Control
```bash
# Review user access
cat /etc/passwd | grep -E "(docker|admin)"

# Check sudo access
sudo -l

# Review SSH access
cat ~/.ssh/authorized_keys
```

## Next Steps

After setting up operations, consider:
1. Setting up monitoring and alerting
2. Creating runbooks for common issues
3. Implementing automated testing
4. Setting up disaster recovery procedures 