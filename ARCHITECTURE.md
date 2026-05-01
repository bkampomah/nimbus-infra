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
| VM               | Allowed inbound                                      |
|------------------|------------------------------------------------------|
| nimbus-alb       | :80/:443 from VPC; :8404 stats from mgmt; :22 mgmt  |
| nimbus-cloud-01  | :80 from ALB only; :22 from mgmt                    |
| nimbus-rds       | :5432 from app subnet; :22 from mgmt                |
| nimbus-s3        | :9000/:9001 from app+data; :22 from mgmt            |
| nimbus-dns       | :53 from VPC; :8081 API from mgmt; :22 from mgmt   |
| nimbus-bastion   | :22 from home/office LAN                            |

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

Backups: `pgbackrest` on nimbus-rds pushes PostgreSQL WAL and base backups to a dedicated MinIO bucket on nimbus-s3.

---

## 9. RDS

**nimbus-rds** (`10.0.20.103`) runs PostgreSQL 16 on Ubuntu 24.04 in the data subnet.

- Nextcloud's database lives here (`nextcloud` DB, `nextcloud` user).
- Backups: `pgbackrest` pushes to MinIO.
- Graduate path: **CloudNativePG** on a small k3s cluster for real HA + PITR.

---

## 10. Route 53

**nimbus-dns** (`10.0.100.10`) runs **PowerDNS** with the `gpgsql` backend (authoritative) and the recursor for `.` resolution.

Zones managed by Terraform via the `pan-net/powerdns` provider:

| Zone             | Purpose                                                  |
|------------------|----------------------------------------------------------|
| `nimbus.local.`  | Internal A records for every VM; split-horizon internal  |
| `nimbusnode.org.`| Internal override for the public domain (split-horizon)  |

Split-horizon for `cloud.nimbusnode.org`: internal clients resolve to `nimbus-alb` (10.0.1.10); external clients resolve via Cloudflare's public DNS (CNAME to the Cloudflare Tunnel).

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
| Backend             | Host match                              | Upstream               |
|---------------------|-----------------------------------------|------------------------|
| `nextcloud-aio`     | `cloud.nimbus.local`                    | 10.0.10.101:11000      |
| `nextcloud-cloud`   | `cloud-app.nimbus.local`, `cloud.nimbusnode.org` | 10.0.10.102:80 |

**Cloudflare Tunnel:** cloudflared runs on nimbus-alb as a systemd service, connecting to the Cloudflare edge over HTTP/2 (TCP, avoids pfSense QUIC/UDP timeouts). The tunnel routes `cloud.nimbusnode.org` → `http://10.0.10.102:80` directly, bypassing HAProxy for external traffic.

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
- `mon.tf` — observability VM (placeholder)

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

This is the "put the load balancer in front without breaking anything" step. The Cloudflare Tunnel still points at AIO directly at this point — external traffic is unaffected.

### 4d — Cleanup (Trivial)

- Confirm split-horizon still works: internal `cloud.nimbus.local` resolves to ALB; Cloudflare external traffic still reaches AIO via its own tunnel.
- Document the traffic flow (see ARCHITECTURE.md §11).
- `git tag phase-4-complete && git push --tags`

---

## 16. Phase 5 — Data + App Tier Build Guide

Phase 5 is where the abstract AWS analogies become concrete. The sub-phases below are ordered by dependency, not difficulty. Do them in sequence.

| Sub-phase | What                  | Complexity | Why                                                               |
|-----------|-----------------------|------------|-------------------------------------------------------------------|
| 5a        | PostgreSQL module     | Medium     | DB config is fiddly — pg_hba, listen_addresses, pgbackrest wiring |
| 5b        | MinIO module          | Easy       | Single-node install is simple; mc alias + bucket creation is it   |
| 5c        | Nextcloud app         | Hard       | `occ maintenance:install` automation via cloud-init is the tricky one |
| 5d        | ALB + DNS wiring      | Easy       | Same HAProxy backend pattern as Phase 4b; DNS record is one line  |
| 5e        | Cutover               | Trivial    | A DNS flip — `cloud.nimbusnode.org` CNAME to the Cloudflare Tunnel|

### 5a — PostgreSQL module (Medium)

The hard parts are not the install — `apt install postgresql-16` is one line. The fiddly parts:

- `pg_hba.conf`: must allow connections from the app subnet (`10.0.10.0/24`) with `scram-sha-256`, not just `localhost`. Cloud-init rewrites this file; ordering matters because postgres reads it top-to-bottom.
- `listen_addresses = '*'`: default is `localhost` only. Must be changed before any remote client can connect.
- `pg_isready` loop in Nextcloud cloud-init: the app VM boots in parallel with the DB VM. The install script must poll until the DB is accepting connections before running `occ maintenance:install`.
- pgbackrest: requires an S3-compatible endpoint (MinIO), a stanza, and a WAL archive command in `postgresql.conf`. Set this up before the DB has any real data.

### 5b — MinIO module (Easy)

Single-node MinIO on a dedicated data disk (`/dev/sdb` → mounted at `/data/minio`). The install is a binary download + systemd unit. The only gotchas:

- The `mc` CLI is packaged as `mcli` in Ubuntu 24.04 apt repos (conflicts with Midnight Commander). Install `mcli`, not `mc`.
- Create the Nextcloud bucket and IAM-style user (access key + secret) before Nextcloud boots, or the objectstore init fails.

### 5c — Nextcloud app (Hard)

The difficulty is fully automating `occ maintenance:install` in a cloud-init script that runs once at first boot, against a remote DB and a remote S3 store. Things that go wrong:

- **Backslash escaping in PHP class names.** `\OC\Files\ObjectStore\S3` must arrive in `config.php` with single backslashes. Shell quoting and YAML escaping interact — use single-quoted shell strings (`'\OC\Files\ObjectStore\S3'`) in the `occ config:system:set` call.
- **MinIO path-style vs virtual-hosted.** Nextcloud defaults to virtual-hosted S3 URLs (`bucket.host`). MinIO requires path-style (`host/bucket`). Set `use_path_style = true` or every object operation returns 404.
- **Heredoc at column 0 breaks YAML.** A `<<EOF` whose terminator sits at column 0 closes the YAML block scalar early. cloud-init silently discards the rest of the file. Use one-liners instead of heredocs inside YAML `|` blocks.
- **MTU 1420.** The pfSense WAN adds overhead. Without MTU clamping, large downloads (Nextcloud tarball, pgbackrest base backups) hit ICMP fragmentation-needed and stall. Set `mtu: 1420` in netplan on every VM.

### 5d — ALB + DNS wiring (Easy)

Add a backend block to the HAProxy module for `nimbus-cloud-01`, add an ACL for the hostname, add a PowerDNS A record. This is identical to what Phase 4b did for the AIO backend — copy, tweak the IP and host header, apply.

### 5e — Cutover (Trivial)

Update the Cloudflare CNAME for `cloud.nimbusnode.org` to point at the new Cloudflare Tunnel (running on nimbus-alb) instead of the old AIO tunnel. Cloudflare propagates in under a minute. The old AIO backend stays reachable internally at `cloud.nimbus.local` for rollback.

---

## 17. Observability

| AWS              | Nimbus (planned)                            |
|------------------|---------------------------------------------|
| CloudWatch Metrics | Prometheus scraping `node-exporter`       |
| CloudWatch Logs    | Loki + Promtail                           |
| CloudWatch Alarms  | Prometheus Alertmanager                   |
| X-Ray              | Tempo or Jaeger (optional)                |
| CloudTrail         | Proxmox audit log shipped into Loki       |

Not yet deployed. Planned for a dedicated `nimbus-mon` VM in the mgmt subnet.

---

## 18. IAM

Planned: **Keycloak** for users/groups/roles + OIDC, and **HashiCorp Vault** for secrets/dynamic DB creds. Together they're the closest FOSS analog to IAM + Secrets Manager + STS.

This is the last phase to tackle — it's the most conceptually loaded piece and easier once the rest of the stack is concrete.
