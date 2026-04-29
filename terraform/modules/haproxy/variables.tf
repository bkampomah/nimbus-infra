# terraform/modules/haproxy/variables.tf

variable "name" { type = string }
variable "proxmox_node" { type = string }
variable "template_vm_id" { type = number }
variable "vm_storage" { type = string }
variable "iso_storage" { type = string }
variable "subnet_bridge" { type = string }

variable "cpu" {
  type    = number
  default = 2
}

variable "ram" {
  type    = number
  default = 2048
}

variable "disk" {
  description = "Root disk size in GB. Must be >= golden template size."
  type        = number
  default     = 25
}

variable "admin_username" { type = string }

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "admin_ssh_keys" { type = list(string) }

variable "static_ip" {
  description = "Static IPv4 with CIDR for the ALB, e.g. 10.0.1.10/24"
  type        = string
}

variable "gateway" {
  description = "Default gateway for the public subnet (pfSense interface)"
  type        = string
}

variable "backends" {
  description = "List of backend routing rules. Each entry maps a Host header to an upstream server. Path-based ACLs can be added per rule later."
  type = list(object({
    name        = string # internal label (e.g. "nextcloud-aio")
    host_match  = string # e.g. "cloud.nimbus.local"
    server_ip   = string # e.g. "10.0.10.101"
    server_port = number # e.g. 11000
    check       = optional(bool, true)
  }))
  default = []
}

variable "cloudflare_tunnel_token" {
  description = "Cloudflare Tunnel token. Leave empty to skip cloudflared install."
  type        = string
  sensitive   = true
  default     = ""
}

variable "alb_allow_cidrs" {
  description = "CIDRs allowed to hit the ALB on :80 (public-facing from the VPC). Defaults to all of Nimbus."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "mgmt_allow_cidrs" {
  description = "CIDRs allowed to hit the HAProxy stats page on :8404. Keep tight - mgmt subnet and localhost only."
  type        = list(string)
  default     = ["10.0.100.0/24", "127.0.0.1/32"]
}
