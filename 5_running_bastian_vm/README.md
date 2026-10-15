- create a cron on the proxmox host that copies the SSL certificate to the bastian vm
- based on 3_vm_provisioning/provision_vm.sh we want to do the following in addition:

1. install nginx
2. apply the `bastion` firewall profile (iptables, replaces ufw): SSH from the admin sources,
   80/443/8080/8443 and mosh public, IPv6 included

```bash
ADMIN_SOURCES="172.105.94.119 116.203.216.1 5.161.184.133 192.168.1.0/24" \
  ../2_infrastructure/setup_firewall.sh bastion --install --disable-ufw
# or from the provisioning host: ADMIN_SOURCES="…" ../3_vm_provissioning/restrict.sh <bastion ip> bastian
```

Note: `copy_ssl_to_bastian.sh` copies the Proxmox node's own TLS private key to the internet-facing
bastion. A compromised bastion could then impersonate the Proxmox UI — prefer a separate
certificate for the bastion (Let's Encrypt).
