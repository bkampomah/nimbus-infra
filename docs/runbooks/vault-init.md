# Runbook — Vault initialization & unseal

One-time, manual. Phase 7d. Cannot be Terraformed: the unseal/recovery keys
must never live in this repo or its state file.

## When to run this

- Right after `terraform apply -target=module.nimbus_vault` lands the VM
  (Stage 4 in the README bootstrap)
- After any `terraform apply -replace=...vault` (rebuild wipes Raft state)
- During disaster recovery from a Raft snapshot

## Prereqs

- Nimbus internal CA imported on your operator machine (or use `-tls-skip-verify`)
- SSH access to `nimbus-vault` (`10.0.100.40`) via Tailscale or mgmt subnet
- Terminal with access to `vault` CLI (`brew install vault` / `apt install vault`)

## 1. Confirm the service is up but sealed

```bash
ssh nimbus@nimbus-vault
sudo systemctl status vault
sudo journalctl -u vault -n 20 --no-pager
```

Expect: `Active: active (running)` and the journal showing
`core: security barrier not initialized`. That's the desired starting state.

## 2. Initialize

From your operator machine, point the CLI at Vault:

```bash
export VAULT_ADDR=https://vault.nimbus.local:8200
# either trust the internal CA …
export VAULT_CACERT=$HOME/.config/nimbus/nimbus-ca.crt
# … or skip TLS verification (lab only):
export VAULT_SKIP_VERIFY=true

vault status
# Initialized: false
# Sealed:      true

vault operator init -key-shares=5 -key-threshold=3 > vault-init.txt
chmod 600 vault-init.txt
```

`vault-init.txt` now contains:
- 5 unseal keys (any 3 of which can unseal the cluster)
- The initial root token

**Move this file off your shell history and into a password manager / 1Password
vault / yubikey-encrypted offline backup.** Anyone with 3 keys + the root
token owns every secret in Nimbus. Then `shred` the local copy.

## 3. Unseal

Vault stays sealed after init until you supply the threshold of keys:

```bash
vault operator unseal   # paste key 1
vault operator unseal   # paste key 2
vault operator unseal   # paste key 3

vault status
# Sealed: false
```

## 4. Apply Phase 7d Terraform

Back in the repo:

```bash
export VAULT_ADDR=https://10.0.100.40:8200
export VAULT_TOKEN=<the root token from vault-init.txt>
export VAULT_SKIP_VERIFY=true

cd terraform/
terraform apply
```

This lands:
- KV v2 mount at `secret/`
- Database engine + `nextcloud` dynamic role
- `file` audit device (logs go to Loki via Promtail)
- OIDC auth method bound to Keycloak
- AppRole auth method with the `terraform` role
- Four policies: `admin`, `operator`, `terraform-read`, `nextcloud-db`

## 5. Switch off the root token

The root token is dangerous — keep it only for break-glass. Once OIDC works:

```bash
# Log in via SSO instead
vault login -method=oidc role=vault-admins

# Confirm the new token has admin
vault token lookup
# policies: [admin default]

# Revoke the root token
vault token revoke <root-token>
```

If you ever need root again:

```bash
vault operator generate-root -init
# follow the prompts, re-providing the unseal keys
```

## After a reboot

Vault stays sealed across reboots — Raft state is encrypted at rest. SSH in,
re-run `vault operator unseal` three times.

For unattended unseal: configure the Transit secrets engine on a separate
small Vault and use `seal "transit"` in nimbus-vault's HCL. Out of scope for
Phase 7; revisit if reboot toil becomes a problem.

## Disaster recovery

Raft snapshot every night via cron (Phase 8 hardening). For now, snapshot
manually before any risky change:

```bash
vault operator raft snapshot save vault-$(date +%Y%m%d).snap
```

Restore:

```bash
vault operator raft snapshot restore vault-YYYYMMDD.snap
```

After restore, the cluster is sealed again — provide unseal keys.
