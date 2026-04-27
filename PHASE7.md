# Phase 7 — IaC cleanup

## Module fragility (rebuild-vulnerable)
- postgres module uses ipconfig0=dhcp, all others static — pfSense
  reservation drift caused IP collision after rebuild. Migrate to
  static_ip variable matching alb/s3 convention.
- pg-backup systemd unit + timer not in cloud-init template.
  Manually installed twice now. Bake into module.
- mc.minio install + alias not in cloud-init. Bake in, including:
  - Binary at /usr/local/bin/mc.minio (NOT mc — collides with Midnight Commander)
  - Config under /root/.mc.minio/ (auto-derived from binary name)
  - sudo HOME=/root or systemd Environment for proper alias-set
  - ReadWritePaths=/root/.mc.minio in pg-backup.service unit
- Cross-module wiring: rds.tf needs to read s3 endpoint + pgbackup
  creds from module.nimbus_s3 outputs.

## PowerDNS / SQLite
- SQLite single-writer — terraform applies need -parallelism=1.
  Migrate backend to gpgsql now that nimbus-rds exists.
- /etc/powerdns/pdns.conf has duplicate gsqlite3-pragma-* lines from
  debugging. Clean up during migration.

## MinIO service quality
- /usr/bin/mc (Midnight Commander) collides with MinIO client.
  Decide: rename to mcli (matches upstream), apt remove mc, or
  always full-path /usr/local/bin/mc.minio.
- API allowlist excludes home LAN. Manually patched UFW. Decide:
  keep tight + Tailscale-only, OR add 192.168.1.0/24 to s3.tf.
- Object lock on pg-backups bucket for ransomware-proof backups
  (deny even root admin from deleting recent versions).

## Module style alignment
- postgres module still uses old var names (target_node, template_id).
  Rewrite interface to match alb/dns/s3 alb-style.
- postgres module's host output uses fragile ipv4_addresses[1][0].
  Switch to: [for ifc in network_interface_names : ifc if ifc != "lo"][0]

## Identity / access
- cloud-init creates user "ansible" but golden template (VMID 9000)
  has user "nimbus" that takes precedence. Update template references.
- Tailscale ACL only in admin console — codify in repo as
  .github/tailscale-acl.json + GitHub Action that deploys on push.

## Operational hygiene
- Document -parallelism=1 requirement in README.
- Document mc.minio binary naming convention.
- Make target / script for "verify all VMs after rebuild" smoke test.
- Clean up duplicate NRPT rule on Windows.
