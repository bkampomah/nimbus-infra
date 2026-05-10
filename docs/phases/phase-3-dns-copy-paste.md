# docs/phases/phase-3-dns-copy-paste.md

## Phase 3 runbook — nimbus-dns

This is the "I sit down at my desk and follow the steps" doc. Every command is copy-paste. Every `CHANGE_ME` is flagged.

## Prerequisites

- pfSense is up, Nimbus SDN VNets exist, `nimbus-mgmt` subnet is routable.
- AIO is dual-homed and `curl http://10.0.10.101:11000` works from nimbus-app.
- Ubuntu 24.04 cloud-init template exists at VMID 9000 (see Phase 2).
- Terraform 1.7+ installed locally.

## Step 1 — pfSense: reserve the static IP

nimbus-dns gets a static IP (`10.0.100.10/24`). Add a DHCP static mapping in pfSense for belt-and-suspenders — even though cloud-init sets the IP, the reservation prevents DHCP from ever handing it out to something else.

Services → DHCP Server → **LAN_MGMT** → Static Mappings → Add. Leave MAC blank for now; fill it in after the VM boots (Proxmox shows it in the Hardware tab).

## Step 2 — Put your values into terraform.tfvars

```bash
cd nimbus-infra/terraform
# If this is the first time you've touched tfvars since the project started:
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and ensure these lines are correct (most have safe defaults):

```hcl
nimbus_dns_static_ip = "10.0.100.10/24"
nimbus_aio_ip        = "10.0.10.101"     # ← CHANGE_ME if different
nimbus_alb_ip        = "10.0.1.10"       # placeholder, Phase 4
```

Also double-check your `subnets.mgmt.bridge` matches whatever you named the SDN VNet for 10.0.100.0/24 (typically `vmbr4` or `nimbus-mgmt`).

## Step 3 — Two-stage apply (the chicken-and-egg)

The `pdns` provider needs a live PowerDNS API endpoint at plan-time. First run creates the VM only; second run adds records.

```bash
terraform init -upgrade

# Stage 1 — build nimbus-dns only.
terraform apply -target=module.nimbus_dns
# Wait ~3-5 minutes. Watch for "nimbus-dns ... ready after N seconds"
# in the Proxmox VM console (or SSH in and tail /var/log/cloud-init-output.log).
```

Before running stage 2, verify PowerDNS is actually answering:

```bash
# From your workstation or any VM in Nimbus:
dig @10.0.100.10 ns1.nimbus.local +short
# Expected: 10.0.100.10

# And that the API responds:
curl -H "X-API-Key: $(terraform output -raw nimbus_dns_api_key 2>/dev/null || echo '<get from tfstate>')" \
  http://10.0.100.10:8081/api/v1/servers/localhost/zones | jq '.[].name'
# Expected: "nimbus.local." and "nimbusnode.org."
```

If both check out, run stage 2:

```bash
# Stage 2 — add all the records.
terraform apply
```

## Step 4 — Point clients at nimbus-dns

Two layers to flip, in order.

**pfSense first** (so any Nimbus client using DHCP picks this up automatically).

Services → DHCP Server → **LAN_APP**, **LAN_DATA**, **LAN_MGMT** → "DNS servers" field on each → set to `10.0.100.10`. Save + Apply each one. Then on each VM:

```bash
sudo dhclient -r && sudo dhclient   # renew DHCP and pick up the new DNS
# or simpler:
sudo systemctl restart systemd-networkd
```

**The AIO VM** needs special handling because it was configured manually. Edit `/etc/netplan/60-nimbus-app.yaml` and add a nameserver:

```yaml
network:
  version: 2
  ethernets:
    ens19:
      dhcp4: true
      dhcp4-overrides:
        use-routes: false
        use-dns: false        # ← keep ignoring pfSense's DNS
      nameservers:
        addresses: [10.0.100.10]
        search: [nimbus.local]
```

```bash
sudo netplan apply
resolvectl status              # confirm 10.0.100.10 is listed for ens19
```

## Step 5 — Verify split-horizon

Inside Nimbus:
```bash
dig cloud.nimbusnode.org +short
# Expected: 10.0.10.101  (your AIO, NOT a Cloudflare edge IP)
```

From outside Nimbus (your phone on LTE, or any non-Nimbus machine):
```bash
dig cloud.nimbusnode.org +short
# Expected: 104.21.x.x or similar (Cloudflare edge — unchanged)
```

If both answers match expectations, split-horizon works. The same DNS name resolves to two different places depending on which network you're on.

## Step 6 — Test internal names

```bash
dig nimbus-cloud-aio.nimbus.local +short
# Expected: 10.0.10.101

dig nimbus-dns.nimbus.local +short
# Expected: 10.0.100.10

ping -c2 nimbus-cloud-aio.nimbus.local
# Resolves and reaches the AIO by name
```

Now you can SSH with hostnames: `ssh Nimbus@nimbus-cloud-aio.nimbus.local`. That's the Route 53 payoff.

## Troubleshooting cheat sheet

| Symptom                                      | Likely cause                                                                 |
|----------------------------------------------|------------------------------------------------------------------------------|
| `dig @10.0.100.10 ...` times out             | Recursor not listening or pfSense firewall dropping UDP/53 on mgmt interface |
| External names (`google.com`) fail to resolve| `upstream_dns` wrong, or pfSense blocking outbound :53 from mgmt             |
| `nimbus.local` names NXDOMAIN                | Recursor's `forward-zones+=` line missing — check `/etc/powerdns/recursor.conf` |
| PowerDNS API returns 401                     | Wrong API key in tfstate; `terraform output` should pull the right one       |
| `terraform apply` stage 2 fails with "connection refused" | nimbus-dns VM not up yet, or IP wrong — ping 10.0.100.10 first  |

## One-time PowerDNS gotcha

The `pan-net/pdns` provider is picky about trailing dots. Every `name` and `zone` in `pdns_record` MUST end with a dot:
- Good: `"cloud.nimbusnode.org."`
- Bad:  `"cloud.nimbusnode.org"`

If you forget, the provider doesn't error — it creates a record under a weirdly-named zone. All the `pdns_record` blocks in `dns.tf` have the dots already. If you add new ones, don't forget.
