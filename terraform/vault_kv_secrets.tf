# terraform/vault_kv_secrets.tf
#
# Phase 7e — secret migration into Vault KV.
#
# Three secrets land in `secret/nimbus/*`:
#   - cloudflared (tunnel token)        — written from var.cloudflare_tunnel_token
#   - powerdns    (HTTP API key)        — auto-piped from module.nimbus_dns.api_key
#   - nextcloud   (admin password)      — written from var.nextcloud_admin_password
#
# Reads:
#   - nextcloud admin password is now consumed in cloud.tf via the data source
#     below (the cleanest migration win — only consumed at install time).
#   - cloudflared/powerdns also have data sources but their *current* consumers
#     (alb.tf, dns.tf provider config) keep using `var.*` for bootstrap reasons:
#       * powerdns provider must be configured during Stage 1 before Vault exists
#       * cloudflared token is consumed in nimbus-alb cloud-init; rebuilding the
#         ALB on-rotation is fine, but the var path is what tfvars users expect.
#     Phase 8 hardening: switch consumers to the data sources, drop the vars.

# ── Writes ──────────────────────────────────────────────────────────────────

resource "vault_kv_secret_v2" "cloudflared" {
  mount = vault_mount.kv.path
  name  = "nimbus/cloudflared"

  data_json = jsonencode({
    tunnel_token = var.cloudflare_tunnel_token
  })

  custom_metadata {
    data = {
      managed_by = "terraform"
      consumer   = "modules/haproxy"
    }
  }
}

# powerdns API key — auto-piped from the DNS module so the operator no longer
# has to terraform-output → paste into tfvars (Stage 2 is now optional once
# this lands; the var.powerdns_api_key entry remains as the bootstrap path).
resource "vault_kv_secret_v2" "powerdns" {
  mount = vault_mount.kv.path
  name  = "nimbus/powerdns"

  data_json = jsonencode({
    api_key = module.nimbus_dns.api_key
  })

  custom_metadata {
    data = {
      managed_by = "terraform"
      consumer   = "powerdns provider config"
    }
  }
}

resource "vault_kv_secret_v2" "nextcloud_admin" {
  mount = vault_mount.kv.path
  name  = "nimbus/nextcloud"

  data_json = jsonencode({
    admin_password = var.nextcloud_admin_password
  })

  custom_metadata {
    data = {
      managed_by = "terraform"
      consumer   = "modules/nextcloud install hook"
    }
  }
}

# ── Reads ───────────────────────────────────────────────────────────────────
# depends_on enforces ordering so the data source refresh sees the latest write.

data "vault_kv_secret_v2" "cloudflared" {
  mount = vault_mount.kv.path
  name  = "nimbus/cloudflared"

  depends_on = [vault_kv_secret_v2.cloudflared]
}

data "vault_kv_secret_v2" "powerdns" {
  mount = vault_mount.kv.path
  name  = "nimbus/powerdns"

  depends_on = [vault_kv_secret_v2.powerdns]
}

data "vault_kv_secret_v2" "nextcloud_admin" {
  mount = vault_mount.kv.path
  name  = "nimbus/nextcloud"

  depends_on = [vault_kv_secret_v2.nextcloud_admin]
}

# ── Outputs ─────────────────────────────────────────────────────────────────

output "vault_kv_paths" {
  description = "KV-v2 paths for all Phase 7e migrated secrets"
  value = {
    cloudflared = "${vault_mount.kv.path}/${vault_kv_secret_v2.cloudflared.name}"
    powerdns    = "${vault_mount.kv.path}/${vault_kv_secret_v2.powerdns.name}"
    nextcloud   = "${vault_mount.kv.path}/${vault_kv_secret_v2.nextcloud_admin.name}"
  }
}
