# terraform/alb.tf
#
# nimbus-alb - HAProxy-based Application Load Balancer for Nimbus.
# Lives in the public subnet; fronts services running in the app subnet
# (starting with the existing Nextcloud AIO at 10.0.10.101:11000).
#
# Phase 4b deliverable.

module "nimbus_alb" {
  source = "./modules/haproxy"

  name           = "${var.company_name}-alb"
  proxmox_node   = var.proxmox_node
  template_vm_id = var.template_vm_id
  vm_storage     = var.proxmox_vm_storage
  iso_storage    = var.proxmox_iso_storage
  subnet_bridge  = var.subnets.public.bridge

  admin_username = var.admin_username
  admin_password = var.admin_password
  admin_ssh_keys = var.admin_ssh_public_keys

  static_ip = "${var.nimbus_alb_ip}/24"
  gateway   = var.subnets.public.gateway

  # Host-based routing: one backend for now. Add more entries here as
  # new app-tier services come online (e.g. nimbus-web-01/02 in Phase 6).
  backends = [
    {
      name        = "nextcloud-aio"
      host_match  = "cloud.nimbus.local"
      server_ip   = var.nimbus_aio_ip
      server_port = 11000
      check       = true
    }
  ]

  alb_allow_cidrs  = [var.vpc_cidr]
  mgmt_allow_cidrs = var.mgmt_allow_cidrs
}

output "nimbus_alb_host" {
  description = "Public-subnet IP of the ALB (matches var.nimbus_alb_ip)"
  value       = module.nimbus_alb.host
}

output "nimbus_alb_stats_url" {
  description = "HAProxy stats page - reachable from mgmt subnet"
  value       = module.nimbus_alb.stats_url
}
