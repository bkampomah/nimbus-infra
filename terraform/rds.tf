# terraform/rds.tf
#
# nimbus-rds - PostgreSQL 16 single-node, RDS-equivalent for Nimbus.
# Lives in the data subnet; serves the app subnet (Nextcloud in 5c) and
# accepts connections only from 10.0.10.0/24 via UFW + pg_hba.conf.
#
# IP is static (10.0.20.103) — set via var.nimbus_rds_ip and passed to the
# postgres module's cloud-init ip_config. Also seeds the PowerDNS A record.
#
# Daily pg_dumpall pushed to nimbus-s3 (pg-backups bucket) via the pgbackup
# service account — credentials read from module.nimbus_s3 outputs.
#
# Phase 5a deliverable, hardened in 5b.1.

# Generated credentials -------------------------------------------------------

resource "random_password" "nextcloud_db" {
  length  = 32
  special = true
  # Avoid special chars that choke libpq connection strings and shell escaping.
  override_special = "!#%&*+-=?@^_"
}

# Module invocation -----------------------------------------------------------

module "nimbus_rds" {
  source = "./modules/postgres"

  name           = "${var.company_name}-rds"
  proxmox_node   = var.proxmox_node
  template_vm_id = var.template_vm_id
  vm_storage     = var.proxmox_vm_storage
  iso_storage    = var.proxmox_iso_storage
  subnet_bridge  = var.subnets.data.bridge
  static_ip      = "${var.nimbus_rds_ip}/24"
  gateway        = var.subnets.data.gateway

  admin_username = var.admin_username
  admin_password = var.admin_password
  admin_ssh_keys = var.admin_ssh_public_keys

  cpu  = 2
  ram  = 4096
  disk = 32

  initial_db_name     = "nextcloud"
  initial_db_user     = "nextcloud"
  initial_db_password = random_password.nextcloud_db.result

  allowed_cidr = var.subnets.app.cidr

  # MinIO target for pg-backup pushes (read from module.nimbus_s3 outputs)
  s3_endpoint   = module.nimbus_s3.api_endpoint
  s3_access_key = module.nimbus_s3.pgbackup_access_key
  s3_secret_key = module.nimbus_s3.pgbackup_secret_key
  s3_bucket     = "pg-backups"
}

# Internal DNS ----------------------------------------------------------------

resource "powerdns_record" "nimbus_rds" {
  zone    = "nimbus.local."
  name    = "${var.company_name}-rds.nimbus.local."
  type    = "A"
  ttl     = 300
  records = [var.nimbus_rds_ip]
}

# Outputs ---------------------------------------------------------------------

output "nimbus_rds_host" {
  description = "Data-subnet IP of nimbus-rds (resolved via guest agent post-DHCP)"
  value       = module.nimbus_rds.host
}

output "nimbus_rds_port" {
  description = "PostgreSQL port"
  value       = module.nimbus_rds.port
}

output "nimbus_rds_db_name" {
  description = "Initial database name"
  value       = module.nimbus_rds.initial_db_name
}

output "nimbus_rds_db_user" {
  description = "Initial database user"
  value       = module.nimbus_rds.initial_db_user
}

output "nimbus_rds_connection" {
  description = "libpq connection string (password stored separately)"
  value       = module.nimbus_rds.connection_string
}

output "nimbus_rds_password" {
  description = "Run 'terraform output -raw nimbus_rds_password' to reveal"
  value       = random_password.nextcloud_db.result
  sensitive   = true
}
