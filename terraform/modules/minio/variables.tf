# terraform/modules/minio/variables.tf

variable "name"           { type = string }
variable "proxmox_node"   { type = string }
variable "template_vm_id" { type = number }
variable "vm_storage"     { type = string }
variable "iso_storage"    { type = string }
variable "subnet_bridge"  { type = string }

variable "cpu"       { type = number  default = 2 }
variable "ram"       { type = number  default = 4096 }
variable "disk"      { type = number  default = 20 }
variable "data_disk" { type = number  default = 200 } # CHANGE_ME — S3 data volume

variable "admin_username" { type = string }
variable "admin_password" { type = string sensitive = true }
variable "admin_ssh_keys" { type = list(string) }

# ─── MinIO root ("IAM root account") ────────────────────────────────────────
variable "minio_root_user" {
  type    = string
  default = "nimbus-admin"
}

variable "minio_root_password" {
  description = "MinIO root password (min 8 chars)"
  type        = string
  sensitive   = true
  # CHANGE_ME in root terraform.tfvars
}

# ─── Bucket + scoped credentials for Nextcloud ──────────────────────────────
# These mimic creating an IAM user with access to a single S3 bucket.

variable "nextcloud_bucket" {
  type    = string
  default = "nextcloud-primary"
}

variable "nextcloud_access_key" {
  description = "Access key ID for the Nextcloud MinIO user"
  type        = string
  sensitive   = true
  # CHANGE_ME in root terraform.tfvars (any >=3-char string; convention: 20 chars)
}

variable "nextcloud_secret_key" {
  description = "Secret access key for the Nextcloud MinIO user"
  type        = string
  sensitive   = true
  # CHANGE_ME in root terraform.tfvars (any >=8-char string; convention: 40 chars)
}
