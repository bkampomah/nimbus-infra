# terraform/cloud.tf
#
# nimbus-cloud-01 - Nextcloud app-tier VM for Phase 5c.
# This runs in parallel with the existing AIO VM until the ALB backend is moved.

module "nimbus_nextcloud" {
  source = "./modules/nextcloud"

  name           = "${var.company_name}-cloud-01"
  proxmox_node   = var.proxmox_node
  template_vm_id = var.template_vm_id
  vm_storage     = var.proxmox_vm_storage
  iso_storage    = var.proxmox_iso_storage
  subnet_bridge  = var.subnets.app.bridge

  admin_username = var.admin_username
  admin_password = var.admin_password
  admin_ssh_keys = var.admin_ssh_public_keys

  cpu  = 4
  ram  = 8192
  disk = 100

  static_ip = "${var.nimbus_cloud_ip}/24"
  gateway   = var.subnets.app.gateway

  nextcloud_admin_pw = var.nextcloud_admin_password
  nextcloud_domain   = var.nextcloud_domain
  extra_trusted_domains = [
    "cloud-app.nimbus.local",
  ]
  trusted_proxies  = concat(["${var.nimbus_alb_ip}/32"], var.cloudflare_ip_ranges)
  alb_allow_cidrs  = ["${var.nimbus_alb_ip}/32"]
  mgmt_allow_cidrs = var.mgmt_allow_cidrs

  db_host     = module.nimbus_rds.host
  db_name     = module.nimbus_rds.initial_db_name
  db_user     = module.nimbus_rds.initial_db_user
  db_password = random_password.nextcloud_db.result

  s3_endpoint   = module.nimbus_s3.api_endpoint
  s3_bucket     = module.nimbus_s3.default_bucket
  s3_access_key = var.nextcloud_s3_access_key
  s3_secret_key = var.nextcloud_s3_secret_key
  loki_url      = module.nimbus_mon.loki_url
}

resource "powerdns_record" "cloud_app" {
  zone    = "nimbus.local."
  name    = "cloud-app.nimbus.local."
  type    = "A"
  ttl     = 300
  records = [var.nimbus_alb_ip]
}

output "nimbus_nextcloud_host" {
  description = "App-subnet IP of nimbus-cloud-01"
  value       = module.nimbus_nextcloud.ipv4_address
}

output "nimbus_nextcloud_backend_target" {
  description = "Backend target for the Phase 5c.3 ALB route"
  value       = module.nimbus_nextcloud.backend_target
}
