terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "2.9.11"
    }
  }
}

provider "proxmox" {
  pm_api_url = "https://proxmox-server:8006/api2/json"
  pm_user = "root@pam"
  pm_password = "your-password"
  pm_tls_insecure = true
}

# Fetch or check for cloud image
resource "null_resource" "cloud_image_check" {
  provisioner "local-exec" {
    command = <<-EOT
      if ! ssh proxmox-server pveam list local | grep -q "debian-12-generic-amd64"; then
        ssh proxmox-server pveam download local debian-12-generic-amd64.qcow2
      fi
    EOT
  }
}

# Customer VM template
module "customer_vm" {
  source = "./modules/customer_vm"
  
  count = length(var.customers)
  
  name = "customer-${var.customers[count.index].name}"
  ip_address = var.customers[count.index].ip
  cpus = 2
  memory = 4096
  disk_size = "50G"
  
  depends_on = [null_resource.cloud_image_check]
} 