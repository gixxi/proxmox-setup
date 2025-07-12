#!/bin/bash
# Wrapper script for provisioning VMs on 192.168.3.x network
# This ensures VMs are configured with the correct network settings

echo "=================================================="
echo " VM PROVISIONING FOR 192.168.3.x NETWORK"
echo "=================================================="

# Set the correct network configuration
export GATEWAY="192.168.3.1"

echo "INFO: Using gateway: $GATEWAY"
echo "INFO: Proxmox host IP: 192.168.3.22"
echo ""

# Show current network usage
echo "Current network usage (192.168.3.x):"
echo "  Proxmox host: 192.168.3.22"
echo "  Gateway: 192.168.3.1"
echo ""

# Check if IP address is provided and validate it's in the correct range
VM_NAME=$1
IP_ADDRESS=$2
CI_USER=$3
CI_PASSWORD=$4

if [ -z "$VM_NAME" ] || [ -z "$IP_ADDRESS" ] || [ -z "$CI_USER" ] || [ -z "$CI_PASSWORD" ]; then
    echo "Error: Missing mandatory parameters"
    echo "Usage: $0 <vm_name> <ip_address> <ci_user> <ci_password> [memory] [cpu] [disk] [vm_id] [storage]"
    echo ""
    echo "IP address should be in 192.168.3.x range (avoid 192.168.3.1 and 192.168.3.22)"
    echo "Example: $0 my-vm 192.168.3.100 admin mypassword"
    exit 1
fi

# Validate IP address is in the correct range
if [[ ! "$IP_ADDRESS" =~ ^192\.168\.3\. ]]; then
    echo "Error: IP address $IP_ADDRESS is not in the 192.168.3.x range"
    echo "Please use an IP address in the 192.168.3.x range"
    exit 1
fi

# Check for reserved IPs
if [ "$IP_ADDRESS" = "192.168.3.1" ]; then
    echo "Error: 192.168.3.1 is the gateway address and cannot be used for VMs"
    exit 1
fi

if [ "$IP_ADDRESS" = "192.168.3.22" ]; then
    echo "Error: 192.168.3.22 is the Proxmox host address and cannot be used for VMs"
    exit 1
fi

echo "INFO: Validating network connectivity..."
# Test if the gateway is reachable
if ping -c 1 192.168.3.1 >/dev/null 2>&1; then
    echo "SUCCESS: Gateway 192.168.3.1 is reachable"
else
    echo "WARNING: Gateway 192.168.3.1 is not reachable"
    echo "This might indicate a network configuration issue"
fi

echo ""
echo "INFO: Starting VM provisioning with correct network configuration..."
echo "VM Name: $VM_NAME"
echo "IP Address: $IP_ADDRESS"
echo "Gateway: $GATEWAY"
echo "DNS Servers: 192.168.3.1, 8.8.8.8, 1.1.1.1"
echo ""

# Call the main provisioning script
./provision_vm.sh "$VM_NAME" "$IP_ADDRESS" "$CI_USER" "$CI_PASSWORD" "$5" "$6" "$7" "$8" "$9"

echo ""
echo "=================================================="
echo " PROVISIONING COMPLETE"
echo "=================================================="
echo "If the VM has internet connectivity issues:"
echo "1. SSH into the VM: ssh $CI_USER@$IP_ADDRESS"
echo "2. Check DNS: cat /etc/resolv.conf"
echo "3. Test connectivity: ping -c 3 8.8.8.8"
echo "4. Test DNS: nslookup google.com"
echo ""
echo "If DNS is still not working, run the fix script:"
echo "  ./fix_vm_dns.sh <vm_id> $IP_ADDRESS" 