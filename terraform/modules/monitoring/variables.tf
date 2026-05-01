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
