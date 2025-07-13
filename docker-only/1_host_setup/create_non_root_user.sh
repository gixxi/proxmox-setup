#!/bin/bash

# Create non-root user with Docker privileges
# This script creates a user that can run Docker commands without sudo

set -e

# Configuration
USERNAME="${1:-gix}"
FULL_NAME="${2:-Docker User}"
SSH_KEY="${3:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

print_status "Creating user: $USERNAME"

# Create user if it doesn't exist
if id "$USERNAME" &>/dev/null; then
    print_warning "User $USERNAME already exists"
else
    useradd -m -s /bin/bash -c "$FULL_NAME" "$USERNAME"
    print_status "User $USERNAME created successfully"
fi

# Create .ssh directory and set permissions
mkdir -p "/home/$USERNAME/.ssh"
chmod 700 "/home/$USERNAME/.ssh"
touch "/home/$USERNAME/.ssh/authorized_keys"
chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"

# Add SSH key if provided
if [[ -n "$SSH_KEY" ]]; then
    echo "$SSH_KEY" >> "/home/$USERNAME/.ssh/authorized_keys"
    print_status "SSH key added to authorized_keys"
else
    print_warning "No SSH key provided. You'll need to add one manually:"
    echo "echo 'YOUR_PUBLIC_KEY' >> /home/$USERNAME/.ssh/authorized_keys"
fi

# Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    print_status "Docker not found. Installing Docker..."
    
    # Update package list
    apt update
    
    # Install prerequisites
    apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    print_status "Docker installed successfully"
else
    print_status "Docker already installed"
fi

# Add user to docker group
usermod -aG docker "$USERNAME"

# Install Docker Compose if not already installed
if ! command -v docker-compose &> /dev/null; then
    print_status "Installing Docker Compose..."
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    print_status "Docker Compose installed successfully"
else
    print_status "Docker Compose already installed"
fi

# Create sudoers entry for Docker commands (optional)
SUDOERS_FILE="/etc/sudoers.d/$USERNAME-docker"
cat > "$SUDOERS_FILE" << EOF
# Allow $USERNAME to run Docker commands without password
$USERNAME ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/docker-compose, /usr/local/bin/docker-compose
EOF

chmod 440 "$SUDOERS_FILE"

# Create common directories
mkdir -p "/home/$USERNAME/docker"
mkdir -p "/home/$USERNAME/scripts"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/docker"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/scripts"

print_status "User setup completed successfully!"
print_status "User: $USERNAME"
print_status "Home directory: /home/$USERNAME"
print_status "Docker group membership: Yes"
print_status "Sudo access for Docker: Yes"

print_warning "Important: Log out and log back in for group changes to take effect"
print_warning "Or run: newgrp docker"

# Test Docker access
print_status "Testing Docker access..."
if su - "$USERNAME" -c "docker --version" 2>/dev/null; then
    print_status "Docker access test successful"
else
    print_warning "Docker access test failed. User may need to log out and back in."
fi

echo ""
print_status "Next steps:"
echo "1. Log out and log back in as $USERNAME"
echo "2. Test Docker: docker run hello-world"
echo "3. Proceed to network configuration" 