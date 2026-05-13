# -----------------------------------------------------------------------------
# Identity & placement
# -----------------------------------------------------------------------------
variable "name" {
  description = "VM hostname / display name (e.g. nimbus-s3)"
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

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "subnet_bridge" {
  description = "Proxmox SDN VNet / bridge name (e.g. nimbus-data)"
  type        = string
}

variable "static_ip" {
  description = "Static IPv4 with CIDR suffix (e.g. 10.0.20.101/24)"
  type        = string
}

variable "gateway" {
  description = "Default gateway (pfSense interface IP on this subnet)"
  type        = string
}

# -----------------------------------------------------------------------------
# Sizing
# -----------------------------------------------------------------------------
variable "cpu_cores" {
  description = "vCPU count"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM in MB"
  type        = number
  default     = 4096
}

variable "root_disk_size_gb" {
  description = "Root disk size in GB — must be >= 22 (template size)"
  type        = number
  default     = 32

  validation {
    condition     = var.root_disk_size_gb >= 22
    error_message = "root_disk_size_gb must be at least 22 GB."
  }
}

variable "data_disk_size_gb" {
  description = "Object-storage data disk size in GB"
  type        = number
  default     = 200
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

# -----------------------------------------------------------------------------
# MinIO credentials & buckets
# -----------------------------------------------------------------------------
variable "minio_root_user" {
  description = "MinIO root admin username (the AWS root account equivalent)"
  type        = string
  default     = "nimbusadmin"
}

variable "minio_root_password" {
  description = "MinIO root admin password (supply via random_password)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.minio_root_password) >= 8
    error_message = "MinIO requires root password to be at least 8 characters."
  }
}

variable "minio_bucket" {
  description = "Initial bucket created on bootstrap"
  type        = string
  default     = "nextcloud-data"
}

variable "pgbackup_access_key" {
  description = "Service account access key for the pg-backup writer (limited to pg-backups bucket)"
  type        = string
  default     = "pgbackup"
}

variable "pgbackup_secret_key" {
  description = "Service account secret key for pg-backup (supply via random_password)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.pgbackup_secret_key) >= 8
    error_message = "MinIO secret key must be at least 8 characters."
  }
}

variable "nextcloud_access_key" {
  description = "Service account access key for Nextcloud primary object storage"
  type        = string

  validation {
    condition     = length(var.nextcloud_access_key) > 0
    error_message = "nextcloud_access_key must not be empty."
  }
}

variable "nextcloud_secret_key" {
  description = "Service account secret key for Nextcloud primary object storage"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.nextcloud_secret_key) >= 8
    error_message = "MinIO secret key must be at least 8 characters."
  }
}

# Phase 7b — kc-backups bucket for nightly Keycloak realm exports.
variable "kc_backup_access_key" {
  description = "Service account access key for the Keycloak realm-export writer (limited to kc-backups bucket)"
  type        = string
  default     = "kc-backup"
}

variable "kc_backup_secret_key" {
  description = "Service account secret key for kc-backup (supply via random_password)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.kc_backup_secret_key) >= 8
    error_message = "MinIO secret key must be at least 8 characters."
  }
}

# -----------------------------------------------------------------------------
# Access controls (UFW)
# -----------------------------------------------------------------------------
variable "api_allow_cidrs" {
  description = "CIDRs allowed to reach the S3 API on port 9000"
  type        = list(string)
}

variable "console_allow_cidrs" {
  description = "CIDRs allowed to reach the web console on port 9001"
  type        = list(string)
}

variable "mgmt_allow_cidrs" {
  description = "CIDRs allowed SSH access (port 22)"
  type        = list(string)
}

variable "loki_url" {
  description = "Promtail push endpoint on nimbus-mon (e.g. http://10.0.100.20:3100). Empty string disables Promtail."
  type        = string
  default     = "http://10.0.100.20:3100"
}

# ── Phase 7c — MinIO console OIDC SSO via Keycloak ─────────────────────────
# Empty oidc_issuer_url disables OIDC env vars.

variable "oidc_issuer_url" {
  description = "OIDC issuer URL (e.g. https://auth.nimbusnode.org/realms/nimbus). Empty disables OIDC."
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OAuth client_id registered in Keycloak for MinIO console"
  type        = string
  default     = ""
}

variable "oidc_client_secret" {
  description = "OAuth client_secret for the MinIO console client"
  type        = string
  sensitive   = true
  default     = ""
}

variable "oidc_policy_claim_name" {
  description = "JWT claim MinIO reads for OIDC policy names. Keycloak's groups claim maps group names to MinIO policies."
  type        = string
  default     = "groups"
}

variable "pgbackup_retention_mode" {
  description = "Default object-lock retention mode for the pg-backups bucket. Use COMPLIANCE to prevent privileged deletes during the window."
  type        = string
  default     = "COMPLIANCE"

  validation {
    condition     = contains(["COMPLIANCE", "GOVERNANCE"], upper(var.pgbackup_retention_mode))
    error_message = "pgbackup_retention_mode must be COMPLIANCE or GOVERNANCE."
  }
}

variable "pgbackup_retention_duration" {
  description = "Default object-lock retention duration for new pg-backups objects, formatted for mc retention set (for example, 30d or 1y)."
  type        = string
  default     = "30d"

  validation {
    condition     = can(regex("^[1-9][0-9]*[dy]$", var.pgbackup_retention_duration))
    error_message = "pgbackup_retention_duration must be a positive day/year duration such as 30d or 1y."
  }
}

variable "nimbus_ca_pem" {
  description = "Internal CA cert PEM. Installed into the system trust store so MinIO validates Keycloak's TLS. Empty skips."
  type        = string
  default     = ""
}
