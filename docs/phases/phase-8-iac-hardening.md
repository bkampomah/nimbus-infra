# Phase 8 — IaC hardening

Cleanup pass after Phase 7 lands. Removes rebuild fragility, manual fixups,
and architectural debt accumulated through Phases 3–7.

## Phase 7 carry-forward
- Add Keycloak admin recovery and OIDC client rotation runbooks.
- Make Nimbus Grafana datasource/dashboard provisioning Grafana-13-safe and
  point `PROVISIONING_CFG_DIR` back at `/etc/grafana/provisioning`; it points
  at an empty runtime directory for now so Grafana OIDC can start cleanly.

## Module fragility (rebuild-vulnerable)
- pg-backup systemd unit + timer not in cloud-init template. Manually
  installed twice now. Bake into `modules/postgres`.
- mc.minio install + alias not in cloud-init. Bake into `modules/minio`:
  - Binary at `/usr/local/bin/mc.minio` (NOT `mc` — collides with Midnight Commander)
  - Config under `/root/.mc.minio/` (auto-derived from binary name)
  - `sudo HOME=/root` or systemd `Environment=` for correct alias-set
  - `ReadWritePaths=/root/.mc.minio` in `pg-backup.service` unit
- `modules/postgres/outputs.tf` host output uses fragile `ipv4_addresses[1][0]`.
  Switch to: `[for ifc in network_interface_names : ifc if ifc != "lo"][0]`

## PowerDNS / SQLite
- SQLite single-writer forces `-parallelism=1` on every apply.
  Migrate backend to `gpgsql` now that nimbus-rds exists.
- `/etc/powerdns/pdns.conf` has duplicate `gsqlite3-pragma-*` lines from
  debugging. Clean up during migration.

## MinIO service quality
- `/usr/bin/mc` (Midnight Commander) collides with MinIO client.
  Decision: full-path `/usr/local/bin/mc.minio` everywhere (recommended), or
  rename to `mcli`, or `apt remove mc`.
- API allowlist excludes home LAN. Manually patched UFW.
  Decision: keep tight + Tailscale-only, OR add `192.168.1.0/24` to `s3.tf`.
- Object lock on `pg-backups` bucket for ransomware-proof backups (deny
  even root admin from deleting recent versions).

## Identity / access
- cloud-init creates user `ansible` but golden template (VMID 9000) has
  user `nimbus` that takes precedence. Update template references to one
  canonical user.
- Tailscale ACL lives only in admin console — codify in repo as
  `.github/tailscale-acl.json` + GitHub Action that deploys on push.

## Operational hygiene
- Remove `-parallelism=1` note from README after gpgsql migration completes.
- Document `mc.minio` binary naming convention in README.
- `scripts/smoke-test.sh` — verify all VMs after rebuild (ping, expected
  ports, key services healthy).
- Clean up duplicate NRPT rule on Windows admin box.
