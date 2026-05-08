# terraform/vault_auth.tf
#
# Phase 7d — Vault auth methods.
#
# Three methods enabled:
#   - token   (built-in, always on; root + child tokens)
#   - oidc    (Keycloak as IdP; humans log in via SSO)
#   - approle (machines: Terraform + per-app secret consumers)

# ── OIDC auth backend bound to Keycloak ────────────────────────────────────
# UI: visiting https://vault.nimbus.local:8200/ui shows a "Sign in with OIDC"
# button. CLI: `vault login -method=oidc role=vault-admins` opens a browser
# to the loopback redirect (localhost:8250).

resource "vault_jwt_auth_backend" "oidc" {
  type               = "oidc"
  path               = "oidc"
  description        = "Keycloak SSO for human operators"
  oidc_discovery_url = "https://${var.keycloak_domain}/realms/${keycloak_realm.nimbus.realm}"
  oidc_client_id     = keycloak_openid_client.vault.client_id
  oidc_client_secret = keycloak_openid_client.vault.client_secret
  default_role       = "vault-admins"
}

# Role: vault-admins — Keycloak group `vault-admins` → Vault `admin` policy.
# bound_claims uses the groups claim from the keycloak_openid_group_membership
# protocol mapper (added in Phase 7c-style mapper for the vault client below).
resource "vault_jwt_auth_backend_role" "vault_admins" {
  backend   = vault_jwt_auth_backend.oidc.path
  role_name = "vault-admins"
  role_type = "oidc"

  bound_audiences = [keycloak_openid_client.vault.client_id]
  user_claim      = "preferred_username"
  groups_claim    = "groups"

  bound_claims_type = "string"
  bound_claims = {
    groups = "vault-admins"
  }

  token_policies = [vault_policy.admin.name]
  token_ttl      = 3600  # 1h
  token_max_ttl  = 28800 # 8h

  allowed_redirect_uris = [
    "https://vault.nimbus.local:8200/ui/vault/auth/oidc/oidc/callback",
    "https://vault.nimbus.local:8200/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]
}

# ── AppRole auth backend ────────────────────────────────────────────────────
# Each non-human consumer (Terraform, Nextcloud-via-VSO, etc.) gets a role
# here. role_id is non-secret (commit-safe); secret_id is rotated.

resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "Service authentication (Terraform, apps)"
}

# Role: terraform — Terraform reads KV secrets at apply time. Long-ish TTLs
# so the operator doesn't spin secret_ids during a plan/apply cycle.
resource "vault_approle_auth_backend_role" "terraform" {
  backend        = vault_auth_backend.approle.path
  role_name      = "terraform"
  token_policies = [vault_policy.terraform_read.name]
  token_ttl      = 1800
  token_max_ttl  = 3600

  # Phase 8: lock secret_id_bound_cidrs to the operator's machine + CI runners.
}

# Role: nextcloud — consumed by Vault Agent on nimbus-cloud-01 to mint dynamic
# Postgres credentials. Phase 7e marquee. Non-expiring secret_ids (lab grade)
# so reboots don't break the agent; Phase 8 rotates via secret_id_ttl + a
# rotation runbook.
resource "vault_approle_auth_backend_role" "nextcloud" {
  backend        = vault_auth_backend.approle.path
  role_name      = "nextcloud"
  token_policies = [vault_policy.nextcloud_db.name]
  token_ttl      = 3600
  token_max_ttl  = 86400

  secret_id_ttl      = 0
  secret_id_num_uses = 0
}

# A secret_id materialized into Terraform state. Cloud-init on nimbus-cloud-01
# writes this onto disk for Vault Agent to read. State holds the secret in
# clear — same blast-radius posture as random_password resources elsewhere.
resource "vault_approle_auth_backend_role_secret_id" "nextcloud" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.nextcloud.role_name
}

# ── Outputs ──────────────────────────────────────────────────────────────────

output "vault_oidc_login_url" {
  description = "Browser-friendly Vault OIDC login URL"
  value       = "https://vault.nimbus.local:8200/ui/vault/auth/${vault_jwt_auth_backend.oidc.path}"
}

output "vault_terraform_role_id" {
  description = "AppRole role_id for Terraform — pair with a freshly minted secret_id from `vault write -f auth/approle/role/terraform/secret-id`"
  value       = vault_approle_auth_backend_role.terraform.role_id
  sensitive   = true
}

output "vault_nextcloud_role_id" {
  description = "AppRole role_id used by Vault Agent on nimbus-cloud-01"
  value       = vault_approle_auth_backend_role.nextcloud.role_id
  sensitive   = true
}
