# terraform/network.tf
#
# VPC-level network configuration lives here. Currently empty — the SDN
# zones and VNets (nimbus-vpc, nimbus-public, nimbus-app, nimbus-data,
# nimbus-mgmt) are defined in the Proxmox UI (see README Phase 1) and
# are not yet supported by bpg/proxmox's SDN resources.
#
# ─── Why no security groups here? ─────────────────────────────────────────
# Earlier versions of this file declared cluster-level firewall security
# groups via proxmox_virtual_environment_cluster_firewall_security_group.
# Those require Sys.Modify at the cluster root, which our Terraform API
# token (PVEAdmin role) does not have.
#
# Nimbus uses UFW inside each VM instead. Cloud-init writes the rules
# on first boot, per role. Benefits:
#   - Same approach works across hypervisors and clouds (portable)
#   - Terraform token can stay least-privileged (PVEAdmin only)
#   - Firewall state is introspectable from the VM: `ufw status`
#
# If you ever need cluster-level firewall (e.g. macros across many VMs),
# grant the token Administrator role and move to:
#   resource "proxmox_virtual_environment_cluster_firewall_security_group"
#
# The per-VM UFW rules live in each VM's cloud-init snippet template.
