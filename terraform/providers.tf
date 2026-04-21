# terraform/providers.tf
#
# Using bpg/proxmox (actively maintained, better cloud-init + SDN support
# than the older telmate/proxmox fork).

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
  }

  # Recommended: remote state.
  # For a first run, leave this commented and use local state, then migrate
  # to Terraform Cloud / an S3-compatible backend (MinIO on nimbus-s3) once
  # that VM exists. Chicken-and-egg is normal on day one.
  #
  # backend "remote" {
  #   organization = "CHANGE_ME-your-tfc-org"
  #   workspaces { name = "nimbus-infra" }
  # }
}

provider "proxmox" {
  # CHANGE_ME: Your Proxmox web UI URL, including the trailing slash.
  # Example: "https://192.168.1.50:8006/"
  endpoint = var.proxmox_endpoint

  # CHANGE_ME: The API token you created with `pveum user token add ...`
  # Format: "<user>@<realm>!<tokenid>=<uuid-secret>"
  # Example: "terraform@pve!tf-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  api_token = var.proxmox_api_token

  # Set to true ONLY if your Proxmox uses a self-signed cert.
  # Safer alternative: install the PVE CA on your workstation and leave this false.
  insecure = true

  # The bpg provider uses SSH for some operations (file uploads, snippets).
  # Make sure your workstation's SSH key is authorized on the Proxmox host
  # for the user below.
  ssh {
    agent    = true
    username = var.proxmox_ssh_username   # CHANGE_ME in tfvars (typically "root")
  }
}
