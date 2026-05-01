# -----------------------------------------------------------------------------
# Identity & placement
# -----------------------------------------------------------------------------
variable "name" {
  description = "VM hostname / display name (e.g. nimbus-bastion)"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VMID"
  type        = number
}

variable "proxmox_node" {
  description = "Proxmox node to deploy on (pve / pve2)"
  type        = string
}

variable "template_vm_id" {
  description = "VMID of the golden Ubuntu template to clone"
  type        = number
}

variable "vm_storage" {
  description = "Proxmox storage pool for VM disks"
  type        = string
}

variable "iso_storage" {
  description = "Proxmox storage pool for cloud-init snippet files"
  type        = string
}

variable "tags" {
  description = "Additional Proxmox tags for the bastion VM"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "subnet_bridge" {
  description = "Proxmox SDN VNet / bridge name (e.g. nimbus-public)"
  type        = string
}

variable "static_ip" {
  description = "Static IPv4 with CIDR suffix (e.g. 10.0.100.20/24)"
  type        = string
}

variable "gateway" {
  description = "Default gateway (pfSense interface IP on this subnet)"
  type        = string
}

variable "ssh_allow_cidrs" {
  description = "CIDRs allowed SSH access to the bastion"
  type        = list(string)
}

variable "pfsense_gui_host" {
  description = "pfSense WebConfigurator host/IP reachable from the bastion"
  type        = string
}

variable "pfsense_gui_port" {
  description = "pfSense WebConfigurator HTTPS port"
  type        = number
  default     = 443
}

variable "tunnel_local_port" {
  description = "Suggested local workstation port for the pfSense SSH tunnel"
  type        = number
  default     = 8443
}

# -----------------------------------------------------------------------------
# Sizing
# -----------------------------------------------------------------------------
variable "cpu" {
  description = "vCPU count"
  type        = number
  default     = 1
}

variable "ram" {
  description = "RAM in MB"
  type        = number
  default     = 1024
}

variable "disk" {
  description = "Root disk size in GB"
  type        = number
  default     = 25

  validation {
    condition     = var.disk >= 22
    error_message = "disk must be at least 22 GB."
  }
}

# -----------------------------------------------------------------------------
# Admin user
# -----------------------------------------------------------------------------
variable "admin_username" {
  description = "Default admin username (cloud-init creates this user)"
  type        = string
}

variable "admin_password" {
  description = "Initial password for admin user (also used for console fallback)"
  type        = string
  sensitive   = true
}

variable "admin_ssh_keys" {
  description = "List of SSH public keys for admin user"
  type        = list(string)
}

variable "loki_url" {
  description = "Promtail push endpoint on nimbus-mon (e.g. http://10.0.100.20:3100). Empty string disables Promtail."
  type        = string
  default     = "http://10.0.100.20:3100"
}
