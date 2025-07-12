#!/bin/bash
# Fix DNS Configuration for Existing VMs
# Usage: ./fix_vm_dns.sh <vm_id> [vm_ip_address]

VM_ID=$1
VM_IP=$2

if [ -z "$VM_ID" ]; then
    echo "Error: VM ID is required"
    echo "Usage: $0 <vm_id> [vm_ip_address]"
    echo ""
    echo "Available VMs:"
    qm list
    exit 1
fi

# Check if VM exists
if ! qm status $VM_ID >/dev/null 2>&1; then
    echo "Error: VM $VM_ID does not exist"
    exit 1
fi

echo "=================================================="
echo " FIXING DNS CONFIGURATION FOR VM $VM_ID"
echo "=================================================="

# If IP not provided, try to get it from cloud-init config
if [ -z "$VM_IP" ]; then
    echo "INFO: Getting IP address from VM cloud-init configuration..."
    VM_IP=$(qm config $VM_ID | grep "ipconfig0" | sed 's/.*ip=\([^,]*\).*/\1/')
    if [ -z "$VM_IP" ]; then
        echo "Error: Could not determine VM IP address. Please provide it as second parameter."
        echo "Usage: $0 <vm_id> <vm_ip_address>"
        exit 1
    fi
    echo "INFO: Detected VM IP: $VM_IP"
fi

echo "INFO: VM ID: $VM_ID"
echo "INFO: VM IP: $VM_IP"
echo "INFO: VM Status: $(qm status $VM_ID)"

# Check if VM is running
if [ "$(qm status $VM_ID)" != "status: running" ]; then
    echo "WARNING: VM $VM_ID is not running. Starting it..."
    qm start $VM_ID
    if [ $? -ne 0 ]; then
        echo "Error: Failed to start VM $VM_ID"
        exit 1
    fi
    echo "INFO: Waiting for VM to boot..."
    sleep 30
fi

echo ""
echo "1. TESTING CURRENT CONNECTIVITY"
echo "==============================="

# Test if we can reach the VM
echo "Testing connectivity to VM..."
ping -c 3 $VM_IP >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "WARNING: Cannot ping VM at $VM_IP"
    echo "This might be normal if ping is blocked by firewall"
else
    echo "INFO: VM is reachable via ping"
fi

echo ""
echo "2. FIXING DNS CONFIGURATION"
echo "==========================="

# Create a temporary script to fix DNS on the VM
TEMP_SCRIPT="/tmp/fix_dns_${VM_ID}.sh"
cat > "$TEMP_SCRIPT" << 'EOF'
#!/bin/bash
# DNS Fix Script for VM

echo "Fixing DNS configuration..."

# Backup original resolv.conf
cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null

# Create new resolv.conf with proper DNS servers
cat > /etc/resolv.conf << 'RESOLV_EOF'
# DNS configuration - Fixed by script
# Primary: Router (matches Proxmox host network)
nameserver 192.168.3.1
# Secondary: Google DNS
nameserver 8.8.8.8
# Tertiary: Cloudflare DNS
nameserver 1.1.1.1
# Search domain
search local
RESOLV_EOF

echo "DNS configuration updated"

# Test DNS resolution
echo "Testing DNS resolution..."
if nslookup google.com >/dev/null 2>&1; then
    echo "SUCCESS: DNS resolution working"
else
    echo "WARNING: DNS resolution still failing"
fi

# Test internet connectivity
echo "Testing internet connectivity..."
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "SUCCESS: Internet connectivity working"
else
    echo "WARNING: Internet connectivity still failing"
fi

# Show current DNS configuration
echo "Current DNS configuration:"
cat /etc/resolv.conf

echo "DNS fix completed"
EOF

# Copy the script to the VM and execute it
echo "INFO: Copying DNS fix script to VM..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$TEMP_SCRIPT" root@$VM_IP:/tmp/ 2>/dev/null
if [ $? -ne 0 ]; then
    echo "WARNING: Could not copy script to VM. Trying alternative method..."
    # Try with different SSH options
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "$TEMP_SCRIPT" root@$VM_IP:/tmp/ 2>/dev/null
fi

echo "INFO: Executing DNS fix script on VM..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@$VM_IP "chmod +x /tmp/fix_dns_${VM_ID}.sh && /tmp/fix_dns_${VM_ID}.sh" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "WARNING: Could not execute script via SSH. Trying alternative method..."
    # Try with different SSH options
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@$VM_IP "chmod +x /tmp/fix_dns_${VM_ID}.sh && /tmp/fix_dns_${VM_ID}.sh" 2>/dev/null
fi

# Clean up temporary script
rm -f "$TEMP_SCRIPT"

echo ""
echo "3. VERIFICATION"
echo "==============="

echo "INFO: Testing DNS resolution from VM..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@$VM_IP "nslookup google.com" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "SUCCESS: DNS resolution is working on VM"
else
    echo "WARNING: DNS resolution still failing on VM"
fi

echo "INFO: Testing internet connectivity from VM..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@$VM_IP "curl -I --connect-timeout 10 https://www.google.com" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "SUCCESS: Internet connectivity is working on VM"
else
    echo "WARNING: Internet connectivity still failing on VM"
fi

echo ""
echo "4. TROUBLESHOOTING"
echo "=================="
echo "If DNS is still not working:"
echo "1. Check if Proxmox host can access internet: ./network_diagnostics.sh"
echo "2. Verify Unifi router DNS settings"
echo "3. Check VM firewall rules"
echo "4. Verify vmbr0 bridge configuration"
echo ""
echo "To manually fix DNS on VM, SSH into it and run:"
echo "  echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
echo "  echo 'nameserver 1.1.1.1' >> /etc/resolv.conf"
echo "  echo 'nameserver 192.168.3.1' >> /etc/resolv.conf"

echo ""
echo "=================================================="
echo " DNS FIX COMPLETED FOR VM $VM_ID"
echo "==================================================" 