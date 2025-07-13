#!/bin/bash

# Debian Live ISO Build Script for Cloud-Init Deployment
# This script creates a Debian Live ISO with cloud-init enabled

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="/tmp/debian-cloud-init-build"
ISO_NAME="debian-cloud-init-$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="$PROJECT_DIR/output"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    print_status "INFO" "Checking prerequisites..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_status "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Check required packages
    local required_packages=(
        "live-build"
        "live-config"
        "live-boot"
        "live-tools"
        "debootstrap"
        "squashfs-tools"
        "xorriso"
        "isolinux"
        "syslinux-common"
        "syslinux-efi"
        "grub-pc-bin"
        "grub-efi-amd64-bin"
        "mtools"
        "dosfstools"
        "rsync"
        "curl"
        "wget"
    )
    
    local missing_packages=()
    for package in "${required_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            missing_packages+=("$package")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        print_status "WARNING" "Missing packages: ${missing_packages[*]}"
        print_status "INFO" "Installing missing packages..."
        apt-get update
        apt-get install -y "${missing_packages[@]}"
    fi
    
    print_status "SUCCESS" "Prerequisites check completed"
}

# Create build directory structure
create_build_structure() {
    print_status "INFO" "Creating build directory structure..."
    
    # Clean up previous build
    rm -rf "$BUILD_DIR"
    
    # Create build directory
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Initialize live build
    lb config \
        --architectures amd64 \
        --binary-images iso-hybrid \
        --distribution bookworm \
        --linux-flavours amd64 \
        --archive-areas "main contrib non-free" \
        --apt-recommends false \
        --apt-options "--yes -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold" \
        --bootappend-live "boot=live components username=live hostname=debian-cloud-init keyboard-layouts=ch locales=de_CH.UTF-8" \
        --bootloader grub-efi \
        --debian-installer false \
        --iso-application "Debian Cloud-Init Live" \
        --iso-publisher "Debian Cloud-Init Project" \
        --iso-volume "Debian Cloud-Init Live" \
        --mode debian \
        --packages-lists "minimal" \
        --security true \
        --source false \
        --updates true \
        --verbose
    
    print_status "SUCCESS" "Build directory structure created"
}

# Configure packages
configure_packages() {
    print_status "INFO" "Configuring packages..."
    
    # Create packages list
    cat > config/package-lists/cloud-init.list.chroot << 'EOF'
# Essential packages for cloud-init deployment
cloud-init
cloud-initramfs-growroot
cloud-utils
zfsutils-linux
zfs-dkms
docker.io
docker-compose
nginx
emacs
vim
git
curl
wget
ufw
nfs-common
htop
tmux
unzip
rsync
ethtool
pciutils
dmidecode
fail2ban
unattended-upgrades
grub-efi-amd64
grub-efi-amd64-bin
keyboard-configuration
console-setup
console-data
EOF
    
    # Create excludes list
    cat > config/package-lists/excludes.list.chroot << 'EOF'
# Exclude unnecessary packages
task-desktop
task-gnome-desktop
task-kde-desktop
task-xfce-desktop
task-lxde-desktop
task-mate-desktop
task-cinnamon-desktop
task-lxqt-desktop
task-print-server
task-ssh-server
task-web-server
task-mail-server
task-database-server
task-file-server
EOF
    
    print_status "SUCCESS" "Package configuration completed"
}

# Configure cloud-init
configure_cloud_init() {
    print_status "INFO" "Configuring cloud-init..."
    
    # Create cloud-init configuration directory
    mkdir -p config/includes.chroot/etc/cloud
    
    # Copy cloud-init templates
    cp -r "$PROJECT_DIR/cloud_init_templates" config/includes.chroot/etc/cloud/
    
    # Create cloud-init configuration
    cat > config/includes.chroot/etc/cloud/cloud.cfg << 'EOF'
# Cloud-init configuration for Debian Live
config:
  ssh_pwauth: false
  disable_root: true

system_info:
  default_user:
    name: live
    groups: [sudo, docker]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL

datasource_list: [NoCloud, ConfigDrive]
datasource:
  NoCloud:
    fs_label: cidata
  ConfigDrive:
    dsmode: local

# Cloud-init modules to run
cloud_init_modules:
  - seed_random
  - write-files
  - growpart
  - resizefs
  - set_hostname
  - update_hostname
  - update_etc_hosts
  - ca-certs
  - rsyslog
  - users-groups
  - ssh

cloud_config_modules:
  - disk_setup
  - mounts
  - ssh-import-id
  - locale
  - set-passwords
  - grub-dpkg
  - apt-pipelining
  - apt-configure
  - package-update-upgrade-install
  - timezone
  - disable-ec2-metadata
  - runcmd

cloud_final_modules:
  - scripts-vendor
  - scripts-per-once
  - scripts-per-boot
  - scripts-per-instance
  - scripts-user
  - ssh-authkey-fingerprints
  - keys-to-console
  - phone-home
  - final-message
  - power-state-change

# Disable certain modules for live environment
disable_root: true
ssh_pwauth: false
EOF
    
    # Create cloud-init seed directory
    mkdir -p config/includes.chroot/var/lib/cloud/seed/nocloud
    
    # Copy default cloud-init user data
    cat > config/includes.chroot/var/lib/cloud/seed/nocloud/user-data << 'EOF'
#cloud-config
# Default cloud-init configuration for live environment

hostname: debian-cloud-init
fqdn: debian-cloud-init.local

users:
  - name: live
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: [sudo, docker]
    lock_passwd: false

ssh_pwauth: false
disable_root: true

packages:
  - cloud-init
  - zfsutils-linux
  - docker.io
  - nginx
  - emacs
  - vim
  - git

runcmd:
  - echo "Cloud-init live environment ready"
  - echo "Boot from this ISO to deploy with cloud-init"
EOF
    
    # Create cloud-init meta data
    cat > config/includes.chroot/var/lib/cloud/seed/nocloud/meta-data << 'EOF'
instance-id: debian-cloud-init-live
local-hostname: debian-cloud-init
EOF
    
    print_status "SUCCESS" "Cloud-init configuration completed"
}

# Configure boot and live environment
configure_boot() {
    print_status "INFO" "Configuring boot and live environment..."
    
    # Create live environment configuration
    cat > config/includes.chroot/etc/live/config.conf.d/cloud-init.conf << 'EOF'
# Live environment configuration for cloud-init
LIVE_HOSTNAME="debian-cloud-init"
LIVE_USERNAME="live"
LIVE_USER_FULLNAME="Live User"
LIVE_USER_DEFAULT_GROUPS="sudo,docker"
LIVE_CONFIG_PERSISTENT="false"
LIVE_CONFIG_PERSISTENT_MEDIA="false"
EOF
    
    # Create autoinstall configuration
    mkdir -p config/includes.chroot/etc/autoinstall
    cat > config/includes.chroot/etc/autoinstall/preseed.cfg << 'EOF'
# Preseed configuration for automated installation
d-i debian-installer/locale string en_US
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string server
d-i netcfg/get_domain string local
d-i passwd/root-password-crypted password $6$rounds=656000$salt$hashedpassword
d-i passwd/user-fullname string Admin User
d-i passwd/username string admin
d-i passwd/user-password-crypted password $6$rounds=656000$salt$hashedpassword
d-i passwd/user-password-again password $6$rounds=656000$salt$hashedpassword
d-i user-setup/allow-password-weak boolean true
d-i pkgsel/include string openssh-server cloud-init zfsutils-linux
d-i pkgsel/update-policy select none
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
EOF
    
    # Create boot menu configuration
    cat > config/includes.binary/isolinux/isolinux.cfg << 'EOF'
# ISOLINUX configuration
UI menu.c32
prompt 0
menu title Debian Cloud-Init Live
timeout 300

label live
        menu label ^Live System (Cloud-Init Ready)
        menu default
        kernel /live/vmlinuz
        append initrd=/live/initrd.img boot=live components username=live hostname=debian-cloud-init

label live-failsafe
        menu label ^Live System (failsafe)
        kernel /live/vmlinuz
        append initrd=/live/initrd.img boot=live components memtest noapic noapm nodma nomce nolapic nomodeset nosmp nosplash vga=normal

label install
        menu label ^Install with Cloud-Init
        kernel /live/vmlinuz
        append initrd=/live/initrd.img boot=live components username=live hostname=debian-cloud-init autoinstall url=file:///etc/autoinstall/preseed.cfg

label memtest
        menu label ^Memory test
        kernel /install/mt86plus

label hd
        menu label ^Boot from first hard disk
        localboot 0x80
EOF
    
    print_status "SUCCESS" "Boot configuration completed"
}

# Configure scripts and utilities
configure_scripts() {
    print_status "INFO" "Configuring scripts and utilities..."
    
    # Create scripts directory
    mkdir -p config/includes.chroot/usr/local/bin
    mkdir -p config/includes.chroot/usr/local/sbin
    
    # Copy deployment scripts
    if [ -d "$PROJECT_DIR/scripts" ]; then
        cp -r "$PROJECT_DIR/scripts"/* config/includes.chroot/usr/local/bin/
        chmod +x config/includes.chroot/usr/local/bin/*
    fi
    
    # Copy workload user creation script
    if [ -f "$PROJECT_DIR/scripts/create_workload_user.sh" ]; then
        cp "$PROJECT_DIR/scripts/create_workload_user.sh" config/includes.chroot/usr/local/bin/
        chmod +x config/includes.chroot/usr/local/bin/create_workload_user.sh
    fi
    
    # Create cloud-init deployment script
    cat > config/includes.chroot/usr/local/bin/deploy-cloud-init.sh << 'EOF'
#!/bin/bash
# Cloud-init deployment script

set -e

echo "=== Cloud-Init Deployment Script ==="
echo "This script will help you deploy a server using cloud-init"
echo ""

# Check if running in live environment
if [ ! -f /etc/live/config.conf ]; then
    echo "Error: This script must be run from the live environment"
    exit 1
fi

# Check for cloud-init configuration
if [ ! -f /etc/cloud/cloud_init_templates/base_config.yml ]; then
    echo "Error: Cloud-init templates not found"
    exit 1
fi

echo "Cloud-init templates found:"
ls -la /etc/cloud/cloud_init_templates/

echo ""
echo "To deploy a server:"
echo "1. Edit the cloud-init templates in /etc/cloud/cloud_init_templates/"
echo "2. Run the installation script"
echo "3. Reboot into the installed system"
echo ""

read -p "Do you want to start the installation? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Starting installation..."
    # Add installation logic here
else
    echo "Installation cancelled"
fi
EOF
    
    chmod +x config/includes.chroot/usr/local/bin/deploy-cloud-init.sh
    
    # Create desktop entry for deployment script
    mkdir -p config/includes.chroot/etc/skel/Desktop
    cat > config/includes.chroot/etc/skel/Desktop/Deploy-Cloud-Init.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Deploy Cloud-Init
Comment=Deploy server using cloud-init
Exec=xterm -e sudo /usr/local/bin/deploy-cloud-init.sh
Icon=system-run
Terminal=true
Categories=System;
EOF
    
    chmod +x config/includes.chroot/etc/skel/Desktop/Deploy-Cloud-Init.desktop
    
    print_status "SUCCESS" "Scripts configuration completed"
}

# Configure desktop environment (minimal)
configure_desktop() {
    print_status "INFO" "Configuring desktop environment..."
    
    # Install minimal desktop packages
    cat >> config/package-lists/cloud-init.list.chroot << 'EOF'
# Minimal desktop for cloud-init deployment
xorg
openbox
lxterminal
pcmanfm
EOF
    
    # Create desktop configuration
    mkdir -p config/includes.chroot/etc/skel/.config/openbox
    cat > config/includes.chroot/etc/skel/.config/openbox/autostart << 'EOF'
#!/bin/bash
# Openbox autostart script

# Start panel
lxpanel &

# Start file manager
pcmanfm --desktop &

# Show deployment script
sleep 5
xterm -e "echo 'Cloud-Init Deployment Environment'; echo ''; echo 'Double-click Deploy-Cloud-Init on desktop or run:'; echo 'sudo /usr/local/bin/deploy-cloud-init.sh'; echo ''; echo 'Press any key to close...'; read -n 1" &
EOF
    
    chmod +x config/includes.chroot/etc/skel/.config/openbox/autostart
    
    print_status "SUCCESS" "Desktop configuration completed"
}

# Build the ISO
build_iso() {
    print_status "INFO" "Building ISO..."
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Build the ISO
    lb build 2>&1 | tee build.log
    
    # Check if build was successful
    if [ -f "binary.iso" ]; then
        mv binary.iso "$OUTPUT_DIR/$ISO_NAME.iso"
        cd "$OUTPUT_DIR"
        sha256sum "$ISO_NAME.iso" > "$ISO_NAME.iso.sha256"
        print_status "SUCCESS" "ISO built successfully: $OUTPUT_DIR/$ISO_NAME.iso"
        print_status "INFO" "Checksum: $OUTPUT_DIR/$ISO_NAME.iso.sha256"
    else
        iso_file=$(find . -maxdepth 1 -name "*.iso" -type f | head -1)
        if [ -n "$iso_file" ] && [ -f "$iso_file" ]; then
            mv "$iso_file" "$OUTPUT_DIR/$ISO_NAME.iso"
            cd "$OUTPUT_DIR"
            sha256sum "$ISO_NAME.iso" > "$ISO_NAME.iso.sha256"
            print_status "SUCCESS" "ISO built successfully: $OUTPUT_DIR/$ISO_NAME.iso"
            print_status "INFO" "Checksum: $OUTPUT_DIR/$ISO_NAME.iso.sha256"
        else
            print_status "ERROR" "ISO build failed - no ISO file found"
            print_status "INFO" "Checking build directory contents:"
            ls -la
            exit 1
        fi
    fi
}

# Clean up
cleanup() {
    print_status "INFO" "Cleaning up build directory..."
    rm -rf "$BUILD_DIR"
    print_status "SUCCESS" "Cleanup completed"
}

# Main execution
main() {
    print_status "INFO" "Starting Debian Cloud-Init ISO build..."
    print_status "INFO" "Build directory: $BUILD_DIR"
    print_status "INFO" "Output directory: $OUTPUT_DIR"
    
    # Run build steps
    check_prerequisites
    create_build_structure
    configure_packages
    configure_cloud_init
    configure_boot
    configure_scripts
    configure_desktop
    build_iso
    cleanup
    
    print_status "SUCCESS" "Debian Cloud-Init ISO build completed successfully!"
    print_status "INFO" "ISO file: $OUTPUT_DIR/$ISO_NAME.iso"
    print_status "INFO" "Next steps:"
    print_status "INFO" "1. Test the ISO in a virtual environment"
    print_status "INFO" "2. Create bootable USB: sudo dd if=$OUTPUT_DIR/$ISO_NAME.iso of=/dev/sdX bs=4M status=progress"
    print_status "INFO" "3. Boot target server from the USB drive"
}

# Run main function
main "$@" 