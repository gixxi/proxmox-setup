#!/bin/bash
# Proxmox iSCSI Recovery Script

ISCSI_TARGET="192.168.2.21"
ISCSI_IQN="iqn.2000-01.com.synology:nottwil-nas-1.Target-1.ed0acaccf93"
VG_NAME="nas-1-vg"
NEW_NODE_NAME=$(hostname)

echo "=== Proxmox iSCSI Recovery Script ==="

echo "1. Connecting to iSCSI target..."
iscsiadm -m discovery -t st -p $ISCSI_TARGET
iscsiadm -m node -T $ISCSI_IQN -p ${ISCSI_TARGET}:3260 --login
iscsiadm -m node -T $ISCSI_IQN -p ${ISCSI_TARGET}:3260 --op update -n node.startup -v automatic

echo "2. Importing LVM Volume Group..."
vgscan
vgimport $VG_NAME 2>/dev/null || echo "VG already imported"
vgchange -ay $VG_NAME

echo "3. Configuring Proxmox storage..."
cat >> /etc/pve/storage.cfg << EOF

iscsi: nas-1-iscsi
        portal $ISCSI_TARGET
        target $ISCSI_IQN
        content none
        nodes $NEW_NODE_NAME

lvmthin: nas-1-data
        vgname $VG_NAME
        thinpool data
        content rootdir,images
        shared 1
        nodes $NEW_NODE_NAME
EOF

echo "4. Scanning for VM disks..."
for lv in $(lvs --noheadings -o lv_name | grep "vm-.*-disk-"); do
    vmid=$(echo $lv | cut -d- -f2)
    if [ ! -f "/etc/pve/qemu-server/${vmid}.conf" ]; then
        echo "Creating basic config for VM $vmid"
        cat > "/etc/pve/qemu-server/${vmid}.conf" << EOF
agent: 1
boot: order=scsi0
cores: 2
memory: 2048
name: recovered-vm-${vmid}
net0: virtio=xx:xx:xx:xx:xx:xx,bridge=vmbr0
scsi0: nas-1-data:${lv},iothread=1
scsihw: virtio-scsi-single
EOF
    fi
done

echo "5. Restarting Proxmox services..."
systemctl restart pve-storage
systemctl restart pveproxy

echo "=== Recovery complete! ==="
echo "Available VMs:"
qm list
echo ""
echo "To start VMs: qm start <vmid>"