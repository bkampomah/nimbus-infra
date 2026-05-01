# terraform/bastion.tf
#
# nimbus-bastion - SSH workstation/jumpbox on the public/DMZ subnet.
# Use it to test semi-external access paths and reach the pfSense
# WebConfigurator through SSH local forwarding.

locals {
  bastion_name = "${var.company_name}-bastion"
  bastion_vm   = local.instances[local.bastion_name]
}

module "nimbus_bastion" {
  source = "./modules/bastion"

  name           = local.bastion_name
  vm_id          = var.nimbus_bastion_vm_id
  proxmox_node   = var.proxmox_node
  template_vm_id = var.template_vm_id
  vm_storage     = var.proxmox_vm_storage
  iso_storage    = var.proxmox_iso_storage
  subnet_bridge  = var.subnets[local.bastion_vm.subnet].bridge

  admin_username = var.admin_username
  admin_password = var.admin_password
  admin_ssh_keys = var.admin_ssh_public_keys

  static_ip = "${var.nimbus_bastion_ip}/24"
  gateway   = var.subnets[local.bastion_vm.subnet].gateway

  cpu  = local.bastion_vm.cpu
  ram  = local.bastion_vm.ram
  disk = local.bastion_vm.disk
  tags = local.bastion_vm.tags

  ssh_allow_cidrs   = var.bastion_ssh_allow_cidrs
  pfsense_gui_host  = var.pfsense_gui_host
  pfsense_gui_port  = var.pfsense_gui_port
  tunnel_local_port = var.pfsense_tunnel_local_port
  loki_url          = module.nimbus_mon.loki_url
}

resource "powerdns_record" "nimbus_bastion" {
  zone    = "nimbus.local."
  name    = "${local.bastion_name}.nimbus.local."
  type    = "A"
  ttl     = 300
  records = [var.nimbus_bastion_ip]
}

output "nimbus_bastion_host" {
  description = "Public/DMZ-subnet IP of the bastion workstation"
  value       = module.nimbus_bastion.host
}

output "nimbus_bastion_ssh_command" {
  description = "SSH command for logging into the bastion"
  value       = module.nimbus_bastion.ssh_command
}

output "pfsense_gui_tunnel_command" {
  description = "Run on your workstation, then browse to pfsense_gui_tunnel_url"
  value       = module.nimbus_bastion.pfsense_tunnel_command
}

output "pfsense_gui_tunnel_url" {
  description = "pfSense GUI URL after the SSH tunnel is running"
  value       = module.nimbus_bastion.pfsense_tunnel_url
}
