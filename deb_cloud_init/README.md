# Debian Cloud-Init Deployment System

A complete system for automated Debian server deployment using cloud-init, with hardware detection and email reporting capabilities.

## Overview

This system provides two-stage deployment:

1. **Hardware Detection ISO**: Detects and reports hardware specifications via email
2. **Cloud-Init Deployment ISO**: Installs and configures Debian servers automatically

## Directory Structure

```
deb_cloud_init/
├── 1_iso_image_for_hardware_detection/     # Hardware detection ISO
│   ├── build_hardware_detection_iso.sh     # Build script for hardware detection ISO
│   ├── hardware_detect.sh                  # Hardware detection script
│   ├── email_config.sh                     # Email configuration
│   └── README.md                           # Hardware detection documentation
├── 2_iso_image_with_cloud_init/           # Cloud-init deployment ISO
│   ├── build_cloud_init_iso.sh            # Build script for deployment ISO
│   ├── cloud_init_templates/              # Cloud-init configuration templates
│   ├── scripts/                           # Deployment scripts
│   └── README.md                          # Deployment documentation
└── README.md                              # This file
```

## Quick Start

### 1. Build Hardware Detection ISO

```bash
cd deb_cloud_init/1_iso_image_for_hardware_detection/

# Build with default settings
sudo ./build_hardware_detection_iso.sh

# Build with custom email address
sudo ./build_hardware_detection_iso.sh --email admin@example.com

# Build with custom output directory
sudo ./build_hardware_detection_iso.sh --output /path/to/output
```

### 2. Build Cloud-Init Deployment ISO

```bash
cd deb_cloud_init/2_iso_image_with_cloud_init/

# Build with default settings
sudo ./build_cloud_init_iso.sh

# Build with SSH key and workload user
sudo ./build_cloud_init_iso.sh --ssh-key ~/.ssh/id_rsa.pub --workload myapp

# Build with root password
sudo ./build_cloud_init_iso.sh --password

# Build with all customizations
sudo ./build_cloud_init_iso.sh \
  --ssh-key ~/.ssh/id_rsa.pub \
  --workload myapp \
  --password \
  --output /path/to/output
```

## Hardware Detection ISO

### Features
- **Automatic hardware detection** on boot
- **Email reporting** with detailed hardware specifications
- **Manual detection tools** for interactive use
- **Minimal footprint** for fast booting

### Hardware Detected
- **Storage**: NVMe drives, SATA drives, RAID controllers
- **Network**: Ethernet interfaces, WiFi adapters
- **CPU**: Model, cores, frequency, cache
- **Memory**: Total RAM, DIMM configuration
- **Motherboard**: Manufacturer, model, BIOS version
- **PCI devices**: Graphics cards, network cards, etc.

### Usage
```bash
# Build the ISO
sudo ./build_hardware_detection_iso.sh --email admin@example.com

# Burn to USB
sudo dd if=output/*.iso of=/dev/sdX bs=4M status=progress

# Boot on target hardware
# System will automatically detect hardware and send email report
```

## Cloud-Init Deployment ISO

### Features
- **Automated Debian installation** with cloud-init
- **ZFS storage configuration** with RAID-1 support
- **Docker and containerization** setup
- **Dual NIC networking** (WAN + 10Gbit NAS)
- **Security hardening** with UFW firewall
- **User management** (admin + workload users)
- **Supervisor process management**

### Configuration Options

#### SSH Key Configuration
```bash
# Set SSH key for admin user
sudo ./build_cloud_init_iso.sh --ssh-key ~/.ssh/id_rsa.pub
```

#### Workload User Creation
```bash
# Create workload user with custom name
sudo ./build_cloud_init_iso.sh --workload myapp
```

#### Root Password
```bash
# Set root password interactively
sudo ./build_cloud_init_iso.sh --password
```

### Cloud-Init Templates

The system includes modular cloud-init templates:

- **`base_config.yml`**: Base system configuration
- **`zfs_config.yml`**: ZFS storage setup
- **`network_config.yml`**: Network configuration
- **`docker_config.yml`**: Docker setup
- **`workload_user_config.yml`**: Workload user creation

### Usage
```bash
# Build with all features
sudo ./build_cloud_init_iso.sh \
  --ssh-key ~/.ssh/id_rsa.pub \
  --workload myapp \
  --password \
  --clean

# Burn to USB
sudo dd if=output/*.iso of=/dev/sdX bs=4M status=progress

# Boot on target hardware
# System will automatically install and configure
```

## Deployment Workflow

### Stage 1: Hardware Detection
1. **Build hardware detection ISO**
2. **Boot on target hardware**
3. **Receive email report** with hardware specifications
4. **Review hardware details** for deployment planning

### Stage 2: Server Deployment
1. **Build cloud-init deployment ISO** with customizations
2. **Boot on target hardware**
3. **Automatic installation** and configuration
4. **SSH access** to deployed server

### Stage 3: Post-Deployment
1. **Verify deployment** with health checks
2. **Create workload users** if needed
3. **Deploy applications** using Docker
4. **Monitor and maintain** the system

## Configuration Examples

### Basic Deployment
```bash
# Hardware detection
cd deb_cloud_init/1_iso_image_for_hardware_detection/
sudo ./build_hardware_detection_iso.sh --email admin@example.com

# Server deployment
cd ../2_iso_image_with_cloud_init/
sudo ./build_cloud_init_iso.sh --ssh-key ~/.ssh/id_rsa.pub
```

### Advanced Deployment
```bash
# Hardware detection with custom output
sudo ./build_hardware_detection_iso.sh \
  --email admin@example.com \
  --output /mnt/storage/isos \
  --clean

# Server deployment with all features
sudo ./build_cloud_init_iso.sh \
  --ssh-key ~/.ssh/id_rsa.pub \
  --workload myapp \
  --password \
  --output /mnt/storage/isos \
  --clean \
  --verbose
```

## Security Features

### User Management
- **Admin user**: Full sudo access, SSH key authentication
- **Workload users**: Limited sudo access, Docker group membership
- **Root access**: Disabled SSH, available via `sudo su -`

### Network Security
- **UFW firewall**: Default deny incoming, allow specific ports
- **SSH hardening**: Key-based authentication, no password login
- **Docker security**: Group-based access, no sudo required

### Data Protection
- **ZFS encryption**: Optional encryption for data pools
- **Controlled access**: Workload users have limited data access
- **Audit trail**: Limited sudo access for monitoring

## Troubleshooting

### Build Issues
```bash
# Check prerequisites
sudo apt-get install live-build live-config live-boot live-tools

# Clean build
sudo ./build_cloud_init_iso.sh --clean --verbose

# Check logs
tail -f build.log
```

### Deployment Issues
```bash
# Check cloud-init logs
sudo journalctl -u cloud-init

# Check system status
sudo systemctl status
sudo zpool status
sudo docker info

# Verify network
ip addr show
sudo ufw status
```

### Hardware Detection Issues
```bash
# Manual hardware detection
/usr/local/bin/hardware_detect.sh

# Check email configuration
/usr/local/bin/email_config.sh

# View detection logs
tail -f /var/log/hardware_detect.log
```

## Requirements

### Build Environment
- **Debian/Ubuntu** system
- **Root privileges** for ISO building
- **Live build tools** (automatically installed)
- **Internet connection** for package downloads

### Target Hardware
- **x86_64** architecture
- **UEFI boot** support (recommended)
- **Network connectivity** for email reporting
- **Minimum 4GB RAM** for deployment

## Support

For issues and questions:
1. Check the individual README files in each directory
2. Review build logs for error messages
3. Verify prerequisites and system requirements
4. Test with minimal configuration first

## License

This project is provided as-is for educational and deployment purposes. 