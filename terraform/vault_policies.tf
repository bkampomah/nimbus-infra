# terraform/vault_policies.tf
#
# Phase 7d — Vault ACL policies. Four baseline policies cover the actors
# we model in this lab: humans (admin/operator), Terraform, and apps.
#
# Policy attachment happens via auth method roles (vault_auth.tf):
#   admin          → OIDC role vault-admins (Keycloak group vault-admins)
#   operator       → OIDC role vault-operators (Phase 7e)
#   terraform-read → AppRole role terraform
#   nextcloud-db   → AppRole role nextcloud (Phase 7e, used by Nextcloud)

# ── admin: full superuser ───────────────────────────────────────────────────

resource "vault_policy" "admin" {
  name = "admin"

  policy = <<-EOT
    # Full control over every path including system + sudo capability.
    path "*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
  EOT
}

# ── operator: KV read/write, no auth/policy/mount changes ──────────────────

resource "vault_policy" "operator" {
  name = "operator"

  policy = <<-EOT
    # Read + write any application secret under the kv-v2 mount.
    path "${vault_mount.kv.path}/data/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # Browse the secret tree.
    path "${vault_mount.kv.path}/metadata/*" {
      capabilities = ["read", "list", "delete"]
    }

    # Self-token introspection (so `vault token lookup` works for the operator).
    path "auth/token/lookup-self" {
      capabilities = ["read"]
    }
    path "auth/token/renew-self" {
      capabilities = ["update"]
    }
  EOT
}

# ── terraform-read: read-only KV access for Terraform AppRole ──────────────

resource "vault_policy" "terraform_read" {
  name = "terraform-read"

  policy = <<-EOT
    # Phase 7e: Terraform reads cloudflared, powerdns, and nextcloud secrets
    # from this scope at apply time. No write — secrets land via the operator.
    path "${vault_mount.kv.path}/data/nimbus/*" {
      capabilities = ["read"]
    }
    path "${vault_mount.kv.path}/metadata/nimbus/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

# ── nextcloud-db: Nextcloud reads dynamic Postgres creds ───────────────────

resource "vault_policy" "nextcloud_db" {
  name = "nextcloud-db"

  policy = <<-EOT
    # Mint a fresh Postgres user/password from the database engine.
    path "${vault_mount.database.path}/creds/${vault_database_secret_backend_role.nextcloud.name}" {
      capabilities = ["read"]
    }
  EOT
}
