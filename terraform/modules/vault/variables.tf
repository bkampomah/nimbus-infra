# terraform/modules/vault/variables.tf

variable "name" { type = string }
variable "proxmox_node" { type = string }
variable "template_vm_id" { type = number }
variable "vm_storage" { type = string }
variable "iso_storage" { type = string }
variable "subnet_bridge" { type = string }

variable "static_ip" {
  description = "Static IPv4 with prefix (e.g. '10.0.100.40/24')"
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
  type    = number
  default = 2048
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

# ── Vault runtime config ────────────────────────────────────────────────────

variable "vault_version" {
  description = "HashiCorp Vault release. Matches releases.hashicorp.com/vault."
  type        = string
  default     = "1.18.2"
}

variable "cluster_name" {
  description = "Vault cluster name (free-form label, surfaces in audit logs)"
  type        = string
  default     = "nimbus"
}

# ── TLS (issued by Nimbus internal CA in certs.tf) ─────────────────────────

variable "tls_cert_pem" {
  description = "Server cert + CA chain (concatenated PEMs). Vault serves this on :8200."
  type        = string
  sensitive   = true
}

variable "tls_key_pem" {
  description = "Private key matching tls_cert_pem"
  type        = string
  sensitive   = true
}

# ── Network access ──────────────────────────────────────────────────────────

variable "client_allow_cidrs" {
  description = "CIDRs allowed to reach Vault on :8200. Default = full VPC; tighten later if needed."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "mgmt_allow_cidrs" {
  description = "CIDRs allowed SSH + node-exporter access"
  type        = list(string)
  default     = ["10.0.100.0/24"]
}

variable "loki_url" {
  description = "Promtail push endpoint on nimbus-mon"
  type        = string
  default     = "http://10.0.100.20:3100"
}

variable "nimbus_ca_pem" {
  description = "Internal CA cert PEM. Installed into the system trust store so Vault validates Keycloak's TLS when wiring the OIDC auth method (Phase 7d). Empty skips."
  type        = string
  default     = ""
}
