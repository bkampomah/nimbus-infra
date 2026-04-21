# docs/nextcloud-cloudflare-tunnel.md

## How traffic flows

```
user browser
    │   https://nimbuscloud.org
    ▼
Cloudflare edge (TLS termination, WAF, caching)
    │   outbound-initiated QUIC tunnel
    ▼
cloudflared  (systemd unit on nimbus-alb)
    │   http://127.0.0.1:8080
    ▼
HAProxy      (nimbus-alb, 127.0.0.1:8080)
    │   http://10.0.10.20:80
    ▼
nginx + PHP-FPM  (nimbus-cloud-01)
    │
    ├─ postgres://nimbus-rds:5432    (Nextcloud metadata)
    └─ s3://nimbus-s3:9000           (user files)
```

Key properties you get from this topology:

- **No inbound ports open on pfSense.** cloudflared makes a persistent
  outbound connection; the tunnel is the only ingress. Your home IP
  stays unpublished.
- **TLS is handled upstream.** Every hop past Cloudflare is plain HTTP
  on private networks. No Let's Encrypt on the ALB, no cert renewal
  scripts.
- **Cloudflare is your WAF and rate limiter.** Turn on Bot Fight Mode
  and a WAF rule for `/remote.php/dav` in the Zero Trust dashboard.
- **The ALB still matters.** When you add nimbus-cloud-02, HAProxy
  load-balances between them. Cloudflare sees a single stable backend.

---

## One-time Cloudflare setup

1. **Zero Trust dashboard** → Networks → Tunnels → **Create a tunnel**.
2. Connector type: **Cloudflared**. Name it `nimbus-alb`. Save.
3. On the next screen you'll see a long `cloudflared service install <TOKEN>`
   command. Copy the token only — the string after `install`.
4. Paste the token into `terraform.tfvars` as `cloudflare_tunnel_token`.
5. On the **Public Hostnames** tab of the tunnel, add a route:
   - Subdomain: *(blank)* or `www`
   - Domain: `nimbuscloud.org`
   - Service: `HTTP` → `127.0.0.1:8080`
   - *Additional application settings → HTTP settings*:
     - HTTP Host Header: `nimbuscloud.org`
     - Origin Server Name: `nimbuscloud.org`
     - Disable Chunked Encoding: **off**
     - **Enable** HTTP/2 connection to origin (cloudflared → HAProxy)

That's the full Cloudflare-side config. DNS is auto-managed — Cloudflare
creates a CNAME from `nimbuscloud.org` to `<tunnel-uuid>.cfargotunnel.com`
when you add the hostname.

---

## Install cloudflared on nimbus-alb

SSH in as `Nimbus` and run:

```bash
# Add Cloudflare's apt repo
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
  | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] \
  https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/cloudflared.list

sudo apt-get update
sudo apt-get install -y cloudflared haproxy

# Install as a systemd service using the token from terraform.tfvars
# CHANGE_ME: paste your tunnel token
sudo cloudflared service install eyJhIjoiCHANGE_ME...

sudo systemctl enable --now cloudflared
sudo systemctl status cloudflared        # should be active + "Registered tunnel connection"
```

Then drop the HAProxy config from this repo onto the ALB:

```bash
sudo cp haproxy/nextcloud.cfg /etc/haproxy/haproxy.cfg
# Fill in the real backend IP from `terraform output nextcloud_backend_target`
sudoedit /etc/haproxy/haproxy.cfg

sudo haproxy -c -f /etc/haproxy/haproxy.cfg   # syntax check
sudo systemctl enable --now haproxy
sudo systemctl reload haproxy
```

---

## PowerDNS — internal-only zone

Cloudflare handles `nimbuscloud.org`. PowerDNS still gets `nimbus.local`
for internal service discovery; nothing in it needs to be public.

```zone
$ORIGIN nimbus.local.
$TTL 300

nimbus-alb      IN A    10.0.1.10     ; CHANGE_ME
nimbus-rds      IN A    10.0.20.10    ; CHANGE_ME — terraform output nimbus_rds_host
nimbus-s3       IN A    10.0.20.20    ; CHANGE_ME
nimbus-cloud-01 IN A    10.0.10.20    ; CHANGE_ME
cloud           IN CNAME nimbus-alb.nimbus.local.  ; optional internal alias
```

---

## pfSense — what you DON'T need

Skip all of these with a Cloudflare Tunnel:

- ❌ WAN port-forward 443 → ALB
- ❌ Firewall WAN rule allowing 443 inbound
- ❌ Public DNS A record pointing at your home IP
- ❌ Let's Encrypt on the ALB
- ❌ Opening port 80 for ACME challenges

What you still need:

- ✅ Outbound NAT from `10.0.0.0/16` so cloudflared can reach Cloudflare
- ✅ DNS resolution for VMs (they need to resolve
  `update.cloudflare.com`, `download.nextcloud.com`, etc.)

---

## Verify end-to-end

```bash
# From your workstation:
curl -I https://nimbuscloud.org/status.php
# Expect: HTTP/2 200
#         server: cloudflare
#         cf-ray: <some-id>
#         …and a JSON body with "installed":true

# On nimbus-alb:
sudo systemctl status cloudflared      # "Registered tunnel connection"
curl -sI http://127.0.0.1:8080/status.php  # proves HAProxy → Nextcloud works

# On nimbus-cloud-01:
sudo -u www-data php /var/www/nextcloud/occ config:system:get overwriteprotocol
# → https
sudo -u www-data php /var/www/nextcloud/occ config:system:get trusted_proxies
# → array with your public subnet + Cloudflare CIDRs

# Confirm real client IP is being captured (not the ALB or 127.0.0.1):
sudo tail -f /var/www/nextcloud/data/nextcloud.log  # on nimbus-cloud-01
# login from your browser, watch the "remoteAddr" field — should be your
# real public IP, not 10.0.1.10 and not 127.0.0.1.
```

If `remoteAddr` shows as the ALB's IP, either Cloudflare's IP ranges
aren't in `trusted_proxies` or nginx isn't reading `CF-Connecting-IP`
(check `/etc/nginx/sites-available/nextcloud` on nimbus-cloud-01).

---

## Security notes

- **Lock HAProxy to loopback.** The `bind 127.0.0.1:8080` line is load-
  bearing. If you change it to `bind *:8080`, anything that can reach
  the ALB on port 8080 can bypass Cloudflare and hit Nextcloud directly
  without the WAF. The `sg-nimbus-alb` Proxmox security group doesn't
  allow 8080 inbound, but defense in depth matters.

- **Consider Cloudflare Access.** For admin-only paths (`/settings/admin`),
  put a Cloudflare Access policy in front of them — email OTP or SSO,
  enforced at the edge before traffic ever enters the tunnel. This is
  the closest analog to "AWS Cognito + ALB authentication rules."

- **Rotate the tunnel token.** If the token leaks, anyone can impersonate
  your connector. In Zero Trust → Tunnels → `nimbus-alb` → Refresh token,
  then redeploy cloudflared. Treat it like an IAM access key.

- **Keep Cloudflare IP ranges current.** The list in
  `variables.tf → cloudflare_ip_ranges` is a snapshot. Refresh quarterly
  from https://www.cloudflare.com/ips-v4/ — stale ranges mean new
  Cloudflare edge nodes stop being trusted and client IPs revert to
  looking like they came from the ALB.
