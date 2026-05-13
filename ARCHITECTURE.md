# Nimbus Architecture — AWS Concepts, Proxmox Reality

This document walks the AWS network model from the outside in and shows exactly what plays each role in Nimbus. Use it as a study guide: when AWS docs say "attach an Internet Gateway to a VPC," you should know which Nimbus object that corresponds to.

---

## 1. Region and Availability Zone

| AWS                                  | Nimbus                                         |
|--------------------------------------|------------------------------------------------|
| Region (e.g. `us-east-1`)            | Your whole Proxmox datacenter                  |
| Availability Zone (`us-east-1a/b/c`) | A Proxmox node in the cluster                  |

> **Learning note:** AZs in AWS are physically separate datacenters with independent power/network. You can *simulate* HA in Nimbus by spreading VMs across multiple Proxmox nodes and using Ceph or ZFS replication. A single-node lab is equivalent to a single-AZ deployment — fine for learning, don't run prod on it.

---

## 2. VPC

**AWS:** An isolated IPv4/IPv6 network you own inside a region. Defined by a CIDR block. Nothing crosses the VPC edge without explicit gateways.

**Nimbus:** A Proxmox **SDN Zone** of type `simple`, named `nimbus-vpc`, with CIDR `10.0.0.0/16`.

```
Datacenter → SDN → Zones → Add → Simple
  ID:     nimbus-vpc
  Nodes:  <your node(s)>
  IPAM:   pve
```

The Zone is the isolation boundary. Subnets inside it route to each other (that's the VPC router, implicit in AWS). Subnets outside it have no path in/out unless you build one.

---

## 3. Subnet

**AWS:** A slice of the VPC CIDR, bound to one AZ, marked "public" or "private" depending on its route table.

**Nimbus:** A Proxmox **VNet** with a **subnet** beneath it.

| Name             | CIDR           | Tier      | "Public" (has route to IGW)? |
|------------------|----------------|-----------|------------------------------|
| `nimbus-public`  | 10.0.1.0/24    | Public    | ✅                           |
| `nimbus-app`     | 10.0.10.0/24   | Private   | ❌ (NAT only)                |
| `nimbus-data`    | 10.0.20.0/24   | Private   | ❌ (no outbound)             |
| `nimbus-mgmt`    | 10.0.100.0/24  | Mgmt      | ✅ (bastion access)          |

Rule of thumb: a subnet is "public" when its default route points at the Internet Gateway; "private" when it points at a NAT Gateway or nothing.

---

## 4. Internet Gateway & NAT Gateway

**AWS:**
- **Internet Gateway (IGW):** Horizontally-scaled, redundant VPC edge. Allows bidirectional internet traffic for any resource with a public IP.
- **NAT Gateway:** Allows private subnets to reach the internet outbound, but blocks unsolicited inbound.

**Nimbus:** Both roles are played by a single **pfSense VM** acting as the VPC edge router.

```
                  vmbr0 (real LAN / WAN)
                        │
                   ┌────┴─────┐
                   │ pfSense  │   = IGW + NAT + route tables
                   └────┬─────┘
          ┌────────┬────┴────┬──────────┐
          │        │         │          │
     nimbus-public app       data      mgmt
```

pfSense interfaces:
- `WAN` → `vmbr0` (DHCP or static from your real LAN)
- `LAN_PUB` → `nimbus-public` (10.0.1.1/24)
- `LAN_APP` → `nimbus-app` (10.0.10.1/24)
- `LAN_DATA` → `nimbus-data` (10.0.20.1/24)
- `LAN_MGMT` → `nimbus-mgmt` (10.0.100.1/24)

**NAT rule (outbound):** Hybrid outbound NAT, map `10.0.0.0/16` → WAN.
**Firewall (inbound WAN):** Default deny. External traffic arrives via Cloudflare Tunnel (cloudflared on nimbus-alb) — no public ports exposed on pfSense.

---

## 5. Route tables

**AWS:** Per-subnet route tables. Public subnets have `0.0.0.0/0 → igw-xxx`; private subnets have `0.0.0.0/0 → nat-xxx` or no default route.

**Nimbus:** pfSense handles all routing. Each VNet's gateway is the pfSense interface on that VNet. pfSense's own default route points at your real LAN gateway (its "IGW").

Private subnets simply don't get a route to `0.0.0.0/0` except through NAT — which is exactly how AWS private subnets work.

---

## 6. Security Groups vs Network ACLs

**AWS:**
- **Security Group (SG):** Stateful, attached to an ENI, default-deny inbound + default-allow outbound.
- **NACL:** Stateless, attached to a subnet, evaluated in rule order, default-allow.

**Nimbus:**
- **SG equivalent:** UFW on each VM (enforced in cloud-init), plus Proxmox firewall at the **VM level**. Stateful. UFW rules are per-VM and scoped to the minimum required ports.
- **NACL equivalent:** Proxmox firewall at the **datacenter or node level**. Useful for "block this bad CIDR everywhere, no exceptions."

Current UFW policy on each VM:
| VM               | Allowed inbound                                                |
|------------------|----------------------------------------------------------------|
| nimbus-alb       | :80/:443 from VPC + cloudflared network; :8404/:22 from mgmt   |
| nimbus-cloud-01  | :80 from ALB only; :22 from mgmt                               |
| nimbus-rds       | :5432 from VPC; :22 from mgmt                                  |
| nimbus-s3        | :9000 from VPC; :9001 from mgmt/home LAN; :22 from mgmt        |
| nimbus-dns       | :53 from VPC; :8081 API from mgmt; :22 from mgmt               |
| nimbus-mon       | :3000/:9090 from mgmt; :3100 from VPC; :22 from mgmt           |
| nimbus-iam       | :8443 from ALB + mgmt; :22 from mgmt                           |
| nimbus-vault     | :8200/:8201 from VPC/operator LAN; :22 from mgmt               |
| nimbus-bastion   | :22 from home/office LAN                                       |

Remote administration from outside the LAN is gated by Tailscale. A Proxmox
LXC advertises `10.0.0.0/16` and `192.168.1.0/24` as subnet routes and is
tagged `tag:nimbus-subnet-router`; `.github/tailscale-acl.hujson` limits who
can use that path. The VM-level UFW rules above still apply after Tailscale
admits the route.

---

## 7. EC2 ↔ Proxmox VM

**AWS:** You launch an instance from an AMI with a user-data script; it boots with cloud-init, gets an IP from the subnet, comes up with your SSH key.

**Nimbus:** Identical flow.
1. Build a template VM (`vmid 9000`) from the Ubuntu 24.04 cloud image — this is your AMI.
2. Terraform clones it for each new instance and injects cloud-init user-data.
3. VM boots, gets static IP from cloud-init netplan config, cloud-init runs, SSH key is in `~/.ssh/authorized_keys`.

Each service lives in its own Terraform module under `terraform/modules/` with a `user-data.yml.tftpl` that installs and configures the service on first boot.

---

## 8. Storage

| AWS      | Nimbus                                      |
|----------|---------------------------------------------|
| EBS      | Proxmox disk on ZFS / Ceph / LVM-thin       |
| EBS snap | Proxmox snapshot                            |
| EFS      | NFS share from a dedicated VM or TrueNAS    |
| S3       | MinIO (`nimbus-s3`, 10.0.20.101)            |

**nimbus-s3** runs MinIO single-node on a dedicated data disk. Nextcloud uses it as Primary Object Storage — all user files are stored as S3 objects, not on local disk. This mirrors the EFS-less S3-native pattern common in AWS-hosted Nextcloud deployments.

Backups: `pg-backup.timer` on nimbus-rds runs a nightly `pg_dumpall`, stores a local copy under `/var/backups/postgres`, and pushes the compressed dump to the `pg-backups` bucket on nimbus-s3 through a scoped MinIO service account. The bucket is object-lock-enabled with default `COMPLIANCE 30d` retention; Phase 8 migrated the live bucket because object lock must exist at bucket creation time.

MinIO operational rules:
- Use `/usr/local/bin/mc.minio --config-dir /root/.mc.minio`; do not rely on `/usr/bin/mc`, which can be Midnight Commander.
- The S3 API is VPC-only in Terraform. Console admin is mgmt/home-LAN scoped and SSO uses Keycloak group names as MinIO policy names.

---

## 9. RDS

**nimbus-rds** (`10.0.20.103`) runs PostgreSQL 16 on Ubuntu 24.04 in the data subnet.

- Nextcloud's database lives here (`nextcloud` DB, `nextcloud` user).
- Keycloak and PowerDNS also store their databases here; no second Postgres VM is used.
- Backups: `pg-backup.timer` pushes nightly dumps to MinIO `pg-backups`.
- Graduate path: **CloudNativePG** on a small k3s cluster for real HA + PITR.

---

## 10. Route 53

**nimbus-dns** (`10.0.100.10`) runs **PowerDNS** with the `gpgsql` backend (authoritative) and the recursor for `.` resolution.

Phase 8 moved authoritative DNS metadata from SQLite to PostgreSQL on
nimbus-rds. Terraform now manages records against PowerDNS without the old
single-writer SQLite apply bottleneck.

Zones managed by Terraform via the `pan-net/powerdns` provider:

| Zone             | Purpose                                                  |
|------------------|----------------------------------------------------------|
| `nimbus.local.`  | Internal A records for every VM; split-horizon internal  |
| `nimbusnode.org.`| Internal override for the public domain (split-horizon)  |

Split-horizon for `cloud.nimbusnode.org`, `aio.nimbusnode.org`, and
`auth.nimbusnode.org`: internal clients resolve to `nimbus-alb` (10.0.1.10);
external clients resolve via Cloudflare's public DNS (CNAMEs to the Cloudflare
Tunnel).

---

## 11. Load Balancer

**nimbus-alb** (`10.0.1.10`) runs **HAProxy 2.8** in the public subnet.

**Frontends:**
- `:80` — plain HTTP. Used by cloudflared (Cloudflare Tunnel) which runs on this host. Backends are selected by `Host` header.
- `:443` — HTTPS with SNI cert selection from `/etc/haproxy/certs/`. HAProxy picks the right cert automatically based on SNI. Backends share the same ACLs as :80.

**TLS certificates:**
- `*.nimbusnode.org` — Let's Encrypt wildcard, issued via acme.sh + Cloudflare DNS-01. Auto-renews via deploy hook.
- `*.nimbus.local` — Internal wildcard from Nimbus step-ca (valid 90 days, renew with `step ca renew`).

**Backends:**
| Backend             | Host match                                        | Upstream               |
|---------------------|---------------------------------------------------|------------------------|
| `nextcloud-aio`     | `cloud.nimbus.local`, `aio.nimbusnode.org`        | 10.0.10.101:11000      |
| `nextcloud-cloud`   | `cloud-app.nimbus.local`, `cloud.nimbusnode.org`  | 10.0.10.102:80         |
| `grafana`           | `mon.nimbus.local`                                | 10.0.100.20:3000       |
| `keycloak`          | `auth.nimbus.local`, `auth.nimbusnode.org`        | 10.0.100.30:8443       |

**Cloudflare Tunnel:** cloudflared runs on nimbus-alb as a systemd service (token-based, no config.yml). Public hostnames in Zero Trust dashboard:
- `cloud.nimbusnode.org` → `http://127.0.0.1:80` (HAProxy HTTP frontend, routes via host ACL)
- `aio.nimbusnode.org`   → `http://127.0.0.1:80` (same ALB listener, different HAProxy ACL match)
- `auth.nimbusnode.org`  → `http://127.0.0.1:80` (same ALB listener, Keycloak backend)

---

## 12. Nextcloud (Primary App)

**nimbus-cloud-01** (`10.0.10.102`) runs **Nextcloud 30.0.17** in the app subnet.

Stack: nginx → PHP-FPM 8.3 → PostgreSQL (nimbus-rds) + MinIO (nimbus-s3 as S3 Primary Object Storage).

Public URL: `https://cloud.nimbusnode.org` (Cloudflare Tunnel → nimbus-cloud-01).
Internal URL: `https://cloud-app.nimbus.local` (HAProxy :443 → nimbus-cloud-01).

Key config decisions:
- MinIO uses path-style addressing (`use_path_style = true`) — MinIO doesn't support virtual-hosted-style URLs.
- MinIO region is `us-east-1` (required non-empty by Nextcloud's S3 client; ignored by MinIO).
- `overwriteprotocol = https` and `overwritehost = cloud.nimbusnode.org` so links generated server-side use the correct public URL even though nginx only speaks HTTP.
- Trusted proxies include the ALB IP and all Cloudflare IPv4 ranges so `X-Forwarded-For` is respected.

---

## 13. Bastion

**nimbus-bastion** (`10.0.1.20`) is a lightweight Ubuntu VM in the public subnet used as a DMZ jumpbox. Primarily useful for reaching the pfSense WebConfigurator via SSH tunnel from your workstation without opening pfSense to the internet.

```bash
# Tunnel pfSense GUI to localhost:8443
ssh -L 8443:10.0.1.1:443 nimbus@10.0.1.20
# Then browse to https://localhost:8443
```

---

## 14. Internal CA

Nimbus runs a **step-ca** internal Certificate Authority for TLS on `*.nimbus.local` services.

- CA cert: `terraform/nimbus-ca.crt` (import into browser / system trust store for warning-free internal HTTPS)
- Server cert: `*.nimbus.local` wildcard, 90-day validity, deployed to HAProxy
- Renewal: manual for now — `step ca renew /etc/haproxy/certs/wildcard-nimbus-local.pem /etc/haproxy/certs/wildcard-nimbus-local.key` then reload haproxy

---

## 15. Phase 4 — Load Balancer Build Guide

Phase 4 introduces the ALB tier and routes internal traffic through it before any public Nextcloud work starts. The sub-phases are ordered so each one is independently verifiable before you move on.

| Sub-phase | What                          | Complexity | Why                                                             |
|-----------|-------------------------------|------------|-----------------------------------------------------------------|
| 4a        | Strip and re-enable files     | Medium     | Restructuring TF layout + the SG→UFW trade-off needs a decision |
| 4b        | Build nimbus-alb VM           | Medium     | Writing the HAProxy cloud-init module from scratch              |
| 4c        | Route cloud.nimbus.local → ALB | Easy      | Config change + one DNS record; same pattern as before          |
| 4d        | Cleanup                       | Trivial    | Verify, document, tag                                           |

### 4a — Strip and re-enable files (Medium)

`compute.tf` was a catch-all that grew unwieldy. Split it into purpose-scoped files:

- `alb.tf` — HAProxy load balancer
- `bastion.tf` — DMZ jumpbox
- `web.tf` — app-tier web VMs (placeholder for future services)
- `mon.tf` — observability VM (`nimbus-mon`, deployed in Phase 6)

The more important change is **deleting the Proxmox firewall security group resources from `network.tf`** and relying on UFW in cloud-init instead. Why:

- Proxmox firewall security groups require the firewall to be enabled at the datacenter level, which has side-effects on other VMs and Proxmox itself.
- UFW rules live in the same cloud-init template as the service they protect — they travel with the VM and are visible in the repo.
- This matches how AWS shops often handle instance-level firewall rules separately from VPC-level ACLs.

Also fix the MinIO module default data disk size during this phase while the codebase is in motion — cheaper to do it now than to come back later when a running VM is attached.

### 4b — Build nimbus-alb VM (Medium)

Write `modules/haproxy/` from scratch. The module's cloud-init file installs HAProxy, writes `haproxy.cfg`, and enables it on boot. Apply with a target so only this resource is created:

```bash
terraform apply -target=module.nimbus_alb
```

Verify before touching DNS:

```bash
curl -v http://10.0.1.10/
# Expect: HAProxy stub 503 (no backend yet — that's correct at this stage)
```

The cloud-init approach means the config is in the repo and version-controlled. The alternative (SSH in and write the config manually) would be faster once but untrackable.

### 4c — Route cloud.nimbus.local through ALB (Easy)

Two changes, both low-risk:

1. **HAProxy config:** add a frontend on `:80` with an ACL matching `Host: cloud.nimbus.local`, pointing to the AIO backend at `10.0.10.101:11000`.
2. **PowerDNS record:** change `cloud.nimbus.local` A record from `10.0.10.101` (AIO direct) to `10.0.1.10` (ALB).

Apply the DNS record via Terraform (`terraform apply` — only the `powerdns_record` resource changes). Verify with:

```bash
curl -H "Host: cloud.nimbus.local" http://10.0.1.10/
# Expect: AIO Nextcloud content proxied through HAProxy
```

This was the "put the load balancer in front without breaking anything" step. At that point in Phase 4, Cloudflare still pointed at AIO directly, so external traffic was unaffected. The current Cloudflare Tunnel host routing is documented in §11.

### 4d — Cleanup (Trivial)

- Confirm split-horizon works: internal `cloud.nimbus.local` resolves to ALB while current public hostnames route through the nimbus-alb Cloudflare Tunnel.
- Document the traffic flow (see ARCHITECTURE.md §11).
- `git tag phase-4-complete && git push --tags`

---

## 16. Phase 5 — Data + App Tier Build Guide

Phase 5 is where the abstract AWS analogies become concrete. The sub-phases below are ordered by dependency, not difficulty. Do them in sequence.

| Sub-phase | What                  | Complexity | Why                                                               |
|-----------|-----------------------|------------|-------------------------------------------------------------------|
| 5a        | PostgreSQL module     | Medium     | DB config is fiddly — pg_hba, listen_addresses, backup wiring     |
| 5b        | MinIO module          | Easy       | Single-node install is simple; buckets + service accounts are it  |
| 5c        | Nextcloud app         | Hard       | `occ maintenance:install` automation via cloud-init is the tricky one |
| 5d        | ALB + DNS wiring      | Easy       | Same HAProxy backend pattern as Phase 4b; DNS record is one line  |
| 5e        | Cutover               | Trivial    | A DNS flip — `cloud.nimbusnode.org` CNAME to the Cloudflare Tunnel|

### 5a — PostgreSQL module (Medium)

The hard parts are not the install — `apt install postgresql-16` is one line. The fiddly parts:

- `pg_hba.conf`: must allow connections from the app subnet (`10.0.10.0/24`) with `scram-sha-256`, not just `localhost`. Cloud-init rewrites this file; ordering matters because postgres reads it top-to-bottom.
- `listen_addresses = '*'`: default is `localhost` only. Must be changed before any remote client can connect.
- `pg_isready` loop in Nextcloud cloud-init: the app VM boots in parallel with the DB VM. The install script must poll until the DB is accepting connections before running `occ maintenance:install`.
- `pg-backup.timer`: runs a nightly `pg_dumpall`, keeps a local compressed copy, and pushes to the MinIO `pg-backups` bucket with `/usr/local/bin/mc.minio`.

### 5b — MinIO module (Easy)

Single-node MinIO on a dedicated data disk (`/dev/sdb` → mounted at `/data/minio`). The install is a binary download + systemd unit. The only gotchas:

- Install the upstream MinIO client as `/usr/local/bin/mc.minio`, not `mc`, to avoid collision with Midnight Commander.
- Create the Nextcloud bucket and IAM-style user (access key + secret) before Nextcloud boots, or the objectstore init fails.
- Create `pg-backups` with `--with-lock` at bucket creation time; object lock cannot be enabled later on an existing bucket.

### 5c — Nextcloud app (Hard)

The difficulty is fully automating `occ maintenance:install` in a cloud-init script that runs once at first boot, against a remote DB and a remote S3 store. Things that go wrong:

- **Backslash escaping in PHP class names.** `\OC\Files\ObjectStore\S3` must arrive in `config.php` with single backslashes. Shell quoting and YAML escaping interact — use single-quoted shell strings (`'\OC\Files\ObjectStore\S3'`) in the `occ config:system:set` call.
- **MinIO path-style vs virtual-hosted.** Nextcloud defaults to virtual-hosted S3 URLs (`bucket.host`). MinIO requires path-style (`host/bucket`). Set `use_path_style = true` or every object operation returns 404.
- **Heredoc at column 0 breaks YAML.** A `<<EOF` whose terminator sits at column 0 closes the YAML block scalar early. cloud-init silently discards the rest of the file. Use one-liners instead of heredocs inside YAML `|` blocks.
- **MTU 1420.** The pfSense WAN adds overhead. Without MTU clamping, large downloads (Nextcloud tarball, backup pushes) hit ICMP fragmentation-needed and stall. Set `mtu: 1420` in netplan on every VM.

### 5d — ALB + DNS wiring (Easy)

Add a backend block to the HAProxy module for `nimbus-cloud-01`, add an ACL for the hostname, add a PowerDNS A record. This is identical to what Phase 4b did for the AIO backend — copy, tweak the IP and host header, apply.

### 5e — Cutover (Trivial)

Update the Cloudflare CNAME for `cloud.nimbusnode.org` to point at the new Cloudflare Tunnel (running on nimbus-alb) instead of the old AIO tunnel. Cloudflare propagates in under a minute. The old AIO backend stays reachable internally at `cloud.nimbus.local` for rollback.

---

## 17. Observability

| AWS                | Nimbus equivalent                                   | Status |
|--------------------|-----------------------------------------------------|--------|
| CloudWatch Metrics | Prometheus scraping `node-exporter` on every VM     | ✅ Phase 6 |
| CloudWatch Logs    | Loki + Promtail (all VMs ship `/var/log/syslog`)    | ✅ Phase 6 |
| CloudWatch Dashboards | Grafana at `mon.nimbus.local` (ALB-proxied)      | ✅ Phase 6 |
| CloudWatch Alarms  | Prometheus Alertmanager                             | 🔲 Planned |
| X-Ray              | Tempo or Jaeger (optional)                          | 🔲 Planned |
| CloudTrail         | Proxmox audit log shipped into Loki                 | 🔲 Planned |

**Deployed (Phase 6):** `nimbus-mon` runs on `10.0.100.20` (mgmt subnet).

- **Prometheus** scrapes `node-exporter` (port 9100) from all Nimbus VMs every 15 s.
- **Loki** receives log streams from **Promtail** agents on each VM.
- **Grafana** at `mon.nimbus.local:3000` — also reachable via the ALB HTTPS frontend on the same hostname.
- Every VM module provisions `node-exporter` and `Promtail` via cloud-init at boot. Phase 8 fixed log-read permissions so syslog, auth logs, and Grafana logs continue shipping after rebuilds.
- Grafana 13 provisioning loads deterministic Prometheus/Loki data-source UIDs and the repo-managed `Nimbus` dashboard folder on rebuild.

---

## 18. IAM

| AWS                         | Nimbus equivalent                                      | Status |
|-----------------------------|--------------------------------------------------------|--------|
| Cognito / IAM Identity Center | Keycloak (`nimbus-iam`, 10.0.100.30)                | ✅ Phase 7 |
| Secrets Manager             | Vault KV v2 (`nimbus-vault`, 10.0.100.40)             | ✅ Phase 7 |
| STS / short-lived credentials | Vault database secrets engine for Nextcloud DB users | ✅ Phase 7/8 |

**Keycloak** is the OIDC identity provider for Nextcloud, Grafana, MinIO console,
and Vault. Terraform owns the `nimbus` realm, clients, protocol mappers, groups,
and seed users. The public hostname is `auth.nimbusnode.org` through Cloudflare
Tunnel; internal ALB access is `auth.nimbus.local`.

**Vault** is internal-only at `vault.nimbus.local:8200`. It uses integrated Raft
storage, Shamir 3-of-5 unseal, file audit logging shipped by Promtail, KV v2 for
static secrets, OIDC admin auth through Keycloak, and the database secrets engine
for Nextcloud's dynamic PostgreSQL credentials. Operators reach it through the
mgmt subnet or Tailscale; it has no Cloudflare Tunnel.

Phase 8 hardened the IAM edge cases: Nextcloud Vault Agent runtime, the dynamic
DB role inheritance, Keycloak/OIDC recovery runbooks, MinIO group-claim policy
mapping, and Tailscale ACL GitOps for remote admin access.
