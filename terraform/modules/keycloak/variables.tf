# terraform/modules/keycloak/variables.tf

variable "name" { type = string }
variable "proxmox_node" { type = string }
variable "template_vm_id" { type = number }
variable "vm_storage" { type = string }
variable "iso_storage" { type = string }
variable "subnet_bridge" { type = string }

variable "static_ip" {
  description = "Static IPv4 with prefix (e.g. '10.0.100.30/24')"
  type        = string
}

variable "gateway" {
  description = "Default gateway for the mgmt subnet"
  type        = string
}

variable "cpu" {
  type    = number
  default = 2
}

variable "ram" {
  description = "RAM in MB. Keycloak baseline is ~1 GB; 4 GB gives JVM headroom."
  type        = number
  default     = 4096
}

variable "disk" {
  type    = number
  default = 32
}

variable "admin_username" { type = string }

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "admin_ssh_keys" { type = list(string) }

# ── Keycloak runtime config ─────────────────────────────────────────────────

variable "keycloak_version" {
  description = "Keycloak release tag (matches the tarball on github.com/keycloak/keycloak/releases)"
  type        = string
  default     = "25.0.6"
}

variable "keycloak_hostname" {
  description = "Public FQDN Keycloak should advertise as its base URL (KC_HOSTNAME). OIDC discovery + redirects key off this."
  type        = string
}

variable "keycloak_admin_user" {
  description = "Bootstrap admin username for the master realm"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Bootstrap admin password — used only for the very first boot. Rotate via the admin console immediately."
  type        = string
  sensitive   = true
}

# ── Database (nimbus-rds) ───────────────────────────────────────────────────

variable "db_host" {
  description = "Postgres host (typically nimbus-rds.nimbus.local or its IP)"
  type        = string
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "db_name" {
  type    = string
  default = "keycloak"
}

variable "db_user" {
  type    = string
  default = "keycloak"
}

variable "db_password" {
  type      = string
  sensitive = true
}

# ── TLS (issued by Nimbus internal CA in certs.tf) ─────────────────────────

variable "tls_cert_pem" {
  description = "Server cert + CA chain (concatenated PEMs). Keycloak serves this on :8443."
  type        = string
  sensitive   = true
}

variable "tls_key_pem" {
  description = "Private key matching tls_cert_pem"
  type        = string
  sensitive   = true
}

# ── Network access ──────────────────────────────────────────────────────────

variable "alb_cidr" {
  description = "CIDR allowed to hit Keycloak on :8443 (the ALB does the upstream connect)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "mgmt_allow_cidrs" {
  description = "CIDRs allowed SSH + node-exporter + direct :8443 admin access"
  type        = list(string)
  default     = ["10.0.100.0/24"]
}

variable "loki_url" {
  description = "Promtail push endpoint on nimbus-mon"
  type        = string
  default     = "http://10.0.100.20:3100"
}

# ── Realm export backup target (Phase 7b) ──────────────────────────────────
# Nightly kc.sh export → MinIO. Empty backup_s3_endpoint disables the timer.

variable "backup_s3_endpoint" {
  description = "S3 API endpoint for realm-export pushes (e.g. http://10.0.20.101:9000). Empty disables the timer."
  type        = string
  default     = ""
}

variable "backup_s3_access_key" {
  description = "Service-account access key with write to the kc-backups bucket"
  type        = string
  default     = ""
}

variable "backup_s3_secret_key" {
  description = "Service-account secret key (paired with backup_s3_access_key)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backup_s3_bucket" {
  description = "Bucket name for realm exports"
  type        = string
  default     = "kc-backups"
}

variable "backup_realms" {
  description = "Realms to export nightly. Each is a separate kc.sh export call."
  type        = list(string)
  default     = ["master", "nimbus"]
}
