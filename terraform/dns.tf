# terraform/dns.tf
#
# Wires up nimbus-dns and manages its records via the pan-net/powerdns provider.
# (Provider declared in providers.tf.)
#
# Bootstrap note (chicken-and-egg):
#   On the FIRST `terraform apply`, the powerdns provider can't authenticate
#   against a PowerDNS that doesn't exist yet. Two-stage apply:
#
#     1. terraform apply -target=module.nimbus_dns
#     2. terraform apply

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

  api_allow_cidrs = var.mgmt_allow_cidrs

}

provider "powerdns" {
  server_url = module.nimbus_dns.api_endpoint
  api_key    = module.nimbus_dns.api_key
}

resource "powerdns_record" "infra" {
  for_each = {
    "nimbus-dns.nimbus.local."       = module.nimbus_dns.host
    "nimbus-alb.nimbus.local."       = var.nimbus_alb_ip
    "nimbus-cloud-aio.nimbus.local." = var.nimbus_aio_ip
  }

  zone    = "nimbus.local."
  name    = each.key
  type    = "A"
  ttl     = 300
  records = [each.value]
}

resource "powerdns_record" "cloud_internal_cname" {
  zone    = "nimbus.local."
  name    = "cloud.nimbus.local."
  type    = "A"
  ttl     = 300
  records = [var.nimbus_aio_ip]
}

resource "powerdns_record" "nimbusnode_internal" {
  for_each = {
    "cloud.nimbusnode.org." = var.nimbus_aio_ip
  }

  zone    = "nimbusnode.org."
  name    = each.key
  type    = "A"
  ttl     = 60
  records = [each.value]
}

output "nimbus_dns_host" {
  description = "Point clients' /etc/resolv.conf (or pfSense DNS) at this"
  value       = module.nimbus_dns.host
}

output "nimbus_dns_api_endpoint" {
  value = module.nimbus_dns.api_endpoint
}

output "nimbus_dns_api_key" {
  description = "Auto-generated PowerDNS API key"
  value       = module.nimbus_dns.api_key
  sensitive   = true
}