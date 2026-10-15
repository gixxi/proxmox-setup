# Common Resources

This directory contains shared resources used by both the hardware detection and cloud-init deployment systems.

## 📁 **Directory Structure**

```
common/
├── README.md                    # This file
├── scripts/                     # Common scripts
│   ├── zfs_setup.sh            # ZFS configuration
│   ├── network_setup.sh        # Network configuration
│   └── security_setup.sh       # Security configuration
├── configs/                     # Common configurations
│   ├── ssh_config              # SSH hardening
│   ├── firewall_config         # UFW configuration
│   └── docker_config           # Docker configuration
└── templates/                   # Common templates
    ├── fstab_template          # Fstab template
    └── netplan_template        # Netplan template
```

## 🔧 **Scripts**

### **ZFS Setup (`scripts/zfs_setup.sh`)**

Handles ZFS pool and dataset creation with proper configuration.

```bash
#!/bin/bash
# ZFS Setup Script
# Usage: ./zfs_setup.sh <data_drives> <os_drive> [options]

# Example usage:
./zfs_setup.sh "nvme0n1 nvme1n1" "nvme2n1" \
  --compression lz4 \
  --recordsize 128K \
  --atime off
```

**Features:**
- Creates data pool with mirror configuration
- Creates OS pool with single drive
- Sets optimal ZFS properties
- Creates standard dataset structure
- Configures mountpoints

### **Network Setup (`scripts/network_setup.sh`)**

Configures dual NIC setup with proper routing.

```bash
#!/bin/bash
# Network Setup Script
# Usage: ./network_setup.sh <wan_interface> <nas_interface> <wan_ip> <nas_ip>

# Example usage:
./network_setup.sh eno1 eno2 "203.0.113.10/24" "192.168.1.10/24"
```

**Features:**
- Configures WAN interface (Internet)
- Configures NAS interface (10Gbit)
- Sets up proper routing
- Configures NFS mounts
- Enables IP forwarding

### **Security Setup (`scripts/security_setup.sh`)**

Applies security hardening configurations.

```bash
#!/bin/bash
# Security Setup Script
# Usage: ./security_setup.sh <admin_user> <ssh_key_file>

# Example usage:
./security_setup.sh admin ~/.ssh/id_rsa.pub
```

**Features:**
- SSH hardening
- Firewall configuration
- User access control
- Service hardening
- Security updates

## ⚙️ **Configurations**

### **SSH Configuration (`configs/ssh_config`)**

Template for SSH hardening configuration.

```bash
# SSH Hardening Configuration
Port 22
Protocol 2
AllowUsers admin
LoginGraceTime 2m
PermitRootLogin no
StrictModes yes
MaxAuthTries 1
PubkeyAuthentication yes
AuthorizedKeysFile %h/.ssh/authorized_keys
RhostsRSAAuthentication no
PasswordAuthentication no
PermitEmptyPasswords no
UsePAM yes
```

### **Firewall Configuration**

ufw is no longer used. All hosts use the shared iptables firewall
`2_infrastructure/setup_firewall.sh` (profiles `proxmox`, `bastion`, `app-vm`, `docker-public`):

```bash
ADMIN_SOURCES="203.0.113.0/24 192.168.1.0/24" ./setup_firewall.sh docker-public --install --disable-ufw
```

Application ports are not opened on the host: containers publish on 127.0.0.1 and nginx proxies.

### **Docker Configuration (`configs/docker_config`)**

Docker daemon configuration template.

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

## 📋 **Templates**

### **Fstab Template (`templates/fstab_template`)**

Template for /etc/fstab configuration.

```bash
# /etc/fstab: static file system information
#
# ZFS datasets are managed by ZFS, not fstab
# Only add non-ZFS mounts here

# NFS mounts
192.168.1.100:/volume1/shared /mnt/nas nfs rw,hard,intr,rsize=8192,wsize=8192 0 0

# USB drives (if needed)
# /dev/sdc1 /mnt/usb vfat defaults 0 0

# Temporary filesystems
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
tmpfs /var/tmp tmpfs defaults,noatime,mode=1777 0 0
```

### **Netplan Template (`templates/netplan_template`)**

Template for Netplan network configuration.

```yaml
# /etc/netplan/01-network.yaml
network:
  version: 2
  ethernets:
    {WAN_INTERFACE}:
      dhcp4: false
      addresses:
        - {WAN_IP}
      gateway4: {WAN_GATEWAY}
      nameservers:
        addresses: [{DNS_SERVERS}]
      mtu: 1500
    
    {NAS_INTERFACE}:
      dhcp4: false
      addresses:
        - {NAS_IP}
      mtu: 9000
      routes:
        - to: 192.168.1.0/24
          via: 192.168.1.1
          table: 200
      routing-policy:
        - from: 192.168.1.0/24
          table: 200
```

## 🔄 **Usage Examples**

### **Using Common Scripts in Cloud-Init**

```yaml
#cloud-config
runcmd:
  # Copy common scripts
  - cp /media/cdrom/common/scripts/* /usr/local/bin/
  - chmod +x /usr/local/bin/*.sh
  
  # Run ZFS setup
  - /usr/local/bin/zfs_setup.sh "nvme0n1 nvme1n1" "nvme2n1"
  
  # Run network setup
  - /usr/local/bin/network_setup.sh eno1 eno2 "203.0.113.10/24" "192.168.1.10/24"
  
  # Run security setup
  - /usr/local/bin/security_setup.sh admin /root/.ssh/id_rsa.pub
```

### **Using Common Configurations**

```yaml
#cloud-config
write_files:
  - path: /etc/ssh/sshd_config
    content: |
      # Include common SSH configuration
      $(cat /media/cdrom/common/configs/ssh_config)
    owner: root:root
    permissions: '0600'
  
  - path: /etc/docker/daemon.json
    content: |
      $(cat /media/cdrom/common/configs/docker_config)
    owner: root:root
    permissions: '0644'
```

### **Using Common Templates**

```yaml
#cloud-config
runcmd:
  # Generate fstab from template
  - sed 's/{NFS_SERVER}/192.168.1.100/g' /media/cdrom/common/templates/fstab_template > /etc/fstab
  
  # Generate netplan from template
  - sed -e 's/{WAN_INTERFACE}/eno1/g' \
        -e 's/{NAS_INTERFACE}/eno2/g' \
        -e 's/{WAN_IP}/203.0.113.10\/24/g' \
        -e 's/{NAS_IP}/192.168.1.10\/24/g' \
        /media/cdrom/common/templates/netplan_template > /etc/netplan/01-network.yaml
```

## 🛠️ **Customization**

### **Adding Custom Scripts**

```bash
# Create custom script
cat > common/scripts/custom_setup.sh << 'EOF'
#!/bin/bash
# Custom setup script
echo "Running custom setup..."
# Add your custom logic here
EOF

chmod +x common/scripts/custom_setup.sh
```

### **Adding Custom Configurations**

```bash
# Create custom configuration
cat > common/configs/custom_config << 'EOF'
# Custom configuration
# Add your custom settings here
EOF
```

### **Adding Custom Templates**

```bash
# Create custom template
cat > common/templates/custom_template << 'EOF'
# Custom template with variables
# {VARIABLE1} will be replaced during deployment
# {VARIABLE2} will be replaced during deployment
EOF
```

## 🔍 **Testing**

### **Test Scripts Locally**

```bash
# Test ZFS setup script
./common/scripts/zfs_setup.sh --dry-run "nvme0n1 nvme1n1" "nvme2n1"

# Test network setup script
./common/scripts/network_setup.sh --dry-run eno1 eno2 "203.0.113.10/24" "192.168.1.10/24"

# Test security setup script
./common/scripts/security_setup.sh --dry-run admin ~/.ssh/id_rsa.pub
```

### **Validate Configurations**

```bash
# Validate SSH configuration
sshd -t -f common/configs/ssh_config

# Validate Docker configuration
python3 -m json.tool common/configs/docker_config

# Validate Netplan configuration
netplan try --dry-run common/templates/netplan_template
```

## 📚 **Best Practices**

1. **Modularity**: Keep scripts focused on single responsibilities
2. **Reusability**: Design scripts to work with different hardware configurations
3. **Error Handling**: Include proper error checking and logging
4. **Documentation**: Document all scripts and configurations
5. **Testing**: Test all scripts in a safe environment before deployment
6. **Version Control**: Track changes to common resources
7. **Backup**: Keep backups of working configurations

## 🔗 **Integration**

These common resources are designed to integrate seamlessly with:
- Hardware detection system
- Cloud-init deployment system
- Manual server configuration
- Automated deployment pipelines

## 📄 **Reference**

- [ZFS on Linux](https://openzfs.github.io/openzfs-docs/)
- [Netplan Documentation](https://netplan.io/reference/)
- [SSH Configuration](https://man.openbsd.org/sshd_config)
- [Docker Daemon Configuration](https://docs.docker.com/engine/reference/commandline/dockerd/)
- [UFW Documentation](https://help.ubuntu.com/community/UFW) 