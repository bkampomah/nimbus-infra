output "vm_id" {
  description = "Proxmox VMID"
  value       = proxmox_virtual_environment_vm.postgres.vm_id
}

output "vm_name" {
  description = "VM hostname"
  value       = proxmox_virtual_environment_vm.postgres.name
}

output "ip_address" {
  description = "Postgres VM IP address"
  value       = var.ip_address
}

output "fqdn" {
  description = "Internal FQDN (resolves via PowerDNS once record is added)"
  value       = "${var.name}.${var.search_domain}"
}

output "postgres_db" {
  description = "Initial database name"
  value       = var.postgres_db
}

output "postgres_user" {
  description = "Initial database user"
  value       = var.postgres_user
}

output "postgres_connection_string" {
  description = "libpq-style connection string (password NOT included)"
  value       = "host=${var.ip_address} port=5432 dbname=${var.postgres_db} user=${var.postgres_user}"
}
