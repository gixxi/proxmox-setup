# Docker-Only Infrastructure Setup

This directory contains scripts and configurations for setting up a Docker-based infrastructure on Debian 12, as an alternative to Proxmox virtualization.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Debian 12 Host                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Internet  │  │   10Gbit    │  │   ZFS Pools │        │
│  │     NIC     │  │     NIC     │  │             │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│         │                │                │               │
│         ▼                ▼                ▼               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Internet  │  │   NFS Mount │  │   data      │        │
│  │   Access    │  │   (Synology)│  │   backup    │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
├─────────────────────────────────────────────────────────────┤
│                    Docker Engine                            │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Nginx     │  │   Certbot   │  │   App       │        │
│  │  (Reverse   │  │  (SSL/TLS)  │  │ Containers  │        │
│  │   Proxy)    │  │             │  │             │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

- `1_host_setup/` - Initial Debian 12 setup and hardening
- `2_network_config/` - Dual NIC configuration (Internet + 10Gbit NAS)
- `3_docker_install/` - Docker and Docker Compose installation
- `4_ssl_setup/` - Nginx and Let's Encrypt SSL configuration
- `5_storage_setup/` - ZFS pools and NFS mounting
- `6_backup_scripts/` - Backup and restore automation
- `7_operations/` - Day-to-day operational scripts

## Key Features

### Network Configuration
- **Internet NIC**: Standard network access
- **10Gbit NIC**: Dedicated connection to Synology NAS
- **NFS Mount**: Persistent storage for Docker volumes

### Storage Strategy
- **ZFS data pool**: Mirror configuration for application data
- **ZFS backup pool**: Mirror configuration for backups
- **NFS integration**: Additional storage from Synology NAS
- **Docker volumes**: Bind mounts to ZFS/NFS locations

### SSL/TLS Management
- **Automatic certificates**: Let's Encrypt with HTTP challenge
- **Domain pattern**: `{hostname}.planet-rocklog.com`
- **Auto-renewal**: Cron-based certificate updates

### Backup Strategy
- **ZFS snapshots**: Native ZFS snapshot management
- **Docker volume backup**: Container-aware backup scripts
- **Timestamped backups**: Human-readable backup names
- **Restore capabilities**: Full restore functionality

### Security
- **SSH hardening**: Key-based authentication only
- **Non-root user**: Docker operations without root
- **Network isolation**: Separate networks for different purposes

## Implementation Order

1. **Host Setup** (`1_host_setup/`)
   - Debian 12 installation
   - SSH hardening
   - Non-root user creation

2. **Network Configuration** (`2_network_config/`)
   - Dual NIC setup
   - NFS mounting

3. **Docker Installation** (`3_docker_install/`)
   - Docker Engine
   - Docker Compose
   - User permissions

4. **Storage Setup** (`5_storage_setup/`)
   - ZFS pools creation
   - Mount point configuration

5. **SSL Setup** (`4_ssl_setup/`)
   - Nginx installation
   - Certbot configuration
   - Certificate automation

6. **Backup Scripts** (`6_backup_scripts/`)
   - ZFS snapshot automation
   - Docker volume backup
   - Restore procedures

7. **Operations** (`7_operations/`)
   - Day-to-day management scripts
   - Monitoring and maintenance

## Benefits Over Proxmox

- **Lower overhead**: Near-native performance
- **Resource efficiency**: Shared kernel, minimal per-container overhead
- **Simpler management**: Docker Compose for orchestration
- **Cost effective**: Better resource utilization
- **Rapid deployment**: Container-based application deployment

## Trade-offs

- **OS isolation**: Limited to Linux containers
- **Hardware passthrough**: No direct hardware access
- **Snapshot granularity**: Container-level vs VM-level
- **Management tools**: CLI-based vs web UI

## Prerequisites

- Debian 12 minimal installation
- At least 2 network interfaces
- 2+ additional drives for ZFS pools
- Synology NAS with NFS export
- Domain DNS configuration for SSL certificates 