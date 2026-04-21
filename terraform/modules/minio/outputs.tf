# terraform/modules/minio/outputs.tf

output "vm_name" {
  value = proxmox_virtual_environment_vm.minio.name
}

output "host" {
  value = try(proxmox_virtual_environment_vm.minio.ipv4_addresses[1][0], "pending-guest-agent")
}

output "endpoint" {
  description = "S3 endpoint URL for Nextcloud and other clients"
  value       = "http://${try(proxmox_virtual_environment_vm.minio.ipv4_addresses[1][0], "pending")}:9000"
}

output "console_url" {
  description = "MinIO admin UI"
  value       = "http://${try(proxmox_virtual_environment_vm.minio.ipv4_addresses[1][0], "pending")}:9001"
}

output "nextcloud_bucket" {
  value = var.nextcloud_bucket
}

output "nextcloud_access_key" {
  value     = var.nextcloud_access_key
  sensitive = true
}

output "nextcloud_secret_key" {
  value     = var.nextcloud_secret_key
  sensitive = true
}
