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

  backend_db_host     = var.nimbus_rds_ip
  backend_db_name     = "powerdns"
  backend_db_user     = "powerdns"
  backend_db_password = random_password.powerdns_db.result

  api_allow_cidrs  = var.mgmt_allow_cidrs
  mgmt_allow_cidrs = var.mgmt_allow_cidrs
  loki_url         = module.nimbus_mon.loki_url
}

provider "powerdns" {
  # server_url is derived from the static IP — always known at plan time.
  # api_key comes from var.powerdns_api_key (see variables.tf bootstrap note).
  server_url = "http://${split("/", var.nimbus_dns_static_ip)[0]}:8081"
  api_key    = var.powerdns_api_key
}

resource "powerdns_record" "infra" {
  for_each = {
    "nimbus-dns.nimbus.local."       = module.nimbus_dns.host
    "nimbus-alb.nimbus.local."       = var.nimbus_alb_ip
    "nimbus-cloud-aio.nimbus.local." = var.nimbus_aio_ip
    # New Nextcloud app-tier internal hostname — ALB routes by Host header
    # to the nextcloud-cloud backend (nimbus-cloud-01 on :80).
    "cloud-app.nimbus.local." = var.nimbus_alb_ip
    # Grafana — ALB routes mon.nimbus.local → nimbus-mon:3000
    "mon.nimbus.local." = var.nimbus_alb_ip
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
  records = [var.nimbus_alb_ip]
}

resource "powerdns_record" "nimbusnode_internal" {
  for_each = {
    "cloud.nimbusnode.org." = var.nimbus_alb_ip
    "aio.nimbusnode.org."   = var.nimbus_alb_ip
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
  description = "PowerDNS HTTP API key (auto-generated)"
  value       = module.nimbus_dns.api_key
  sensitive   = true
}
