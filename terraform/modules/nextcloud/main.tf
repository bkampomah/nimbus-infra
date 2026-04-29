# terraform/modules/nextcloud/main.tf
#
# Nextcloud VM module.
#
# What this module does:
#   - Clones a VM from the golden template
#   - Renders a cloud-init file that installs Nextcloud + nginx + PHP-FPM
#   - Wires Nextcloud to an external PostgreSQL (nimbus-rds)
#   - Configures MinIO as Primary Object Storage (the S3 equivalent)
#   - Registers the "sg-nextcloud" security group membership
#
# What this module does NOT do:
#   - Create the database/user (the postgres module does that)
#   - Create the MinIO bucket/keys (the minio module does that)
#   - Set up TLS — TLS terminates on the ALB, the VM speaks plain HTTP to it
#
# Call from root main.tf like:
#
#   module "nextcloud" {
#     source              = "./modules/nextcloud"
#     name                = "${var.company_name}-cloud-01"
#     proxmox_node        = var.proxmox_node
#     template_vm_id      = var.template_vm_id
#     vm_storage          = var.proxmox_vm_storage
#     iso_storage         = var.proxmox_iso_storage
#     subnet_bridge       = var.subnets.app.bridge
#     admin_username      = var.admin_username
#     admin_password      = var.admin_password
#     admin_ssh_keys      = var.admin_ssh_public_keys
#     nextcloud_admin_pw  = var.nextcloud_admin_password
#     nextcloud_domain    = "cloud.nimbus.local"
#     static_ip           = "${var.nimbus_cloud_ip}/24"
#     gateway             = var.subnets.app.gateway
#     trusted_proxies     = [var.subnets.public.cidr]
#     alb_allow_cidrs     = [var.subnets.public.cidr]
#     mgmt_allow_cidrs    = var.mgmt_allow_cidrs
#     db_host             = module.postgres.host
#     db_name             = "nextcloud"
#     db_user             = "nextcloud"
#     db_password         = var.nextcloud_db_password
#     s3_endpoint         = module.minio.endpoint
#     s3_bucket           = "nextcloud-primary"
#     s3_access_key       = module.minio.nextcloud_access_key
#     s3_secret_key       = module.minio.nextcloud_secret_key
#   }

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
      hostname           = var.name
      admin_username     = var.admin_username
      admin_password     = var.admin_password
      admin_ssh_keys     = var.admin_ssh_keys
      nextcloud_admin_pw = var.nextcloud_admin_pw
      nextcloud_domain   = var.nextcloud_domain
      trusted_proxies    = var.trusted_proxies
      alb_allow_cidrs    = var.alb_allow_cidrs
      mgmt_allow_cidrs   = var.mgmt_allow_cidrs
      db_host            = var.db_host
      db_name            = var.db_name
      db_user            = var.db_user
      db_password        = var.db_password
      s3_endpoint        = var.s3_endpoint
      s3_bucket          = var.s3_bucket
      s3_access_key      = var.s3_access_key
      s3_secret_key      = var.s3_secret_key
    })
  }
}

resource "proxmox_virtual_environment_vm" "nextcloud" {
  name        = var.name
  node_name   = var.proxmox_node
  description = "Managed by Terraform — Nextcloud web tier"
  tags        = ["nextcloud", "app-tier", "web"]

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
        address = var.static_ip
        gateway = var.gateway
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
    ignore_changes = [
      initialization[0].user_account,
      # bpg/proxmox forces VM replace when user_data_file_id changes.
      # Ignore so template updates don't rebuild running VMs.
      # To intentionally rebuild: terraform apply -replace=module.nimbus_nextcloud.proxmox_virtual_environment_vm.cloud
      initialization[0].user_data_file_id,
    ]
  }
}
