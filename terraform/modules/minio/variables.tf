# terraform/modules/minio/variables.tf

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
  description = "Root disk size in GB. Must be >= golden template size (21.5G)."
  type        = number
  default     = 25
}

variable "data_disk" {
  type    = number
  default = 200
}

variable "admin_username" { type = string }

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "admin_ssh_keys" { type = list(string) }

variable "minio_root_user" {
  type    = string
  default = "nimbus-admin"
}

variable "minio_root_password" {
  description = "MinIO root password (min 8 chars)"
  type        = string
  sensitive   = true
}

variable "nextcloud_bucket" {
  type    = string
  default = "nextcloud-primary"
}

variable "nextcloud_access_key" {
  description = "Access key ID for the Nextcloud MinIO user"
  type        = string
  sensitive   = true
}

variable "nextcloud_secret_key" {
  description = "Secret access key for the Nextcloud MinIO user"
  type        = string
  sensitive   = true
}
