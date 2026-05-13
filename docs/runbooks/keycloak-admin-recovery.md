# Runbook - Keycloak admin recovery

Recover admin access to the `nimbus` realm without rebuilding `nimbus-iam`.

## Scope

Use this when:

- `nimbus-admin` is locked, disabled, or its password is lost.
- The `nimbus-admin` realm-management role assignment drifted.
- You need a clean temporary password for an admin smoke test.

Do not use this for normal user onboarding. Manage users and groups through
Terraform or the Keycloak admin console once admin access is restored.

## Prereqs

- `nimbus-iam` is running on `10.0.100.30`.
- You have the current `master` realm `admin` password.
- SSH access through `nimbus-bastion`.

In the current lab, the `master` admin password is also the Terraform provider
credential. If you rotate it manually without updating the provider auth model,
future Keycloak Terraform plans will fail. Keep it as break-glass until a
dedicated Terraform service account is added.

## 1. Check Keycloak health

```bash
curl -fsS https://auth.nimbusnode.org/realms/nimbus/.well-known/openid-configuration >/dev/null

ssh -J nimbus-bastion nimbus@10.0.100.30 \
  'systemctl is-active keycloak && sudo journalctl -u keycloak -n 30 --no-pager'
```

## 2. Get the break-glass master admin password

If it has not been manually rotated:

```bash
cd ~/code/nimbus-infra/terraform
terraform output -raw keycloak_admin_password
```

If it has been rotated, retrieve the current value from your password manager.
Do not paste the password into chat or commit it to the repo.

## 3. Reset `nimbus-admin`

SSH to the Keycloak VM with a TTY so the password prompt is not recorded in
shell history:

```bash
ssh -t -J nimbus-bastion nimbus@10.0.100.30
```

On `nimbus-iam`:

```bash
sudo -iu keycloak

/opt/keycloak/bin/kcadm.sh config credentials \
  --server https://auth.nimbusnode.org \
  --realm master \
  --user admin
```

Enter the master admin password when prompted.

Set a temporary password for `nimbus-admin`:

```bash
NEW_PASS="$(openssl rand -base64 24)"

/opt/keycloak/bin/kcadm.sh set-password \
  -r nimbus \
  --username nimbus-admin \
  --new-password "$NEW_PASS" \
  --temporary

printf 'temporary nimbus-admin password: %s\n' "$NEW_PASS"
unset NEW_PASS
```

Log in at `https://auth.nimbusnode.org/admin/` as `nimbus-admin` and complete
the forced password change.

## 4. Restore realm-admin if needed

If `nimbus-admin` can log in but cannot manage the realm:

```bash
/opt/keycloak/bin/kcadm.sh add-roles \
  -r nimbus \
  --uusername nimbus-admin \
  --cclientid realm-management \
  --rolename realm-admin
```

Then run a normal Terraform apply from the repo to reconcile managed users,
groups, and role assignments:

```bash
cd ~/code/nimbus-infra/terraform
terraform plan
terraform apply
```

## 5. Verify

```bash
# Discovery endpoint is public through the Cloudflare Tunnel.
curl -fsS https://auth.nimbusnode.org/realms/nimbus/.well-known/openid-configuration \
  | jq -r '.issuer'

# Admin user exists and is enabled.
ssh -J nimbus-bastion nimbus@10.0.100.30 \
  "sudo -iu keycloak /opt/keycloak/bin/kcadm.sh get users -r nimbus -q username=nimbus-admin --fields username,enabled"
```

Expected issuer:

```text
https://auth.nimbusnode.org/realms/nimbus
```

## If master admin is also lost

Do not edit the Keycloak database by hand as a first move.

Preferred recovery order:

1. Retrieve the current master admin password from the password manager.
2. Restore the `keycloak` database or a nightly realm export from MinIO.
3. Rebuild `nimbus-iam` only if the database and exports are unusable.

After any restore, re-run Terraform so the `nimbus` realm, clients, groups, and
seed users match the repo.
