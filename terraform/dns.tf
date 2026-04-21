# terraform/dns.tf
#
# Wires up nimbus-dns and manages its records via the pan-net/pdns provider.
#
# Bootstrap note (chicken-and-egg):
#   On the FIRST `terraform apply`, the pdns provider can't authenticate
#   against a PowerDNS that doesn't exist yet. Two-stage apply:
#
#     1. terraform apply -target=module.nimbus_dns
#        (builds the VM, PowerDNS comes up, zones get seeded by cloud-init)
#
#     2. terraform apply
#        (pdns provider now has a live endpoint + API key; records sync)
#
#   After that, normal applies work in one shot.

terraform {
  required_providers {
    pdns = {
      source  = "pan-net/pdns"
      version = "~> 1.5"
    }
  }
}

# ─── nimbus-dns VM ──────────────────────────────────────────────────────────
module "nimbus_dns" {
  source = "./modules/powerdns"

  name           = "${var.company_name}-dns"
  proxmox_node   = var.proxmox_node
  template_vm_id = var.template_vm_id
  vm_storage     = var.proxmox_vm_storage
  iso_storage    = var.proxmox_iso_storage
  subnet_bridge  = var.subnets.mgmt.bridge

  admin_username = var.admin_username
  admin_password = var.admin_password
  admin_ssh_keys = var.admin_ssh_public_keys

  static_ip = var.nimbus_dns_static_ip
  gateway   = var.subnets.mgmt.gateway

  upstream_dns   = ["1.1.1.1", "9.9.9.9"]
  internal_zones = ["nimbus.local", "nimbusnode.org"]

  api_allow_cidrs = [
    var.vpc_cidr,     # all of Nimbus
    "127.0.0.1/32",
  ]
}

# ─── PowerDNS provider (records-as-code) ────────────────────────────────────
provider "pdns" {
  server_url = module.nimbus_dns.api_endpoint
  api_key    = module.nimbus_dns.api_key
}

# ─── nimbus.local records (internal infra) ──────────────────────────────────
# These are the "internal hostnames" — only resolvable inside Nimbus.
# Route 53 private hosted zone equivalent.

resource "pdns_record" "infra" {
  for_each = {
    "nimbus-dns.nimbus.local."       = module.nimbus_dns.host
    "nimbus-alb.nimbus.local."       = var.nimbus_alb_ip       # placeholder until Phase 4
    "nimbus-cloud-aio.nimbus.local." = var.nimbus_aio_ip       # your existing Nextcloud AIO
    # Add more as VMs come online. Keep trailing dots — PowerDNS wants FQDNs.
  }

  zone    = "nimbus.local."
  name    = each.key
  type    = "A"
  ttl     = 300
  records = [each.value]
}

# Internal CNAME: cloud.nimbus.local → nimbus-alb.nimbus.local
# (Once nimbus-alb exists. Until then, point it at the AIO directly.)
resource "pdns_record" "cloud_internal_cname" {
  zone    = "nimbus.local."
  name    = "cloud.nimbus.local."
  type    = "A"
  ttl     = 300
  records = [var.nimbus_aio_ip]   # direct to AIO for now; later flip to ALB
}

# ─── nimbusnode.org records (split-horizon) ─────────────────────────────────
# Inside Nimbus, "cloud.nimbusnode.org" resolves to the internal IP, so
# internal traffic skips the Cloudflare Tunnel entirely. External clients
# still hit Cloudflare — their DNS never touches nimbus-dns.

resource "pdns_record" "nimbusnode_internal" {
  for_each = {
    "cloud.nimbusnode.org." = var.nimbus_aio_ip
    # Add more subdomains as you publish services externally.
  }

  zone    = "nimbusnode.org."
  name    = each.key
  type    = "A"
  ttl     = 60    # short TTL — you may flip this between AIO and ALB as Phase 4 lands
  records = [each.value]
}

# ─── Outputs ────────────────────────────────────────────────────────────────
output "nimbus_dns_host" {
  description = "Point clients' /etc/resolv.conf (or pfSense DNS) at this"
  value       = module.nimbus_dns.host
}

output "nimbus_dns_api_endpoint" {
  value = module.nimbus_dns.api_endpoint
}
