# terraform/modules/postgres/main.tf
#
# "nimbus-rds" — PostgreSQL 16 on Ubuntu, the RDS equivalent for Nimbus.
#
# Scope:
#   - One VM, one PostgreSQL instance
#   - Creates one initial database + role via cloud-init (for Nextcloud)
#   - Listens only on the data-tier subnet (enforced by pg_hba.conf + SG)
#   - Daily backups via systemd timer to /var/backups/postgres + push to MinIO
#
# Real RDS does far more (automated backups, PITR, multi-AZ). Layer those
# on later — distributed MinIO + cross-host replication is the natural next step.

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

resource "proxmox_virtual_environment_file" "user_data" {
  content_type = "snippets"
  datastore_id = var.iso_storage
  node_name    = var.proxmox_node

  source_raw {
    file_name = "${var.name}-user-data.yaml"
    data = templatefile("${path.module}/user-data.yml.tftpl", {
      hostname        = var.name
      admin_username  = var.admin_username
      admin_password  = var.admin_password
      admin_ssh_keys  = var.admin_ssh_keys
      initial_db_name = var.initial_db_name
      initial_db_user = var.initial_db_user
      initial_db_pw   = var.initial_db_password
      allowed_cidr    = var.allowed_cidr

      # MinIO targets for the pg-backup push step
      s3_endpoint   = var.s3_endpoint
      s3_access_key = var.s3_access_key
      s3_secret_key = var.s3_secret_key
      s3_bucket     = var.s3_bucket
    })
  }
}

resource "proxmox_virtual_environment_vm" "rds" {
  name        = var.name
  node_name   = var.proxmox_node
  description = "Managed by Terraform — PostgreSQL (nimbus-rds)"
  tags        = ["postgres", "data-tier", "rds"]

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
    datastore_id      = var.vm_storage
    user_data_file_id = proxmox_virtual_environment_file.user_data.id

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

  lifecycle {
    ignore_changes = [initialization[0].user_account]
  }
}
