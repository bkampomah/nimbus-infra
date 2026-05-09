# terraform/keycloak_users.tf
#
# Phase 7b — seed users.
#
# Two users land in the realm so SSO smoke tests in 7c have something to
# log in with. Real per-app onboarding (groups, role mappings) is 7c
# territory — keep this skeletal.
#
# Initial passwords are temporary=true so first login forces a rotation.

resource "random_password" "nimbus_admin_seed" {
  length           = 20
  special          = true
  override_special = "!#%&*+-=?@^_"
  # Realm password policy requires at least 1 of each class.
  min_special = 1
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
}

resource "random_password" "nimbus_test_seed" {
  length           = 20
  special          = true
  override_special = "!#%&*+-=?@^_"
  min_special      = 1
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
}

# ── nimbus-admin (realm admin) ──────────────────────────────────────────────

resource "keycloak_user" "nimbus_admin" {
  realm_id   = keycloak_realm.nimbus.id
  username   = "nimbus-admin"
  enabled    = true
  email      = "nimbus-admin@nimbus.local"
  first_name = "Nimbus"
  last_name  = "Admin"

  # Skip email verification — no SMTP wired in homelab.
  email_verified = true

  initial_password {
    value     = random_password.nimbus_admin_seed.result
    temporary = true
  }
}

# ── nimbus-test (regular user, used for SSO smoke tests in 7c) ──────────────

resource "keycloak_user" "nimbus_test" {
  realm_id   = keycloak_realm.nimbus.id
  username   = "nimbus-test"
  enabled    = true
  email      = "nimbus-test@nimbus.local"
  first_name = "Nimbus"
  last_name  = "Test"

  email_verified = true

  initial_password {
    value     = random_password.nimbus_test_seed.result
    temporary = true
  }
}

# ── Realm-admin role assignment for nimbus-admin ────────────────────────────
# realm-management is Keycloak's built-in client; its `realm-admin` composite
# role grants full control of the nimbus realm without touching master.

data "keycloak_openid_client" "realm_management" {
  realm_id  = keycloak_realm.nimbus.id
  client_id = "realm-management"
}

data "keycloak_role" "realm_admin" {
  realm_id  = keycloak_realm.nimbus.id
  client_id = data.keycloak_openid_client.realm_management.id
  name      = "realm-admin"
}

resource "keycloak_user_roles" "nimbus_admin_realm_admin" {
  realm_id = keycloak_realm.nimbus.id
  user_id  = keycloak_user.nimbus_admin.id
  role_ids = [data.keycloak_role.realm_admin.id]
}

# ── Phase 7c — App-role groups ──────────────────────────────────────────────
# Grafana's OIDC role_attribute_path reads the `groups` claim. Membership in
# grafana-admins → Admin; grafana-editors → Editor; otherwise Viewer.

resource "keycloak_group" "grafana_admins" {
  realm_id = keycloak_realm.nimbus.id
  name     = "grafana-admins"
}

resource "keycloak_group" "grafana_editors" {
  realm_id = keycloak_realm.nimbus.id
  name     = "grafana-editors"
}

# Phase 7d — Vault OIDC role gates on this group → admin policy.
resource "keycloak_group" "vault_admins" {
  realm_id = keycloak_realm.nimbus.id
  name     = "vault-admins"
}

# Put the seed admin in app-admin groups so smoke tests work without manual
# UI clicks. 7c: grafana-admins → Grafana Admin. 7d: vault-admins → Vault admin policy.
resource "keycloak_user_groups" "nimbus_admin_groups" {
  realm_id = keycloak_realm.nimbus.id
  user_id  = keycloak_user.nimbus_admin.id
  group_ids = [
    keycloak_group.grafana_admins.id,
    keycloak_group.vault_admins.id,
  ]
}

# ── Outputs ──────────────────────────────────────────────────────────────────

output "keycloak_seed_admin_username" {
  description = "Seed realm-admin username — log in once, change the temporary password"
  value       = keycloak_user.nimbus_admin.username
}

output "keycloak_seed_admin_password" {
  description = "Seed realm-admin password (temporary=true, rotate on first login)"
  value       = random_password.nimbus_admin_seed.result
  sensitive   = true
}

output "keycloak_seed_test_username" {
  description = "Seed regular-user username for 7c SSO smoke tests"
  value       = keycloak_user.nimbus_test.username
}

output "keycloak_seed_test_password" {
  description = "Seed regular-user password (temporary=true, rotate on first login)"
  value       = random_password.nimbus_test_seed.result
  sensitive   = true
}
