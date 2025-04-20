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

## 2_infrastructure

## 3_vm_provisioning
