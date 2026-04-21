# terraform/network.tf
#
# "Security Groups" and "NACLs" for Nimbus, implemented with the
# Proxmox datacenter firewall. Proxmox literally calls these "security
# groups" so the analogy carries over cleanly.
#
# These resources do NOT create the VPC/subnets themselves — do that once
# in the Proxmox UI under Datacenter → SDN (see README §3 Phase 1). Once
# the SDN bits stabilize in bpg/proxmox we'll codify them here too.

# ─── sg-nimbus-alb ──────────────────────────────────────────────────────────
# Attached to the load balancer VM. Open to the internet on 80/443.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "alb" {
  name    = "sg-${var.company_name}-alb"
  comment = "Public HTTP/HTTPS to the ${var.company_name} ALB"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "80"
    comment = "HTTP from anywhere"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "443"
    comment = "HTTPS from anywhere"
  }
}

# ─── sg-nimbus-web ──────────────────────────────────────────────────────────
# Attached to web/api VMs in the private-app subnet. Only the ALB talks to them.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "web" {
  name    = "sg-${var.company_name}-web"
  comment = "App tier — only reachable from the ALB"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "80"
    source  = var.subnets.public.cidr
    comment = "HTTP from the public subnet (the ALB lives there)"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "443"
    source  = var.subnets.public.cidr
    comment = "HTTPS from the public subnet"
  }
}

# ─── sg-nimbus-db ───────────────────────────────────────────────────────────
# Attached to the database VM. Only the app tier talks to it.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "db" {
  name    = "sg-${var.company_name}-db"
  comment = "Database — only reachable from the app tier"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "5432"
    source  = var.subnets.app.cidr
    comment = "PostgreSQL from the app subnet"
  }
}

# ─── sg-nimbus-ssh ──────────────────────────────────────────────────────────
# Attached to every VM. SSH only from the management subnet (the bastion).
resource "proxmox_virtual_environment_cluster_firewall_security_group" "ssh" {
  name    = "sg-${var.company_name}-ssh"
  comment = "SSH from management / bastion only"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = var.subnets.mgmt.cidr
    comment = "SSH from management subnet"
  }
}

# ─── sg-nimbus-bastion ──────────────────────────────────────────────────────
# Attached to the bastion VM only. This is the one SSH entry point from
# outside the VPC.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "bastion" {
  name    = "sg-${var.company_name}-bastion"
  comment = "Bastion host — SSH from your known IPs only"

  rule {
    type   = "in"
    action = "ACCEPT"
    proto  = "tcp"
    dport  = "22"
    # CHANGE_ME: your home/office public IP (find via `curl ifconfig.me`).
    # Leave as 0.0.0.0/0 ONLY for a throwaway lab — that's world-open SSH.
    source  = "203.0.113.10/32"
    comment = "SSH from admin public IP"
  }
}

# ─── sg-nimbus-nextcloud ────────────────────────────────────────────────────
# Attached to nimbus-cloud-01. Plain HTTP:80 from the ALB subnet only;
# TLS terminates on the ALB.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "nextcloud" {
  name    = "sg-${var.company_name}-nextcloud"
  comment = "Nextcloud app tier — only reachable from the ALB"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "80"
    source  = var.subnets.public.cidr
    comment = "HTTP from ALB subnet"
  }
}

# ─── sg-nimbus-minio ────────────────────────────────────────────────────────
# Attached to nimbus-s3. S3 API from app tier; console from mgmt only.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "minio" {
  name    = "sg-${var.company_name}-minio"
  comment = "MinIO — S3 API from app tier, console from mgmt"

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "9000"
    source  = var.subnets.app.cidr
    comment = "S3 API from app tier"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "9001"
    source  = var.subnets.mgmt.cidr
    comment = "Admin console from mgmt subnet"
  }
}
