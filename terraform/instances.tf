# terraform/instances.tf
#
# Shared catalog of all Nimbus VMs. Each role-specific file (alb.tf,
# bastion.tf, etc.) picks entries out of this map. Defining it here
# keeps the VM "sizing catalog" in one place — like a central page of
# EC2 instance types.
#
# Cross-references between VMs (e.g. the ALB needing to know the web
# tier's IP) happen via the terraform state after each VM is deployed,
# not via this catalog.

locals {
  instances = {
    # ── Public tier ────────────────────────────────────────────────────────
    "${var.company_name}-bastion" = {
      subnet = "mgmt" # SSH jumpbox; mgmt so sg-ssh rules align
      cpu    = 1
      ram    = 1024
      disk   = 25
      tags   = ["bastion", "public"]
    }
    "${var.company_name}-alb" = {
      subnet = "public"
      cpu    = 2
      ram    = 2048
      disk   = 25
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

    # ── Management tier ────────────────────────────────────────────────────
    "${var.company_name}-mon" = {
      subnet = "mgmt"
      cpu    = 2
      ram    = 4096
      disk   = 50
      tags   = ["monitoring", "mgmt"]
    }
  }
}
