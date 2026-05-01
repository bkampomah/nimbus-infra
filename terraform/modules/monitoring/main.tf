# terraform/modules/monitoring/main.tf
#
# nimbus-mon — observability VM (CloudWatch equivalent).
#
# What this module does:
#   - Clones a VM from the golden template
#   - Installs Prometheus, Grafana, and Loki via cloud-init
#   - Pre-wires Prometheus + Loki as Grafana data sources via provisioning files
#   - Configures Prometheus scrape targets (node-exporter on every Nimbus VM)
#   - UFW: Grafana/Prometheus from mgmt only; Loki from full VPC (all VMs push logs)
#
# What this module does NOT do:
#   - Install node-exporter or Promtail on other VMs (that's Phase 6b/6c)
#   - Create persistent Grafana dashboards (add to provisioning/ later)

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
      hostname         = var.name
      admin_username   = var.admin_username
      admin_password   = var.admin_password
      admin_ssh_keys   = var.admin_ssh_keys
      scrape_targets   = var.scrape_targets
      mgmt_allow_cidrs = var.mgmt_allow_cidrs
      loki_allow_cidrs = var.loki_allow_cidrs
      loki_url         = var.loki_url
    })
  }
}

resource "proxmox_virtual_environment_vm" "mon" {
  name        = var.name
  node_name   = var.proxmox_node
  description = "Managed by Terraform — Observability (Prometheus + Grafana + Loki)"
  tags        = ["monitoring", "mgmt-tier", "grafana"]

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
      initialization[0].ip_config,
      initialization[0].user_data_file_id,
    ]
  }
}
