# terraform/modules/postgres/variables.tf

variable "name" { type = string }
variable "proxmox_node" { type = string }
variable "template_vm_id" { type = number }
variable "vm_storage" { type = string }
variable "iso_storage" { type = string }
variable "subnet_bridge" { type = string }
variable "static_ip" {
  description = "Static IPv4 address with prefix (e.g. '10.0.20.100/24')"
  type        = string
}
variable "gateway" {
  description = "Default gateway for the data subnet"
  type        = string
}

variable "cpu" {
  type    = number
  default = 2
}

variable "ram" {
  type    = number
  default = 4096
}

variable "disk" {
  type    = number
  default = 50
}

variable "admin_username" { type = string }

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "admin_ssh_keys" { type = list(string) }

variable "initial_db_name" {
  type    = string
  default = "nextcloud"
}

variable "initial_db_user" {
  type    = string
  default = "nextcloud"
}

variable "initial_db_password" {
  type      = string
  sensitive = true
}

variable "additional_databases" {
  description = <<-EOT
    Extra (database, role) pairs to provision at first boot beyond the initial
    Nextcloud DB. Each entry creates a database owned by a role of the same name
    with the supplied password. Used by Phase 7 to host the Keycloak DB on the
    same nimbus-rds without standing up a second Postgres VM.
  EOT
  type = list(object({
    name     = string
    user     = string
    password = string
  }))
  default   = []
  sensitive = true
}

# ── Phase 7d — Vault database secrets engine admin role ────────────────────
# Vault's database engine needs a Postgres role with permission to create new
# users on demand. Empty disables the role creation.
#
# In homelab we make it SUPERUSER for simplicity; Phase 8 hardening tightens
# to membership-of-target-DB-owner + GRANT OPTION.

variable "vault_admin_user" {
  description = "Username Vault uses to mint dynamic Postgres credentials. Empty disables."
  type        = string
  default     = ""
}

variable "vault_admin_password" {
  description = "Password for the Vault admin role on Postgres. Required when vault_admin_user is set."
  type        = string
  sensitive   = true
  default     = ""
}

variable "allowed_cidr" {
  description = "CIDR allowed to connect to Postgres over the network"
  type        = string
  default     = "10.0.10.0/24"
}

# ---------------------------------------------------------------------------
# Backup destination — MinIO (S3-compatible)
# Wired from module.nimbus_s3 outputs in rds.tf so changing the bucket name
# or rotating the service-account secret in s3.tf propagates automatically.
# ---------------------------------------------------------------------------
variable "s3_endpoint" {
  description = "S3 API endpoint URL for backup pushes (e.g. http://10.0.20.101:9000)"
  type        = string
}

variable "s3_access_key" {
  description = "Service-account access key with write to the backup bucket"
  type        = string
}

variable "s3_secret_key" {
  description = "Service-account secret key (paired with s3_access_key)"
  type        = string
  sensitive   = true
}

variable "s3_bucket" {
  description = "Bucket name for postgres dumps"
  type        = string
  default     = "pg-backups"
}

variable "mgmt_allow_cidrs" {
  description = "CIDRs allowed SSH and node-exporter access (:22, :9100)"
  type        = list(string)
  default     = ["10.0.100.0/24"]
}

variable "loki_url" {
  description = "Promtail push endpoint on nimbus-mon (e.g. http://10.0.100.20:3100). Empty string disables Promtail."
  type        = string
  default     = "http://10.0.100.20:3100"
}
