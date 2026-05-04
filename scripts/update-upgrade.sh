#!/usr/bin/env bash
# scripts/update-upgrade.sh
#
# Run apt update + upgrade on every Nimbus VM via the bastion jump host.
# Usage:
#   ./scripts/update-upgrade.sh                 # all VMs
#   ./scripts/update-upgrade.sh --only nimbus-alb,nimbus-dns
#   ./scripts/update-upgrade.sh --reboot        # auto-reboot VMs that need it
#   ./scripts/update-upgrade.sh --dry-run       # check connectivity + pending upgrades only

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
ADMIN_USER="${NIMBUS_ADMIN_USER:-nimbus}"
BASTION_IP="${NIMBUS_BASTION_IP:-10.0.1.20}"
SSH_KEY="${NIMBUS_SSH_KEY:-}"   # leave empty to use ssh-agent / default key

# ── VM inventory ──────────────────────────────────────────────────────────────
# Ordered: bastion first (no jump needed), then internal VMs via bastion.
declare -A VM_IPS=(
  ["nimbus-bastion"]="10.0.1.20"
  ["nimbus-alb"]="10.0.1.10"
  ["nimbus-dns"]="10.0.100.10"
  ["nimbus-mon"]="10.0.100.20"
  ["nimbus-cloud-01"]="10.0.10.102"
  ["nimbus-s3"]="10.0.20.101"
  ["nimbus-rds"]="10.0.20.103"
)
VM_ORDER=(nimbus-bastion nimbus-alb nimbus-dns nimbus-mon nimbus-cloud-01 nimbus-s3 nimbus-rds)

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi

log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${RESET} $*"; }
ok()   { echo -e "${GREEN}  ✓${RESET} $*"; }
warn() { echo -e "${YELLOW}  ⚠${RESET} $*"; }
err()  { echo -e "${RED}  ✗${RESET} $*"; }

# ── SSH helpers ───────────────────────────────────────────────────────────────
SSH_COMMON_OPTS=(
  -o StrictHostKeyChecking=no
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o ServerAliveInterval=30
)
[[ -n "$SSH_KEY" ]] && SSH_COMMON_OPTS+=(-i "$SSH_KEY")

ssh_run() {
  local ip="$1"; shift
  local cmd="$*"
  if [[ "$ip" == "$BASTION_IP" ]]; then
    ssh "${SSH_COMMON_OPTS[@]}" "${ADMIN_USER}@${ip}" "$cmd"
  else
    ssh "${SSH_COMMON_OPTS[@]}" \
      -J "${ADMIN_USER}@${BASTION_IP}" \
      "${ADMIN_USER}@${ip}" "$cmd"
  fi
}

can_reach() {
  local ip="$1"
  ssh_run "$ip" "true" &>/dev/null
}

# ── Commands run on each VM ───────────────────────────────────────────────────
APT_UPDATE_UPGRADE='
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update -qq 2>&1 | tail -3
  sudo apt-get upgrade -y \
    -o Dpkg::Options::="--force-confold" \
    -o Dpkg::Options::="--force-confdef" \
    2>&1 | grep -E "upgraded|newly|removed|not upgraded|Err:|error" || true
  sudo apt-get autoremove -y -qq
  sudo apt-get clean -qq
'
APT_DRY_RUN='
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update -qq 2>&1 | tail -1
  echo "Upgradeable packages:"
  apt list --upgradeable 2>/dev/null | grep -v "^Listing" || echo "  (none)"
'
REBOOT_CHECK='test -f /var/run/reboot-required && echo REBOOT_REQUIRED || echo OK'
DO_REBOOT='sudo systemctl reboot'

# ── Flags ─────────────────────────────────────────────────────────────────────
ONLY_VMS=()
AUTO_REBOOT=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)   IFS=',' read -ra ONLY_VMS <<< "$2"; shift 2 ;;
    --reboot) AUTO_REBOOT=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Main ──────────────────────────────────────────────────────────────────────
REBOOT_NEEDED=()
FAILED=()
SKIPPED=()

header() {
  local name="$1" ip="$2"
  printf "\n${BOLD}── %-20s %s ─${RESET}\n" "$name" "$ip" \
    | head -c 60; echo "${RESET}"
  echo -e "${BOLD}── ${name} (${ip}) ──────────────────────────────────────────${RESET}"
}

process_vm() {
  local name="$1"
  local ip="${VM_IPS[$name]}"

  header "$name" "$ip"

  if ! can_reach "$ip"; then
    err "Unreachable — skipping"
    SKIPPED+=("$name")
    return
  fi

  if $DRY_RUN; then
    log "Dry-run: checking pending upgrades..."
    ssh_run "$ip" "$APT_DRY_RUN" || { err "Check failed"; FAILED+=("$name"); return; }
  else
    log "Updating packages..."
    ssh_run "$ip" "$APT_UPDATE_UPGRADE" || { err "Upgrade failed"; FAILED+=("$name"); return; }
    ok "Packages updated"
  fi

  local reboot_status
  reboot_status=$(ssh_run "$ip" "$REBOOT_CHECK" 2>/dev/null) || reboot_status="UNKNOWN"

  if [[ "$reboot_status" == "REBOOT_REQUIRED" ]]; then
    if $AUTO_REBOOT && ! $DRY_RUN; then
      warn "Rebooting $name..."
      ssh_run "$ip" "$DO_REBOOT" 2>/dev/null || true
      ok "Reboot initiated"
    else
      warn "Reboot required (run with --reboot to auto-reboot)"
      REBOOT_NEEDED+=("$name  $ip")
    fi
  else
    ok "No reboot needed"
  fi
}

echo -e "${BOLD}Nimbus VM Update & Upgrade${RESET}"
echo "  Admin user : $ADMIN_USER"
echo "  Bastion    : $BASTION_IP"
$DRY_RUN  && echo -e "  Mode       : ${YELLOW}DRY-RUN (no changes)${RESET}"
$AUTO_REBOOT && echo -e "  Mode       : ${YELLOW}auto-reboot enabled${RESET}"
echo "  Started    : $(date)"

for name in "${VM_ORDER[@]}"; do
  if [[ ${#ONLY_VMS[@]} -gt 0 ]] && [[ ! " ${ONLY_VMS[*]} " =~ " ${name} " ]]; then
    continue
  fi
  process_vm "$name"
done

echo ""
echo -e "${BOLD}── Summary ─────────────────────────────────────────────────${RESET}"

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo -e "${YELLOW}Skipped (unreachable):${RESET}"
  printf '  - %s\n' "${SKIPPED[@]}"
fi

if [[ ${#REBOOT_NEEDED[@]} -gt 0 ]]; then
  echo -e "${YELLOW}Reboot required:${RESET}"
  printf '  - %s\n' "${REBOOT_NEEDED[@]}"
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo -e "${RED}Failed:${RESET}"
  printf '  - %s\n' "${FAILED[@]}"
  exit 1
fi

if [[ ${#SKIPPED[@]} -eq 0 && ${#REBOOT_NEEDED[@]} -eq 0 && ${#FAILED[@]} -eq 0 ]]; then
  echo -e "${GREEN}All VMs updated successfully.${RESET}"
fi
