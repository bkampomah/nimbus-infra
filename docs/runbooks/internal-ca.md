# Internal CA — Nimbus Split-Horizon HTTPS

> Covers: why a private CA, how to distribute the root cert, and how to verify
> HTTPS works end-to-end for both the legacy AIO and the new Nextcloud app.

## What's deployed

| Component | Where | Purpose |
|---|---|---|
| Nimbus Internal CA | Terraform state | Signs the ALB server cert |
| ALB server cert | `/etc/haproxy/nimbus-alb.pem` on nimbus-alb | HAProxy HTTPS frontend |
| HAProxy HTTPS frontend | `10.0.1.10:443` | Internal TLS termination |

### Cert SANs

The single cert issued to nimbus-alb covers all internal hostnames that route
through the ALB:

| SAN | Resolves to (internal) | Routed to |
|---|---|---|
| `nimbus-alb.nimbus.local` | 10.0.1.10 | — (direct ALB access) |
| `cloud.nimbus.local` | 10.0.1.10 | AIO at 10.0.10.101:11000 |
| `cloud.nimbusnode.org` | 10.0.1.10 (split-horizon) | AIO at 10.0.10.101:11000 |
| `cloud-app.nimbus.local` | 10.0.1.10 | New Nextcloud at 10.0.10.102:80 |
| IP SAN | 10.0.1.10 | — |

External traffic for `cloud.nimbusnode.org` still goes via Cloudflare → AIO's
own cloudflared daemon (independent of this cert — Cloudflare handles external
TLS). The self-CA cert is strictly for internal VPN/LAN clients.

---

## One-time: distribute the CA cert to clients

On your workstation (WSL or macOS), export the cert:

```bash
cd ~/code/nimbus-infra/terraform
terraform output -raw nimbus_ca_cert > nimbus-ca.crt
```

Then import it on each client platform:

### Windows

```powershell
# Run as Administrator
certutil -addstore -f "Root" nimbus-ca.crt
# Verify:
certutil -store Root | Select-String "Nimbus"
```

Or via GUI: `certmgr.msc` → Trusted Root Certification Authorities → Import.

**NRPT reminder**: Windows already has an NRPT rule pointing `nimbus.local` at
10.0.100.10 (nimbus-dns). The `nimbusnode.org` split-horizon needs a second rule:

```powershell
# Run as Administrator (add if not already present)
Add-DnsClientNrptRule -Namespace ".nimbusnode.org" -NameServers "10.0.100.10"
```

This ensures `cloud.nimbusnode.org` resolves internally (to 10.0.1.10 → ALB)
rather than externally (to Cloudflare), so the self-CA cert is matched correctly.

### macOS

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain nimbus-ca.crt
```

Verify: open Keychain Access → System → Certificates → look for "Nimbus Internal CA".

For split-horizon DNS on macOS, add a resolver file:
```bash
sudo mkdir -p /etc/resolver
echo "nameserver 10.0.100.10" | sudo tee /etc/resolver/nimbusnode.org
echo "nameserver 10.0.100.10" | sudo tee /etc/resolver/nimbus.local
```

### Ubuntu / Debian

```bash
sudo cp nimbus-ca.crt /usr/local/share/ca-certificates/nimbus-ca.crt
sudo update-ca-certificates
# Verify:
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt nimbus-ca.crt
```

For DNS, either point `/etc/resolv.conf` at 10.0.100.10 or add a systemd-resolved
override per-interface (via netplan).

### iOS

1. Email or AirDrop `nimbus-ca.crt` to the device.
2. Tap the attachment → "Install Profile" appears in Settings.
3. Settings → General → VPN & Device Management → tap the profile → Install.
4. Settings → General → About → Certificate Trust Settings → toggle "Nimbus
   Internal CA" to full trust.

### Android

1. Transfer `nimbus-ca.crt` to the device.
2. Settings → Security → Encryption & credentials → Install a certificate →
   CA certificate → select the file.
3. Confirm with your device PIN.

---

## Verification

After trusting the CA, from each client:

```bash
# New Nextcloud (app-tier)
curl -sv https://cloud-app.nimbus.local/status.php 2>&1 | grep -E "SSL|HTTP|subject"
# Expect: SSL connection using TLS ... , HTTP 200, subject: CN=nimbus-alb.nimbus.local

# Legacy AIO (split-horizon — Cloudflare handles external TLS)
curl -sv https://cloud.nimbusnode.org/ 2>&1 | grep -E "SSL|issuer"
# Expect: SSL connection, issuer: CN=Nimbus Internal CA
# (You're hitting the ALB internally, not Cloudflare, so you see the self-CA cert)

# From any Nimbus VM (nimbus-dns, bastion, etc.):
curl -sv --cacert /dev/stdin https://cloud-app.nimbus.local/status.php <<'EOF'
$(terraform output -raw nimbus_ca_cert)
EOF
```

---

## How the AIO Cloudflare tunnel fits in

```
External user
    │  https://cloud.nimbusnode.org
    ▼
Cloudflare edge  (Cloudflare's own cert — trusted by all browsers)
    │  outbound tunnel
    ▼
cloudflared on AIO (192.168.1.72:port)
    │  http://localhost:11000
    ▼
AIO Apache
```

```
Internal user (Nimbus VPN / home LAN with NRPT)
    │  https://cloud.nimbusnode.org
    │  resolves to 10.0.1.10 via nimbus-dns split-horizon
    ▼
nimbus-alb:443  (Nimbus Internal CA cert — trusted after one-time import)
    │  http://10.0.10.101:11000  (nextcloud-aio HAProxy backend)
    ▼
AIO Apache
```

The two paths are completely independent. Cloudflare's cert and Nimbus Internal
CA are separate trust anchors — one for external, one for internal.

---

## AIO trusted-proxy config (one-time, not Terraform-managed)

When internal clients hit the AIO over HTTPS through the ALB, the AIO sees
plain HTTP from 10.0.1.10 (the ALB). The AIO's Nextcloud must trust the ALB
as a reverse proxy so that `overwriteprotocol = https` and
`X-Forwarded-Proto: https` headers produce correct HTTPS links:

```bash
# On the AIO admin host (192.168.1.72):
sudo docker exec -it nextcloud-aio-nextcloud \
  php /var/www/html/occ config:system:set trusted_proxies 0 --value="10.0.1.10"
sudo docker exec -it nextcloud-aio-nextcloud \
  php /var/www/html/occ config:system:set overwriteprotocol --value="https"
```

Or set `APACHE_TRUSTED_PROXIES=10.0.1.10` in the AIO mastercontainer env and
restart. The AIO web UI (https://192.168.1.72:8080) → Advanced settings has a
"Trusted Proxies" field if you prefer the GUI.

---

## Cert rotation

The CA and server cert are both set to 10 years (homelab). When you do need to rotate:

```bash
# Rotate server cert only (CA stays, clients don't need to re-import root)
cd ~/code/nimbus-infra/terraform
terraform taint tls_private_key.nimbus_alb
terraform taint tls_cert_request.nimbus_alb
terraform taint tls_locally_signed_cert.nimbus_alb
terraform apply
# This triggers a cloud-init snippet change → Proxmox rebuilds nimbus-alb
```

To rotate the CA itself (clients must re-import the new root):
```bash
terraform taint tls_private_key.nimbus_ca
terraform taint tls_self_signed_cert.nimbus_ca
# Also taint all server certs signed by the old CA
terraform taint tls_locally_signed_cert.nimbus_alb
terraform apply
terraform output -raw nimbus_ca_cert > nimbus-ca.crt
# Re-distribute nimbus-ca.crt to all clients
```
