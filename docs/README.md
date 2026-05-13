# Nimbus Docs

This directory is organized by how the document is used:

- `phases/` — phase-scoped build guides, migration notes, and punch lists.
- `runbooks/` — repeatable operating procedures and verification steps.
- `reference/` — supporting config snippets, SSH inventory, and topology notes.
- `images/` — rendered diagrams and visual assets used by the main README.

Current high-value entry points:

- `phases/phase-7-iam.md` — Keycloak and Vault build guide.
- `phases/phase-8-iac-hardening.md` — IaC hardening punch list.
- `runbooks/vault-init.md` — manual Vault initialization and unseal procedure.
- `runbooks/keycloak-admin-recovery.md` — recover `nimbus-admin` realm admin access.
- `runbooks/oidc-client-rotation.md` — rotate Keycloak OIDC client secrets and push them to apps.
- `runbooks/tailscale-acl.md` — manage the tailnet policy and Nimbus subnet router through GitOps.
- `phases/phase-3-dns.md` — PowerDNS architecture and verification.
- `phases/phase-3-dns-copy-paste.md` — older copy-paste DNS setup flow.
- `reference/ssh-config.txt` — SSH config for Nimbus lab hosts.
