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
    data = templatefile("${path.module}/user-data.yml.tftpl", {
      hostname            = var.name
      admin_username      = var.admin_username
      admin_password      = var.admin_password
      admin_ssh_keys      = var.admin_ssh_keys
      minio_root_user     = var.minio_root_user
      minio_root_password = var.minio_root_password
      minio_bucket        = var.minio_bucket
      pgbackup_access_key = var.pgbackup_access_key
      pgbackup_secret_key = var.pgbackup_secret_key
      api_allow_cidrs     = var.api_allow_cidrs
      console_allow_cidrs = var.console_allow_cidrs
      mgmt_allow_cidrs    = var.mgmt_allow_cidrs
    })
    file_name = "${var.name}-user-data.yml"
  }
}

# -----------------------------------------------------------------------------
# The VM — cloned from golden Ubuntu template, with separate data disk
# -----------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "minio" {
  name        = var.name
  description = "MinIO single-node — S3-equivalent for nimbus-data subnet. Managed by Terraform."
  tags        = ["terraform", "minio", "s3", "nimbus-data"]
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
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  # Root disk (OS, MinIO binary)
  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    size         = var.root_disk_size_gb
  }

  # Data disk (object storage) — formatted xfs, mounted at /mnt/minio in cloud-init
  disk {
    datastore_id = var.vm_storage
    interface    = "scsi1"
    size         = var.data_disk_size_gb
    file_format  = "raw"
    iothread     = true
  }

  network_device {
    bridge = var.subnet_bridge
    model  = "virtio"
  }

  initialization {
    datastore_id = var.vm_storage

    ip_config {
      ipv4 {
        address = var.static_ip
        gateway = var.gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.user_data.id
  }

  operating_system {
    type = "l26"
  }
}
