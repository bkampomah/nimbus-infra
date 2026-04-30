terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}


# terraform/modules/haproxy/main.tf
#
# nimbus-alb - an HAProxy-based load balancer in front of app-tier services.
# Patterned after the powerdns module: cloud-init installs + configures at
# first boot so the module is self-contained.

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
      static_ip               = var.static_ip
      backends                = var.backends
      mgmt_allow_cidrs        = var.mgmt_allow_cidrs
      alb_allow_cidrs         = var.alb_allow_cidrs
      cloudflare_tunnel_token = var.cloudflare_tunnel_token
      tls_pem                 = var.tls_pem
    })
  }
}

resource "proxmox_virtual_environment_vm" "alb" {
  name        = var.name
  node_name   = var.proxmox_node
  description = "Managed by Terraform - HAProxy load balancer"
  tags        = ["alb", "public", "haproxy"]

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
      # Ignore both — to intentionally rebuild: terraform apply -replace=module.nimbus_alb.proxmox_virtual_environment_vm.alb
      initialization[0].ip_config,
      initialization[0].user_data_file_id,
    ]
  }
}
