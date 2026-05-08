# terraform/s3.tf
#
# nimbus-s3 - MinIO single-node, S3-compatible object storage for Nimbus.
# Lives in the data subnet; serves the app subnet (Nextcloud in 5c) and
# accepts pg-backup uploads from nimbus-rds via a scoped service account.
#
# Phase 5b deliverable.

# Generated credentials -------------------------------------------------------

resource "random_password" "minio_root" {
  length           = 32
  special          = true
  override_special = "!#%&*+-=?@^_"
}

resource "random_password" "pgbackup_secret" {
  length           = 40
  special          = true
  override_special = "!#%&*+-=?@^_"
}

# Phase 7b — service-account secret for the Keycloak realm-export writer.
resource "random_password" "kc_backup_secret" {
  length           = 40
  special          = true
  override_special = "!#%&*+-=?@^_"
}

# Module invocation -----------------------------------------------------------

module "nimbus_s3" {
  source = "./modules/minio"

  name           = "${var.company_name}-s3"
  vm_id          = 113
  proxmox_node   = var.proxmox_node
  template_vm_id = var.template_vm_id
  vm_storage     = var.proxmox_vm_storage
  iso_storage    = var.proxmox_iso_storage
  subnet_bridge  = var.subnets.data.bridge

  admin_username = var.admin_username
  admin_password = var.admin_password
  admin_ssh_keys = var.admin_ssh_public_keys

  static_ip = "${var.nimbus_s3_ip}/24"
  gateway   = var.subnets.data.gateway

  root_disk_size_gb = var.nimbus_s3_root_disk_size_gb
  data_disk_size_gb = var.nimbus_s3_data_disk_size_gb

  minio_root_user      = var.minio_root_user
  minio_root_password  = random_password.minio_root.result
  minio_bucket         = "nextcloud-data"
  pgbackup_access_key  = "pgbackup"
  pgbackup_secret_key  = random_password.pgbackup_secret.result
  nextcloud_access_key = var.nextcloud_s3_access_key
  nextcloud_secret_key = var.nextcloud_s3_secret_key
  kc_backup_access_key = "kc-backup"
  kc_backup_secret_key = random_password.kc_backup_secret.result

  # Access controls:
  #   API     - reachable from any VPC subnet (app needs it, mgmt for admin work)
  #   Console - admin UI: mgmt subnet plus the operator's home LAN
  #   SSH     - mgmt subnet only
  api_allow_cidrs     = [var.vpc_cidr]
  console_allow_cidrs = concat(var.mgmt_allow_cidrs, ["192.168.1.0/24"])
  mgmt_allow_cidrs    = var.mgmt_allow_cidrs
  loki_url            = module.nimbus_mon.loki_url

  # Phase 7c — MinIO console OIDC SSO via Keycloak. role_policy=consoleAdmin
  # gives every Keycloak-authenticated user full MinIO admin in homelab; tighten
  # via per-group claim mapping in Phase 8.
  oidc_issuer_url    = "https://${var.keycloak_domain}/realms/${keycloak_realm.nimbus.realm}"
  oidc_client_id     = keycloak_openid_client.minio_console.client_id
  oidc_client_secret = keycloak_openid_client.minio_console.client_secret
  oidc_role_policy   = "consoleAdmin"
  nimbus_ca_pem      = tls_self_signed_cert.nimbus_ca.cert_pem
}

# Internal DNS ----------------------------------------------------------------

resource "powerdns_record" "nimbus_s3" {
  zone    = "nimbus.local."
  name    = "${var.company_name}-s3.nimbus.local."
  type    = "A"
  ttl     = 300
  records = [var.nimbus_s3_ip]
}

# Outputs ---------------------------------------------------------------------

output "nimbus_s3_host" {
  description = "Data-subnet IP of nimbus-s3 (matches var.nimbus_s3_ip)"
  value       = module.nimbus_s3.host
}

output "nimbus_s3_api" {
  description = "S3 API endpoint - use from Nextcloud, mc client, etc."
  value       = module.nimbus_s3.api_endpoint
}

output "nimbus_s3_console" {
  description = "Web admin console - reachable from mgmt subnet and home LAN"
  value       = module.nimbus_s3.console_endpoint
}

output "nimbus_s3_root_user" {
  description = "MinIO root admin username"
  value       = module.nimbus_s3.minio_root_user
}

output "nimbus_s3_root_password" {
  description = "Run 'terraform output -raw nimbus_s3_root_password' to reveal"
  value       = random_password.minio_root.result
  sensitive   = true
}

output "nimbus_s3_pgbackup_access_key" {
  description = "Service account access key for the pg-backup writer"
  value       = module.nimbus_s3.pgbackup_access_key
}

output "nimbus_s3_pgbackup_secret_key" {
  description = "Run 'terraform output -raw nimbus_s3_pgbackup_secret_key' to reveal"
  value       = random_password.pgbackup_secret.result
  sensitive   = true
}

output "nimbus_s3_kc_backup_access_key" {
  description = "Service account access key for the Keycloak realm-export writer"
  value       = module.nimbus_s3.kc_backup_access_key
}

output "nimbus_s3_kc_backup_secret_key" {
  description = "Run 'terraform output -raw nimbus_s3_kc_backup_secret_key' to reveal"
  value       = random_password.kc_backup_secret.result
  sensitive   = true
}
