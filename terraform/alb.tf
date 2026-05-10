# terraform/alb.tf
#
# nimbus-alb - HAProxy-based Application Load Balancer for Nimbus.
# Lives in the public subnet; fronts services running in the app subnet.
#
# Phase 4b: initial ALB + AIO backend.
# Phase 5c/5d: nimbus-cloud-01 is now the primary public Nextcloud.
#   cloud.nimbusnode.org (Cloudflare Tunnel CNAME) → nextcloud-cloud backend.
#   AIO kept reachable on cloud.nimbus.local for internal use.

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

  backends = [
    {
      name        = "nextcloud-aio"
      host_match  = "cloud.nimbus.local aio.nimbusnode.org"
      server_ip   = var.nimbus_aio_ip
      server_port = 11000
      check       = true
    },
    {
      name        = "nextcloud-cloud"
      host_match  = "cloud-app.nimbus.local ${var.nextcloud_domain}" # cloud.nimbusnode.org + cloud-app.nimbus.local
      server_ip   = var.nimbus_cloud_ip
      server_port = 80
      check       = true
    },
    {
      name        = "grafana"
      host_match  = "mon.nimbus.local"
      server_ip   = var.nimbus_mon_ip
      server_port = 3000
      check       = true
    },
    # Phase 7 — Keycloak. TLS upstream (HAProxy re-encrypts to :8443 with
    # `ssl verify none`). Both internal and Cloudflare-Tunnel hostnames route
    # here; Keycloak's KC_HOSTNAME pins the public URL for OIDC discovery.
    {
      name        = "keycloak"
      host_match  = "auth.nimbus.local ${var.keycloak_domain}"
      server_ip   = var.nimbus_iam_ip
      server_port = 8443
      check       = true
      tls         = true
    },
  ]

  alb_allow_cidrs         = distinct(concat([var.vpc_cidr, "172.18.0.0/12"], var.mgmt_allow_cidrs))
  mgmt_allow_cidrs        = var.mgmt_allow_cidrs
  cloudflare_tunnel_token = var.cloudflare_tunnel_token
  loki_url                = module.nimbus_mon.loki_url

  # Combined PEM bundle (server cert + CA chain + private key) for the internal
  # HTTPS frontend. HAProxy binds :443 on the ALB's VPC IP and uses this cert.
  # Clients trust the CA by importing the nimbus_ca_cert Terraform output.
  tls_pem = "${tls_locally_signed_cert.nimbus_alb.cert_pem}${tls_self_signed_cert.nimbus_ca.cert_pem}${tls_private_key.nimbus_alb.private_key_pem}"
}

output "nimbus_alb_host" {
  description = "Public-subnet IP of the ALB (matches var.nimbus_alb_ip)"
  value       = module.nimbus_alb.host
}

output "nimbus_alb_stats_url" {
  description = "HAProxy stats page - reachable from mgmt subnet"
  value       = module.nimbus_alb.stats_url
}

output "nimbus_alb_tls_pem" {
  description = "Combined ALB PEM bundle for /etc/haproxy/nimbus-alb.pem"
  value       = "${tls_locally_signed_cert.nimbus_alb.cert_pem}${tls_self_signed_cert.nimbus_ca.cert_pem}${tls_private_key.nimbus_alb.private_key_pem}"
  sensitive   = true
}
