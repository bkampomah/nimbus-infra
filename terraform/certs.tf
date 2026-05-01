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
    "cloud.nimbus.local",       # legacy AIO path (internal split-horizon)
    "cloud-app.nimbus.local",   # new Nextcloud path
    "cloud.nimbusnode.org",     # AIO domain — internal redirect lands here
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

# ── Outputs ───────────────────────────────────────────────────────────────────

output "nimbus_ca_cert" {
  description = "Internal CA root cert — import into OS/browser trust store on each client. See docs/runbooks/internal-ca.md."
  value       = tls_self_signed_cert.nimbus_ca.cert_pem
}
