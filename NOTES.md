# Nimbus Notes
Lab journal for build progress and gotchas.

---

## Phase 5f — 2026-05-01

### Nextcloud upgraded to 30.0.17

Upgraded from 29.0.7 → 30.0.17 on running nimbus-cloud-01. After the file swap and `occ upgrade`, maintenance mode was not automatically turned off, causing a 503. Fix:

```bash
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off
```

PHP-FPM was also hitting `pm.max_children = 5` repeatedly under load. Raised to 15 in `/etc/php/8.3/fpm/pool.d/www.conf`.

### HAProxy HTTPS frontend

Added a `:443` frontend to HAProxy with SNI-based cert selection. HAProxy reads from a directory (`/etc/haproxy/certs/`) and picks the right cert by SNI automatically — no explicit `ssl crt-list` needed when using a directory.

Two certs in the directory:
- `nimbusnode-le.pem` — LE wildcard for `*.nimbusnode.org` (fullchain + key)
- `wildcard-nimbus-local.pem` — step-ca wildcard for `*.nimbus.local` (cert + root CA + key)

Cert file format: `fullchain.cer` contents + `ca.cer` contents + private key, concatenated, chmod 640 root:haproxy.

### Internal CA in Terraform

Added `hashicorp/tls` provider to generate the Nimbus CA and ALB server cert in Terraform (`certs.tf`). The CA cert is exported as `terraform/nimbus-ca.crt` — import into browsers/system trust for warning-free access to `*.nimbus.local`.

The cloud-init template for HAProxy embeds the TLS PEM bundle as base64 (`encoding: b64`) to avoid YAML indentation issues with PEM block headers.

---

## Phase 5e — 2026-04 (HTTPS setup)

### acme.sh + Let's Encrypt

Domain in Cloudflare is `nimbusnode.org`, not `nimbuscloud.org`. Always verify with:
```bash
curl -s -H "Authorization: Bearer $CF_Token" \
  "https://api.cloudflare.com/client/v4/zones" | jq '.[].name'
```

Issued wildcard cert for `*.nimbusnode.org` and `nimbusnode.org` using Cloudflare DNS-01 plugin. Deploy hook copies cert to `/etc/haproxy/certs/nimbusnode-le.pem` and reloads HAProxy.

### Cloudflare Tunnel

cloudflared runs on nimbus-alb (not on nimbus-cloud-01 directly). Tunnel routes `cloud.nimbusnode.org → http://10.0.10.102:80`.

Key gotcha: **Cloudflare dashboard ingress routes take precedence over config.yml ingress rules**. Dashboard routes are loaded first. If the dashboard has a route for a hostname, config.yml ingress for that hostname is ignored. Fix: keep dashboard and config.yml consistent, or use one or the other exclusively.

cloudflared must use `protocol: http2` (TCP) on this network. pfSense has UDP timeouts that drop QUIC connections, causing cloudflared to lose connectivity every few minutes.

`cloudflared service install` writes a systemd unit that uses `tunnel run --token` only — it doesn't reference config.yml. Fix:
```bash
sed -i 's|tunnel run --token|tunnel --config /etc/cloudflared/config.yml run --token|' \
  /etc/systemd/system/cloudflared.service
systemctl daemon-reload && systemctl restart cloudflared
```

### Nextcloud objectstore class escaping

The PHP class `\OC\Files\ObjectStore\S3` requires exactly one backslash as the namespace separator. In the shell command:
```bash
sudo -u www-data php occ config:system:set objectstore class --value='\OC\Files\ObjectStore\S3'
```
Single quotes prevent the shell from interpreting backslashes. In the Terraform template (`user-data.yml.tftpl`), use `'\OC\Files\ObjectStore\S3'` — the shell single-quoting handles it. Earlier versions of the template had `\\OC\\Files\\ObjectStore\\S3` which produced `\\OC\\Files\\ObjectStore\\S3` in config.php (double backslashes), causing PHP to fail with "Class not found."

---

## Phase 5c/5d — 2026-04 (nimbus-cloud-01 Nextcloud)

### MinIO as S3 Primary Object Storage

Two MinIO-specific quirks that differ from AWS S3:

1. **Path-style addressing required.** MinIO doesn't support virtual-hosted-style URLs (`bucket.host`). Nextcloud defaults to virtual-hosted. Must set `use_path_style = true` or every object request returns 404.

2. **Region must be non-empty.** MinIO ignores the region value entirely, but Nextcloud's S3 client rejects an empty string at startup. Use `us-east-1` (MinIO's built-in default mock region).

### bpg/proxmox lifecycle ignore_changes

The `bpg/proxmox` provider forces a VM replace whenever `initialization[0].ip_config` or `initialization[0].user_data_file_id` changes. Add both to `lifecycle.ignore_changes` in every VM module to prevent accidental rebuilds:

```hcl
lifecycle {
  ignore_changes = [
    initialization[0].user_account,
    initialization[0].ip_config,
    initialization[0].user_data_file_id,
  ]
}
```

To intentionally rebuild: `terraform apply -replace=module.<name>.proxmox_virtual_environment_vm.<resource>`

### cloud-init heredoc YAML gotcha

A heredoc whose `EOF` terminator sits at column 0 terminates the YAML block scalar early. cloud-init discards the entire user-data file silently when this happens. Fix: use a one-liner instead of a heredoc for any shell content inside a YAML `|` block. Example in the Nextcloud cron setup:

```bash
# BAD — EOF at column 0 breaks YAML parsing
cat <<EOF | crontab -u www-data -
*/5 * * * * php -f $NC_WEBROOT/cron.php
EOF

# GOOD
echo "*/5 * * * * php -f $NC_WEBROOT/cron.php" | crontab -u www-data -
```

---

## Phase 5b — 2026-04 (pgbackrest + MinIO backups)

pgbackrest ships PostgreSQL backups to MinIO using the S3 interface. The MinIO `mc` CLI binary is named `mcli` in the Ubuntu 24.04 package repos (the `mc` name conflicts with the Midnight Commander file manager). Install as:

```bash
apt install mcli
```

Configure alias: `mcli alias set nimbus-s3 http://10.0.20.101:9000 <key> <secret>`

---

## Phase 4b — 2026-03 (nimbus-alb HAProxy)

### HAProxy installed manually after pfSense internet outage

nimbus-alb's cloud-init ran before pfSense internet was restored, so packages failed to install. Fix: restore internet, then run `sudo apt-get install -y haproxy` and restart the install script manually.

### HAProxy stats page

HAProxy exposes a stats page at `:8404` (restricted to mgmt subnet by UFW). Useful for real-time backend health checks.

---

## Phase 3 — 2026-03 (PowerDNS)

### Two-stage bootstrap

The PowerDNS provider (`pan-net/powerdns`) needs the DNS VM to exist and be reachable before it can create records. Bootstrap order:

```bash
terraform apply -target=module.nimbus_dns   # Stage 1: VM only
terraform output -raw nimbus_dns_api_key    # Stage 2: get key
# add key to terraform.tfvars as powerdns_api_key
terraform apply                             # Stage 3: full apply
```

### PowerDNS cloud-init bugs fixed

Five bugs found and fixed in the original cloud-init template:
1. Race condition: `pdns_server` starts before `postgresql` is ready → added `pg_isready` loop
2. Wrong socket path in `pdns.conf` → corrected to `/var/run/postgresql`
3. DB schema not imported → added `psql < /usr/share/doc/pdns-backend-pgsql/schema.pgsql.sql`
4. API key not set → added `api-key` directive
5. Recursor not configured → added separate `pdns-recursor` install and config

---

## General gotchas

### MTU 1420

The VPC path MTU is 1420 (pfSense WAN headroom). Without this, large TCP transfers hit ICMP fragmentation-needed and get reset mid-stream (manifests as Nextcloud tarball downloads failing at ~30% or Postgres connections dropping). Set via netplan:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      mtu: 1420
```

Applied in all VM cloud-init templates via `/etc/netplan/99-nimbus-mtu.yaml`.

### PHP-FPM memory exhaustion → 503

Nextcloud PHP-FPM can exhaust available memory during upgrades or heavy background jobs (observed peak: 2.6G on a 4GB VM). Symptoms: 503 from nginx, stale OPcache state even after files are updated. Fix:

```bash
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --on
sudo systemctl restart php8.3-fpm   # flushes OPcache
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off
sudo -u www-data php /var/www/nextcloud/occ upgrade
```

If pm.max_children warnings appear in `/var/log/php8.3-fpm.log`, raise the limit:
```bash
sudo sed -i 's/^pm\.max_children.*/pm.max_children = 15/' /etc/php/8.3/fpm/pool.d/www.conf
sudo systemctl reload php8.3-fpm
```

### Terraform sensitive variables in cloud-init

Terraform passes sensitive variables (passwords, keys) into cloud-init templates as plaintext strings. The rendered user-data file is stored in Proxmox snippet storage — treat the Proxmox host's storage as having the same sensitivity as the secrets themselves.

### bpg/proxmox provider SSH requirement

The `bpg/proxmox` provider needs SSH access to the Proxmox host (not just the API) for uploading snippet files. Set `proxmox_ssh_username` in `terraform.tfvars` and ensure your SSH key is authorized on the Proxmox host.
