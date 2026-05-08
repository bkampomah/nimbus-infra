# terraform/modules/keycloak/outputs.tf

output "host" {
  description = "Static IPv4 of nimbus-iam (matches var.static_ip)"
  value       = split("/", var.static_ip)[0]
}

output "vm_name" {
  value = proxmox_virtual_environment_vm.iam.name
}

output "https_url" {
  description = "Direct HTTPS endpoint (mgmt-only access; public traffic goes via ALB)"
  value       = "https://${split("/", var.static_ip)[0]}:8443"
}
