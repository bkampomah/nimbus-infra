# Runbook - OIDC client secret rotation

Rotate Keycloak OIDC client secrets and push the new value to the consuming
service. Phase 7 configured four confidential clients:

| Client ID | Consumer | Terraform output |
|-----------|----------|------------------|
| `nextcloud` | `nimbus-cloud-01` / `user_oidc` | `keycloak_client_secret_nextcloud` |
| `grafana` | `nimbus-mon` / Grafana generic OAuth | `keycloak_client_secret_grafana` |
| `minio-console` | `nimbus-s3` / MinIO console SSO | `keycloak_client_secret_minio_console` |
| `vault` | `nimbus-vault` / Vault OIDC auth backend | `keycloak_client_secret_vault` |

## Rules

- Rotate one client at a time.
- Keep the old browser session open until the new login path is verified.
- Do not run with `set -x`; these commands handle client secrets.
- Running VMs ignore cloud-init user-data changes, so app configs must be
  pushed manually after Keycloak changes.

## 1. Preflight

```bash
cd ~/code/nimbus-infra/terraform

curl -fsS https://auth.nimbusnode.org/realms/nimbus/.well-known/openid-configuration >/dev/null

# Phase 7+ plans usually need Vault provider auth because the root module
# contains Vault resources and data sources, even when rotating a non-Vault app.
export VAULT_ADDR=https://10.0.100.40:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN='<vault-admin-token>'

terraform validate
terraform plan
```

## 2. Regenerate the client secret in Keycloak

Use the admin console:

1. Open `https://auth.nimbusnode.org/admin/`.
2. Select realm `nimbus`.
3. Go to **Clients** and open the target client ID.
4. Go to **Credentials**.
5. Regenerate the client secret.

Then refresh Terraform state so `terraform output` reads the new secret:

```bash
terraform apply -refresh-only -target=keycloak_openid_client.<resource_name>
```

Resource names:

```text
nextcloud
grafana
minio_console
vault
```

Example:

```bash
terraform apply -refresh-only -target=keycloak_openid_client.grafana
terraform output -raw keycloak_client_secret_grafana >/dev/null
```

## 3. Push to Nextcloud

```bash
NEXTCLOUD_SECRET="$(terraform output -raw keycloak_client_secret_nextcloud)"

ssh nimbus-cloud-01 "sudo -u www-data php /var/www/nextcloud/occ user_oidc:provider Keycloak \
  --clientid='nextcloud' \
  --clientsecret='$NEXTCLOUD_SECRET' \
  --discoveryuri='https://auth.nimbusnode.org/realms/nimbus/.well-known/openid-configuration' \
  --scope='openid profile email' \
  --mapping-uid=preferred_username \
  --mapping-display-name=name \
  --mapping-email=email \
  --unique-uid=0"

unset NEXTCLOUD_SECRET
```

Verify:

```bash
curl -fsS https://cloud.nimbusnode.org/status.php | jq .
```

Then test a browser login through the "Log in with Keycloak" button.

## 4. Push to Grafana

```bash
GRAFANA_SECRET="$(terraform output -raw keycloak_client_secret_grafana)"

printf '%s' "$GRAFANA_SECRET" | ssh nimbus-mon '
  secret="$(cat)"
  sudo sed -i "s|^GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=.*|GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=${secret}|" /etc/default/grafana-server
  sudo systemctl restart grafana-server
  unset secret
'

unset GRAFANA_SECRET
```

Verify:

```bash
ssh nimbus-mon 'systemctl is-active grafana-server'
curl -kI https://mon.nimbus.local/login/generic_oauth
```

Expected: Grafana returns a redirect to Keycloak. Finish with a browser login.

## 5. Push to MinIO console

```bash
MINIO_SECRET="$(terraform output -raw keycloak_client_secret_minio_console)"

printf '%s' "$MINIO_SECRET" | ssh nimbus-s3 '
  secret="$(cat)"
  sudo sed -i "s|^MINIO_IDENTITY_OPENID_CLIENT_SECRET=.*|MINIO_IDENTITY_OPENID_CLIENT_SECRET=${secret}|" /etc/default/minio
  sudo systemctl restart minio
  unset secret
'

unset MINIO_SECRET
```

Verify:

```bash
ssh nimbus-s3 'systemctl is-active minio'
ssh nimbus-s3 "sudo grep -qx 'MINIO_IDENTITY_OPENID_CLAIM_NAME=groups' /etc/default/minio"
curl -fsS http://10.0.20.101:9001 >/dev/null
```

Then test "Login with SSO" in the MinIO console as a user in the Keycloak
`consoleAdmin` group. Users outside that group can authenticate, but should not
receive MinIO permissions.

## 6. Push to Vault

The Vault OIDC secret is managed by Terraform through
`vault_jwt_auth_backend.oidc`.

```bash
terraform apply -refresh-only -target=keycloak_openid_client.vault
terraform apply -target=vault_jwt_auth_backend.oidc
```

Verify CLI login:

```bash
export VAULT_ADDR=https://10.0.100.40:8200
export VAULT_SKIP_VERIFY=true

vault login -method=oidc role=vault-admins
vault token lookup
```

Expected policies include `admin` and `default`.

## 7. Final check

```bash
terraform plan
unset VAULT_TOKEN
```

Expected: no unexpected OIDC-client drift. If only the refreshed client secret
is reflected in state, apply the plan and keep the state current.

## Rollback

Keycloak does not keep the previous client secret after regeneration. Rollback
means regenerating a new secret again, refreshing Terraform state, and pushing
that new value to the consumer.
