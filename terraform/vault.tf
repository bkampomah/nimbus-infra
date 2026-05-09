# terraform/vault.tf
#
# nimbus-vault — HashiCorp Vault (Secrets Manager + STS equivalent, Phase 7).
#
# Topology:
#   client (operator CLI / app) → DNS vault.nimbus.local → nimbus-vault :8200
#
# Vault is internal-only — no ALB, no Cloudflare Tunnel. Keep blast radius
# small: only Tailscale/mgmt-subnet clients can reach it.
#
# After first apply, Vault is RUNNING but SEALED. Initialize manually:
#   ssh nimbus@nimbus-vault
#   vault operator init -key-shares=5 -key-threshold=3
# Capture the unseal/recovery keys to your operator machine, NOT this repo.
# Runbook: docs/runbooks/vault-unseal.md (Phase 7f).

module "nimbus_vault" {
  source = "./modules/vault"

  name           = "${var.company_name}-vault"
  proxmox_node   = var.proxmox_node
  template_vm_id = var.template_vm_id
  vm_storage     = var.proxmox_vm_storage
  iso_storage    = var.proxmox_iso_storage
  subnet_bridge  = var.subnets.mgmt.bridge

  admin_username = var.admin_username
  admin_password = var.admin_password
  admin_ssh_keys = var.admin_ssh_public_keys

  static_ip = "${var.nimbus_vault_ip}/24"
  gateway   = var.subnets.mgmt.gateway

  cluster_name = var.company_name

  tls_cert_pem = "${tls_locally_signed_cert.nimbus_vault.cert_pem}${tls_self_signed_cert.nimbus_ca.cert_pem}"
  tls_key_pem  = tls_private_key.nimbus_vault.private_key_pem

  # VPC + operator LAN — Phase 7e fix. Operator-from-LAN was blocked at first
  # apply because vault provider needed LAN access for terraform.
  client_allow_cidrs = concat([var.vpc_cidr], ["192.168.0.0/16"])
  mgmt_allow_cidrs   = var.mgmt_allow_cidrs
  loki_url           = module.nimbus_mon.loki_url

  # Phase 7d — Vault's OIDC auth method needs to dial Keycloak's TLS endpoint
  # for JWKS + discovery. CA goes into the system trust store at boot.
  nimbus_ca_pem = tls_self_signed_cert.nimbus_ca.cert_pem
}

# ── Internal DNS ─────────────────────────────────────────────────────────────
# Vault is reached directly (not via ALB) — DNS points straight at the VM.
resource "powerdns_record" "nimbus_vault" {
  for_each = {
    "vault.nimbus.local."        = var.nimbus_vault_ip
    "nimbus-vault.nimbus.local." = var.nimbus_vault_ip
  }

  zone    = "nimbus.local."
  name    = each.key
  type    = "A"
  ttl     = 300
  records = [each.value]
}

# ── Outputs ──────────────────────────────────────────────────────────────────

output "nimbus_vault_host" {
  description = "Static IPv4 of nimbus-vault"
  value       = module.nimbus_vault.host
}

output "nimbus_vault_api_addr" {
  description = "VAULT_ADDR for operator shells (set with: export VAULT_ADDR=...)"
  value       = module.nimbus_vault.api_addr
}
