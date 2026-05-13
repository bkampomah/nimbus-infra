# terraform/keycloak.tf
#
# Phase 7b — realm-as-code via the keycloak/keycloak provider.
#
# Provider auth: master-realm admin user/password (the bootstrap admin
# created by KEYCLOAK_ADMIN env in modules/keycloak). Future hardening:
# replace this with a dedicated service account using client_credentials.
#
# Bootstrap chicken-and-egg:
#   On a fresh tree, nimbus-iam must be running before this provider can
#   authenticate. Order:
#     1. terraform apply -target=module.nimbus_rds
#     2. terraform apply -target=module.nimbus_dns
#     3. capture powerdns_api_key into terraform.tfvars
#     4. terraform apply -target=module.nimbus_iam
#     5. terraform apply after Vault is initialized/unsealed
#
# We hit Keycloak directly on the IP (not the CF-tunneled hostname) so realm
# config can land before Cloudflare Tunnel ingress is configured. The cert
# in certs.tf has var.nimbus_iam_ip in its IP SANs, so verification works
# once you trust the Nimbus internal CA — but we set
# tls_insecure_skip_verify=true here to keep this independent of trust-store
# state on the operator's machine. Provider connects from the Terraform host,
# not from anything user-facing, so this is acceptable.

provider "keycloak" {
  client_id                = "admin-cli"
  username                 = "admin"
  password                 = random_password.keycloak_admin.result
  url                      = "https://${var.nimbus_iam_ip}:8443"
  realm                    = "master"
  tls_insecure_skip_verify = true

  # Defer the auth probe until the first resource is touched. Without this,
  # `terraform plan` against a tree where nimbus-iam isn't yet up errors out
  # at provider init.
  initial_login = false
}

# ── nimbus realm ────────────────────────────────────────────────────────────
# The single realm everything in Nimbus authenticates against. The master
# realm stays for Keycloak self-administration only.

resource "keycloak_realm" "nimbus" {
  realm        = "nimbus"
  enabled      = true
  display_name = "Nimbus"

  registration_allowed     = false
  reset_password_allowed   = true
  remember_me              = true
  verify_email             = false
  login_with_email_allowed = true

  # Password policy: length 12+, mixed case, digit, special, not username.
  password_policy = "length(12) and upperCase(1) and lowerCase(1) and digits(1) and specialChars(1) and notUsername(undefined)"

  # Tokens — short-lived access (15m) and longer SSO session (10h).
  sso_session_idle_timeout = "10h0m0s"
  sso_session_max_lifespan = "10h0m0s"
  access_token_lifespan    = "15m0s"
  refresh_token_max_reuse  = 0

  ssl_required = "external"

  # Brute-force protection. The presence of the brute_force_detection block
  # turns it on. After 30 failed logins the account is temporarily locked
  # for 60s, doubling up to 15min per attempt; counter resets after 12h.
  security_defenses {
    brute_force_detection {
      permanent_lockout                = false
      max_login_failures               = 30
      wait_increment_seconds           = 60
      quick_login_check_milli_seconds  = 1000
      minimum_quick_login_wait_seconds = 60
      max_failure_wait_seconds         = 900
      failure_reset_time_seconds       = 43200
    }
  }

  internationalization {
    supported_locales = ["en"]
    default_locale    = "en"
  }
}

# ── Outputs ──────────────────────────────────────────────────────────────────

output "keycloak_realm" {
  description = "The Keycloak realm everything in Nimbus authenticates against"
  value       = keycloak_realm.nimbus.realm
}

output "keycloak_realm_issuer" {
  description = "Public OIDC issuer URL — apps put this in their OIDC config"
  value       = "https://${var.keycloak_domain}/realms/${keycloak_realm.nimbus.realm}"
}
