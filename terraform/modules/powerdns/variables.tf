# terraform/modules/powerdns/variables.tf

variable "name"           { type = string }
variable "proxmox_node"   { type = string }
variable "template_vm_id" { type = number }
variable "vm_storage"     { type = string }
variable "iso_storage"    { type = string }
variable "subnet_bridge"  { type = string }

variable "cpu"  { type = number  default = 1 }
variable "ram"  { type = number  default = 1024 }
variable "disk" { type = number  default = 20 }

variable "admin_username" { type = string }
variable "admin_password" { type = string  sensitive = true }
variable "admin_ssh_keys" { type = list(string) }

# ─── Network ────────────────────────────────────────────────────────────────
variable "static_ip" {
  description = "Static IPv4 with CIDR for nimbus-dns, e.g. 10.0.100.10/24"
  type        = string
  # CHANGE_ME in root terraform.tfvars
}

variable "gateway" {
  description = "Default gateway for the mgmt subnet (pfSense interface)"
  type        = string
  # CHANGE_ME — matches your subnets.mgmt.gateway, typically 10.0.100.1
}

# ─── DNS config ─────────────────────────────────────────────────────────────
variable "upstream_dns" {
  description = "Upstream resolvers for external names (pdns_recursor forward-to)"
  type        = list(string)
  default     = ["1.1.1.1", "9.9.9.9"]
}

variable "recursor_forwards" {
  description = <<-EOT
    Zones that should be forwarded to a specific resolver instead of
    recursed. Leave empty for most setups — the default is "recurse
    everything not in internal_zones via upstream_dns".
  EOT
  type = map(string)
  default = {}
}

variable "internal_zones" {
  description = <<-EOT
    Zones nimbus-dns is authoritative for. Order matters for the zone
    file templating. Keep nimbus.local first.
  EOT
  type    = list(string)
  default = ["nimbus.local", "nimbusnode.org"]
}

variable "api_allow_cidrs" {
  description = "CIDRs allowed to hit the PowerDNS HTTP API (for Terraform)"
  type        = list(string)
  default     = ["10.0.0.0/16", "127.0.0.1/32"]
}
