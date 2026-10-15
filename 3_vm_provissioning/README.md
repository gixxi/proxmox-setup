# Provisioning VMs

## Invariants

- Node-indenpendend storage **proxmox-data** based on nas storage with NFS export

## Steps involved

The VM provisioning process is automated through the `provision_vm.sh` script, which performs the following steps:

1. **Parameter validation**: Checks that all required parameters are provided (VM name, VM ID, memory size, CPU cores, disk size, etc.)

2. **Template verification**: Ensures the specified template exists in the Proxmox storage

3. **Resource allocation**: Determines the optimal Proxmox node for VM placement based on current cluster load

4. **VM creation**: Clones the template to create a new VM with the specified VM ID

5. **Hardware configuration**: Sets up the VM with requested CPU, memory, and network settings

6. **Storage configuration**: Allocates and configures the requested disk space

7. **Cloud-init configuration**: Applies user-provided cloud-init settings (SSH keys, initial user, etc.)

8. **Network configuration**: Sets up IP addressing according to the specified network parameters

9. **VM finalization**: Completes any remaining configuration tasks before the VM is ready to start

The script handles error conditions at each step and provides appropriate feedback to the user.

## Usage

> ./provision_vm.sh <customer_name> <ip_address> <memory in MB> <cpu> <disk in GB>

on a remote proxmox node you need to do the following assuming you have ssh access to the proxmox node.

> cat provision_vm.sh | ssh <proxmox_user@proxmox_host> | 'bash -s -- <customer_name> <ip_address> <root_user> <root_password> <memory in MB> <cpu> <disk in GB>'

The parameters are optional:

- <memory in MB> defaults to 2048
- <cpu> defaults to 1
- <disk in GB> defaults to 10

## Restricting the surface as per the usage profile

Depending on the usage of the profile we dissable certain services

## Service Configuration Based on VM Role

Depending on the intended role of the VM, certain services should be enabled or disabled:

Either you log into the VM and do the following:


### Bastian/Gateway VM

For VMs serving as bastian hosts or gateways, configure the following to disable the docker service:

```bash
systemctl disable docker
```

### Application Service VM

Application VMs disable nginx (the bastion terminates TLS) and get the `app-vm` firewall profile
(`../2_infrastructure/setup_firewall.sh`, iptables — ufw is not used anymore):

- SSH only from `ADMIN_SOURCES`
- containers reachable only from the bastion (`BASTION_SOURCES`) on the app port 8080 (httpkit)
- nREPL (4050 → 18080-18090) and CouchDB (5984 → 28080-28090) are **not** reachable over the
  network at all: the Makefile (`../lib/vlic_runner_makefile.sh`) binds them to 127.0.0.1.
  Use an SSH tunnel: `ssh -L 18080:127.0.0.1:18080 root@<vm>`

Both nREPL and CouchDB 1.x without admin are remote code execution; the former
`ufw allow 18080:18090/tcp` / `28080:28090/tcp` rules exposed them to the whole network
(and ufw does not even filter Docker-published ports).

```bash
ADMIN_SOURCES="116.203.216.1 5.161.184.133 192.168.1.0/24" BASTION_SOURCES="<bastion ip>" \
CIRCLECI_APIKEY=… ./restrict.sh <ip_address> app
ADMIN_SOURCES="…" ./restrict.sh <ip_address> bastian
```




