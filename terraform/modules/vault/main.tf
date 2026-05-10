# terraform/modules/vault/main.tf
#
# nimbus-vault — HashiCorp Vault (Secrets Manager + STS equivalent).
#
# Scope:
#   - One VM, one Vault instance with integrated Raft storage
#   - HTTPS-only on :8200 with a cert issued by the Nimbus internal CA
#   - Service starts SEALED on first boot — `vault operator init` is a manual
#     one-shot in Phase 7d (recovery keys must NOT live in this repo)
#
# What this module does NOT do:
#   - Initialize / unseal Vault (Phase 7d, runbook in docs/runbooks/vault-unseal.md)
#   - Configure secrets engines or auth methods (Phase 7d via vault_* providers)
#   - Provision policies or migrate secrets from tfvars (Phase 7e)
#
# Cluster mode is single-node Raft. To grow to HA later: bump replication, add
# nodes pointing at this one as `retry_join`.

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
      vault_version      = var.vault_version
      cluster_name       = var.cluster_name
      vault_ip           = split("/", var.static_ip)[0]
      tls_cert_pem       = var.tls_cert_pem
      tls_key_pem        = var.tls_key_pem
      client_allow_cidrs = var.client_allow_cidrs
      mgmt_allow_cidrs   = var.mgmt_allow_cidrs
      loki_url           = var.loki_url
      nimbus_ca_pem      = var.nimbus_ca_pem
    })
  }
}

resource "proxmox_virtual_environment_vm" "vault" {
  name        = var.name
  node_name   = var.proxmox_node
  description = "Managed by Terraform — HashiCorp Vault (nimbus-vault)"
  tags        = ["vault", "secrets", "mgmt-tier"]

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
      # bpg/proxmox forces VM replace when user_data_file_id or ip_config changes.
      # Critical here: rebuilding nimbus-vault wipes raft data → all secrets gone.
      # Take a snapshot before:
      #   terraform apply -replace=module.nimbus_vault.proxmox_virtual_environment_vm.vault
      initialization[0].ip_config,
      initialization[0].user_data_file_id,
    ]
  }
}
