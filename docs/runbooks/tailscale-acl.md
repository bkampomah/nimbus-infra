# Runbook - Tailscale ACL GitOps

Nimbus keeps its tailnet policy in `.github/tailscale-acl.hujson`. GitHub
Actions tests the policy on pull requests and applies it on pushes to `main`.

## Model

- One Proxmox-hosted Tailscale LXC acts as the subnet router and exit node.
- The LXC owns `tag:nimbus-subnet-router`.
- It advertises `10.0.0.0/16` for the Nimbus VPC and `192.168.1.0/24` for the
  home LAN.
- Tailnet members can reach ALB app entrypoints and Nimbus DNS.
- Tailscale admins can reach management/control-plane ports and use the exit
  node.

The policy file replaces the entire tailnet policy when applied. Before the
first GitOps apply, copy the current policy from the Tailscale admin console so
you can compare it with the repo version.

## GitHub setup

Create a Tailscale federated identity for this repository with the
`policy_file` scope. Add these repository secrets:

```text
TS_TAILNET
TS_OAUTH_ID
TS_AUDIENCE
```

`TS_TAILNET` is the tailnet name shown in the Tailscale admin console. The
OAuth ID and audience come from the federated identity.

## LXC router setup

On the Tailscale LXC:

```bash
sudo tailscale up \
  --advertise-tags=tag:nimbus-subnet-router \
  --advertise-routes=10.0.0.0/16,192.168.1.0/24 \
  --advertise-exit-node
```

The policy auto-approves those routes and the exit-node advertisement for
devices tagged `tag:nimbus-subnet-router`.

Tailscale auto-approvers are not retroactive for already-pending routes. If a
route is already pending in the admin console, remove and re-advertise the
route from the LXC after the policy is applied.

## Firewall note

The Nimbus VM UFW rules still apply after Tailscale allows a route. With the
default subnet-router SNAT behavior, traffic reaches Nimbus VMs from the LXC's
LAN-side address, which fits the existing `192.168.0.0/16` management allowlist.
If you disable subnet-route SNAT, add the relevant Tailscale client CIDRs to
`mgmt_allow_cidrs` before expecting Vault, MinIO console, PowerDNS API, or SSH
to work through the route.
