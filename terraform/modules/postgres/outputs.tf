# terraform/modules/postgres/outputs.tf
output "connection_string" {
  description = "libpq connection string without password"
  value       = "postgresql://${var.initial_db_user}@${try(proxmox_virtual_environment_vm.rds.ipv4_addresses[1][0], "pending-guest-agent")}:5432/${var.initial_db_name}"
}

output "vm_name" {
  value = proxmox_virtual_environment_vm.rds.name
}

output "host" {
  description = "Primary IPv4 — use as db_host for clients"
  value       = try(proxmox_virtual_environment_vm.rds.ipv4_addresses[1][0], "pending-guest-agent")
}

output "port" {
  value = 5432
}

output "initial_db_name" { value = var.initial_db_name }
output "initial_db_user" { value = var.initial_db_user }
