# terraform/modules/postgres/variables.tf

variable "name"           { type = string }
variable "proxmox_node"   { type = string }
variable "template_vm_id" { type = number }
variable "vm_storage"     { type = string }
variable "iso_storage"    { type = string }
variable "subnet_bridge"  { type = string }

variable "cpu"  { type = number  default = 2 }
variable "ram"  { type = number  default = 4096 }
variable "disk" { type = number  default = 50 }

variable "admin_username" { type = string }
variable "admin_password" { type = string sensitive = true }
variable "admin_ssh_keys" { type = list(string) }

# Initial DB/role provisioned on first boot (for Nextcloud).
variable "initial_db_name"     { type = string  default = "nextcloud" }
variable "initial_db_user"     { type = string  default = "nextcloud" }
variable "initial_db_password" { type = string  sensitive = true }

# Who is allowed to connect (written into pg_hba.conf).
# Default: the whole app subnet. Tighten in prod.
variable "allowed_cidr" {
  description = "CIDR allowed to connect to Postgres over the network"
  type        = string
  default     = "10.0.10.0/24" # CHANGE_ME if your app subnet differs
}
