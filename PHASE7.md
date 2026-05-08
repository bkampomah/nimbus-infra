# Phase 7 — IAM (Keycloak + Vault)

AWS analogue: Cognito (User Pools) + Secrets Manager + STS dynamic credentials.

## Architecture

| Component | VM           | IP           | Subnet | Public hostname                  | Internal             |
|-----------|--------------|--------------|--------|----------------------------------|----------------------|
| Keycloak  | nimbus-iam   | 10.0.100.30  | mgmt   | auth.nimbusnode.org (CF Tunnel)  | auth.nimbus.local    |
| Vault     | nimbus-vault | 10.0.100.40  | mgmt   | — (Tailscale-only)               | vault.nimbus.local   |

### Locked decisions
- **Two VMs**, not one combined — separate blast radius, different scaling profiles.
- **Keycloak DB on nimbus-rds** — add a `keycloak` database alongside `nextcloud`. No second Postgres.
- **Vault storage = integrated Raft**, single node, Shamir 3-of-5 unseal. No auto-unseal.
- **Vault never goes public.** Internal-only via `vault.nimbus.local`, Tailscale gates external admin access.
- **Defer Vault PKI** — step-ca keeps issuing internal certs for Phase 7.
- **`admin_password` stays in tfvars** as break-glass. Migrate lower-criticality secrets first.

---

## Sub-phases

### 7a — Modules + VM provisioning *(Medium)* — ✅ done
- `modules/keycloak/` — Java 21, Keycloak 25, Postgres backend on nimbus-rds, systemd, internal CA cert on `:8443`
- `modules/vault/` — Vault 1.18, raft storage at `/opt/vault/data`, systemd, internal CA cert on `:8200`, audit log → file → Promtail
- New TF root files: `iam.tf`, `vault.tf`
- PowerDNS A records (`auth.nimbus.local`, `vault.nimbus.local`)
- HAProxy backends on nimbus-alb — TLS re-encrypt (not passthrough) so we can inject `X-Forwarded-*` headers
- Cloudflare Tunnel: add `auth.nimbusnode.org` hostname (Vault gets no tunnel)

### 7b — Keycloak realm-as-code *(Medium)* — ✅ done
- **Provider:** `keycloak/keycloak` v5 (the official one — `mrparkers/keycloak` was deprecated when donated late 2024). Auth via master-realm admin user/password.
- **Provider URL:** `https://${nimbus_iam_ip}:8443` directly (cert SAN covers the IP) with `tls_insecure_skip_verify=true` and `initial_login=false` so plan/init work before nimbus-iam is reachable.
- `nimbus` realm — brute-force protection (30 failures / 12h, 60s→15min lockout), password policy `length(12) and upperCase(1) and lowerCase(1) and digits(1) and specialChars(1) and notUsername`.
- OIDC clients: `nextcloud`, `grafana`, `minio-console`, `vault` (all CONFIDENTIAL, standard flow only).
- Seed users: `nimbus-admin` (realm-management/realm-admin role) + `nimbus-test`, both with temporary passwords.
- Nightly `kc.sh export` at 03:00 → MinIO `kc-backups` bucket. Service stops Keycloak briefly for the offline export (~10s window). Phase 8 hardening: switch to admin REST API export to remove the downtime.
- **Bootstrap stage 4:** `terraform apply -target=module.nimbus_iam` must run before realm config can apply. Documented in README day-one commands.

### 7c — App SSO integration *(Easy–Medium)* — ✅ done
- **Trust-store install** — every app VM that talks to Keycloak (nextcloud / monitoring / minio) gets `nimbus-ca.crt` written to `/usr/local/share/ca-certificates/` and `update-ca-certificates` runs in cloud-init. No `tls_skip_verify` flags anywhere.
- **Nextcloud:** `occ app:install user_oidc` + `occ user_oidc:provider Keycloak --discoveryuri ...` runs after `maintenance:install`. UID/email/displayname mapping wired.
- **Grafana:** `/etc/default/grafana-server` rendered with `GF_AUTH_GENERIC_OAUTH_*` env vars. `GF_SERVER_ROOT_URL=https://mon.nimbus.local` so OIDC redirects come back via the ALB. Role mapping JMESPath: `grafana-admins → Admin`, `grafana-editors → Editor`, else `Viewer`. Backed by a `keycloak_openid_group_membership_protocol_mapper` on the grafana client that adds a `groups` claim.
- **MinIO console:** `MINIO_IDENTITY_OPENID_*` appended to `/etc/default/minio`. Every OIDC user gets `consoleAdmin` via `MINIO_IDENTITY_OPENID_ROLE_POLICY` (homelab-grade; Phase 8 swaps to per-group claim-based policies).
- **Groups in Keycloak:** `grafana-admins` + `grafana-editors`. Seed `nimbus-admin` user is placed in `grafana-admins` so the "log in via Keycloak, land in Grafana as Admin" smoke test works without manual UI clicks.
- **Break-glass:** local admin user retained on every app — `nimbus` (Nextcloud admin), default Grafana admin, MinIO root.

#### Smoke tests (run after `terraform apply`)
1. **Nextcloud:** open `https://cloud.nimbusnode.org` → "Log in with Keycloak" link → enter `nimbus-test` + temporary password → forced rotation → land in Nextcloud.
2. **Grafana:** open `https://mon.nimbus.local` → "Sign in with Keycloak" → as `nimbus-admin` → confirm Org Role = Admin in user profile.
3. **MinIO console:** open `http://10.0.20.101:9001` → "Login with SSO" → confirm bucket list visible.
4. Each app: confirm local admin login still works (break-glass).

### 7d — Vault bootstrap *(Hard)* — ✅ done
- **`vault operator init` stays manual.** Recovery + unseal keys (Shamir 3-of-5) live on the operator's machine, not the repo. Procedure in `docs/runbooks/vault-init.md`.
- **Provider auth via `VAULT_TOKEN` env.** Operator exports root (or post-OIDC admin) token before `terraform apply`. Provider sets `skip_child_token=true` + `skip_get_vault_version=true` so plans don't fight a flaky parent connection.
- **Audit device:** file at `/var/log/vault/audit.log` (already on Promtail's vault-audit scrape from 7a, so it streams to Loki).
- **Secrets engines:** `kv-v2` at `secret/`, `database` at `database/` with a `nextcloud` dynamic role (1h default TTL, 24h max). Phase 7e wires Nextcloud to consume it.
- **Auth methods:** `oidc` (Keycloak IdP, role `vault-admins`), `approle` (role `terraform` for KV reads). Token method is built-in.
- **Postgres `vault` role = SUPERUSER** on nimbus-rds. Created by the postgres module's cloud-init when `vault_admin_user` is set. Phase 8 tightens to membership-of-target-DB-owner.
- **Policies:** `admin` (full), `operator` (KV CRUD), `terraform-read` (`secret/data/nimbus/*` read), `nextcloud-db` (`database/creds/nextcloud` read).
- **Keycloak `vault-admins` group** → Vault `admin` policy via OIDC role bound_claims. Seed `nimbus-admin` placed in it.
- **Bootstrap is now 6 stages** in the README. Stage 4 = target nimbus-vault VM. Stage 5 = manual `vault operator init`. Stage 6 = full apply with `VAULT_TOKEN` exported.

### 7e — Secret migration *(Medium)* — ✅ done

| Secret                      | From              | To                            | Read pattern |
|-----------------------------|-------------------|-------------------------------|--------------|
| cloudflared_tunnel_token    | tfvars            | `secret/nimbus/cloudflared`   | tfvars (consumer); Vault is canonical store |
| powerdns_api_key            | auto-from-DNS-VM  | `secret/nimbus/powerdns`      | tfvars (provider config); Vault is canonical store |
| nextcloud_admin_password    | tfvars            | `secret/nimbus/nextcloud`     | **`data "vault_kv_secret_v2"`** |
| nextcloud Postgres creds    | random_password   | Vault `database/` (dynamic)   | **Vault Agent on nimbus-cloud-01** |
| admin_password (VM admin)   | tfvars            | stays                         | break-glass |

- **Static secrets:** all three written to Vault KV via `vault_kv_secret_v2`. The nextcloud admin password is consumed via the data source — that's the cleanest migration target since it's only used at install time. Cloudflared and powerdns_api_key keep their existing var-based consumers (the powerdns provider must work during Stage 1 before Vault exists; the cloudflared token only matters when the ALB is rebuilt). Phase 8 hardens these to Vault-only reads.
- **Postgres dynamic creds (the marquee):** Vault Agent runs on nimbus-cloud-01 as a systemd unit, authenticates via AppRole, renders a Nextcloud overlay config (`config/db.config.php`) with creds minted from `database/creds/nextcloud`, and reloads php-fpm on every rotation. Old leases stay valid until Vault revokes them, so in-flight requests don't see auth errors during cred rotation.
- **AppRole secret_id is materialized** into Terraform state and staged to disk via cloud-init. Lab grade — Phase 8 response-wraps the secret_id at handoff.
- **Static `nextcloud` Postgres role stays** as break-glass; Nextcloud's runtime uses Vault-minted dynamic users after Vault Agent's first render.
- **Sudoers narrowly scoped** for vault-agent: `install -o www-data ... db.config.php` and `systemctl reload php8.3-fpm.service`. Nothing else.

#### What rotation looks like
1. Vault Agent renews the lease until `max_ttl` (24h).
2. At lease boundary, agent re-fetches creds from `database/creds/nextcloud` → Vault mints new Postgres user, returns new lease.
3. Agent re-renders `/var/lib/vault-agent/db.config.php` and runs `vault-agent-deploy-db` (sudo install + reload php-fpm).
4. PHP-FPM workers reconnect with new creds. Old creds stay valid briefly until Vault revocation kicks in.

### 7f — Runbooks + cutover *(Trivial)*
- `docs/runbooks/vault-unseal.md` — recovery procedure
- `docs/runbooks/keycloak-admin-recovery.md` — bootstrap admin if locked out
- `docs/runbooks/oidc-client-rotation.md`
- README phase-table update; AWS service map: Cognito → Keycloak (was IAM combined)
- Tag `phase-7-complete`

---

## Sequencing

7a → 7b → 7d → (7c ‖ 7e) → 7f. 7c and 7e parallelize once Keycloak realm + Vault engines exist.
