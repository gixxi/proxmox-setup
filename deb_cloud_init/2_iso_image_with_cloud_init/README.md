# Cloud-Init Deployment ISO

This directory contains tools to create a Debian Live ISO that automatically installs and configures servers using cloud-init based on hardware detection reports.

## 🎯 **Purpose**

The cloud-init deployment ISO is a Debian Live system that:
1. Boots with cloud-init enabled
2. Reads hardware-specific configuration
3. Installs Debian with ZFS storage
4. Configures networking and services
5. Sets up Docker and applications
6. Applies security hardening

## 📁 **Files Overview**

- `cloud_init_templates/` - Cloud-init configuration templates
- `debian_live_config/` - Debian Live build configuration
- `scripts/` - Deployment and configuration scripts

## 🚀 **Quick Start**

### **1. Review Hardware Report**
```bash
# After running hardware detection, review the email report
# Note the hardware configuration details
```

### **2. Customize Cloud-Init Configuration**
```bash
# Edit cloud_init_templates/ with your specific hardware config
nano cloud_init_templates/base_config.yml
nano cloud_init_templates/network_config.yml
```

### **3. Build the ISO**
```bash
# Build the cloud-init deployment ISO
./debian_live_config/build_iso.sh
```

### **4. Deploy Server**
```bash
# Boot target server from the cloud-init ISO
# Server will install and configure automatically
```

## ☁️ **Cloud-Init Configuration**

### **Configuration Structure**

The cloud-init configuration is split into modular components:

#### **Base Configuration (`base_config.yml`)**
```yaml
#cloud-config
hostname: server-{TIMESTAMP}
users:
  - name: admin
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-rsa YOUR_PUBLIC_KEY_HERE

packages:
  - zfsutils-linux
  - zfs-dkms
  - docker.io
  - nginx
  - emacs
  - vim
  - git
  - curl
  - wget
  - ufw
  - nfs-common

ssh_pwauth: false
disable_root: true
```

#### **ZFS Configuration (`zfs_config.yml`)**
```yaml
# ZFS storage configuration
# Based on hardware detection report
runcmd:
  # Create ZFS pools
  - zpool create data mirror /dev/nvme0n1 /dev/nvme1n1
  - zpool create rpool /dev/nvme2n1
  
  # Create datasets
  - zfs create data/docker
  - zfs create data/apps
  - zfs create rpool/ROOT
  - zfs create rpool/ROOT/debian
  - zfs create rpool/var
  - zfs create rpool/var/log
  
  # Set mountpoints
  - zfs set mountpoint=/data/docker data/docker
  - zfs set mountpoint=/data/apps data/apps
  - zfs set mountpoint=/ rpool/ROOT/debian
  - zfs set mountpoint=/var rpool/var
  - zfs set mountpoint=/var/log rpool/var/log
```

#### **Network Configuration (`network_config.yml`)**
```yaml
# Network configuration
# Based on hardware detection report
network:
  version: 2
  ethernets:
    eno1:  # WAN Interface
      dhcp4: false
      addresses:
        - 203.0.113.10/24  # CHANGE THIS
      gateway4: 203.0.113.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
    
    eno2:  # NAS Interface
      dhcp4: false
      addresses:
        - 192.168.1.10/24  # CHANGE THIS
      mtu: 9000

mounts:
  - [ "192.168.1.100:/volume1/shared", "/mnt/nas", "nfs", "rw,hard,intr,rsize=8192,wsize=8192", "0", "0" ]
```

#### **Docker Configuration (`docker_config.yml`)**
```yaml
# Docker configuration
runcmd:
  # Configure Docker
  - mkdir -p /etc/docker
  - |
    cat > /etc/docker/daemon.json << 'DOCKER_EOF'
    {
      "storage-driver": "overlay2",
      "data-root": "/data/docker",
      "log-driver": "json-file",
      "log-opts": {
        "max-size": "10m",
        "max-file": "3"
      }
    }
    DOCKER_EOF
  
  # Start Docker
  - systemctl enable --now docker
```

### **Configuration Generation**

#### **Manual Configuration**
```bash
# 1. Copy template files
cp cloud_init_templates/base_config.yml cloud_init_templates/my_config.yml

# 2. Edit with your hardware details
nano cloud_init_templates/my_config.yml

# 3. Update network interfaces, IP addresses, SSH keys
```

#### **Automated Configuration**
```bash
# Use the configuration generator
./scripts/generate_cloud_init.sh \
  --hostname "server01" \
  --wan-ip "203.0.113.10/24" \
  --nas-ip "192.168.1.10/24" \
  --ssh-key "~/.ssh/id_rsa.pub" \
  --nvme-drives "nvme0n1 nvme1n1 nvme2n1" \
  --network-interfaces "eno1 eno2"
```

## 🔧 **Deployment Process**

### **Installation Flow**

```bash
# 1. Boot from cloud-init ISO
# 2. Cloud-init reads configuration
# 3. Debian installer runs with preseed
# 4. System reboots into installed OS
# 5. Cloud-init applies configuration
# 6. Services start automatically
```

### **Preseed Configuration**

The ISO includes a preseed file for automated installation:

```bash
# debian_live_config/autoinstall/preseed.cfg
d-i debian-installer/locale string en_US
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string server
d-i netcfg/get_domain string local
d-i passwd/root-password-crypted password $6$...
d-i passwd/user-fullname string Admin User
d-i passwd/username string admin
d-i passwd/user-password-crypted password $6$...
d-i passwd/user-password-again password $6$...
d-i user-setup/allow-password-weak boolean true
d-i pkgsel/include string openssh-server
d-i pkgsel/update-policy select none
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
```

### **ZFS Installation**

The system installs with ZFS support:

```bash
# Install ZFS packages
apt-get install -y zfsutils-linux zfs-dkms

# Create ZFS pools during installation
zpool create rpool /dev/nvme2n1
zpool create data mirror /dev/nvme0n1 /dev/nvme1n1

# Create datasets
zfs create rpool/ROOT
zfs create rpool/ROOT/debian
zfs create rpool/var
zfs create rpool/var/log
zfs create data/docker
zfs create data/apps
```

## 🔒 **Security Configuration**

### **SSH Hardening**
```yaml
ssh_config:
  PasswordAuthentication: false
  PubkeyAuthentication: true
  PermitRootLogin: false
  AllowUsers: admin
  Port: 22
  Protocol: 2
  LoginGraceTime: 30
  MaxAuthTries: 3
  StrictModes: true
  UsePAM: true
```

### **Firewall Configuration**
```yaml
runcmd:
  # Configure UFW firewall
  - ufw allow from 203.0.113.0/24 to any port 22
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - ufw allow 8080:8090/tcp
  - ufw --force enable
```

### **System Hardening**
```yaml
runcmd:
  # Disable unnecessary services
  - systemctl disable bluetooth
  - systemctl disable cups
  - systemctl disable avahi-daemon
  
  # Configure automatic security updates
  - apt-get install -y unattended-upgrades
  - dpkg-reconfigure -plow unattended-upgrades
```

## 📋 **Configuration Templates**

### **Template Variables**

Templates support variable substitution:

```yaml
# Variables that can be used in templates
{HOSTNAME}          # Server hostname
{WAN_IP}            # WAN interface IP
{NAS_IP}            # NAS interface IP
{GATEWAY}           # Default gateway
{DNS_SERVERS}       # DNS servers
{SSH_KEY}           # SSH public key
{NVME_DRIVES}       # NVMe drive list
{NETWORK_INTERFACES} # Network interface list
{TIMEZONE}          # System timezone
```

### **Custom Templates**

Create custom templates for specific use cases:

```bash
# Create application-specific template
cp cloud_init_templates/base_config.yml cloud_init_templates/app_server.yml

# Add application-specific configuration
cat >> cloud_init_templates/app_server.yml << 'EOF'
packages:
  - openjdk-17-jdk
  - maven
  - postgresql-client

runcmd:
  - mkdir -p /data/apps/myapp
  - chown admin:admin /data/apps/myapp
EOF
```

## 🛠️ **Scripts**

### **Configuration Generator**
```bash
# Generate cloud-init config from hardware report
./scripts/generate_cloud_init.sh \
  --hardware-report /path/to/hardware-report.txt \
  --output /path/to/cloud-init.yml
```

### **Configuration Validator**
```bash
# Validate cloud-init configuration
./scripts/validate_config.sh /path/to/cloud-init.yml
```

### **Installation Script**
```bash
# Run installation with cloud-init
./scripts/install_cloud_init.sh /path/to/cloud-init.yml
```

## 🔍 **Troubleshooting**

### **Common Issues**

#### **Cloud-Init Not Running**
```bash
# Check cloud-init status
cloud-init status

# Check cloud-init logs
tail -f /var/log/cloud-init-output.log

# Check cloud-init configuration
cat /etc/cloud/cloud.cfg
```

#### **ZFS Installation Fails**
```bash
# Check if ZFS modules are loaded
lsmod | grep zfs

# Check ZFS pool status
zpool status

# Check disk availability
lsblk -d -o NAME,SIZE,MODEL
```

#### **Network Configuration Issues**
```bash
# Check network interfaces
ip addr show

# Check network configuration
cat /etc/netplan/*.yaml

# Test network connectivity
ping -c 3 8.8.8.8
```

#### **Docker Installation Issues**
```bash
# Check Docker service status
systemctl status docker

# Check Docker configuration
cat /etc/docker/daemon.json

# Check Docker storage
docker info | grep "Storage Driver"
```

### **Debug Mode**

Enable debug logging in cloud-init:

```yaml
# Add to cloud-init configuration
debug: true
log_level: DEBUG
```

## 📊 **Example Deployments**

### **Basic Server**
```bash
# Minimal configuration for basic server
./scripts/generate_cloud_init.sh \
  --hostname "basic-server" \
  --wan-ip "203.0.113.10/24" \
  --ssh-key "~/.ssh/id_rsa.pub"
```

### **Application Server**
```bash
# Configuration for application server
./scripts/generate_cloud_init.sh \
  --hostname "app-server" \
  --wan-ip "203.0.113.11/24" \
  --nas-ip "192.168.1.11/24" \
  --ssh-key "~/.ssh/id_rsa.pub" \
  --template "app_server"
```

### **Database Server**
```bash
# Configuration for database server
./scripts/generate_cloud_init.sh \
  --hostname "db-server" \
  --wan-ip "203.0.113.12/24" \
  --nas-ip "192.168.1.12/24" \
  --ssh-key "~/.ssh/id_rsa.pub" \
  --template "database_server"
```

## 🔄 **Automation**

### **Batch Deployment**
```bash
# Deploy multiple servers
for server in server01 server02 server03; do
    ./scripts/generate_cloud_init.sh \
      --hostname "$server" \
      --wan-ip "203.0.113.$((10 + i))/24" \
      --ssh-key "~/.ssh/id_rsa.pub"
done
```

### **CI/CD Integration**
```bash
# Integrate with CI/CD pipeline
./scripts/generate_cloud_init.sh \
  --hostname "$CI_COMMIT_REF_SLUG" \
  --wan-ip "$WAN_IP" \
  --ssh-key "$SSH_PUBLIC_KEY" \
  --output "/artifacts/cloud-init.yml"
```

## 📚 **Best Practices**

1. **Test First**: Always test configurations in a virtual environment
2. **Version Control**: Track cloud-init configurations in version control
3. **Modular Design**: Use separate templates for different components
4. **Security First**: Always include security hardening configurations
5. **Documentation**: Document custom configurations and modifications
6. **Backup Strategy**: Implement backup and recovery procedures
7. **Monitoring**: Set up monitoring and alerting for deployed servers

## 🔗 **Next Steps**

After deployment:
1. Verify system configuration
2. Test all services and applications
3. Set up monitoring and backup
4. Document the deployment
5. Plan for maintenance and updates

## 📄 **Templates Reference**

See `cloud_init_templates/` directory for all available templates and examples. 