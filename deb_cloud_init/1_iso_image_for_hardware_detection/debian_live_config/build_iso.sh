#!/bin/bash

# Debian Live ISO Build Script for Hardware Detection
# This script creates a minimal Debian Live ISO for hardware detection

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="/workspace/debian-hardware-detect-build"
ISO_NAME="debian-hardware-detect-$(date +%Y%m%d-%H%M%S)"
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
        
        # Detect package manager
        if command -v apt-get >/dev/null 2>&1; then
            # Debian/Ubuntu
            apt-get update
            apt-get install -y "${missing_packages[@]}"
        elif command -v dnf >/dev/null 2>&1; then
            # Fedora/RHEL/CentOS
            print_status "INFO" "Detected Fedora/RHEL system, installing equivalent packages..."
            
            # Map Debian packages to Fedora equivalents
            local fedora_packages=()
            for package in "${missing_packages[@]}"; do
                case $package in
                    "live-build")
                        fedora_packages+=("livecd-tools")
                        ;;
                    "live-config")
                        fedora_packages+=("livecd-tools")
                        ;;
                    "live-boot")
                        fedora_packages+=("livecd-tools")
                        ;;
                    "live-tools")
                        fedora_packages+=("livecd-tools")
                        ;;
                    "debootstrap")
                        fedora_packages+=("debootstrap")
                        ;;
                    "squashfs-tools")
                        fedora_packages+=("squashfs-tools")
                        ;;
                    "xorriso")
                        fedora_packages+=("xorriso")
                        ;;
                    "isolinux")
                        fedora_packages+=("syslinux")
                        ;;
                    "syslinux-common")
                        fedora_packages+=("syslinux")
                        ;;
                    "syslinux-efi")
                        fedora_packages+=("syslinux")
                        ;;
                    "grub-pc-bin")
                        fedora_packages+=("grub2")
                        ;;
                    "grub-efi-amd64-bin")
                        fedora_packages+=("grub2-efi-x64")
                        ;;
                    "mtools")
                        fedora_packages+=("mtools")
                        ;;
                    "dosfstools")
                        fedora_packages+=("dosfstools")
                        ;;
                    "rsync")
                        fedora_packages+=("rsync")
                        ;;
                    "curl")
                        fedora_packages+=("curl")
                        ;;
                    "wget")
                        fedora_packages+=("wget")
                        ;;
                    *)
                        fedora_packages+=("$package")
                        ;;
                esac
            done
            
            dnf install -y "${fedora_packages[@]}"
        elif command -v yum >/dev/null 2>&1; then
            # Older RHEL/CentOS
            yum install -y "${missing_packages[@]}"
        else
            print_status "ERROR" "Unsupported package manager. Please install the required packages manually."
            exit 1
        fi
    fi
    
    print_status "SUCCESS" "Prerequisites check completed"
}

# Create build directory structure
create_build_structure() {
    print_status "INFO" "Creating build directory structure..."
    
    # Clean up previous build completely
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
        --bootappend-live "boot=live components username=live hostname=hardware-detect keyboard-layouts=ch locales=de_CH.UTF-8" \
        --bootloader grub-efi \
        --debian-installer false \
        --iso-application "Debian Hardware Detection Live" \
        --iso-publisher "Debian Hardware Detection Project" \
        --iso-volume "Debian Hardware Detection Live" \
        --mode debian \
        --security true \
        --source false \
        --updates true \
        --verbose
    
    print_status "SUCCESS" "Build directory structure created"
}

# Configure packages
configure_packages() {
    print_status "INFO" "Configuring packages..."
    
    # Create necessary directories
    mkdir -p config/package-lists
    
    # Create packages list for hardware detection
    cat > config/package-lists/hardware-detect.list.chroot << 'EOF'
# Essential packages for hardware detection
curl
wget
ethtool
pciutils
dmidecode
util-linux
net-tools
iproute2
systemd
systemd-sysv
grub-efi-amd64
grub-efi-amd64-bin
keyboard-configuration
console-setup
console-data
EOF
    
    # Note: No excludes list needed for minimal hardware detection ISO
    
    print_status "SUCCESS" "Package configuration completed"
}

# Configure hardware detection scripts
configure_hardware_detection() {
    print_status "INFO" "Configuring hardware detection scripts..."
    
    # Create scripts directory
    mkdir -p config/includes.chroot/usr/local/bin
    mkdir -p config/includes.chroot/usr/local/sbin
    
    # Copy hardware detection script
    cp "$PROJECT_DIR/hardware_detect.sh" config/includes.chroot/usr/local/bin/
    chmod +x config/includes.chroot/usr/local/bin/hardware_detect.sh
    
    # Copy email configuration
    cp "$PROJECT_DIR/email_config.sh" config/includes.chroot/usr/local/bin/
    chmod +x config/includes.chroot/usr/local/bin/email_config.sh
    
    # Create auto-start script
    cat > config/includes.chroot/usr/local/bin/auto-detect.sh << 'EOF'
#!/bin/bash
# Auto-start hardware detection script

set -e

echo "=== Debian Hardware Detection Live ==="
echo "Starting automatic hardware detection..."
echo ""

# Wait for network to be ready
echo "Waiting for network connectivity..."
for i in {1..60}; do
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo "Network connectivity established"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "Warning: Network connectivity not established after 60 seconds"
    fi
    sleep 1
done

# Run hardware detection
echo "Starting hardware detection..."
/usr/local/bin/hardware_detect.sh

echo ""
echo "Hardware detection completed."
echo "Check your email for the hardware report."
echo ""
echo "Press Enter to shutdown or Ctrl+C to continue..."
read -r

# Shutdown the system
echo "Shutting down..."
shutdown -h now
EOF
    
    chmod +x config/includes.chroot/usr/local/bin/auto-detect.sh
    
    # Create manual detection script
    cat > config/includes.chroot/usr/local/bin/manual-detect.sh << 'EOF'
#!/bin/bash
# Manual hardware detection script

echo "=== Manual Hardware Detection ==="
echo "This script will detect hardware and send a report via email"
echo ""

# Check email configuration
if [ ! -f /usr/local/bin/email_config.sh ]; then
    echo "Error: Email configuration not found"
    exit 1
fi

# Show current email configuration
echo "Current email configuration:"
source /usr/local/bin/email_config.sh
echo "SMTP Server: $SMTP_SERVER:$SMTP_PORT"
echo "From: $EMAIL_FROM"
echo "To: $EMAIL_TO"
echo ""

read -p "Do you want to test email configuration? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    /usr/local/bin/email_config.sh test
fi

echo ""
read -p "Do you want to run hardware detection? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Hardware detection cancelled"
    exit 0
fi

# Run hardware detection
/usr/local/bin/hardware_detect.sh

echo ""
echo "Hardware detection completed."
echo "Check your email for the hardware report."
EOF
    
    chmod +x config/includes.chroot/usr/local/bin/manual-detect.sh
    
    print_status "SUCCESS" "Hardware detection configuration completed"
}

# Configure auto-start
configure_autostart() {
    print_status "INFO" "Configuring auto-start..."
    
    # Create necessary directories
    mkdir -p config/includes.chroot/etc/systemd/system
    mkdir -p config/includes.chroot/etc/systemd/system/multi-user.target.wants
    mkdir -p config/includes.chroot/etc
    
    # Create systemd service for auto-start
    cat > config/includes.chroot/etc/systemd/system/hardware-detect.service << 'EOF'
[Unit]
Description=Hardware Detection Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/auto-detect.sh
StandardOutput=journal
StandardError=journal
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable the service
    ln -sf /etc/systemd/system/hardware-detect.service config/includes.chroot/etc/systemd/system/multi-user.target.wants/
    
    # Create alternative startup script for console
    cat > config/includes.chroot/etc/rc.local << 'EOF'
#!/bin/bash
# Hardware detection startup script

# Wait for system to be fully booted
sleep 10

# Check if running in live environment
if [ -f /etc/live/config.conf ]; then
    echo "Starting hardware detection in 5 seconds..."
    echo "Press Ctrl+C to cancel"
    sleep 5
    
    # Run hardware detection
    /usr/local/bin/auto-detect.sh
fi

exit 0
EOF
    
    chmod +x config/includes.chroot/etc/rc.local
    
    print_status "SUCCESS" "Auto-start configuration completed"
}

# Configure boot menu
configure_boot() {
    print_status "INFO" "Configuring boot menu..."
    
    # Create necessary directories
    mkdir -p config/includes.binary/isolinux
    
    # Create boot menu configuration
    cat > config/includes.binary/isolinux/isolinux.cfg << 'EOF'
# ISOLINUX configuration for hardware detection
UI menu.c32
prompt 0
menu title Debian Hardware Detection Live
timeout 300

label auto-detect
        menu label ^Auto Hardware Detection
        menu default
        kernel /live/vmlinuz
        append initrd=/live/initrd.img boot=live components username=live hostname=hardware-detect

label manual-detect
        menu label ^Manual Hardware Detection
        kernel /live/vmlinuz
        append initrd=/live/initrd.img boot=live components username=live hostname=hardware-detect manual=true

label live-failsafe
        menu label ^Live System (failsafe)
        kernel /live/vmlinuz
        append initrd=/live/initrd.img boot=live components memtest noapic noapm nodma nomce nolapic nomodeset nosmp nosplash vga=normal

label memtest
        menu label ^Memory test
        kernel /install/mt86plus

label hd
        menu label ^Boot from first hard disk
        localboot 0x80
EOF
    
    print_status "SUCCESS" "Boot menu configuration completed"
}

# Configure desktop environment (minimal)
configure_desktop() {
    print_status "INFO" "Configuring desktop environment..."
    
    # Install minimal desktop packages
    cat >> config/package-lists/hardware-detect.list.chroot << 'EOF'
# Minimal desktop for hardware detection
xorg
openbox
xterm
lxpanel
EOF
    
    # Create desktop configuration
    mkdir -p config/includes.chroot/etc/skel/.config/openbox
    cat > config/includes.chroot/etc/skel/.config/openbox/autostart << 'EOF'
#!/bin/bash
# Openbox autostart script for hardware detection

# Start panel
lxpanel &

# Show hardware detection options
sleep 5
xterm -e "echo 'Debian Hardware Detection Live'; echo ''; echo 'Options:'; echo '1. Auto detection (runs automatically)'; echo '2. Manual detection: /usr/local/bin/manual-detect.sh'; echo '3. Test email: /usr/local/bin/email_config.sh test'; echo ''; echo 'Press any key to close...'; read -n 1" &
EOF
    
    chmod +x config/includes.chroot/etc/skel/.config/openbox/autostart
    
    # Create desktop shortcuts
    mkdir -p config/includes.chroot/etc/skel/Desktop
    cat > config/includes.chroot/etc/skel/Desktop/Hardware-Detection.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Hardware Detection
Comment=Run hardware detection manually
Exec=xterm -e sudo /usr/local/bin/manual-detect.sh
Icon=system-run
Terminal=true
Categories=System;
EOF
    
    cat > config/includes.chroot/etc/skel/Desktop/Test-Email.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Test Email
Comment=Test email configuration
Exec=xterm -e sudo /usr/local/bin/email_config.sh test
Icon=mail-send
Terminal=true
Categories=Network;
EOF
    
    chmod +x config/includes.chroot/etc/skel/Desktop/*.desktop
    
    print_status "SUCCESS" "Desktop configuration completed"
}

# Configure email templates
configure_email_templates() {
    print_status "INFO" "Configuring email templates..."
    
    # Create templates directory
    mkdir -p config/includes.chroot/usr/local/share/hardware-detect/templates
    
    # Copy email templates
    if [ -d "$PROJECT_DIR/templates" ]; then
        cp -r "$PROJECT_DIR/templates"/* config/includes.chroot/usr/local/share/hardware-detect/templates/
    fi
    
    # Create default email template
    cat > config/includes.chroot/usr/local/share/hardware-detect/templates/hardware_report_template.txt << 'EOF'
=== Hardware Detection Report ===
Date: {DATE}
Hostname: {HOSTNAME}
Detection Time: {DETECTION_TIME} seconds

=== System Information ===
CPU: {CPU_MODEL}
Cores: {CPU_CORES} physical, {TOTAL_THREADS} logical
Memory: {MEMORY_TOTAL} {MEMORY_TYPE}
Motherboard: {MOTHERBOARD}
BIOS: {BIOS_VENDOR} {BIOS_VERSION}

=== Storage Devices ===
{STORAGE_INFO}

=== Network Interfaces ===
{NETWORK_INFO}

=== Generated Configuration ===
{CONFIG_INFO}

=== Recommendations ===
{RECOMMENDATIONS}

---
This report was automatically generated by the Debian Hardware Detection System.
EOF
    
    print_status "SUCCESS" "Email templates configuration completed"
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
        # Move ISO to output directory
        mv binary.iso "$OUTPUT_DIR/$ISO_NAME.iso"
        cd "$OUTPUT_DIR"
        sha256sum "$ISO_NAME.iso" > "$ISO_NAME.iso.sha256"
        print_status "SUCCESS" "ISO built successfully: $OUTPUT_DIR/$ISO_NAME.iso"
        print_status "INFO" "Checksum: $OUTPUT_DIR/$ISO_NAME.iso.sha256"
    elif [ -f "live-image-amd64.hybrid.iso" ]; then
        mv live-image-amd64.hybrid.iso "$OUTPUT_DIR/$ISO_NAME.iso"
        cd "$OUTPUT_DIR"
        sha256sum "$ISO_NAME.iso" > "$ISO_NAME.iso.sha256"
        print_status "SUCCESS" "ISO built successfully: $OUTPUT_DIR/$ISO_NAME.iso"
        print_status "INFO" "Checksum: $OUTPUT_DIR/$ISO_NAME.iso.sha256"
    else
        # Look for any ISO file in the current directory
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
    print_status "INFO" "Starting Debian Hardware Detection ISO build..."
    print_status "INFO" "Build directory: $BUILD_DIR"
    print_status "INFO" "Output directory: $OUTPUT_DIR"
    
    # Clean any existing build artifacts
    if [ -d "$BUILD_DIR" ]; then
        print_status "INFO" "Cleaning existing build directory..."
        rm -rf "$BUILD_DIR"
    fi
    
    # Run build steps
    check_prerequisites
    create_build_structure
    configure_packages
    configure_hardware_detection
    configure_autostart
    configure_boot
    configure_desktop
    configure_email_templates
    build_iso
    cleanup
    
    print_status "SUCCESS" "Debian Hardware Detection ISO build completed successfully!"
    print_status "INFO" "ISO file: $OUTPUT_DIR/$ISO_NAME.iso"
    print_status "INFO" "Next steps:"
    print_status "INFO" "1. Configure email settings in the ISO"
    print_status "INFO" "2. Test the ISO in a virtual environment"
    print_status "INFO" "3. Create bootable USB: sudo dd if=$OUTPUT_DIR/$ISO_NAME.iso of=/dev/sdX bs=4M status=progress"
    print_status "INFO" "4. Boot target server from the USB drive"
    print_status "INFO" "5. Hardware report will be sent via email automatically"
}

# Run main function
main "$@" 