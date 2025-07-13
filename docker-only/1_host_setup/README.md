# Host Setup - Debian 12

This directory contains scripts for initial Debian 12 setup and hardening.

## Prerequisites

- Fresh Debian 12 minimal installation
- Root access
- SSH key pair for the user you want to create

## Files

- `install_debian12.sh` - Automated Debian 12 installation guide
- `create_non_root_user.sh` - Create non-root user with Docker privileges
- `harden_ssh.sh` - SSH hardening configuration
- `install_zfs.sh` - ZFS installation and basic configuration

## Installation Order

1. Install Debian 12 (manual or automated)
2. Run `create_non_root_user.sh` to create your user
3. Run `harden_ssh.sh` to secure SSH access
4. Run `install_zfs.sh` to prepare for storage setup

## Manual Debian 12 Installation Steps

### 1. Download and Boot
- Download Debian 12 netinst ISO
- Create bootable USB
- Boot from USB

### 2. Installation Options
- **Language**: English
- **Location**: Your timezone
- **Keyboard**: Your layout
- **Network**: Configure both NICs
- **Hostname**: Choose meaningful hostname
- **Domain**: Leave empty or set to `planet-rocklog.com`
- **Root password**: Set strong password
- **User account**: Create initial user (will be replaced)
- **Partitioning**: Use entire disk with LVM
- **Software selection**: Minimal installation only

### 3. Post-Installation
- Update system: `apt update && apt upgrade`
- Install essential packages: `apt install sudo curl wget git`

## Security Considerations

- Use strong passwords
- Keep root account for emergencies
- Create dedicated user for Docker operations
- Use SSH keys only (no password authentication)
- Regular security updates

## Next Steps

After completing host setup, proceed to:
1. `../2_network_config/` - Configure dual NIC setup
2. `../3_docker_install/` - Install Docker and Docker Compose 