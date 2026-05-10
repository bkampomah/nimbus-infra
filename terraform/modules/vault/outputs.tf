# terraform/modules/vault/outputs.tf

output "host" {
  description = "Static IPv4 of nimbus-vault (matches var.static_ip)"
  value       = split("/", var.static_ip)[0]
}

output "vm_name" {
  value = proxmox_virtual_environment_vm.vault.name
}

output "api_addr" {
  description = "Vault API endpoint — set VAULT_ADDR to this on operator machines"
  value       = "https://${split("/", var.static_ip)[0]}:8200"
}
