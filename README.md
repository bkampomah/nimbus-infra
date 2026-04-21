# Nimbus — AWS-Style Network on Proxmox

A learning project that recreates an AWS-style multi-tier network (VPC, subnets, security groups, EC2, ELB, RDS, S3, Route 53) on a Proxmox cluster, managed as code with Terraform and GitOps'd through GitHub Actions.

> **Credentials (lab only):** username `Nimbus` / password `changeme`.
> `changeme` is fine for a throwaway lab, but switch to SSH keys and rotate the password before exposing anything to the internet. Cloud-init in this repo provisions both so you can SSH in immediately and harden later.

---

## 1. What you'll build

A single Proxmox node (or cluster) hosting a virtual "AWS region" called **Nimbus**, with one VPC, a public tier, two private tiers, and the core services that sit on top.

```
                 ┌────────────────────────────────────────────┐
 Internet ──┐    │  Proxmox host(s) — "nimbus-region-1"       │
            │    │                                            │
            ▼    │   ┌──────────── Nimbus VPC (10.0.0.0/16) ──┼──┐
       ┌────────┴─┐  │                                        │  │
       │ pfSense  │  │  Public subnet   10.0.1.0/24           │  │
       │ (IGW/NAT)│──┤    ├─ nimbus-alb   (HAProxy / Traefik) │  │
       └──────────┘  │    └─ nimbus-bastion                   │  │
                     │                                        │  │
                     │  Private-app     10.0.10.0/24          │  │
                     │    ├─ nimbus-web-01 / 02  (EC2-like)   │  │
                     │    └─ nimbus-api-01 / 02               │  │
                     │                                        │  │
                     │  Private-data    10.0.20.0/24          │  │
                     │    ├─ nimbus-rds  (PostgreSQL)         │  │
                     │    └─ nimbus-s3   (MinIO)              │  │
                     │                                        │  │
                     │  Management      10.0.100.0/24         │  │
                     │    ├─ nimbus-dns  (PowerDNS) = Route53 │  │
                     │    └─ nimbus-mon  (Prom/Grafana/Loki)  │  │
                     └────────────────────────────────────────┘  │
                                                                 │
                        GitHub ── Actions ── Terraform ──────────┘
```

See `ARCHITECTURE.md` for the full AWS-to-Proxmox mapping.

---

## 2. AWS → Proxmox/FOSS service map (short version)

| AWS                 | Nimbus equivalent                             |
|---------------------|-----------------------------------------------|
| Region / AZ         | Proxmox datacenter / node                     |
| VPC                 | Proxmox SDN Zone (type: `simple` or `vlan`)   |
| Subnet              | SDN VNet + subnet                             |
| Internet Gateway    | pfSense/OPNsense WAN interface                |
| NAT Gateway         | pfSense outbound NAT                          |
| Route Table         | pfSense / SDN routes                          |
| Security Group      | Proxmox firewall (VM-level, stateful)         |
| Network ACL         | Proxmox firewall (datacenter/node-level)      |
| EC2 instance        | Proxmox VM (cloud-init enabled)               |
| AMI                 | Proxmox VM template from cloud image          |
| EBS volume          | Proxmox disk on ZFS / Ceph / LVM-thin         |
| S3                  | MinIO                                         |
| RDS                 | PostgreSQL VM (or CloudNativePG on k8s later) |
| Route 53            | PowerDNS (auth + recursor)                    |
| ELB / ALB           | HAProxy or Traefik                            |
| IAM                 | Keycloak + HashiCorp Vault                    |
| CloudWatch          | Prometheus + Grafana + Loki                   |
| CloudTrail          | Proxmox audit log shipped to Loki             |

---

## 3. Phased plan

### Phase 0 — Prereqs (manual, one-time)

1. Proxmox VE 8.x installed, reachable on your LAN.
2. Create a Proxmox API token for Terraform (see §5).
3. Create GitHub repo `nimbus-infra` and add secrets (see §6).
4. Download an Ubuntu 24.04 cloud image on the Proxmox host:
   ```bash
   cd /var/lib/vz/template/iso
   wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
   ```
5. Install on your workstation: `terraform >= 1.7`, `git`, `ssh-keygen`.

### Phase 1 — Network foundation (the "VPC")

- Configure Proxmox SDN manually the first time (bpg/proxmox Terraform provider SDN support is still evolving; doing it by hand once makes the mental model stick).
  - SDN Zone: `nimbus-vpc` (type `simple`)
  - VNets: `nimbus-public`, `nimbus-app`, `nimbus-data`, `nimbus-mgmt`
  - Subnets as diagrammed above
- Deploy pfSense as the VPC edge (Internet Gateway + NAT Gateway). Give it one NIC per VNet plus one on your real LAN bridge (`vmbr0`).
- Codify firewall rules (your "security groups") in Terraform using `proxmox_virtual_environment_firewall_*` resources.

### Phase 2 — Golden image (the "AMI")

- Build a reusable Ubuntu 24.04 cloud-init template VM (ID 9000).
- Snapshot it. Every EC2-equivalent VM clones from this template.
- Commit the `cloud-init/user-data.yml.tftpl` so the template is reproducible.

### Phase 3 — Compute (the "EC2 fleet")

- Terraform module `modules/compute` that wraps `proxmox_virtual_environment_vm` and takes: name, subnet, cpu, ram, disk, tags, SSH keys.
- Stand up: bastion (public), 2× web + 2× api (private-app), db (private-data).

### Phase 4 — Managed services

- `nimbus-rds`: PostgreSQL 16 on Ubuntu, backups to MinIO.
- `nimbus-s3`: MinIO single-node or 4-node erasure-coded.
- `nimbus-alb`: HAProxy with cert-manager-style Let's Encrypt via Caddy, OR Traefik if you prefer declarative.
- `nimbus-dns`: PowerDNS authoritative for `nimbus.local`, forwarder for external.

### Phase 5 — Observability (the "CloudWatch")

- Prometheus + node-exporter on each VM.
- Grafana dashboards committed as JSON in the repo.
- Loki + Promtail for logs; ship Proxmox `/var/log/pveproxy/access.log` as your CloudTrail.

### Phase 6 — GitOps lifecycle

- `main` branch = prod state; PRs run `terraform plan` and post the diff as a comment.
- Merging to `main` runs `terraform apply` with approval.
- State stored remotely (recommend Terraform Cloud free tier, or MinIO+DynamoDB-style locking via `nimbus-s3` once it exists — chicken-and-egg: bootstrap locally, migrate later).

---

## 4. Repository layout

```
nimbus-infra/
├── README.md                       <- you are here
├── ARCHITECTURE.md                 <- AWS-to-Proxmox mapping in depth
├── .gitignore
├── .github/workflows/terraform.yml <- plan on PR, apply on merge
├── terraform/
│   ├── providers.tf                <- bpg/proxmox provider
│   ├── variables.tf                <- all CHANGE_ME inputs
│   ├── terraform.tfvars.example    <- copy to terraform.tfvars, edit
│   ├── network.tf                  <- firewall rules (SGs/NACLs)
│   ├── compute.tf                  <- VMs cloned from template
│   └── modules/                    <- add as you grow
└── cloud-init/
    └── user-data.yml.tftpl         <- Nimbus user, SSH keys, base pkgs
```

---

## 5. Proxmox API token (do this first)

On the Proxmox host (shell or web UI → Datacenter → Permissions → API Tokens):

```bash
# Create a user for Terraform
pveum user add terraform@pve --comment "Terraform service account"

# Grant it the rights it needs (tight enough to be safe, loose enough to work)
pveum aclmod / -user terraform@pve -role PVEAdmin

# Create a token; COPY THE SECRET — it is only shown once
pveum user token add terraform@pve tf-token --privsep 0
```

You will get something like:
```
┌──────────────┬──────────────────────────────────────┐
│ full-tokenid │ terraform@pve!tf-token               │
├──────────────┼──────────────────────────────────────┤
│ value        │ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx │
└──────────────┴──────────────────────────────────────┘
```

The `full-tokenid` goes into `PROXMOX_VE_API_TOKEN_ID`, the `value` goes into `PROXMOX_VE_API_TOKEN_SECRET`. Both are referenced from `terraform.tfvars` / GitHub secrets.

---

## 6. GitHub secrets

In your `nimbus-infra` repo → Settings → Secrets and variables → Actions, add:

| Secret                           | Value                                               |
|----------------------------------|-----------------------------------------------------|
| `PROXMOX_VE_ENDPOINT`            | `https://<your-proxmox-ip>:8006/`                   |
| `PROXMOX_VE_API_TOKEN`           | `terraform@pve!tf-token=<secret-uuid>`              |
| `PROXMOX_VE_SSH_USERNAME`        | `root`                                              |
| `PROXMOX_VE_SSH_PRIVATE_KEY`     | contents of an SSH key authorized on Proxmox host   |
| `NIMBUS_ADMIN_SSH_PUBLIC_KEY`    | your workstation's `~/.ssh/id_ed25519.pub`          |

---

## 7. Day-one commands

```bash
git clone git@github.com:<you>/nimbus-infra.git
cd nimbus-infra/terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — every CHANGE_ME is called out
terraform init
terraform plan
terraform apply
```

## 8. Day-two maintenance

- **Drift detection:** nightly GitHub Action runs `terraform plan` and opens an issue if drift is found.
- **Upgrades:** bump the Ubuntu cloud image in the template VM, re-snapshot, `terraform taint` one VM at a time to do rolling replacement.
- **Backups:** Proxmox Backup Server → external disk; MinIO bucket versioning for S3-style data.
- **Secrets rotation:** rotate the `tf-token` quarterly; update GitHub secret; no code change needed.

---

## 9. What's explicitly NOT in Terraform (and why)

| Thing                  | Why not                                                |
|------------------------|--------------------------------------------------------|
| Proxmox SDN zones/vnets| Provider coverage is partial; set up once by hand      |
| pfSense config         | Use the pfSense UI + config.xml backup in repo         |
| Grafana dashboards     | JSON files in repo, loaded via provisioning            |
| OS-level config        | Use Ansible or cloud-init; Terraform just lands the VM |

Treat Terraform as the "control plane for infrastructure shape" and keep configuration management separate. That mirrors how most mature AWS shops actually run.
