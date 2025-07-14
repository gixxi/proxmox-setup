# PXE TFTP Server Setup

This directory contains everything needed to set up a PXE TFTP server to boot the Debian Hardware Detection ISO over the network.

## Overview

PXE (Preboot eXecution Environment) allows computers to boot from a network server instead of local storage. This setup provides:

- **Network boot capability** for hardware detection
- **No USB drives required** - boot directly over network
- **Centralized management** - serve multiple machines from one server
- **Automated deployment** - perfect for headless servers

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Target Host   │    │  PXE TFTP       │    │  Email Server   │
│                 │    │  Server         │    │                 │
│ - Boots via PXE │◄──►│ - dnsmasq       │◄──►│ - Receives      │
│ - Runs hardware │    │ - tftp-server   │    │   hardware      │
│   detection     │    │ - Serves ISO    │    │   reports       │
│ - Sends report  │    │ - DHCP server   │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Components

### 1. **dnsmasq** - DHCP and TFTP server
- Provides DHCP leases to target machines
- Serves TFTP boot files
- Handles PXE boot requests

### 2. **tftp-server** - File transfer protocol
- Serves boot files (kernel, initrd, ISO)
- Lightweight and fast

### 3. **syslinux** - Boot loader
- Provides PXE boot loader files
- Handles boot menu and kernel loading

## Network Requirements

- **Server IP**: Static IP on the target network
- **Ports**: 
  - UDP 67 (DHCP)
  - UDP 69 (TFTP)
  - TCP 53 (DNS, optional)
- **Firewall**: Must allow DHCP and TFTP traffic

## Quick Start

1. **Install packages**:
   ```bash
   sudo dnf install -y dnsmasq syslinux tftp-server
   ```

2. **Configure network**:
   ```bash
   ./configure_network.sh
   ```

3. **Setup TFTP server**:
   ```bash
   ./setup_tftp.sh
   ```

4. **Configure dnsmasq**:
   ```bash
   ./configure_dnsmasq.sh
   ```

5. **Start services**:
   ```bash
   ./start_services.sh
   ```

## Usage

### Booting a target machine:

1. **Enable PXE boot** in target machine BIOS/UEFI
2. **Set network boot** as first boot option
3. **Power on** the target machine
4. **Select boot option** from PXE menu
5. **Hardware detection** runs automatically
6. **Report sent** via email

### Network boot process:

1. Target machine broadcasts DHCP request
2. dnsmasq responds with IP and PXE boot info
3. Target downloads boot loader via TFTP
4. Boot loader downloads kernel and initrd
5. System boots into hardware detection environment
6. Hardware detection runs and sends report

## Configuration Files

- `dnsmasq.conf` - DHCP and TFTP configuration
- `pxelinux.cfg/default` - PXE boot menu
- `tftpboot/` - Boot files directory
- `firewall.sh` - Firewall configuration

## Troubleshooting

### Common Issues:

1. **Target won't boot**:
   - Check firewall settings
   - Verify DHCP server is running
   - Check network connectivity

2. **DHCP not responding**:
   - Ensure dnsmasq is running
   - Check interface configuration
   - Verify no other DHCP servers

3. **TFTP timeout**:
   - Check TFTP server status
   - Verify file permissions
   - Check SELinux settings

### Debug Commands:

```bash
# Check service status
systemctl status dnsmasq
systemctl status tftp

# Check DHCP leases
cat /var/lib/misc/dnsmasq.leases

# Test TFTP
tftp localhost
get pxelinux.0
quit

# Check firewall
firewall-cmd --list-services
```

## Security Considerations

- **Network isolation**: Run on dedicated network if possible
- **Firewall rules**: Only allow necessary ports
- **DHCP scope**: Limit to target network range
- **Access control**: Restrict TFTP access if needed

## Performance

- **Boot time**: ~30-60 seconds depending on network speed
- **Bandwidth**: ~500MB per boot (kernel + initrd + ISO)
- **Concurrent boots**: Limited by network bandwidth
- **Storage**: ~1GB for boot files and ISO

## Integration with Hardware Detection

The PXE server works seamlessly with the hardware detection ISO:

1. **ISO extraction**: Boot files extracted from ISO
2. **Network boot**: Target boots via PXE
3. **Hardware detection**: Runs automatically
4. **Email reporting**: Report sent to configured email
5. **Shutdown**: System powers off after detection

## Next Steps

After setting up the PXE server:

1. **Test with a VM** first
2. **Configure target machines** for PXE boot
3. **Deploy to production** network
4. **Monitor boot logs** for issues
5. **Scale as needed** for multiple networks

## Files in this directory

- `README.md` - This documentation
- `install_packages.sh` - Package installation script
- `configure_network.sh` - Network configuration
- `setup_tftp.sh` - TFTP server setup
- `configure_dnsmasq.sh` - dnsmasq configuration
- `start_services.sh` - Service management
- `firewall.sh` - Firewall configuration
- `test_pxe.sh` - PXE boot testing
- `dnsmasq.conf` - dnsmasq configuration template
- `pxelinux.cfg/default` - PXE boot menu template 