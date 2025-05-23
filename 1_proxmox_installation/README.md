# Proxmox Installation


# Disaster Recovery

## Remounting the disks

assume you still have the disks on the storage pool, replace proxmox_data with your storage pool name

```bash
# List the disks
ls -l /var/lib/vz/images/


# Reattach disks to VM (replace VM_ID with your VM ID)



VM_ID=106 && qm set $VM_ID --scsi0 proxmox_data:$VM_ID/vm-$VM_ID-disk-0.raw --ide2 proxmox_data:$VM_ID/vm-$VM_ID-cloudinit.qcow2


```





