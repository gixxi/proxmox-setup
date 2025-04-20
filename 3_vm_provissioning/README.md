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

> cat provision_vm.sh | ssh <proxmox_user@proxmox_host> | 'bash -s -- <customer_name> <ip_address> <memory in MB> <cpu> <disk in GB>'

