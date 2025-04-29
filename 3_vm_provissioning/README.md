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

When provisioning a VM intended to run application services to disable the nginx service as well as extending the firewall rules to allow machine-to-machine communication for TCP on ports 8080-8090 (used for the httpkit clojure server), 18080-18090 (used for clojure repl) and 28080-28090 (used for couchdb). The rules are inserted first to ensure that any **deny** rules are overridden:

```bash
systemctl disable nginx
ufw allow 8080:8090/tcp
ufw allow 18080:18090/tcp
ufw allow 28080:28090/tcp
```

... or call the script restrict.sh with the following parameters:

```bash
./restrict.sh <ip_address> <app or bastian>
```




