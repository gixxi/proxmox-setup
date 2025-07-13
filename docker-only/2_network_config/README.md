# Network Configuration - Dual NIC Setup

This directory contains scripts for configuring dual network interfaces on Debian 12.

## Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Debian 12 Host                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐                    ┌─────────────┐        │
│  │   Internet  │                    │   10Gbit    │        │
│  │     NIC     │                    │     NIC     │        │
│  │  (eth0/enp) │                    │  (eth1/enp) │        │
│  └─────────────┘                    └─────────────┘        │
│         │                                    │              │
│         ▼                                    ▼              │
│  ┌─────────────┐                    ┌─────────────┐        │
│  │   Internet  │                    │   Synology  │        │
│  │   Access    │                    │     NAS     │        │
│  │  (DHCP/     │                    │   (NFS)     │        │
│  │   Static)   │                    │             │        │
│  └─────────────┘                    └─────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Files

- `detect_interfaces.sh` - Detect and list available network interfaces
- `configure_dual_nic.sh` - Configure both network interfaces
- `setup_nfs_mount.sh` - Mount NFS share from Synology NAS
- `test_network.sh` - Test network connectivity

## Network Interface Configuration

### Internet NIC (Primary)
- **Purpose**: Internet access and external communication
- **Configuration**: DHCP or static IP
- **Network**: Your local network (e.g., 192.168.1.0/24)
- **Gateway**: Your router's IP address

### 10Gbit NIC (Secondary)
- **Purpose**: High-speed connection to Synology NAS
- **Configuration**: Static IP on dedicated network
- **Network**: Dedicated network (e.g., 10.0.0.0/24)
- **Gateway**: None (direct connection)

## Configuration Options

### Option 1: systemd-networkd (Recommended)
- Modern network configuration
- Better performance
- Cleaner configuration files

### Option 2: NetworkManager
- Traditional approach
- GUI configuration available
- More familiar to some users

## Prerequisites

- Two network interfaces detected
- Synology NAS with NFS export configured
- Network information for both interfaces

## Configuration Steps

1. **Detect Interfaces**
   ```bash
   ./detect_interfaces.sh
   ```

2. **Configure Network Interfaces**
   ```bash
   ./configure_dual_nic.sh
   ```

3. **Setup NFS Mount**
   ```bash
   ./setup_nfs_mount.sh
   ```

4. **Test Configuration**
   ```bash
   ./test_network.sh
   ```

## Network Configuration Examples

### Internet NIC (systemd-networkd)
```ini
[Match]
Name=enp0s3

[Network]
DHCP=yes
```

### 10Gbit NIC (systemd-networkd)
```ini
[Match]
Name=enp0s8

[Network]
Address=10.0.0.10/24
```

### NFS Mount (/etc/fstab)
```
192.168.1.100:/volume1/docker-data /mnt/nas nfs defaults,noatime 0 0
```

## Troubleshooting

### Common Issues
1. **Interface not detected**: Check hardware and drivers
2. **NFS mount fails**: Verify NAS IP and export permissions
3. **Network connectivity issues**: Check routing and firewall rules

### Debugging Commands
```bash
# Check interface status
ip link show

# Check IP configuration
ip addr show

# Test connectivity
ping -c 4 8.8.8.8

# Check NFS mounts
mount | grep nfs

# Check routing
ip route show
```

## Next Steps

After network configuration, proceed to:
1. `../3_docker_install/` - Install Docker and Docker Compose
2. `../5_storage_setup/` - Configure ZFS pools 