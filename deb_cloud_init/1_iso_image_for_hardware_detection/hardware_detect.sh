#!/bin/bash

# Hardware Detection Script for Debian Cloud-Init Deployment
# This script detects server hardware and sends a detailed report via email

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/hardware-detect.log"
REPORT_FILE="/tmp/hardware-report.txt"
HOSTNAME="server-$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

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

# Initialize system
setup_environment() {
    log "Setting up hardware detection environment"
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Set hostname
    hostnamectl set-hostname "$HOSTNAME"
    
    # Wait for network to be ready
    print_status "INFO" "Waiting for network connectivity..."
    for i in {1..30}; do
        if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            print_status "SUCCESS" "Network connectivity established"
            break
        fi
        if [ $i -eq 30 ]; then
            print_status "WARNING" "Network connectivity not established, continuing anyway"
        fi
        sleep 1
    done
    
    # Install required packages if not present
    if ! command -v curl >/dev/null 2>&1; then
        print_status "INFO" "Installing required packages..."
        apt-get update -qq
        apt-get install -y curl wget ethtool pciutils dmidecode >/dev/null 2>&1 || true
    fi
}

# Detect storage devices
detect_storage_devices() {
    log "Detecting storage devices"
    print_status "INFO" "Detecting storage devices..."
    
    # NVMe drives
    local nvme_drives=()
    if ls /dev/nvme* >/dev/null 2>&1; then
        while IFS= read -r -d '' drive; do
            if [[ "$drive" =~ nvme[0-9]+n[0-9]+$ ]]; then
                nvme_drives+=("$drive")
            fi
        done < <(find /dev -name "nvme*" -type b -print0 2>/dev/null | sort -z)
    fi
    
    # SATA drives
    local sata_drives=()
    for drive in /dev/sd[a-z]; do
        if [ -b "$drive" ]; then
            sata_drives+=("$drive")
        fi
    done
    
    # USB drives
    local usb_drives=()
    for drive in /dev/sd[a-z]; do
        if [ -b "$drive" ] && [[ "$(udevadm info --name="$drive" --query=property | grep ID_BUS=usb)" ]]; then
            usb_drives+=("$drive")
        fi
    done
    
    # Store results
    echo "NVME_DRIVES=(${nvme_drives[*]})" > /tmp/storage_detection.txt
    echo "SATA_DRIVES=(${sata_drives[*]})" >> /tmp/storage_detection.txt
    echo "USB_DRIVES=(${usb_drives[*]})" >> /tmp/storage_detection.txt
    
    print_status "SUCCESS" "Found ${#nvme_drives[@]} NVMe drives, ${#sata_drives[@]} SATA drives, ${#usb_drives[@]} USB drives"
}

# Detect network interfaces
detect_network_interfaces() {
    log "Detecting network interfaces"
    print_status "INFO" "Detecting network interfaces..."
    
    local network_interfaces=()
    local interface_details=()
    
    # Get all network interfaces
    while IFS= read -r interface; do
        if [[ "$interface" =~ ^[a-zA-Z0-9]+$ ]] && [ "$interface" != "lo" ]; then
            network_interfaces+=("$interface")
            
            # Get interface details
            local mac=$(ip link show "$interface" | grep link | awk '{print $2}')
            local speed=$(ethtool "$interface" 2>/dev/null | grep Speed | awk '{print $2}' || echo "Unknown")
            local driver=$(ethtool -i "$interface" 2>/dev/null | grep driver | awk '{print $2}' || echo "Unknown")
            local model=$(lspci | grep -i ethernet | grep "$interface" | cut -d: -f3- || echo "Unknown")
            
            interface_details+=("$interface|$mac|$speed|$driver|$model")
        fi
    done < <(ip link show | grep -E "^[0-9]+:" | awk -F: '{print $2}' | tr -d ' ')
    
    # Store results
    echo "NETWORK_INTERFACES=(${network_interfaces[*]})" > /tmp/network_detection.txt
    printf "%s\n" "${interface_details[@]}" > /tmp/network_details.txt
    
    print_status "SUCCESS" "Found ${#network_interfaces[@]} network interfaces"
}

# Detect system information
detect_system_info() {
    log "Detecting system information"
    print_status "INFO" "Detecting system information..."
    
    # CPU information
    local cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    local cpu_cores=$(lscpu | grep "CPU(s):" | head -1 | awk '{print $2}')
    local cpu_threads=$(lscpu | grep "Thread(s) per core" | awk '{print $4}')
    local total_threads=$((cpu_cores * cpu_threads))
    
    # Memory information
    local memory_total=$(free -h | grep Mem | awk '{print $2}')
    local memory_type=$(dmidecode -t memory 2>/dev/null | grep "Type:" | head -1 | awk '{print $2}' || echo "Unknown")
    
    # Motherboard information
    local motherboard=$(dmidecode -t baseboard 2>/dev/null | grep "Product Name" | head -1 | cut -d: -f2 | xargs || echo "Unknown")
    
    # BIOS information
    local bios_vendor=$(dmidecode -t bios 2>/dev/null | grep "Vendor" | head -1 | cut -d: -f2 | xargs || echo "Unknown")
    local bios_version=$(dmidecode -t bios 2>/dev/null | grep "Version" | head -1 | cut -d: -f2 | xargs || echo "Unknown")
    
    # Store results
    cat > /tmp/system_info.txt << EOF
CPU_MODEL="$cpu_model"
CPU_CORES=$cpu_cores
CPU_THREADS=$cpu_threads
TOTAL_THREADS=$total_threads
MEMORY_TOTAL="$memory_total"
MEMORY_TYPE="$memory_type"
MOTHERBOARD="$motherboard"
BIOS_VENDOR="$bios_vendor"
BIOS_VERSION="$bios_version"
EOF
    
    print_status "SUCCESS" "System information detected"
}

# Generate hardware report
create_hardware_report() {
    log "Creating hardware report"
    print_status "INFO" "Creating hardware report..."
    
    # Load detected information
    source /tmp/storage_detection.txt
    source /tmp/network_detection.txt
    source /tmp/system_info.txt
    
    # Create report
    cat > "$REPORT_FILE" << EOF
=== Hardware Detection Report ===
Date: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $HOSTNAME
Detection Time: $(($(date +%s) - $(stat -c %Y /proc/uptime))) seconds

=== System Information ===
CPU: $CPU_MODEL
Cores: $CPU_CORES physical, $TOTAL_THREADS logical
Memory: $MEMORY_TOTAL $MEMORY_TYPE
Motherboard: $MOTHERBOARD
BIOS: $BIOS_VENDOR $BIOS_VERSION

=== Storage Devices ===
EOF
    
    # Add NVMe drives
    if [ ${#NVME_DRIVES[@]} -gt 0 ]; then
        echo "NVMe Drives:" >> "$REPORT_FILE"
        for drive in "${NVME_DRIVES[@]}"; do
            local size=$(lsblk -d -o SIZE "$drive" | tail -1)
            local model=$(lsblk -d -o MODEL "$drive" | tail -1)
            local serial=$(lsblk -d -o SERIAL "$drive" | tail -1)
            printf "  %-12s %-8s %-30s %s\n" "$drive" "$size" "$model" "$serial" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    fi
    
    # Add SATA drives
    if [ ${#SATA_DRIVES[@]} -gt 0 ]; then
        echo "SATA Drives:" >> "$REPORT_FILE"
        for drive in "${SATA_DRIVES[@]}"; do
            local size=$(lsblk -d -o SIZE "$drive" | tail -1)
            local model=$(lsblk -d -o MODEL "$drive" | tail -1)
            local serial=$(lsblk -d -o SERIAL "$drive" | tail -1)
            printf "  %-12s %-8s %-30s %s\n" "$drive" "$size" "$model" "$serial" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    fi
    
    # Add network interfaces
    echo "=== Network Interfaces ===" >> "$REPORT_FILE"
    while IFS='|' read -r interface mac speed driver model; do
        echo "Interface: $interface" >> "$REPORT_FILE"
        echo "  MAC: $mac" >> "$REPORT_FILE"
        echo "  Speed: $speed" >> "$REPORT_FILE"
        echo "  Driver: $driver" >> "$REPORT_FILE"
        echo "  Model: $model" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done < /tmp/network_details.txt
    
    # Add generated configuration
    echo "=== Generated Configuration ===" >> "$REPORT_FILE"
    echo "NVME_DRIVES=(${NVME_DRIVES[*]})" >> "$REPORT_FILE"
    echo "NETWORK_INTERFACES=(${NETWORK_INTERFACES[*]})" >> "$REPORT_FILE"
    
    # Determine interface assignments
    if [ ${#NETWORK_INTERFACES[@]} -ge 2 ]; then
        echo "WAN_IFACE=${NETWORK_INTERFACES[0]}" >> "$REPORT_FILE"
        echo "NAS_IFACE=${NETWORK_INTERFACES[1]}" >> "$REPORT_FILE"
    fi
    
    # Determine storage assignments
    if [ ${#NVME_DRIVES[@]} -ge 3 ]; then
        echo "DATA_POOL_DRIVES=\"${NVME_DRIVES[0]} ${NVME_DRIVES[1]}\"" >> "$REPORT_FILE"
        echo "OS_POOL_DRIVE=\"${NVME_DRIVES[2]}\"" >> "$REPORT_FILE"
    elif [ ${#NVME_DRIVES[@]} -ge 2 ]; then
        echo "DATA_POOL_DRIVES=\"${NVME_DRIVES[0]} ${NVME_DRIVES[1]}\"" >> "$REPORT_FILE"
        echo "OS_POOL_DRIVE=\"${NVME_DRIVES[0]}\"" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
    
    # Add recommendations
    echo "=== Recommendations ===" >> "$REPORT_FILE"
    if [ ${#NVME_DRIVES[@]} -ge 3 ]; then
        echo "- Use ${NVME_DRIVES[0]} and ${NVME_DRIVES[1]} for ZFS data pool (mirror)" >> "$REPORT_FILE"
        echo "- Use ${NVME_DRIVES[2]} for OS pool (single drive)" >> "$REPORT_FILE"
    elif [ ${#NVME_DRIVES[@]} -ge 2 ]; then
        echo "- Use ${NVME_DRIVES[0]} and ${NVME_DRIVES[1]} for ZFS data pool (mirror)" >> "$REPORT_FILE"
        echo "- Use ${NVME_DRIVES[0]} for OS pool (single drive)" >> "$REPORT_FILE"
    fi
    
    if [ ${#NETWORK_INTERFACES[@]} -ge 2 ]; then
        echo "- Configure ${NETWORK_INTERFACES[0]} as WAN interface" >> "$REPORT_FILE"
        echo "- Configure ${NETWORK_INTERFACES[1]} as NAS interface" >> "$REPORT_FILE"
        
        # Check if second interface is 10Gbit
        local nas_speed=$(grep "${NETWORK_INTERFACES[1]}" /tmp/network_details.txt | cut -d'|' -f3)
        if [[ "$nas_speed" == *"10000"* ]]; then
            echo "- Set MTU 9000 on ${NETWORK_INTERFACES[1]} for optimal 10Gbit performance" >> "$REPORT_FILE"
        fi
    fi
    
    echo "" >> "$REPORT_FILE"
    
    print_status "SUCCESS" "Hardware report created: $REPORT_FILE"
}

# Generate cloud-init template
generate_cloud_init_template() {
    log "Generating cloud-init template"
    print_status "INFO" "Generating cloud-init template..."
    
    # Load detected information
    source /tmp/storage_detection.txt
    source /tmp/network_detection.txt
    source /tmp/system_info.txt
    
    # Create cloud-init template
    cat > /tmp/cloud-init-template.yml << EOF
#cloud-config
# Generated cloud-init configuration template
# Based on hardware detection from $HOSTNAME
# Date: $(date '+%Y-%m-%d %H:%M:%S')

hostname: server-$(date +%Y%m%d-%H%M%S)

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

network:
  version: 2
  ethernets:
EOF
    
    # Add network interfaces
    if [ ${#NETWORK_INTERFACES[@]} -ge 2 ]; then
        cat >> /tmp/cloud-init-template.yml << EOF
    ${NETWORK_INTERFACES[0]}:
      dhcp4: false
      addresses:
        - 203.0.113.10/24  # WAN IP - CHANGE THIS
      gateway4: 203.0.113.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
    
    ${NETWORK_INTERFACES[1]}:
      dhcp4: false
      addresses:
        - 192.168.1.10/24  # NAS IP - CHANGE THIS
      mtu: 9000
EOF
    fi
    
    cat >> /tmp/cloud-init-template.yml << EOF

mounts:
  - [ "192.168.1.100:/volume1/shared", "/mnt/nas", "nfs", "rw,hard,intr,rsize=8192,wsize=8192", "0", "0" ]

runcmd:
EOF
    
    # Add ZFS pool creation
    if [ ${#NVME_DRIVES[@]} -ge 3 ]; then
        cat >> /tmp/cloud-init-template.yml << EOF
  # Create ZFS pools
  - zpool create data mirror /dev/${NVME_DRIVES[0]} /dev/${NVME_DRIVES[1]}
  - zpool create rpool /dev/${NVME_DRIVES[2]}
  
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
EOF
    elif [ ${#NVME_DRIVES[@]} -ge 2 ]; then
        cat >> /tmp/cloud-init-template.yml << EOF
  # Create ZFS pools
  - zpool create data mirror /dev/${NVME_DRIVES[0]} /dev/${NVME_DRIVES[1]}
  - zpool create rpool /dev/${NVME_DRIVES[0]}
  
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
EOF
    fi
    
    cat >> /tmp/cloud-init-template.yml << EOF
  
  # Create mount directories
  - mkdir -p /data/docker /data/apps /mnt/nas
  
  # Mount NFS
  - mount -a
  
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
  
  # Configure firewall
  - ufw allow from 203.0.113.0/24 to any port 22
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - ufw allow 8080:8090/tcp
  - ufw --force enable
  
  # Set timezone
  - timedatectl set-timezone Europe/Zurich
EOF
    
    # Append template to report
    echo "=== Cloud-Init Template ===" >> "$REPORT_FILE"
    cat /tmp/cloud-init-template.yml >> "$REPORT_FILE"
    
    print_status "SUCCESS" "Cloud-init template generated"
}

# Send email report
send_email_report() {
    log "Sending email report"
    print_status "INFO" "Sending email report..."
    
    # Check if email configuration exists
    if [ ! -f "$SCRIPT_DIR/email_config.sh" ]; then
        print_status "WARNING" "Email configuration not found, skipping email report"
        return 0
    fi
    
    # Source email configuration
    source "$SCRIPT_DIR/email_config.sh"
    
    # Check if required variables are set
    if [ -z "$SMTP_SERVER" ] || [ -z "$EMAIL_FROM" ] || [ -z "$EMAIL_TO" ]; then
        print_status "WARNING" "Email configuration incomplete, skipping email report"
        return 0
    fi
    
    # Create email content
    local email_subject="Hardware Detection Report - $HOSTNAME"
    local email_body=$(cat "$REPORT_FILE")
    
    # Send email using curl
    if command -v curl >/dev/null 2>&1; then
        local smtp_url="smtp://$SMTP_SERVER:$SMTP_PORT"
        local email_data="From: $EMAIL_FROM
To: $EMAIL_TO
Subject: $email_subject
Content-Type: text/plain; charset=UTF-8

$email_body"
        
        if curl --mail-from "$EMAIL_FROM" \
                --mail-rcpt "$EMAIL_TO" \
                --upload-file <(echo "$email_data") \
                --ssl-reqd \
                --user "$EMAIL_FROM:$EMAIL_PASSWORD" \
                "$smtp_url" >/dev/null 2>&1; then
            print_status "SUCCESS" "Email report sent to $EMAIL_TO"
        else
            print_status "ERROR" "Failed to send email report"
        fi
    else
        print_status "WARNING" "curl not available, cannot send email"
    fi
}

# Display console report
display_console_report() {
    log "Displaying console report"
    print_status "INFO" "Displaying hardware report on console..."
    
    echo ""
    echo "=================================================="
    echo "              HARDWARE DETECTION REPORT"
    echo "=================================================="
    echo ""
    
    # Display summary
    source /tmp/storage_detection.txt
    source /tmp/network_detection.txt
    source /tmp/system_info.txt
    
    echo "System: $CPU_MODEL ($CPU_CORES cores, $TOTAL_THREADS threads)"
    echo "Memory: $MEMORY_TOTAL $MEMORY_TYPE"
    echo "Storage: ${#NVME_DRIVES[@]} NVMe drives, ${#SATA_DRIVES[@]} SATA drives"
    echo "Network: ${#NETWORK_INTERFACES[@]} interfaces"
    echo ""
    
    # Display full report
    cat "$REPORT_FILE"
    
    echo ""
    echo "=================================================="
    echo "Report saved to: $REPORT_FILE"
    echo "Log file: $LOG_FILE"
    echo "=================================================="
    echo ""
}

# Wait for user confirmation
wait_for_user_confirmation() {
    log "Waiting for user confirmation"
    print_status "INFO" "Hardware detection complete"
    echo ""
    echo "Press Enter to shutdown or Ctrl+C to continue..."
    read -r
}

# Main execution
main() {
    log "Starting hardware detection"
    print_status "INFO" "Starting hardware detection on $HOSTNAME"
    
    # Run detection steps
    setup_environment
    detect_storage_devices
    detect_network_interfaces
    detect_system_info
    create_hardware_report
    generate_cloud_init_template
    send_email_report
    display_console_report
    wait_for_user_confirmation
    
    log "Hardware detection completed successfully"
    print_status "SUCCESS" "Hardware detection completed"
}

# Run main function
main "$@" 