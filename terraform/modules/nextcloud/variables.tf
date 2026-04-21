# terraform/modules/nextcloud/variables.tf

# ─── VM shape / Proxmox ─────────────────────────────────────────────────────
variable "name"           { type = string }
variable "proxmox_node"   { type = string }
variable "template_vm_id" { type = number }
variable "vm_storage"     { type = string }
variable "iso_storage"    { type = string }
variable "subnet_bridge"  { type = string }
variable "cpu"            { type = number  default = 4 }
variable "ram"            { type = number  default = 8192 }
variable "disk"           { type = number  default = 100 }

# ─── Linux admin (matches the rest of Nimbus) ───────────────────────────────
variable "admin_username" { type = string }
variable "admin_password" { type = string sensitive = true }
variable "admin_ssh_keys" { type = list(string) }

# ─── Nextcloud app config ───────────────────────────────────────────────────
variable "nextcloud_admin_pw" {
  description = "Password for the initial Nextcloud web admin user"
  type        = string
  sensitive   = true
  # CHANGE_ME in root terraform.tfvars
}

variable "nextcloud_domain" {
  description = "FQDN users hit (registered with PowerDNS + cert on the ALB)"
  type        = string
  default     = "cloud.nimbus.local"
}

variable "trusted_proxies" {
  description = "CIDRs Nextcloud will trust for X-Forwarded-For. Must include the ALB subnet."
  type        = list(string)
}

# ─── PostgreSQL backend (the "RDS" endpoint) ────────────────────────────────
variable "db_host"     { type = string }
variable "db_name"     { type = string  default = "nextcloud" }
variable "db_user"     { type = string  default = "nextcloud" }
variable "db_password" { type = string  sensitive = true }

# ─── MinIO primary storage (the "S3" endpoint) ──────────────────────────────
variable "s3_endpoint" {
  description = "MinIO URL, e.g. http://nimbus-s3.nimbus.local:9000"
  type        = string
}
variable "s3_bucket"     { type = string  default = "nextcloud-primary" }
variable "s3_access_key" { type = string  sensitive = true }
variable "s3_secret_key" { type = string  sensitive = true }
