#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Starting Bastian VM provisioning..."

# --- Optional: Reuse common provisioning steps ---
# If 3_vm_provisioning/provision_vm.sh contains common setup steps
# (like user creation, package updates, ssh key setup), you might call it here:
#
# echo "Running common provisioning steps..."
# bash ../3_vm_provisioning/provision_vm.sh
#
# Or source it if it defines functions/variables needed later:
# source ../3_vm_provisioning/provision_vm.sh

# --- Install Nginx and UFW ---
echo "Updating package list..."
apt-get update

echo "Installing nginx and ufw..."
apt-get install -y nginx ufw

# --- Configure UFW (Uncomplicated Firewall) ---
echo "Configuring UFW firewall rules..."

# Reset UFW to default state (optional, but good for clean setup)
# ufw --force reset

# Default policies (optional but recommended: deny incoming, allow outgoing)
# ufw default deny incoming
# ufw default allow outgoing

# Allow SSH (port 22) from specific IPs
echo "Allowing SSH from specific IPs..."
ufw allow from 172.105.94.119 to any port 22 proto tcp
ufw allow from 116.203.216.1 to any port 22 proto tcp
ufw allow from 192.168.1.0/24 to any port 22 proto tcp
ufw allow from 5.161.184.133 to any port 22 proto tcp

# Explicitly deny SSH from other sources (IPv4 and IPv6)
# Note: If default incoming policy is deny, this might be redundant,
# but it matches the requested 'ufw status' output structure.
echo "Denying SSH from other sources..."
ufw deny proto tcp from any to any port 22 comment 'Deny all other SSH IPv4'
ufw deny proto tcp from any to any port 22 comment 'Deny all other SSH IPv6' # UFW applies deny to both v4/v6 unless specified

# Allow HTTP (port 80)
echo "Allowing HTTP (port 80)..."
ufw allow 80/tcp

# Allow HTTPS (port 443)
echo "Allowing HTTPS (port 443)..."
ufw allow 443/tcp

# Allow custom TCP ports (8080, 8443)
echo "Allowing custom TCP ports 8080 and 8443..."
ufw allow 8080/tcp
ufw allow 8443/tcp

# Allow Mosh UDP ports (60000:61000)
echo "Allowing Mosh UDP ports (60000:61000)..."
ufw allow 60000:61000/udp

# Enable UFW
echo "Enabling UFW..."
# Use --force to enable without interactive prompt, useful in scripts
ufw --force enable

echo "UFW enabled. Current status:"
ufw status verbose

echo "Bastian VM provisioning complete."

exit 0 