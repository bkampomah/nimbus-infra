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
    # Phase 7b — Keycloak realm-as-code. Hits the master realm admin REST API
    # on nimbus-iam:8443 to provision realms, clients, users.
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.0"
    }
    # Phase 7d — Vault secrets engines, auth methods, policies. Authenticates
    # via VAULT_TOKEN env var (operator's root token initially; an admin token
    # under OIDC after the realm is wired). Vault must be initialized + unsealed
    # before plan/apply hits any vault_* resource — see docs/runbooks/vault-init.md.
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.4"
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
    agent       = var.proxmox_ssh_agent
    username    = var.proxmox_ssh_username
    private_key = var.proxmox_ssh_private_key_file != "" ? file(pathexpand(var.proxmox_ssh_private_key_file)) : null
  }
}
