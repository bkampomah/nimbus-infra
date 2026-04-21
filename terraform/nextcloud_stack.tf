# terraform/nextcloud_stack.tf
#
# Wires together nimbus-rds, nimbus-s3, and nimbus-cloud-01.
# Order of operations is handled implicitly by Terraform through the
# output → variable references below.

# ─── nimbus-rds (PostgreSQL = RDS) ──────────────────────────────────────────
module "nimbus_rds" {
  source = "./modules/postgres"

  name           = "${var.company_name}-rds"
  proxmox_node   = var.proxmox_node
  template_vm_id = var.template_vm_id
  vm_storage     = var.proxmox_vm_storage
  iso_storage    = var.proxmox_iso_storage
  subnet_bridge  = var.subnets.data.bridge

  admin_username = var.admin_username
  admin_password = var.admin_password
  admin_ssh_keys = var.admin_ssh_public_keys

  initial_db_name     = "nextcloud"
  initial_db_user     = "nextcloud"
  initial_db_password = var.nextcloud_db_password
  allowed_cidr        = var.subnets.app.cidr
}

# ─── nimbus-s3 (MinIO = S3) ─────────────────────────────────────────────────
module "nimbus_s3" {
  source = "./modules/minio"

  name           = "${var.company_name}-s3"
  proxmox_node   = var.proxmox_node
  template_vm_id = var.template_vm_id
  vm_storage     = var.proxmox_vm_storage
  iso_storage    = var.proxmox_iso_storage
  subnet_bridge  = var.subnets.data.bridge

  admin_username = var.admin_username
  admin_password = var.admin_password
  admin_ssh_keys = var.admin_ssh_public_keys

  minio_root_user      = var.minio_root_user
  minio_root_password  = var.minio_root_password
  nextcloud_bucket     = "nextcloud-primary"
  nextcloud_access_key = var.nextcloud_s3_access_key
  nextcloud_secret_key = var.nextcloud_s3_secret_key
}

# ─── nimbus-cloud-01 (Nextcloud app tier) ───────────────────────────────────
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

  nextcloud_admin_pw = var.nextcloud_admin_password
  nextcloud_domain   = var.nextcloud_domain
  trusted_proxies    = concat([var.subnets.public.cidr], var.cloudflare_ip_ranges)

  db_host     = module.nimbus_rds.host
  db_name     = module.nimbus_rds.initial_db_name
  db_user     = module.nimbus_rds.initial_db_user
  db_password = var.nextcloud_db_password

  s3_endpoint   = module.nimbus_s3.endpoint
  s3_bucket     = module.nimbus_s3.nextcloud_bucket
  s3_access_key = var.nextcloud_s3_access_key
  s3_secret_key = var.nextcloud_s3_secret_key
}

# ─── Handy outputs ──────────────────────────────────────────────────────────
output "nextcloud_backend_target" {
  description = "Point HAProxy / Traefik at this host:port"
  value       = module.nimbus_nextcloud.backend_target
}

output "nimbus_rds_host"    { value = module.nimbus_rds.host }
output "nimbus_s3_endpoint" { value = module.nimbus_s3.endpoint }
output "nimbus_s3_console"  { value = module.nimbus_s3.console_url }
