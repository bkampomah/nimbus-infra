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
**Firewall (inbound WAN):** Default deny, then port-forward 80/443 → `nimbus-alb`.

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
- **SG equivalent:** Proxmox firewall at the **VM level** (`Datacenter → VM → Firewall`). Stateful. Use **security groups** (yes, Proxmox literally calls them that) to reuse rule sets across VMs — e.g. `sg-web`, `sg-db`, `sg-ssh-from-bastion`.
- **NACL equivalent:** Proxmox firewall at the **datacenter or node level**. Useful for "block this bad CIDR everywhere, no exceptions."

Example security groups for Nimbus:

| SG name             | Purpose                      | Inbound rules                              |
|---------------------|------------------------------|--------------------------------------------|
| `sg-nimbus-web`     | Attached to web/api VMs      | 80,443 from `sg-nimbus-alb`                |
| `sg-nimbus-alb`     | Attached to load balancer    | 80,443 from `0.0.0.0/0`                    |
| `sg-nimbus-db`      | Attached to nimbus-rds       | 5432 from `sg-nimbus-web`                  |
| `sg-nimbus-ssh`     | Attached to everything       | 22 from `10.0.100.0/24` (mgmt only)        |
| `sg-nimbus-bastion` | Attached to nimbus-bastion   | 22 from your home/office public IP         |

This is defined in `terraform/network.tf`.

---

## 7. EC2 ↔ Proxmox VM

**AWS:** You launch an instance from an AMI with a user-data script; it boots with cloud-init, gets an IP from the subnet, comes up with your SSH key.

**Nimbus:** Identical flow.
1. Build a template VM (`vmid 9000`) from the Ubuntu cloud image — this is your AMI.
2. Terraform clones it for each new instance and injects cloud-init user-data.
3. VM boots, DHCP from pfSense, cloud-init runs, your SSH key is in `~Nimbus/.ssh/authorized_keys`.

The cloud-init file in `cloud-init/user-data.yml.tftpl` is a template — Terraform interpolates hostname and SSH keys per-VM.

---

## 8. Storage

| AWS      | Nimbus                                      |
|----------|---------------------------------------------|
| EBS      | Proxmox disk on ZFS / Ceph / LVM-thin       |
| EBS snap | Proxmox snapshot                            |
| EFS      | NFS share from a dedicated VM or TrueNAS    |
| S3       | MinIO (S3-compatible API, supports IAM/STS) |

MinIO is a drop-in for 99% of S3 SDK code. Run it as a single node for lab, or 4-node erasure-coded for "production-ish."

---

## 9. RDS

PostgreSQL 16 on a dedicated Ubuntu VM in `nimbus-data` subnet. Backups via `pgbackrest` pushed to the MinIO bucket — that mirrors how RDS automated backups land in S3 under the hood.

Once you're comfortable, graduate to **CloudNativePG** on a small k3s cluster for real HA + point-in-time recovery.

---

## 10. Route 53

**PowerDNS** with the `gpgsql` backend for authoritative zones, and the recursor for `.` resolution.

- Authoritative zone: `nimbus.local` (A records for every VM, managed via the PowerDNS API from Terraform using the `pan-net/pdns` provider).
- Split-horizon optional: serve different answers to internal vs external clients.

---

## 11. Load Balancers

**AWS ALB → HAProxy or Traefik** on `nimbus-alb` in the public subnet.

- HAProxy: closer to how ALB/NLB feel, config file in repo.
- Traefik: declarative, pulls labels from Docker/k8s, closer to "ALB + Ingress Controller" combined.

Pick one, commit its config.

---

## 12. Observability

| AWS              | Nimbus                                      |
|------------------|---------------------------------------------|
| CloudWatch Metrics | Prometheus scraping `node-exporter`       |
| CloudWatch Logs    | Loki + Promtail                           |
| CloudWatch Alarms  | Prometheus Alertmanager                   |
| X-Ray              | Tempo or Jaeger (optional)                |
| CloudTrail         | Proxmox audit log shipped into Loki       |

All on `nimbus-mon` in the mgmt subnet.

---

## 13. IAM

Run **Keycloak** for users/groups/roles + OIDC, and **HashiCorp Vault** for secrets/dynamic DB creds. Together they're the closest FOSS analog to IAM + Secrets Manager + STS.

This is the last phase to tackle — it's the most conceptually loaded piece and easier once the rest of the stack is concrete.
