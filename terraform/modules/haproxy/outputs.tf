# terraform/modules/haproxy/outputs.tf

output "vm_name" {
  value = proxmox_virtual_environment_vm.alb.name
}

output "host" {
  description = "Public-subnet IPv4 of the ALB"
  value       = split("/", var.static_ip)[0]
}

output "stats_url" {
  description = "HAProxy stats page (mgmt subnet only)"
  value       = "http://${split("/", var.static_ip)[0]}:8404/"
}
