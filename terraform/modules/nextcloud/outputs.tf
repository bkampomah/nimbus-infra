# terraform/modules/nextcloud/outputs.tf

output "vm_name" {
  value = proxmox_virtual_environment_vm.nextcloud.name
}

output "ipv4_address" {
  description = "Static app-subnet IPv4"
  value       = split("/", var.static_ip)[0]
}

output "backend_target" {
  description = "host:port for HAProxy/Traefik to point at"
  value       = "${split("/", var.static_ip)[0]}:80"
}
