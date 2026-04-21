# terraform/compute.tf
#
# EC2-equivalent VMs for Nimbus. Every VM is cloned from the Ubuntu 24.04
# cloud-init template (VMID var.template_vm_id) and configured via cloud-init.
#
# The pattern:
#   - `locals.instances` is a small catalog of VMs (name, tier, size).
#   - `proxmox_virtual_environment_vm.instances` fans that map out.
#   - Each VM gets its own cloud-init snippet rendered from user-data.yml.tftpl.
#
# Add or remove entries in `locals.instances` to grow/shrink your fleet.

locals {
  instances = {
    # ── Public tier ────────────────────────────────────────────────────────
    "${var.company_name}-bastion" = {
      subnet = "mgmt" # mgmt so SSH-from-bastion rules align; or put in public if you prefer
      cpu    = 1
      ram    = 1024
      disk   = 20
      tags   = ["bastion", "public"]
    }
    "${var.company_name}-alb" = {
      subnet = "public"
      cpu    = 2
      ram    = 2048
      disk   = 20
      tags   = ["alb", "public"]
    }

    # ── Private app tier ───────────────────────────────────────────────────
    "${var.company_name}-web-01" = {
      subnet = "app"
      cpu    = 2
      ram    = 2048
      disk   = 30
      tags   = ["web", "app-tier"]
    }
    "${var.company_name}-web-02" = {
      subnet = "app"
      cpu    = 2
      ram    = 2048
      disk   = 30
      tags   = ["web", "app-tier"]
    }

    # ── Private data tier ──────────────────────────────────────────────────
    "${var.company_name}-rds" = {
      subnet = "data"
      cpu    = 2
      ram    = 4096
      disk   = 50
      tags   = ["db", "data-tier"]
    }

    # ── Management tier ────────────────────────────────────────────────────
    "${var.company_name}-mon" = {
      subnet = "mgmt"
      cpu    = 2
      ram    = 4096
      disk   = 50
      tags   = ["monitoring", "mgmt"]
    }
    "${var.company_name}-dns" = {
      subnet = "mgmt"
      cpu    = 1
      ram    = 1024
      disk   = 20
      tags   = ["dns", "mgmt"]
    }
  }
}

# ─── Per-VM cloud-init user-data ────────────────────────────────────────────
# Each VM gets a rendered snippet uploaded to the Proxmox "snippets" storage
# and attached via cloud-init.

resource "proxmox_virtual_environment_file" "user_data" {
  for_each = local.instances

  content_type = "snippets"
  datastore_id = var.proxmox_iso_storage
  node_name    = var.proxmox_node

  source_raw {
    file_name = "${each.key}-user-data.yaml"
    data = templatefile("${path.module}/../cloud-init/user-data.yml.tftpl", {
      hostname       = each.key
      admin_username = var.admin_username
      admin_password = var.admin_password
      ssh_keys       = var.admin_ssh_public_keys
    })
  }
}

# ─── VMs ────────────────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_vm" "instances" {
  for_each = local.instances

  name        = each.key
  node_name   = var.proxmox_node
  description = "Managed by Terraform — ${join(", ", each.value.tags)}"
  tags        = each.value.tags

  # Clone from the golden template (= launch from AMI).
  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  cpu {
    cores = each.value.cpu
    type  = "host"
  }

  memory {
    dedicated = each.value.ram
  }

  disk {
    datastore_id = var.proxmox_vm_storage
    interface    = "scsi0"
    size         = each.value.disk
    file_format  = "raw"
  }

  network_device {
    bridge = var.subnets[each.value.subnet].bridge
    model  = "virtio"
  }

  # Cloud-init config. DHCP from pfSense inside the VNet — same as AWS
  # where each ENI gets an IP from the subnet's DHCP pool.
  initialization {
    datastore_id      = var.proxmox_vm_storage
    user_data_file_id = proxmox_virtual_environment_file.user_data[each.key].id

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
    ignore_changes = [
      # Avoid churn on cloud-init re-renders once the VM is up.
      initialization[0].user_account,
    ]
  }
}

# ─── Outputs ────────────────────────────────────────────────────────────────

output "instance_ips" {
  description = "Map of VM name → primary IPv4 address (populated once qemu-guest-agent is up)"
  value = {
    for name, vm in proxmox_virtual_environment_vm.instances :
    name => try(vm.ipv4_addresses[1][0], "pending-guest-agent")
  }
}
