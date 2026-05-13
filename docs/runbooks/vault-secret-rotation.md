# Runbook — Vault secret rotation

How to rotate the secrets Vault now owns (Phase 7e). Three flavors:

- **Static KV** (cloudflared, powerdns_api_key, nextcloud admin) — humans rotate, Terraform writes
- **Dynamic Postgres creds** (nextcloud) — Vault rotates automatically every lease; nothing to do
- **AppRole secret_id** (vault-agent on nimbus-cloud-01) — rotate periodically; manual + Terraform

## Static KV updates

Operator workflow when one of the inputs changes (e.g. you regenerate the
Cloudflare Tunnel token or rotate the Nextcloud admin password):

```bash
# Edit terraform.tfvars with the new value
$EDITOR terraform.tfvars

# Apply — vault_kv_secret_v2 detects the diff and writes a new version
terraform apply
```

`vault_kv_secret_v2` keeps version history (KV v2). Roll back with:

```bash
vault kv get -version=N secret/nimbus/cloudflared
vault kv rollback -version=N secret/nimbus/cloudflared
```

## Postgres dynamic creds — no operator action

Vault Agent on nimbus-cloud-01 handles this end-to-end. To verify it's
working, on nimbus-cloud-01:

```bash
sudo systemctl status vault-agent
sudo journalctl -u vault-agent -n 50

# What creds is Nextcloud using right now?
sudo -u www-data php /var/www/nextcloud/occ config:system:get dbuser
# Should show a username like "v-approle-nextclou-XXXX".

# Confirm Postgres sees the dynamic role
psql -h 10.0.20.103 -U postgres -c "\du+" | grep approle
```

To force an immediate re-render (e.g. after editing the database role):

```bash
sudo systemctl restart vault-agent
# Watch the new creds land
sudo journalctl -u vault-agent -f
```

To revoke ALL dynamic creds Vault has minted (panic button):

```bash
# As an admin Vault user
vault lease revoke -prefix database/creds/nextcloud
```

Within the next reconnect, php-fpm workers will re-auth with whatever Vault
mints next; the agent's auto-renew loop catches the revocation and re-fetches.

## AppRole secret_id rotation

The current setup creates a non-expiring secret_id. To rotate:

```bash
# 1. Create a new secret_id, capture the value
NEW_SECRET_ID=$(vault write -force \
  -format=json auth/approle/role/nextcloud/secret-id \
  | jq -r '.data.secret_id')

# 2. Push it to nimbus-cloud-01
ssh nimbus@nimbus-cloud-01 "
  sudo install -o vault-agent -g vault-agent -m 0600 /dev/stdin /etc/vault-agent/secret-id <<< '$NEW_SECRET_ID'
  sudo systemctl restart vault-agent
"

# 3. Confirm the agent re-authenticated
ssh nimbus@nimbus-cloud-01 "sudo journalctl -u vault-agent -n 20"

# 4. Once the new secret_id is healthy, destroy the old one. List accessors:
vault list -format=json auth/approle/role/nextcloud/secret-id
# Find the old accessor and:
vault write auth/approle/role/nextcloud/secret-id-accessor/destroy \
  secret_id_accessor=<accessor>
```

For Terraform-managed rotation, replace the `vault_approle_auth_backend_role_secret_id`
resource:

```bash
terraform apply -replace=vault_approle_auth_backend_role_secret_id.nextcloud
# Triggers a new secret_id. cloud-init re-renders nimbus-cloud-01 user-data
# but the VM's lifecycle.ignore_changes blocks the rebuild — manually
# distribute as above, or apply -replace on the VM too.
```

## Detecting drift

If someone fingers a secret directly via `vault kv put` outside Terraform,
the next `terraform apply` reverts it (vault_kv_secret_v2 manages the value).
That's intentional — Terraform is the source of truth for KV writes.

To audit who's touched what, the audit device (Phase 7d) logs every Vault
operation to Loki:

```logql
# Grafana / Logs explore
{job="vault-audit"} |= "secret/data/nimbus/" |= "update"
```

## Disaster: AppRole secret_id lost

If `/etc/vault-agent/secret-id` is corrupted/deleted on nimbus-cloud-01 and
no copy exists, vault-agent can't auth:

```bash
# As admin, mint a fresh secret_id
NEW_SECRET_ID=$(vault write -force \
  -format=json auth/approle/role/nextcloud/secret-id \
  | jq -r '.data.secret_id')

# Push + restart agent (same as rotation above)
```

While vault-agent is broken, Nextcloud keeps running on whatever creds were
last rendered into config/db.config.php — until those creds expire (default
1h, max 24h). Past max_ttl, Nextcloud DB connections fail; restore the
secret_id before that or fall back to the static `nextcloud` Postgres role
in config/config.php (break-glass).
