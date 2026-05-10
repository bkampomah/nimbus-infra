# terraform/cloud.tf
#
# nimbus-cloud-01 - Nextcloud app-tier VM for Phase 5c.
# This runs in parallel with the existing AIO VM until the ALB backend is moved.

module "nimbus_nextcloud" {
  source = "./modules/nextcloud"

  name           = "${var.company_name}-cloud-01"
  proxmox_node   = var.proxmox_node
  template_vm_id = var.template_vm_id
  vm_storage     = var.proxmox_vm_storage
  iso_storage    = var.proxmox_iso_storage
  subnet_bridge  = var.subnets.app.bridge

  admin_username = var.admin_username
  admin_password = var.admin_password
  admin_ssh_keys = var.admin_ssh_public_keys

  cpu  = 4
  ram  = 8192
  disk = 100

  static_ip = "${var.nimbus_cloud_ip}/24"
  gateway   = var.subnets.app.gateway

  # Phase 7e — admin password now reads from Vault. Tfvars stays as bootstrap
  # input (vault_kv_secret_v2.nextcloud_admin writes from var); the consumer
  # reads from Vault. This is the cleanest migration target — only consumed
  # in the install hook, no rotation logic needed downstream.
  nextcloud_admin_pw = data.vault_kv_secret_v2.nextcloud_admin.data["admin_password"]
  nextcloud_domain   = var.nextcloud_domain
  extra_trusted_domains = [
    "cloud-app.nimbus.local",
  ]
  trusted_proxies  = concat(["${var.nimbus_alb_ip}/32"], var.cloudflare_ip_ranges)
  alb_allow_cidrs  = ["${var.nimbus_alb_ip}/32"]
  mgmt_allow_cidrs = var.mgmt_allow_cidrs

  db_host     = module.nimbus_rds.host
  db_name     = module.nimbus_rds.initial_db_name
  db_user     = module.nimbus_rds.initial_db_user
  db_password = random_password.nextcloud_db.result

  s3_endpoint   = module.nimbus_s3.api_endpoint
  s3_bucket     = module.nimbus_s3.default_bucket
  s3_access_key = var.nextcloud_s3_access_key
  s3_secret_key = var.nextcloud_s3_secret_key
  loki_url      = module.nimbus_mon.loki_url

  # Phase 7c — OIDC SSO via Keycloak.
  oidc_issuer_url    = "https://${var.keycloak_domain}/realms/${keycloak_realm.nimbus.realm}"
  oidc_client_id     = keycloak_openid_client.nextcloud.client_id
  oidc_client_secret = keycloak_openid_client.nextcloud.client_secret
  nimbus_ca_pem      = tls_self_signed_cert.nimbus_ca.cert_pem

  # Phase 7e — Vault Agent renders dynamic Postgres creds into Nextcloud's
  # config tree, reloading php-fpm on each rotation. role_id is non-secret;
  # secret_id is materialized into Terraform state once and read by cloud-init.
  # Phase 8 hardening: response-wrap the secret_id at handoff.
  vault_addr              = module.nimbus_vault.api_addr
  vault_approle_role_id   = vault_approle_auth_backend_role.nextcloud.role_id
  vault_approle_secret_id = vault_approle_auth_backend_role_secret_id.nextcloud.secret_id
  vault_db_role_path      = "${vault_mount.database.path}/creds/${vault_database_secret_backend_role.nextcloud.name}"
}

# cloud-app.nimbus.local. is declared in dns.tf via the for_each "infra" map —
# removing this duplicate to avoid the "address already in use" race that hit
# Stage G.2 when both resources tried to create the same record.

output "nimbus_nextcloud_host" {
  description = "App-subnet IP of nimbus-cloud-01"
  value       = module.nimbus_nextcloud.ipv4_address
}

output "nimbus_nextcloud_backend_target" {
  description = "Backend target for the Phase 5c.3 ALB route"
  value       = module.nimbus_nextcloud.backend_target
}
