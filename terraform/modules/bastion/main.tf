terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

# -----------------------------------------------------------------------------
# Cloud-init user-data snippet
# -----------------------------------------------------------------------------
resource "proxmox_virtual_environment_file" "user_data" {
  content_type = "snippets"
  datastore_id = var.iso_storage
  node_name    = var.proxmox_node

  source_raw {
    file_name = "${var.name}-user-data.yml"
    data = templatefile("${path.module}/user-data.yml.tftpl", {
      hostname          = var.name
      admin_username    = var.admin_username
      admin_password    = var.admin_password
      admin_ssh_keys    = var.admin_ssh_keys
      ssh_allow_cidrs   = var.ssh_allow_cidrs
      pfsense_gui_host  = var.pfsense_gui_host
      pfsense_gui_port  = var.pfsense_gui_port
      tunnel_local_port = var.tunnel_local_port
    })
  }
}

# -----------------------------------------------------------------------------
# Bastion VM - SSH workstation/jumpbox for public/DMZ testing and pfSense GUI tunneling
# -----------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "bastion" {
  name        = var.name
  description = "Managed by Terraform - SSH bastion workstation for Nimbus public/DMZ testing and pfSense GUI access"
  tags        = concat(["terraform"], var.tags)
  node_name   = var.proxmox_node
  vm_id       = var.vm_id

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.cpu
    type  = "host"
  }

  memory {
    dedicated = var.ram
  }

  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    size         = var.disk
    file_format  = "raw"
  }

  network_device {
    bridge = var.subnet_bridge
    model  = "virtio"
  }

  initialization {
    datastore_id      = var.vm_storage
    user_data_file_id = proxmox_virtual_environment_file.user_data.id

    ip_config {
      ipv4 {
        address = var.static_ip
        gateway = var.gateway
      }
    }
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [initialization[0].user_account]
  }
}
