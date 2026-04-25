terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

# terraform/modules/postgres/main.tf
#
# nimbus-rds - a Postgres-based DB.
resource "proxmox_virtual_environment_file" "user_data" {
  content_type = "snippets"
  datastore_id = var.iso_storage
  node_name    = var.proxmox_node

  source_raw {
    file_name = "${var.name}-user-data.yaml"
    data = templatefile("${path.module}/user-data.yml.tftpl", {
      hostname         = var.name
      search_domain     = var.search_domain
      admin_ssh_keys    = var.admin_ssh_keys
      admin_username   = var.admin_username
      admin_password   = var.admin_password
      postgres_db       = var.postgres_db
      postgres_user     = var.postgres_user
      postgres_password = var.postgres_password
      allowed_cidr      = var.allowed_cidr
      wsl_cidr          = var.wsl_cidr
      mgmt_cidr         = var.mgmt_cidr
      dns_server        = var.dns_server
    })
  }
}

# -----------------------------------------------------------------------------
# The VM itself — cloned from the golden Ubuntu 24.04 template.
# -----------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "postgres" {
  name        = var.name
  node_name   = var.proxmox_node
  description = "PostgreSQL 16 — RDS-equivalent for nimbus-data subnet. Managed by Terraform."
  tags        = ["terraform", "postgres", "rds", "nimbus-data"]

  clone {
    vm_id = var.template_vm_id
    full  = true
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
    datastore_id = var.vm_storage

    ip_config {
      ipv4 {
        address = "${var.ip_address}/${var.subnet_prefix}"
        gateway = var.gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.user_data.id
  }

  operating_system {
    type = "l26"
  }
}
