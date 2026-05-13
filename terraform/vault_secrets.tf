# terraform/vault_secrets.tf
#
# Phase 7d — Vault provider config + secrets engines + audit device.
#
# Provider auth: token from VAULT_TOKEN env var. Operator runs:
#   export VAULT_TOKEN=<root-token-from-vault-operator-init>
#   export VAULT_ADDR=https://10.0.100.40:8200
#   terraform apply
#
# Vault MUST be initialized + unsealed before any vault_* resource can plan.
# See docs/runbooks/vault-init.md for the bootstrap procedure.

provider "vault" {
  address = module.nimbus_vault.api_addr

  # The Nimbus internal CA isn't in the operator's system trust store by
  # default. Read it through ca_cert_file = nimbus-ca.crt in the repo root,
  # or skip TLS verify in the lab. Operators set VAULT_CACERT instead for
  # CLI use. For Terraform: skip is fine since we control both ends.
  skip_tls_verify = true

  # Don't create a child token before each call — the parent token (root, or
  # an OIDC-minted admin token) goes straight through. Avoids brittle child-
  # token creation if the parent is sealed/unstable.
  skip_child_token = true

  # Don't probe Vault's version endpoint on every operation; not all paths
  # are reachable when sealed. Pin once and move on.
  skip_get_vault_version = true
}

# ── Audit device ────────────────────────────────────────────────────────────
# Promtail's vault-audit scrape (modules/vault user-data) tails this file.
# Without this, audit log entries are dropped — Vault's default is no audit.

resource "vault_audit" "file" {
  type = "file"
  path = "file"
  options = {
    file_path     = "/var/log/vault/audit.log"
    log_raw       = "false"
    hmac_accessor = "true"
  }
}

# ── KV v2 mount ─────────────────────────────────────────────────────────────
# Application secrets land under secret/nimbus/<app>. Phase 7e migrates
# cloudflared / powerdns / nextcloud-admin creds out of tfvars into here.

resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv-v2"
  description = "Application secrets (Phase 7d-onward)"
}

# ── Database secrets engine ────────────────────────────────────────────────
# Vault mints short-lived Postgres roles on-demand for apps that ask for
# database/creds/<role>. The marquee Phase 7e demo: nextcloud rotates.

resource "vault_mount" "database" {
  path        = "database"
  type        = "database"
  description = "Dynamic Postgres credentials for nimbus-rds"
}

# Connection — Vault dials nimbus-rds as the SUPERUSER `vault` role created
# by the postgres module's cloud-init. allowed_roles=* would let any role
# template use this connection; we restrict to the explicit list.
resource "vault_database_secret_backend_connection" "nimbus_rds" {
  backend       = vault_mount.database.path
  name          = "nimbus-rds"
  allowed_roles = ["nextcloud"]

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@${var.nimbus_rds_ip}:5432/postgres?sslmode=disable"
    username       = "vault"
    password       = random_password.vault_db_admin.result
  }
}

# Role: nextcloud — Vault mints a short-lived role with full privileges on
# the nextcloud DB. App requests `vault read database/creds/nextcloud` and
# gets a fresh username/password back.
resource "vault_database_secret_backend_role" "nextcloud" {
  backend     = vault_mount.database.path
  name        = "nextcloud"
  db_name     = vault_database_secret_backend_connection.nimbus_rds.name
  default_ttl = 3600  # 1h
  max_ttl     = 86400 # 24h

  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'",
    "GRANT ALL PRIVILEGES ON DATABASE nextcloud TO \"{{name}}\"",
    "GRANT ALL ON SCHEMA public TO \"{{name}}\"",
    "GRANT \"nextcloud\" TO \"{{name}}\"",
  ]

  revocation_statements = [
    "REVOKE \"nextcloud\" FROM \"{{name}}\"",
    "REASSIGN OWNED BY \"{{name}}\" TO postgres",
    "DROP OWNED BY \"{{name}}\"",
    "REVOKE ALL PRIVILEGES ON DATABASE nextcloud FROM \"{{name}}\"",
    "DROP ROLE \"{{name}}\"",
  ]
}
