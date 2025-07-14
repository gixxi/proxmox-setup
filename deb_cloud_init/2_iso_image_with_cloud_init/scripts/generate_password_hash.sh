#!/bin/bash

# Generate Password Hash for Cloud-Init
# This script generates a secure password hash for use in cloud-init configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if password is provided as argument
if [ -z "$1" ]; then
    print_status "ERROR" "Usage: $0 <password>"
    echo ""
    echo "Examples:"
    echo "  $0 mySecurePassword123"
    echo "  $0 \"Complex Password with Spaces\""
    echo ""
    echo "This script generates a SHA-512 password hash for cloud-init configuration."
    echo "The hash can be used in the 'chpasswd' section of your cloud-init YAML."
    exit 1
fi

PASSWORD="$1"

print_status "INFO" "Generating password hash for cloud-init..."

# Generate SHA-512 hash
HASH=$(openssl passwd -6 -salt xyz "$PASSWORD")

if [ $? -eq 0 ]; then
    print_status "SUCCESS" "Password hash generated successfully!"
    echo ""
    echo "Password: $PASSWORD"
    echo "Hash: $HASH"
    echo ""
    echo "Use this in your cloud-init configuration:"
    echo "---"
    echo "chpasswd:"
    echo "  list: |"
    echo "    root:$PASSWORD"
    echo "  expire: false"
    echo "---"
    echo ""
    echo "Or for the hash version:"
    echo "---"
    echo "chpasswd:"
    echo "  list: |"
    echo "    root:$HASH"
    echo "  expire: false"
    echo "---"
    echo ""
    print_status "WARNING" "Remember to:"
    echo "  - Use a strong, unique password"
    echo "  - Keep the password secure"
    echo "  - Root SSH login is disabled by default for security"
    echo "  - Access root via: sudo su - (as admin user)"
else
    print_status "ERROR" "Failed to generate password hash"
    exit 1
fi 