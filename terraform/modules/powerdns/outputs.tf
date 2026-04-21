# terraform/modules/powerdns/outputs.tf

output "vm_name" {
  value = proxmox_virtual_environment_vm.dns.name
}

output "host" {
  description = "IPv4 of nimbus-dns (strip CIDR from static_ip)"
  value       = split("/", var.static_ip)[0]
}

output "api_endpoint" {
  description = "URL for the PowerDNS HTTP API — use this in the pdns provider"
  value       = "http://${split("/", var.static_ip)[0]}:8081"
}

output "api_key" {
  description = "Auto-generated PowerDNS API key — feed to the pdns provider"
  value       = random_password.api_key.result
  sensitive   = true
}

output "internal_zones" {
  value = var.internal_zones
}
