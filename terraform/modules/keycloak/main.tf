# terraform/modules/keycloak/main.tf
#
# nimbus-iam — Keycloak 25 (OIDC identity provider).
#
# Scope:
#   - One VM, one Keycloak instance running in production mode
#   - Postgres-backed (DB lives on nimbus-rds; provisioned by the postgres module)
#   - HTTPS-only on :8443 with a cert issued by the Nimbus internal CA
#   - Bootstrap admin created from KEYCLOAK_ADMIN env on first boot
#
# What this module does NOT do:
#   - Realm/client provisioning (Phase 7b — mrparkers/keycloak provider against
#     the running instance)
#   - SSO integration with apps (Phase 7c)
#   - Cloudflare Tunnel ingress (configured in iam.tf via the existing
#     nimbus-alb cloudflared install — Keycloak just needs to be reachable on
#     :8443 from the ALB).

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
      hostname                = var.name
      admin_username          = var.admin_username
      admin_password          = var.admin_password
      admin_ssh_keys          = var.admin_ssh_keys
      keycloak_version        = var.keycloak_version
      keycloak_hostname       = var.keycloak_hostname
      keycloak_admin_user     = var.keycloak_admin_user
      keycloak_admin_password = var.keycloak_admin_password
      db_host                 = var.db_host
      db_port                 = var.db_port
      db_name                 = var.db_name
      db_user                 = var.db_user
      db_password             = var.db_password
      tls_cert_pem            = var.tls_cert_pem
      tls_key_pem             = var.tls_key_pem
      alb_cidr                = var.alb_cidr
      mgmt_allow_cidrs        = var.mgmt_allow_cidrs
      loki_url                = var.loki_url
      backup_s3_endpoint      = var.backup_s3_endpoint
      backup_s3_access_key    = var.backup_s3_access_key
      backup_s3_secret_key    = var.backup_s3_secret_key
      backup_s3_bucket        = var.backup_s3_bucket
      backup_realms           = var.backup_realms
    })
  }
}

resource "proxmox_virtual_environment_vm" "iam" {
  name        = var.name
  node_name   = var.proxmox_node
  description = "Managed by Terraform — Keycloak (nimbus-iam)"
  tags        = ["keycloak", "iam", "mgmt-tier"]

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
      # bpg/proxmox forces VM replace on user_data_file_id / ip_config drift.
      # Ignore both — to intentionally rebuild:
      #   terraform apply -replace=module.nimbus_iam.proxmox_virtual_environment_vm.iam
      initialization[0].ip_config,
      initialization[0].user_data_file_id,
    ]
  }
}
