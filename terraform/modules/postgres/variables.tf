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
  default = 4096
}

variable "disk" {
  type    = number
  default = 32
}

variable "ip_address" {
  description = "IPv4 address for the VM (no CIDR, just the address)"
  type        = string
}

variable "subnet_prefix" {
  description = "IPv4 subnet prefix length (e.g. 24)"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Default gateway — pfSense interface IP on this subnet"
  type        = string
}

variable "admin_username" { type = string }

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "admin_ssh_keys" { type = list(string) }

variable "postgres_db" {
  description = "Initial database to create"
  type        = string
  default     = "nextcloud"
}

variable "postgres_user" {
  description = "Initial database user (owner of postgres_db)"
  type        = string
  default     = "nextcloud"
}

variable "postgres_password" {
  description = "Password for postgres_user — supply via random_password resource"
  type        = string
  sensitive   = true
}

variable "allowed_cidr" {
  description = "CIDR block allowed to connect to postgres on 5432 (app subnet)"
  type        = string
  default     = "10.0.10.0/24"
}

variable "mgmt_cidr" {
  description = "CIDR block allowed SSH access (mgmt subnet)"
  type        = string
  default     = "10.0.100.0/24"
}

variable "wsl_cidr" {
  description = "WSL terraform manager"
  type        = string
  default     = "192.168.0.0/16"
}

variable "dns_server" {
  description = "Internal DNS server IP (PowerDNS)"
  type        = string
  default     = "10.0.100.10"
}

variable "search_domain" {
  description = "DNS search domain"
  type        = string
  default     = "nimbus.local"
}
