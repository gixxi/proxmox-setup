resource "proxmox_vm_qemu" "customer_vm" {
  name = var.name
  target_node = "proxmox-node"
  clone = "debian-12-template"
  
  cores = var.cpus
  memory = var.memory
  
  disk {
    type = "scsi"
    size = var.disk_size
    storage = "local-lvm"
  }
  
  network {
    model = "virtio"
    bridge = "vmbr0"
  }
  
  ipconfig0 = "ip=${var.ip_address}/24,gw=192.168.1.1"
  
  # Cloud-init settings
  ciuser = "admin"
  cipassword = var.password
  cicustom = "user=local:snippets/cloud-init-user.yml"
  
  # Provisioning with custom script
  provisioner "remote-exec" {
    inline = [
      "apt-get update && apt-get upgrade -y",
      "apt-get install -y docker.io supervisor emacs vim nano curl wget",
      "systemctl enable --now docker",
      "echo 'AllowUsers root@192.168.1.0/24' >> /etc/ssh/sshd_config",
      "systemctl restart sshd",
      "timedatectl set-timezone Europe/Zurich"
    ]
  }
} 