# terraform/variables.tf
#
# Every variable without a default is required in terraform.tfvars.
# Variables WITH defaults are safe to leave alone for a first run.

# ─────────────────────────────────────────────────────────────────────────────
# Proxmox connection (REQUIRED — set in terraform.tfvars or via env vars)
# ─────────────────────────────────────────────────────────────────────────────

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint, e.g. https://192.168.1.50:8006/"
  type        = string
  # CHANGE_ME in terraform.tfvars
}

variable "proxmox_api_token" {
  description = "Full API token: user@realm!tokenid=uuid-secret"
  type        = string
  sensitive   = true
  # CHANGE_ME in terraform.tfvars
}

variable "proxmox_ssh_username" {
  description = "SSH user on the Proxmox host (for file uploads by the provider)"
  type        = string
  default     = "root"
}

variable "proxmox_ssh_agent" {
  description = "Use ssh-agent for Proxmox file uploads by the provider"
  type        = bool
  default     = true
}

variable "proxmox_ssh_private_key_file" {
  description = "Optional private key path for Proxmox file uploads when ssh-agent auth is unavailable"
  type        = string
  default     = ""
  sensitive   = true
}

variable "proxmox_node" {
  description = "Name of the Proxmox node VMs should be created on (see `pvesh get /nodes`)"
  type        = string
  # CHANGE_ME in terraform.tfvars — e.g. "pve" or "nimbus-node-01"
}

# ─────────────────────────────────────────────────────────────────────────────
# Storage pools on the Proxmox node
# ─────────────────────────────────────────────────────────────────────────────

variable "proxmox_vm_storage" {
  description = "Storage pool for VM disks (ZFS / Ceph / LVM-thin). Check `pvesm status`."
  type        = string
  default     = "nvme-lvm" # CHANGE_ME if you use ZFS/Ceph — typical values: "local-zfs", "ceph-rbd"
}

variable "proxmox_iso_storage" {
  description = "Storage pool that holds ISOs / cloud images / snippets"
  type        = string
  default     = "sata-backups"
}

# ─────────────────────────────────────────────────────────────────────────────
# Nimbus identity
# ─────────────────────────────────────────────────────────────────────────────

variable "company_name" {
  description = "Short name used as a prefix/tag on every resource"
  type        = string
  default     = "nimbus"
}

variable "admin_username" {
  description = "Default Linux user created by cloud-init on every VM"
  type        = string
  default     = "nimbus"
}

variable "admin_password" {
  description = <<-EOT
    Initial password for the admin user.
    LAB DEFAULT: "changeme" — fine for a learning environment.
    PRODUCTION:  rotate immediately and rely on SSH keys.
  EOT
  type        = string
  sensitive   = true
  default     = "changeme" # CHANGE_ME for anything you actually care about
}

variable "admin_ssh_public_keys" {
  description = "SSH public keys authorized for the admin user (one per line)"
  type        = list(string)
  # CHANGE_ME in terraform.tfvars — paste your ~/.ssh/id_ed25519.pub content
}

# ─────────────────────────────────────────────────────────────────────────────
# Network layout — the "VPC"
# These match ARCHITECTURE.md and cloud-init DHCP expectations.
# ─────────────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR for the whole Nimbus VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnets" {
  description = "Nimbus subnet map — keyed by tier"
  type = map(object({
    cidr    = string
    gateway = string
    bridge  = string # the Proxmox bridge/VNet name, e.g. "vmbr1" or "nimbus-app"
    public  = bool
  }))
  default = {
    public = {
      cidr    = "10.0.1.0/24"
      gateway = "10.0.1.1"
      bridge  = "public" # CHANGE_ME to match the SDN VNet you created
      public  = true
    }
    app = {
      cidr    = "10.0.10.0/24"
      gateway = "10.0.10.1"
      bridge  = "app" # CHANGE_ME
      public  = false
    }
    data = {
      cidr    = "10.0.20.0/24"
      gateway = "10.0.20.1"
      bridge  = "data" # CHANGE_ME
      public  = false
    }
    mgmt = {
      cidr    = "10.0.100.0/24"
      gateway = "10.0.100.1"
      bridge  = "mgmt" # CHANGE_ME
      public  = true   # mgmt is reachable from pfSense/bastion
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Golden image (the "AMI")
# ─────────────────────────────────────────────────────────────────────────────

variable "template_vm_id" {
  description = "VMID of the Ubuntu 24.04 cloud-init template you built by hand"
  type        = number
  default     = 9000 # CHANGE_ME if you used a different VMID
}

# ─────────────────────────────────────────────────────────────────────────────
# Nextcloud stack (nimbus-rds + nimbus-s3 + nimbus-cloud-01)
# ─────────────────────────────────────────────────────────────────────────────

variable "nextcloud_domain" {
  description = <<-EOT
    Public FQDN users hit. With a Cloudflare Tunnel this is your Cloudflare
    hostname (e.g. cloud.nimbusnode.org). Internally, nimbus-alb is still
    reachable as cloud.nimbus.local via PowerDNS for health checks /
    bastion access, but this variable drives Nextcloud's overwrite.*
    settings so that emailed links, share URLs, and mobile app login all
    use the public name.
  EOT
  type        = string
  default     = "cloud.nimbusnode.org"
}

variable "cloudflare_tunnel_token" {
  description = <<-EOT
    Token from `cloudflared tunnel token <tunnel-name>` (or pasted from the
    Zero Trust dashboard when creating a "Remotely-managed" tunnel).
    Leave empty to skip cloudflared install on the ALB — useful if you
    want to install it manually or run it elsewhere.
  EOT
  type        = string
  sensitive   = true
  default     = ""
  # CHANGE_ME in terraform.tfvars
}

variable "nimbus_s3_ip" {
  description = "Current IP of your s3 VM on the nimbus-data subnet"
  type        = string
  default     = "10.0.20.101"
}

variable "nimbus_s3_root_disk_size_gb" {
  description = "Root disk size in GB for nimbus-s3"
  type        = number
  default     = 32
}


variable "nimbus_s3_data_disk_size_gb" {
  description = "MinIO data disk size in GB for nimbus-s3"
  type        = number
  default     = 200
}

variable "nimbus_rds_ip" {
  description = "Static IP for nimbus-rds in the data subnet"
  type        = string
  default     = "10.0.20.103"
}

variable "nimbus_cloud_ip" {
  description = "Static IP for nimbus-cloud-01 in the app subnet"
  type        = string
  default     = "10.0.10.102"
}

variable "cloudflare_ip_ranges" {
  description = <<-EOT
    CIDRs Nextcloud should trust as reverse proxies in addition to the ALB.
    Default is Cloudflare's public IP ranges (IPv4 only; add IPv6 if you
    enable it). Refresh from https://www.cloudflare.com/ips-v4/ quarterly.
  EOT
  type        = list(string)
  default = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
  ]
}

variable "nextcloud_admin_password" {
  description = "Initial password for the Nextcloud web UI admin user"
  type        = string
  sensitive   = true
  # CHANGE_ME in terraform.tfvars
}

variable "minio_root_user" {
  description = "MinIO root (admin) username"
  type        = string
  default     = "nimbus-admin"
}

variable "nextcloud_s3_access_key" {
  description = "MinIO access key ID used by Nextcloud (IAM-style user)"
  type        = string
  sensitive   = true
  # CHANGE_ME in terraform.tfvars
}

variable "nextcloud_s3_secret_key" {
  description = "MinIO secret key used by Nextcloud"
  type        = string
  sensitive   = true
  # CHANGE_ME in terraform.tfvars
}

# ─────────────────────────────────────────────────────────────────────────────
# nimbus-dns (PowerDNS / Route 53 equivalent)
# ─────────────────────────────────────────────────────────────────────────────

variable "nimbus_dns_static_ip" {
  description = "Static IP (with CIDR) for nimbus-dns inside the mgmt subnet"
  type        = string
  default     = "10.0.100.10/24" # CHANGE_ME if your mgmt subnet differs
}

variable "nimbus_mon_ip" {
  description = "Static IP for nimbus-mon (Prometheus/Grafana/Loki) in the mgmt subnet"
  type        = string
  default     = "10.0.100.20"
}

variable "nimbus_aio_ip" {
  description = "Current IP of your Nextcloud AIO VM on the nimbus-app subnet"
  type        = string
  default     = "10.0.10.101" # CHANGE_ME — confirm with `ip -4 addr` on AIO
}

variable "nimbus_alb_ip" {
  description = "Planned IP of nimbus-alb (placeholder until Phase 4 lands)"
  type        = string
  default     = "10.0.1.10" # CHANGE_ME later when ALB is built
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 7 — IAM stack (nimbus-iam Keycloak + nimbus-vault HashiCorp Vault)
# Both VMs live in the mgmt subnet (10.0.100.0/24).
# Keycloak is fronted by nimbus-alb (TLS re-encrypt) and reachable externally
# via Cloudflare Tunnel; Vault stays internal-only (Tailscale + mgmt subnet).
# ─────────────────────────────────────────────────────────────────────────────

variable "nimbus_iam_ip" {
  description = "Static IP for nimbus-iam (Keycloak) in the mgmt subnet"
  type        = string
  default     = "10.0.100.30"
}

variable "nimbus_vault_ip" {
  description = "Static IP for nimbus-vault in the mgmt subnet"
  type        = string
  default     = "10.0.100.40"
}

variable "keycloak_domain" {
  description = <<-EOT
    Public FQDN for Keycloak. With a Cloudflare Tunnel this is the external
    hostname (e.g. auth.nimbusnode.org). Sets KC_HOSTNAME so OIDC redirects
    target the public URL — without this, Keycloak emits localhost:8443 in
    the discovery document and SSO redirects break.
  EOT
  type        = string
  default     = "auth.nimbusnode.org"
}

variable "mgmt_allow_cidrs" {
  description = "CIDRs allowed to reach management APIs (e.g. PowerDNS API, future ALB admin UIs). Typically your home/office LAN plus the VPC itself."
  type        = list(string)
  default     = ["10.0.0.0/16", "192.168.0.0/16", "127.0.0.1/32"]
}

# ─────────────────────────────────────────────────────────────────────────────
# nimbus-bastion (DMZ workstation/jumpbox for pfSense GUI testing)
# ─────────────────────────────────────────────────────────────────────────────

variable "nimbus_bastion_vm_id" {
  description = "Proxmox VMID for nimbus-bastion"
  type        = number
  default     = 209
}

variable "nimbus_bastion_ip" {
  description = "Static IP for nimbus-bastion in the public/DMZ subnet"
  type        = string
  default     = "10.0.1.20"
}

variable "bastion_ssh_allow_cidrs" {
  description = "CIDRs allowed to SSH into nimbus-bastion"
  type        = list(string)
  default     = ["192.168.0.0/16", "10.0.0.0/16"]
}

variable "pfsense_gui_host" {
  description = "pfSense WebConfigurator host/IP reachable from nimbus-bastion"
  type        = string
  default     = "10.0.1.1"
}

variable "pfsense_gui_port" {
  description = "pfSense WebConfigurator HTTPS port"
  type        = number
  default     = 443
}

variable "pfsense_tunnel_local_port" {
  description = "Local workstation port used by the suggested SSH tunnel"
  type        = number
  default     = 8443
}

# ─────────────────────────────────────────────────────────────────────────────
# PowerDNS provider (two-stage bootstrap)
# Stage 1: terraform apply -target=module.nimbus_dns
# Stage 2: terraform output -raw nimbus_dns_api_key → set powerdns_api_key here
# Stage 3: terraform apply
# ─────────────────────────────────────────────────────────────────────────────

variable "powerdns_api_key" {
  description = <<-EOT
    PowerDNS HTTP API key. Leave empty on the first apply (Stage 1).
    After the DNS VM is up, run:
      terraform output -raw nimbus_dns_api_key
    then set this variable in terraform.tfvars and run terraform apply again.
  EOT
  type        = string
  sensitive   = true
  default     = ""
}
