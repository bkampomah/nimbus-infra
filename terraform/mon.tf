# terraform/mon.tf
#
# nimbus-mon — Prometheus + Grafana + Loki (CloudWatch equivalent).
#
# Scrape targets are all Nimbus VMs running node-exporter on :9100.
# node-exporter is installed on each VM in Phase 6b/6c.
# Add a target here when a new VM is added to the fleet.

module "nimbus_mon" {
  source = "./modules/monitoring"

  name           = "${var.company_name}-mon"
  proxmox_node   = var.proxmox_node
  template_vm_id = var.template_vm_id
  vm_storage     = var.proxmox_vm_storage
  iso_storage    = var.proxmox_iso_storage
  subnet_bridge  = var.subnets.mgmt.bridge

  admin_username = var.admin_username
  admin_password = var.admin_password
  admin_ssh_keys = var.admin_ssh_public_keys

  static_ip = "${var.nimbus_mon_ip}/24"
  gateway   = var.subnets.mgmt.gateway

  mgmt_allow_cidrs = var.mgmt_allow_cidrs
  loki_allow_cidrs = [var.vpc_cidr]
  loki_url         = module.nimbus_mon.loki_url

  scrape_targets = [
    {
      name    = "prometheus"
      targets = ["localhost:9090"]
    },
    {
      name = "node-exporter"
      targets = [
        "${var.nimbus_alb_ip}:9100",     # nimbus-alb
        "${var.nimbus_bastion_ip}:9100", # nimbus-bastion
        "${var.nimbus_cloud_ip}:9100",   # nimbus-cloud-01
        "${var.nimbus_rds_ip}:9100",     # nimbus-rds
        "${var.nimbus_s3_ip}:9100",      # nimbus-s3
        # nimbus-dns IP is embedded in the static_ip var (strip /24)
        "${split("/", var.nimbus_dns_static_ip)[0]}:9100",
        "${var.nimbus_iam_ip}:9100",   # nimbus-iam (Phase 7)
        "${var.nimbus_vault_ip}:9100", # nimbus-vault (Phase 7)
        "localhost:9100",              # nimbus-mon itself
      ]
    },
    {
      name    = "loki"
      targets = ["localhost:3100"]
    },
  ]

  # Phase 7c — Grafana OIDC SSO via Keycloak. ROOT_URL must match the public
  # hostname Grafana is reachable on (the ALB-fronted mon.nimbus.local).
  grafana_root_url   = "https://mon.nimbus.local"
  oidc_issuer_url    = "https://${var.keycloak_domain}/realms/${keycloak_realm.nimbus.realm}"
  oidc_client_id     = keycloak_openid_client.grafana.client_id
  oidc_client_secret = keycloak_openid_client.grafana.client_secret
  nimbus_ca_pem      = tls_self_signed_cert.nimbus_ca.cert_pem
}

output "nimbus_mon_grafana_url" {
  description = "Grafana UI — reachable from mgmt subnet"
  value       = module.nimbus_mon.grafana_url
}

output "nimbus_mon_prometheus_url" {
  description = "Prometheus UI — reachable from mgmt subnet"
  value       = module.nimbus_mon.prometheus_url
}

output "nimbus_mon_loki_url" {
  description = "Loki push endpoint — used by Promtail on each VM"
  value       = module.nimbus_mon.loki_url
}
