# terraform/modules/monitoring/variables.tf

variable "name" { type = string }
variable "proxmox_node" { type = string }
variable "template_vm_id" { type = number }
variable "vm_storage" { type = string }
variable "iso_storage" { type = string }
variable "subnet_bridge" { type = string }

variable "static_ip" {
  description = "Static IPv4 address with prefix (e.g. '10.0.100.20/24')"
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

variable "scrape_targets" {
  description = "Prometheus scrape jobs. Each entry becomes a scrape_config block."
  type = list(object({
    name    = string
    targets = list(string)
  }))
  default = []
}

variable "mgmt_allow_cidrs" {
  description = "CIDRs allowed to reach Grafana (:3000), Prometheus (:9090), and SSH (:22)"
  type        = list(string)
  default     = ["10.0.100.0/24"]
}

variable "loki_allow_cidrs" {
  description = "CIDRs allowed to push logs to Loki (:3100). All VMs need this."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "loki_url" {
  description = "Promtail push endpoint on nimbus-mon (e.g. http://10.0.100.20:3100). Empty string disables Promtail."
  type        = string
  default     = "http://10.0.100.20:3100"
}

# ── Phase 7c — Grafana OIDC SSO via Keycloak ───────────────────────────────
# Empty oidc_issuer_url disables OIDC env vars — keeps the module backward-
# compatible with Phase 6 deploys.

variable "grafana_root_url" {
  description = "Public root URL Grafana advertises (e.g. https://mon.nimbus.local). Used by GF_SERVER_ROOT_URL — required for OIDC redirects."
  type        = string
  default     = "https://mon.nimbus.local"
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL (e.g. https://auth.nimbusnode.org/realms/nimbus). Empty disables OIDC."
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OAuth client_id registered in Keycloak for Grafana"
  type        = string
  default     = ""
}

variable "oidc_client_secret" {
  description = "OAuth client_secret for the Grafana client"
  type        = string
  sensitive   = true
  default     = ""
}

variable "nimbus_ca_pem" {
  description = "Internal CA cert PEM. Installed into the system trust store so Grafana validates Keycloak's TLS. Empty skips."
  type        = string
  default     = ""
}
