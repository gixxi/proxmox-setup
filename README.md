# proxmox-setup
Setting up proxmox on bare metal. Describes preliminary actions, setting up the cluster nodes and best practices right after

# Preliminary actions

# Toolchain

Our toolchain is based on Proxmox VE and Proxmox tools

- pveam - proxmox ve application manager
- qm - manage virtual machines

## Why proxmox?

Proxmox VE is an excellent choice for building your own datacenter as a complement to cloud services for several reasons:

1. **Cost-effectiveness**: Proxmox offers enterprise-level virtualization without licensing costs, significantly reducing TCO compared to proprietary solutions or public cloud for predictable workloads.

2. **Data sovereignty**: Maintaining your own infrastructure ensures complete control over sensitive data, addressing compliance requirements that may be challenging in public clouds.

3. **Performance**: Direct hardware access provides consistent performance without the "noisy neighbor" issues common in shared cloud environments.

4. **Flexibility**: Proxmox supports both KVM virtual machines and LXC containers, allowing you to choose the right isolation level for each workload.

5. **Integration with cloud**: Proxmox works well in hybrid scenarios, letting you keep critical workloads on-premises while bursting to cloud when needed.

6. **Learning opportunity**: Managing Proxmox develops valuable skills in virtualization, networking, and infrastructure management that transfer to cloud environments.

7. **Community support**: Active community and comprehensive documentation make troubleshooting and optimization accessible.

By combining Proxmox on-premises with strategic cloud usage, you can optimize for cost, performance, and security while maintaining flexibility for future growth.

## Why Proxmox tools instead of OpenTofu?

Right now, we are using Proxmox tools to provision and manage infrastructure resources, create and destroy resources, and manage the lifecycle of infrastructure. This allows to start with a simple and easy to understand and use the proxmox tools.

# Folder structure

## 1_proxmox_installation

How to install Proxmox VE on bare metal.

## 2_infrastructure

- Hardening of the bastian vm (SSH hardening, firewall, ...)
- Setup dummy users that are allowed to login via SSH

## 3_vm_provisioning

Provision a VM for the following use cases:

- Bastian VM (Gateway to the internet, DNS, Nginx, ...)
- Customer VM (Running the application)

## 4_running_planet_rocklog

Running Planet Rocklog on a Proxmox VM that was provisioned in the previous step [(../3_vm_provissioning/README.md)](../3_vm_provissioning/README.md)
involves some additional steps to get the Docker container running.

## 5_running_bastian_vm

Running the bastian vm that is used to manage the infrastructure.

- Setup nginx to proxy the requests to the application
- Setup DNS records on the domain registrar

# TLDR; (for provisioning an application vm)

```bash
# Provision the VM

root@hub100:~/develop/devops/proxmox-setup/3_vm_provissioning# ./provision_vm.sh planet-rocklog-<customer> 192.168.1.<ip-prefix> root <password> 5000 2 10

# Create nginx location and virtual host

root@hub100:~/develop/devops/proxmox-setup/5_running_bastian_vm# ./create_nginx_proxy_configuration.sh <bastian-vm-ip> planetrocklog.com <customer> 192.168.1.<ip-prefix> 8080

# Restrict the vm to run only the container

root@hub100:~/develop/devops/proxmox-setup/4_running_planet_rocklog# ./restrict.sh 192.168.1.<ip-prefix> app

```