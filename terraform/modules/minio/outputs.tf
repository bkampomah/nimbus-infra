output "vm_id" {
  description = "Proxmox VMID"
  value       = proxmox_virtual_environment_vm.minio.vm_id
}

output "name" {
  description = "VM hostname"
  value       = proxmox_virtual_environment_vm.minio.name
}

output "host" {
  description = "Static IP without CIDR suffix"
  value       = split("/", var.static_ip)[0]
}

output "api_endpoint" {
  description = "S3 API endpoint URL"
  value       = "http://${split("/", var.static_ip)[0]}:9000"
}

output "console_endpoint" {
  description = "Web admin console URL"
  value       = "http://${split("/", var.static_ip)[0]}:9001"
}

output "minio_root_user" {
  description = "MinIO root admin username"
  value       = var.minio_root_user
}

output "default_bucket" {
  description = "Initial bucket name"
  value       = var.minio_bucket
}

output "pgbackup_access_key" {
  description = "Service account key for the pg-backup writer"
  value       = var.pgbackup_access_key
}

# Added in 5b.1 — postgres module reads this to wire the backup push
output "pgbackup_secret_key" {
  description = "Service account secret for the pg-backup writer (sensitive)"
  value       = var.pgbackup_secret_key
  sensitive   = true
}

# Added in 7b — keycloak module reads these for the nightly realm-export push
output "kc_backup_access_key" {
  description = "Service account key for the Keycloak realm-export writer"
  value       = var.kc_backup_access_key
}

output "kc_backup_secret_key" {
  description = "Service account secret for the Keycloak realm-export writer (sensitive)"
  value       = var.kc_backup_secret_key
  sensitive   = true
}
