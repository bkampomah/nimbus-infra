# terraform/modules/nextcloud/outputs.tf

output "vm_name" {
  value = proxmox_virtual_environment_vm.nextcloud.name
}

output "ipv4_address" {
  description = "Primary IPv4 once qemu-guest-agent reports in"
  value       = try(proxmox_virtual_environment_vm.nextcloud.ipv4_addresses[1][0], "pending-guest-agent")
}

output "backend_target" {
  description = "host:port for HAProxy/Traefik to point at"
  value       = "${try(proxmox_virtual_environment_vm.nextcloud.ipv4_addresses[1][0], "pending-guest-agent")}:80"
}
