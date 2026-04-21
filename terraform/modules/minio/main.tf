# terraform/modules/minio/main.tf
#
# "nimbus-s3" — MinIO single-node, the S3 equivalent for Nimbus.
#
# Scope:
#   - One VM running MinIO via systemd
#   - Root credentials seeded from vars
#   - On first boot: creates a bucket + a dedicated access key pair for
#     Nextcloud, matching IAM-user-scoped-to-one-bucket on AWS
#
# For a "multi-AZ-ish" setup later: switch to 4 MinIO VMs with MNMD mode
# across two Proxmox nodes. Same module, just fan it out.

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
      hostname              = var.name
      admin_username        = var.admin_username
      admin_password        = var.admin_password
      admin_ssh_keys        = var.admin_ssh_keys
      minio_root_user       = var.minio_root_user
      minio_root_password   = var.minio_root_password
      nextcloud_bucket      = var.nextcloud_bucket
      nextcloud_access_key  = var.nextcloud_access_key
      nextcloud_secret_key  = var.nextcloud_secret_key
    })
  }
}

resource "proxmox_virtual_environment_vm" "minio" {
  name        = var.name
  node_name   = var.proxmox_node
  description = "Managed by Terraform — MinIO (nimbus-s3)"
  tags        = ["minio", "s3", "data-tier"]

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

  # Boot/OS disk
  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    size         = var.disk
    file_format  = "raw"
  }

  # Data disk (kept separate so you can grow it / back it up independently,
  # the way you'd attach a dedicated EBS volume for S3-like storage in AWS).
  disk {
    datastore_id = var.vm_storage
    interface    = "scsi1"
    size         = var.data_disk
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
