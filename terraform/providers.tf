# terraform/providers.tf
#
# Using bpg/proxmox (actively maintained, better cloud-init + SDN support
# than the older telmate/proxmox fork).
# The pan-net/powerdns provider manages records on nimbus-dns once it's running.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    powerdns = {
      source  = "pan-net/powerdns"
      version = "~> 1.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # backend "remote" {
  #   organization = "CHANGE_ME-your-tfc-org"
  #   workspaces { name = "nimbus-infra" }
  # }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true

  ssh {
    agent    = true
    username = var.proxmox_ssh_username
  }
}
