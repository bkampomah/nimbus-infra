# terraform/modules/nextcloud/variables.tf

variable "name" { type = string }
variable "proxmox_node" { type = string }
variable "template_vm_id" { type = number }
variable "vm_storage" { type = string }
variable "iso_storage" { type = string }
variable "subnet_bridge" { type = string }

variable "static_ip" {
  description = "Static IPv4 with CIDR suffix, e.g. 10.0.10.102/24"
  type        = string
}

variable "gateway" {
  description = "Default gateway for the app subnet"
  type        = string
}

variable "cpu" {
  type    = number
  default = 4
}

variable "ram" {
  type    = number
  default = 8192
}

variable "disk" {
  type    = number
  default = 100
}

variable "admin_username" { type = string }

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "admin_ssh_keys" { type = list(string) }

variable "nextcloud_admin_pw" {
  description = "Password for the initial Nextcloud web admin user"
  type        = string
  sensitive   = true
}

variable "nextcloud_domain" {
  description = "FQDN users hit (registered with PowerDNS + cert on the ALB)"
  type        = string
  default     = "cloud.nimbus.local"
}

variable "extra_trusted_domains" {
  description = "Additional hostnames Nextcloud should accept, such as internal test DNS names."
  type        = list(string)
  default     = []
}

variable "trusted_proxies" {
  description = "CIDRs Nextcloud will trust for X-Forwarded-For"
  type        = list(string)
}

variable "alb_allow_cidrs" {
  description = "CIDRs allowed to reach Nextcloud over HTTP/HTTPS"
  type        = list(string)
}

variable "mgmt_allow_cidrs" {
  description = "CIDRs allowed SSH access"
  type        = list(string)
}

variable "db_host" { type = string }

variable "db_name" {
  type    = string
  default = "nextcloud"
}

variable "db_user" {
  type    = string
  default = "nextcloud"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "s3_endpoint" {
  description = "MinIO URL, e.g. http://nimbus-s3.nimbus.local:9000"
  type        = string
}

variable "s3_bucket" {
  type    = string
  default = "nextcloud-primary"
}

variable "s3_access_key" {
  type      = string
  sensitive = true
}

variable "s3_secret_key" {
  type      = string
  sensitive = true
}

variable "loki_url" {
  description = "Promtail push endpoint on nimbus-mon (e.g. http://10.0.100.20:3100). Empty string disables Promtail."
  type        = string
  default     = "http://10.0.100.20:3100"
}

# ── Phase 7c — OIDC SSO via Keycloak ───────────────────────────────────────
# Empty oidc_issuer_url disables the user_oidc app install — keeps the
# module backwards-compatible with Phase 5 deploys.

variable "oidc_issuer_url" {
  description = "OIDC issuer URL (e.g. https://auth.nimbusnode.org/realms/nimbus). Empty disables OIDC."
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OAuth client_id registered in Keycloak for Nextcloud"
  type        = string
  default     = ""
}

variable "oidc_client_secret" {
  description = "OAuth client_secret for the Nextcloud client"
  type        = string
  sensitive   = true
  default     = ""
}

variable "nimbus_ca_pem" {
  description = "Internal CA cert PEM. Installed into the system trust store so Nextcloud's outbound calls to Keycloak validate. Empty skips the install."
  type        = string
  default     = ""
}

# ── Phase 7e — Vault Agent for dynamic Postgres credentials ────────────────
# Empty vault_addr disables the agent — module stays backward compatible with
# Phase 5 deploys that don't have Vault yet.

variable "vault_addr" {
  description = "Vault API endpoint (e.g. https://vault.nimbus.local:8200). Empty disables Vault Agent."
  type        = string
  default     = ""
}

variable "vault_approle_role_id" {
  description = "AppRole role_id for Vault Agent. Public — commit-safe."
  type        = string
  default     = ""
}

variable "vault_approle_secret_id" {
  description = "AppRole secret_id for Vault Agent. Sensitive."
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_db_role_path" {
  description = "Vault path that mints dynamic DB creds (e.g. database/creds/nextcloud)."
  type        = string
  default     = "database/creds/nextcloud"
}

variable "vault_version" {
  description = "Vault binary version installed for Vault Agent (must match nimbus-vault for compat)."
  type        = string
  default     = "1.18.2"
}
