# terraform/certs.tf
#
# Internal CA and ALB server certificate for Nimbus split-horizon HTTPS.
#
# Why a self-CA instead of Let's Encrypt internally:
#   The hostnames covered (*.nimbus.local, cloud.nimbusnode.org internal)
#   are not publicly resolvable, so ACME HTTP-01/DNS-01 can't issue for them.
#   A private CA lets internal clients trust the ALB's HTTPS with zero public
#   exposure. Clients import nimbus_ca_cert once; all future certs signed by
#   this CA are trusted automatically.
#
# Rotation:
#   terraform taint tls_locally_signed_cert.nimbus_alb
#   terraform apply
#   (This regenerates the server cert but keeps the CA key stable, so
#    clients don't need to re-import the root cert.)
#
# Distributing the CA cert to clients:
#   terraform output -raw nimbus_ca_cert > nimbus-ca.crt
#   See docs/runbooks/internal-ca.md for per-platform import instructions.

# ── Internal Root CA ──────────────────────────────────────────────────────────

resource "tls_private_key" "nimbus_ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "nimbus_ca" {
  private_key_pem = tls_private_key.nimbus_ca.private_key_pem

  subject {
    common_name  = "Nimbus Internal CA"
    organization = "Nimbus Lab"
  }

  validity_period_hours = 87600 # 10 years — homelab only
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# ── ALB Server Certificate ────────────────────────────────────────────────────
# SANs cover every internal hostname that routes through the ALB so a single
# cert serves both the legacy AIO path (cloud.nimbusnode.org split-horizon)
# and the new Nextcloud path (cloud-app.nimbus.local).

resource "tls_private_key" "nimbus_alb" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "nimbus_alb" {
  private_key_pem = tls_private_key.nimbus_alb.private_key_pem

  subject {
    common_name  = "nimbus-alb.nimbus.local"
    organization = "Nimbus Lab"
  }

  dns_names = [
    "nimbus-alb.nimbus.local",
    "cloud.nimbus.local",     # legacy AIO path (internal split-horizon)
    "cloud-app.nimbus.local", # new Nextcloud path
    "mon.nimbus.local",       # Grafana via ALB (internal)
    "cloud.nimbusnode.org",   # AIO domain — internal redirect lands here
    "aio.nimbusnode.org",     # AIO public hostname via ALB/Cloudflare
    "auth.nimbus.local",      # Phase 7 — Keycloak via ALB (internal)
    var.keycloak_domain,      # Phase 7 — Keycloak via ALB (CF Tunnel re-encrypt)
  ]

  ip_addresses = [var.nimbus_alb_ip]
}

resource "tls_locally_signed_cert" "nimbus_alb" {
  cert_request_pem   = tls_cert_request.nimbus_alb.cert_request_pem
  ca_private_key_pem = tls_private_key.nimbus_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.nimbus_ca.cert_pem

  validity_period_hours = 87600 # 10 years

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# ── nimbus-iam (Keycloak) Server Certificate ─────────────────────────────────
# Phase 7. Keycloak listens on :8443; HAProxy connects upstream over HTTPS
# (`ssl verify none` — see modules/haproxy/user-data.yml.tftpl). SANs cover
# both ALB-fronted hostnames (in case anything bypasses the ALB) and the
# internal direct-admin hostname.

resource "tls_private_key" "nimbus_iam" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "nimbus_iam" {
  private_key_pem = tls_private_key.nimbus_iam.private_key_pem

  subject {
    common_name  = "nimbus-iam.nimbus.local"
    organization = "Nimbus Lab"
  }

  dns_names = [
    "nimbus-iam.nimbus.local",
    "auth.nimbus.local",
    var.keycloak_domain,
  ]

  ip_addresses = [var.nimbus_iam_ip]
}

resource "tls_locally_signed_cert" "nimbus_iam" {
  cert_request_pem   = tls_cert_request.nimbus_iam.cert_request_pem
  ca_private_key_pem = tls_private_key.nimbus_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.nimbus_ca.cert_pem

  validity_period_hours = 87600 # 10 years

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# ── nimbus-vault Server Certificate ──────────────────────────────────────────
# Phase 7. Vault is internal-only — no ALB, no Cloudflare Tunnel. Clients
# (operator CLI, app pods later) hit https://vault.nimbus.local:8200 directly.

resource "tls_private_key" "nimbus_vault" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "nimbus_vault" {
  private_key_pem = tls_private_key.nimbus_vault.private_key_pem

  subject {
    common_name  = "vault.nimbus.local"
    organization = "Nimbus Lab"
  }

  dns_names = [
    "vault.nimbus.local",
    "nimbus-vault.nimbus.local",
  ]

  ip_addresses = [var.nimbus_vault_ip]
}

resource "tls_locally_signed_cert" "nimbus_vault" {
  cert_request_pem   = tls_cert_request.nimbus_vault.cert_request_pem
  ca_private_key_pem = tls_private_key.nimbus_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.nimbus_ca.cert_pem

  validity_period_hours = 87600 # 10 years

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "nimbus_ca_cert" {
  description = "Internal CA root cert — import into OS/browser trust store on each client. See docs/runbooks/internal-ca.md."
  value       = tls_self_signed_cert.nimbus_ca.cert_pem
}
