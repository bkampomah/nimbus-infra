# -----------------------------------------------------------------------------
# Phase 5a — nimbus-rds (PostgreSQL 16) in nimbus-data subnet
# -----------------------------------------------------------------------------

# Generated password for the nextcloud DB user — sensitive, surfaced via output.
resource "random_password" "nextcloud_db" {
  length  = 32
  special = true
  # Avoid special chars that choke libpq connection strings and shell escaping.
  override_special = "!#%&*+-=?@^_"
}

module "postgres" {
  source = "./modules/postgres"

  # --- VM placement ------------------------------------------------------
  name           = "${var.company_name}-rds"
  proxmox_node   = var.proxmox_node
  template_vm_id = var.template_vm_id
  vm_storage     = var.proxmox_vm_storage
  iso_storage    = var.proxmox_iso_storage

  # --- Networking --------------------------------------------------------
  ip_address    = "10.0.20.100"
  subnet_prefix = 24
  gateway       = "10.0.20.1"
  subnet_bridge = var.subnets.data.bridge # VERIFY: Proxmox SDN VNet bridge name

  # --- Sizing ------------------------------------------------------------
  #cpu_cores    = 2
  #memory_mb    = 4096
  #disk_size_gb = 32

  # --- Credentials / DB --------------------------------------------------
  admin_username    = var.admin_username
  admin_password    = var.admin_password
  admin_ssh_keys    = var.admin_ssh_public_keys
  postgres_db       = "nextcloud"
  postgres_user     = "nextcloud"
  postgres_password = random_password.nextcloud_db.result

  # --- Access controls --------------------------------------------------
  allowed_cidr  = "10.0.10.0/24"
  wsl_cidr      = "192.168.0.0/16"
  mgmt_cidr     = "10.0.100.0/24"
  dns_server    = "10.0.100.10"
  search_domain = "nimbus.local"
}

# -----------------------------------------------------------------------------
# PowerDNS A record — nimbus-rds.nimbus.local -> 10.0.20.100
# -----------------------------------------------------------------------------
resource "powerdns_record" "nimbus_rds" {
  zone    = "nimbus.local."
  name    = "nimbus-rds.nimbus.local."
  type    = "A"
  ttl     = 300
  records = ["10.0.20.100"]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "nimbus_rds_ip" {
  value       = module.postgres.ip_address
  description = "nimbus-rds IP address"
}

output "nimbus_rds_fqdn" {
  value       = module.postgres.fqdn
  description = "nimbus-rds FQDN (resolves via PowerDNS)"
}

output "nimbus_rds_connection" {
  value       = module.postgres.postgres_connection_string
  description = "libpq connection string (password stored separately)"
}

output "nimbus_rds_password" {
  value       = random_password.nextcloud_db.result
  sensitive   = true
  description = "Run 'terraform output -raw nimbus_rds_password' to reveal"
}
