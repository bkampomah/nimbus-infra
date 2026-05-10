# terraform/iam.tf
#
# nimbus-iam — Keycloak (OIDC identity provider, Phase 7).
#
# Topology:
#   external client → Cloudflare Tunnel → cloudflared@nimbus-alb → ALB :80
#     → HAProxy host-header routes "auth.nimbusnode.org" → nimbus-iam :8443 (HTTPS, verify none)
#   internal client → DNS auth.nimbus.local → ALB :443 (internal CA cert)
#     → HAProxy host-header routes "auth.nimbus.local" → nimbus-iam :8443 (HTTPS, verify none)
#
# DB lives on nimbus-rds (provisioned via the postgres module's additional_databases input).
# Cloudflare Tunnel hostname (auth.nimbusnode.org) is added in the Cloudflare Zero Trust
# dashboard pointing at http://nimbus-alb:80 — same pattern as Nextcloud.

# Bootstrap admin password — used only for the very first start, then rotate.
# Phase 7e migrates this to Vault KV; for now retrieve via terraform output.
resource "random_password" "keycloak_admin" {
  length           = 24
  special          = true
  override_special = "!#%&*+-=?@^_"
}

module "nimbus_iam" {
  source = "./modules/keycloak"

  name           = "${var.company_name}-iam"
  proxmox_node   = var.proxmox_node
  template_vm_id = var.template_vm_id
  vm_storage     = var.proxmox_vm_storage
  iso_storage    = var.proxmox_iso_storage
  subnet_bridge  = var.subnets.mgmt.bridge

  admin_username = var.admin_username
  admin_password = var.admin_password
  admin_ssh_keys = var.admin_ssh_public_keys

  static_ip = "${var.nimbus_iam_ip}/24"
  gateway   = var.subnets.mgmt.gateway

  keycloak_hostname       = var.keycloak_domain
  keycloak_admin_password = random_password.keycloak_admin.result

  # DB on nimbus-rds — provisioned by postgres module additional_databases.
  # Use the IP directly (not nimbus-rds.nimbus.local) so we don't depend on
  # PowerDNS being reachable during Keycloak first boot.
  db_host     = var.nimbus_rds_ip
  db_password = random_password.keycloak_db.result

  # TLS issued by the internal CA (see certs.tf). Concatenate server cert + CA
  # so clients walking the chain land on a known root.
  tls_cert_pem = "${tls_locally_signed_cert.nimbus_iam.cert_pem}${tls_self_signed_cert.nimbus_ca.cert_pem}"
  tls_key_pem  = tls_private_key.nimbus_iam.private_key_pem

  alb_cidr         = var.subnets.public.cidr
  mgmt_allow_cidrs = var.mgmt_allow_cidrs
  loki_url         = module.nimbus_mon.loki_url

  # Phase 7b — nightly realm export to MinIO (kc-backups bucket).
  backup_s3_endpoint   = module.nimbus_s3.api_endpoint
  backup_s3_access_key = module.nimbus_s3.kc_backup_access_key
  backup_s3_secret_key = module.nimbus_s3.kc_backup_secret_key
  backup_s3_bucket     = "kc-backups"
}

# ── Internal DNS ─────────────────────────────────────────────────────────────
# auth.nimbus.local resolves to the ALB (which routes by Host header to
# nimbus-iam over HTTPS). nimbus-iam.nimbus.local is the direct-admin name
# pointing at the VM IP for emergency access from mgmt.
resource "powerdns_record" "nimbus_iam_alb" {
  zone    = "nimbus.local."
  name    = "auth.nimbus.local."
  type    = "A"
  ttl     = 300
  records = [var.nimbus_alb_ip]
}

resource "powerdns_record" "nimbus_iam_direct" {
  zone    = "nimbus.local."
  name    = "nimbus-iam.nimbus.local."
  type    = "A"
  ttl     = 300
  records = [var.nimbus_iam_ip]
}

# Split-horizon: same public hostname resolves to ALB internally; externally
# Cloudflare's CNAME points at the Tunnel.
resource "powerdns_record" "nimbus_iam_public_internal" {
  zone    = "nimbusnode.org."
  name    = "${var.keycloak_domain}."
  type    = "A"
  ttl     = 60
  records = [var.nimbus_alb_ip]
}

# ── Outputs ──────────────────────────────────────────────────────────────────

output "nimbus_iam_host" {
  description = "Static IPv4 of nimbus-iam"
  value       = module.nimbus_iam.host
}

output "nimbus_iam_admin_url" {
  description = "Public Keycloak admin console URL — log in once, rotate the bootstrap password"
  value       = "https://${var.keycloak_domain}/admin/"
}

output "keycloak_admin_password" {
  description = "Bootstrap Keycloak admin password — rotate immediately"
  value       = random_password.keycloak_admin.result
  sensitive   = true
}
