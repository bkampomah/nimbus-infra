output "vm_name" {
  description = "Bastion VM name"
  value       = proxmox_virtual_environment_vm.bastion.name
}

output "host" {
  description = "IPv4 of the bastion (strip CIDR from static_ip)"
  value       = split("/", var.static_ip)[0]
}

output "ssh_command" {
  description = "SSH command for logging into the bastion"
  value       = "ssh ${var.admin_username}@${split("/", var.static_ip)[0]}"
}

output "pfsense_tunnel_command" {
  description = "Run this on your workstation, then browse to the pfsense_tunnel_url"
  value       = "ssh -N -L ${var.tunnel_local_port}:${var.pfsense_gui_host}:${var.pfsense_gui_port} ${var.admin_username}@${split("/", var.static_ip)[0]}"
}

output "pfsense_tunnel_url" {
  description = "pfSense GUI URL after the SSH tunnel is running"
  value       = "https://localhost:${var.tunnel_local_port}"
}
