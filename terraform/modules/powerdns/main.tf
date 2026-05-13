# terraform/modules/powerdns/main.tf
#
# "nimbus-dns" — PowerDNS authoritative server with API + recursor.
#
# Scope:
#   - One VM, running:
#       * pdns_server  (authoritative, PostgreSQL backend on nimbus-rds)
#       * pdns_recursor (for forwarding google.com / github.com / etc.)
#       * pdns.conf API enabled so Terraform can manage records
#   - Split-horizon ready: authoritative serves nimbus.local AND
#     nimbusnode.org internally; external clients still hit Cloudflare.
#   - Clients in Nimbus point at this VM's IP for DNS.
#
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "random_password" "api_key" {
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true
}

resource "proxmox_virtual_environment_file" "user_data" {
  content_type = "snippets"
  datastore_id = var.iso_storage
  node_name    = var.proxmox_node

  source_raw {
    file_name = "${var.name}-user-data.yaml"
    data = templatefile("${path.module}/user-data.yml.tftpl", {
      hostname          = var.name
      admin_username    = var.admin_username
      admin_password    = var.admin_password
      admin_ssh_keys    = var.admin_ssh_keys
      api_key           = random_password.api_key.result
      api_allow_cidrs   = var.api_allow_cidrs
      mgmt_allow_cidrs  = var.mgmt_allow_cidrs
      recursor_forwards = var.recursor_forwards
      upstream_dns      = var.upstream_dns
      internal_zones    = var.internal_zones
      backend_db_host   = var.backend_db_host
      backend_db_port   = var.backend_db_port
      backend_db_name   = var.backend_db_name
      backend_db_user   = var.backend_db_user
      backend_db_pass   = var.backend_db_password
      loki_url          = var.loki_url
    })
  }
}

resource "proxmox_virtual_environment_vm" "dns" {
  name        = var.name
  node_name   = var.proxmox_node
  description = "Managed by Terraform — PowerDNS (nimbus-dns / Route 53 equivalent)"
  tags        = ["powerdns", "dns", "mgmt"]

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
        # Static IP — DNS needs to be predictable. DHCP reservations work
        # too, but a static config is one less thing that can break.
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
      # bpg/proxmox forces VM replace when ip_config or user_data_file_id changes.
      # Ignore both — to intentionally rebuild:
      #   terraform apply -replace=module.nimbus_dns.proxmox_virtual_environment_vm.dns
      initialization[0].ip_config,
      initialization[0].user_data_file_id,
    ]
  }
}
