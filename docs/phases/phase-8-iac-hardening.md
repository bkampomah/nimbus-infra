# Phase 8 — IaC hardening

Cleanup pass after Phase 7 lands. Removes rebuild fragility, manual fixups,
and architectural debt accumulated through Phases 3–7.

## Completed
- Grafana 13 datasource/dashboard provisioning repaired. `nimbus-mon` now points
  `PROVISIONING_CFG_DIR` back at `/etc/grafana/provisioning`, provisions
  Prometheus/Loki with deterministic UIDs (`prometheus`, `loki`), and restores
  the `Nimbus` folder plus `nimbus-aws-infra` dashboard from repo JSON.
- Existing `nimbus-mon` was manually synced on 2026-05-11 because cloud-init
  user-data changes are ignored on the running VM.
- Promtail log-read permissions repaired. The monitoring module now adds the
  `promtail` user to `adm` and `grafana` so `/var/log/syslog`,
  `/var/log/auth.log`, and Grafana logs are shipped to Loki after rebuild.
- Nextcloud Vault Agent runtime repaired. The Nextcloud module now writes the
  agent PID under `/run/vault-agent/` and keeps `NoNewPrivileges=false` so the
  scoped sudo deploy wrapper can install rendered DB config and reload PHP-FPM.
- Vault dynamic DB role for Nextcloud repaired and applied on 2026-05-11.
  Freshly rotated users now inherit the existing `nextcloud` PostgreSQL role;
  verified by restarting `vault-agent` and confirming Nextcloud stayed healthy.
- Keycloak admin recovery and OIDC client secret rotation runbooks added.
- Backup and MinIO client rebuild safety repaired. `pg-backup.service` and
  `pg-backup.timer` are in the Postgres cloud-init template,
  `/usr/local/bin/mc.minio` is used instead of `mc`, Postgres/Keycloak backup
  jobs and MinIO bootstrap use explicit `/root/.mc.minio` config, Keycloak
  realm export inherits the configured RDS environment instead of falling back
  to localhost, and the Postgres `host` output now derives from `var.static_ip`
  instead of guest-agent interface ordering.
- PowerDNS authoritative backend migrated from SQLite to `gpgsql` on
  nimbus-rds. Terraform now creates the `powerdns` database credentials,
  `nimbus-dns` initializes the PostgreSQL schema during rebuild, record replay
  was verified, and `-parallelism=1` is no longer needed for DNS applies.
- Proxmox provider SSH uploads now keep agent auth as the default and allow an
  optional private-key-file fallback for snippet recovery when the provider
  cannot use the local SSH agent.
- MinIO console SSO no longer grants `consoleAdmin` to every OIDC login.
  Keycloak now emits a `groups` claim for the MinIO client, MinIO reads that
  claim as the policy list, and only the seeded `nimbus-admin` user is placed
  in the Keycloak `consoleAdmin` group.
- Fresh `pg-backups` buckets are created with object lock and a default
  `COMPLIANCE 30d` retention rule. Existing buckets that predate object lock
  need a one-time migration or rebuild; cloud-init logs a warning instead of
  failing the entire MinIO bootstrap.
- MinIO API access remains VPC-only in Terraform (`api_allow_cidrs =
  [var.vpc_cidr]`). Home-LAN administration should go through Tailscale or the
  bastion rather than codifying the manual LAN UFW patch.
- Linux admin identity is canonicalized on `nimbus`: Terraform defaults
  `var.admin_username` to `nimbus`, all module user-data templates consume that
  variable, and no `ansible` user references remain in repo code.
- `scripts/smoke-test.sh` covers post-rebuild external ingress, internal DNS,
  SSH/service health, app probes, MinIO OIDC claim mode, and pg-backups
  retention.
- Tailscale tailnet policy is codified in `.github/tailscale-acl.hujson` and
  applied by `.github/workflows/tailscale-acl.yml`. The Proxmox LXC subnet
  router/exit node is modeled as `tag:nimbus-subnet-router`, auto-approved for
  Nimbus VPC (`10.0.0.0/16`), home LAN (`192.168.1.0/24`), and exit-node
  advertisements.

## Phase 7 carry-forward
- No open Phase 7 runbook carry-forward items.

## Module fragility (rebuild-vulnerable)
- No open backup/client rebuild-safety items.

## PowerDNS backend
- No open PowerDNS backend migration items.

## MinIO service quality
- Live `nimbus-s3` may still need rebuild/migration before `pg-backups` object
  lock applies, because older MinIO/S3 behavior requires object lock at bucket
  creation.

## Identity / access
- No open tailnet policy items.

## Operational hygiene
- Clean up duplicate NRPT rule on Windows admin box.
