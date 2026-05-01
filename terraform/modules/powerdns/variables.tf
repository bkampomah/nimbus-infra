# terraform/modules/powerdns/variables.tf

variable "name" { type = string }
variable "proxmox_node" { type = string }
variable "template_vm_id" { type = number }
variable "vm_storage" { type = string }
variable "iso_storage" { type = string }
variable "subnet_bridge" { type = string }

variable "cpu" {
  type    = number
  default = 1
}

variable "ram" {
  type    = number
  default = 1024
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

variable "static_ip" {
  description = "Static IPv4 with CIDR for nimbus-dns, e.g. 10.0.100.10/24"
  type        = string
}

variable "gateway" {
  description = "Default gateway for the mgmt subnet (pfSense interface)"
  type        = string
}

variable "upstream_dns" {
  description = "Upstream resolvers for external names"
  type        = list(string)
  default     = ["1.1.1.1", "9.9.9.9"]
}

variable "recursor_forwards" {
  description = "Zones forwarded to specific resolvers instead of recursed"
  type        = map(string)
  default     = {}
}

variable "internal_zones" {
  description = "Zones nimbus-dns is authoritative for"
  type        = list(string)
  default     = ["nimbus.local", "nimbusnode.org"]
}

variable "api_allow_cidrs" {
  description = "CIDRs allowed to hit the PowerDNS HTTP API"
  type        = list(string)
  default     = ["10.0.0.0/16", "127.0.0.1/32"]
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
