#!/usr/bin/env bash
# scripts/smoke-test.sh
#
# Phase 8 post-rebuild smoke checks for Nimbus.
# Usage:
#   ./scripts/smoke-test.sh
#   ./scripts/smoke-test.sh --skip-external
#   ./scripts/smoke-test.sh --skip-ssh
#   NIMBUS_SSH_JUMP=nimbus@10.0.1.20 ./scripts/smoke-test.sh

set -u

# Config
ADMIN_USER="${NIMBUS_ADMIN_USER:-nimbus}"
AIO_USER="${NIMBUS_AIO_USER:-serveradmin}"
SSH_KEY="${NIMBUS_SSH_KEY:-}"
SSH_JUMP="${NIMBUS_SSH_JUMP:-}"
SSH_TIMEOUT="${NIMBUS_SSH_TIMEOUT:-8}"
HTTP_TIMEOUT="${NIMBUS_HTTP_TIMEOUT:-10}"

DNS_IP="${NIMBUS_DNS_IP:-10.0.100.10}"
ALB_IP="${NIMBUS_ALB_IP:-10.0.1.10}"
CLOUD_PUBLIC_URL="${NIMBUS_CLOUD_PUBLIC_URL:-https://cloud.nimbusnode.org}"
AIO_PUBLIC_URL="${NIMBUS_AIO_PUBLIC_URL:-https://aio.nimbusnode.org}"
AUTH_PUBLIC_URL="${NIMBUS_AUTH_PUBLIC_URL:-https://auth.nimbusnode.org}"
REALM="${NIMBUS_KEYCLOAK_REALM:-nimbus}"

SKIP_EXTERNAL=false
SKIP_SSH=false
SKIP_DNS=false

declare -A HOST_IPS=(
  ["nimbus-bastion"]="10.0.1.20"
  ["nimbus-alb"]="10.0.1.10"
  ["nimbus-dns"]="10.0.100.10"
  ["nimbus-mon"]="10.0.100.20"
  ["nimbus-cloud-01"]="10.0.10.102"
  ["nimbus-s3"]="10.0.20.101"
  ["nimbus-rds"]="10.0.20.103"
  ["nimbus-iam"]="10.0.100.30"
  ["nimbus-vault"]="10.0.100.40"
  ["nimbus-aio"]="192.168.1.72"
)

declare -A HOST_USERS=(
  ["nimbus-aio"]="$AIO_USER"
)

HOST_ORDER=(
  nimbus-bastion
  nimbus-alb
  nimbus-dns
  nimbus-mon
  nimbus-cloud-01
  nimbus-s3
  nimbus-rds
  nimbus-iam
  nimbus-vault
  nimbus-aio
)

if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  CYAN=''
  BOLD=''
  RESET=''
fi

PASS=0
FAIL=0
WARN=0
SKIP=0
FAILED_CHECKS=()

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-external) SKIP_EXTERNAL=true; shift ;;
    --skip-ssh) SKIP_SSH=true; shift ;;
    --skip-dns) SKIP_DNS=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 2 ;;
  esac
done

log_section() {
  printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"
}

pass() {
  PASS=$((PASS + 1))
  printf '%b[PASS]%b %s\n' "$GREEN" "$RESET" "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  FAILED_CHECKS+=("$1")
  printf '%b[FAIL]%b %s\n' "$RED" "$RESET" "$1"
}

warn() {
  WARN=$((WARN + 1))
  printf '%b[WARN]%b %s\n' "$YELLOW" "$RESET" "$1"
}

skip() {
  SKIP=$((SKIP + 1))
  printf '%b[SKIP]%b %s\n' "$CYAN" "$RESET" "$1"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run_check() {
  local name="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    pass "$name"
  else
    fail "$name"
    if [[ -n "$output" ]]; then
      printf '       %s\n' "$output" | tail -8
    fi
  fi
}

http_code() {
  local url="$1"
  curl -k -sS --max-time "$HTTP_TIMEOUT" -o /dev/null -w '%{http_code}' "$url"
}

check_http() {
  local name="$1"
  local url="$2"
  local allowed="$3"
  local code
  if ! code="$(http_code "$url")"; then
    fail "$name"
    return
  fi
  if [[ " $allowed " == *" $code "* ]]; then
    pass "$name ($code)"
  else
    fail "$name (HTTP $code, expected one of: $allowed)"
  fi
}

dig_short() {
  local server="$1"
  local name="$2"
  if have_cmd dig; then
    dig @"$server" "$name" +short
  elif have_cmd nslookup; then
    nslookup "$name" "$server" 2>/dev/null | awk '/^Address: / { print $2 }' | tail -1
  else
    return 127
  fi
}

check_dns() {
  local name="$1"
  local query="$2"
  local expected="$3"
  local got
  if ! have_cmd dig && ! have_cmd nslookup; then
    skip "$name (dig/nslookup not installed)"
    return
  fi
  got="$(dig_short "$DNS_IP" "$query" | tr '\n' ' ')"
  if [[ " $got " == *" $expected "* ]]; then
    pass "$name ($query -> $expected)"
  else
    fail "$name ($query -> ${got:-empty}, expected $expected)"
  fi
}

ssh_base_opts() {
  printf '%s\n' \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout="$SSH_TIMEOUT" \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=2
}

ssh_run() {
  local host="$1"
  shift
  local ip="${HOST_IPS[$host]}"
  local user="${HOST_USERS[$host]:-$ADMIN_USER}"
  local opts=()
  local opt

  while IFS= read -r opt; do
    opts+=("$opt")
  done < <(ssh_base_opts)

  if [[ -n "$SSH_KEY" ]]; then
    opts+=(-i "$SSH_KEY")
  fi
  if [[ -n "$SSH_JUMP" && "$host" != "nimbus-bastion" && "$host" != "nimbus-aio" ]]; then
    opts+=(-J "$SSH_JUMP")
  fi

  ssh "${opts[@]}" "${user}@${ip}" "$@"
}

check_ssh() {
  local host="$1"
  run_check "ssh $host" ssh_run "$host" "hostname >/dev/null"
}

check_service() {
  local host="$1"
  local service="$2"
  run_check "$host service $service" ssh_run "$host" "sudo systemctl is-active --quiet '$service'"
}

check_remote() {
  local host="$1"
  local name="$2"
  local cmd="$3"
  run_check "$host $name" ssh_run "$host" "$cmd"
}

external_checks() {
  if $SKIP_EXTERNAL; then
    skip "external HTTP checks disabled"
    return
  fi

  log_section "External Ingress"
  check_http "cloud status endpoint" "$CLOUD_PUBLIC_URL/status.php" "200"
  check_http "cloud .mjs MIME probe" "$CLOUD_PUBLIC_URL/apps/settings/js/esm-test.mjs" "200"
  check_http "AIO login page" "$AIO_PUBLIC_URL/login" "200"
  check_http "Keycloak OIDC discovery" "$AUTH_PUBLIC_URL/realms/$REALM/.well-known/openid-configuration" "200"

  local mjs_type
  mjs_type="$(curl -k -sS -I --max-time "$HTTP_TIMEOUT" "$CLOUD_PUBLIC_URL/apps/settings/js/esm-test.mjs" \
    | awk 'BEGIN{IGNORECASE=1} /^content-type:/ {print $2}' \
    | tr -d '\r')"
  if [[ "$mjs_type" == "application/javascript" || "$mjs_type" == "text/javascript" ]]; then
    pass "cloud .mjs Content-Type ($mjs_type)"
  else
    fail "cloud .mjs Content-Type (${mjs_type:-missing})"
  fi
}

dns_checks() {
  if $SKIP_DNS; then
    skip "DNS checks disabled"
    return
  fi

  log_section "Internal DNS"
  check_dns "cloud split-horizon" "cloud.nimbusnode.org" "$ALB_IP"
  check_dns "AIO split-horizon" "aio.nimbusnode.org" "$ALB_IP"
  check_dns "ALB record" "nimbus-alb.nimbus.local" "$ALB_IP"
  check_dns "Grafana record" "mon.nimbus.local" "$ALB_IP"
  check_dns "Vault record" "vault.nimbus.local" "10.0.100.40"
}

ssh_checks() {
  if $SKIP_SSH; then
    skip "SSH/service checks disabled"
    return
  fi

  log_section "SSH Reachability"
  local host
  for host in "${HOST_ORDER[@]}"; do
    check_ssh "$host"
  done

  log_section "Core Services"
  check_service nimbus-alb haproxy
  check_service nimbus-alb cloudflared
  check_service nimbus-dns pdns
  check_service nimbus-dns pdns-recursor
  check_service nimbus-mon prometheus
  check_service nimbus-mon grafana-server
  check_service nimbus-mon loki
  check_service nimbus-cloud-01 nginx
  check_service nimbus-cloud-01 php8.3-fpm
  check_service nimbus-cloud-01 redis-server
  check_service nimbus-cloud-01 vault-agent
  check_service nimbus-s3 minio
  check_service nimbus-rds postgresql
  check_service nimbus-rds pg-backup.timer
  check_service nimbus-iam keycloak
  check_service nimbus-vault vault

  log_section "Application Probes"
  check_remote nimbus-alb "HAProxy cloud route" \
    "curl -fsS -o /dev/null -H 'Host: cloud.nimbusnode.org' http://127.0.0.1/status.php"
  check_remote nimbus-alb "HAProxy AIO route" \
    "curl -fsS -o /dev/null -H 'Host: aio.nimbusnode.org' http://127.0.0.1/login"
  check_remote nimbus-mon "Prometheus ready" "curl -fsS http://127.0.0.1:9090/-/ready >/dev/null"
  check_remote nimbus-mon "Loki ready" "curl -fsS http://127.0.0.1:3100/ready >/dev/null"
  check_remote nimbus-mon "Grafana health" "curl -fsS http://127.0.0.1:3000/api/health >/dev/null"
  check_remote nimbus-cloud-01 "Nextcloud occ status" \
    "sudo -u www-data php /var/www/nextcloud/occ status | grep -q 'installed: true'"
  check_remote nimbus-cloud-01 "Nextcloud setupchecks criticals" \
    "sudo -u www-data php /var/www/nextcloud/occ setupchecks --output=json | grep -q '\"severity\":\"success\"'"
  check_remote nimbus-cloud-01 "Redis ping" "redis-cli ping | grep -q PONG"
  check_remote nimbus-s3 "MinIO ready" "curl -fsS http://127.0.0.1:9000/minio/health/ready >/dev/null"
  check_remote nimbus-s3 "MinIO OIDC groups claim" \
    "sudo grep -qx 'MINIO_IDENTITY_OPENID_CLAIM_NAME=groups' /etc/default/minio && ! sudo grep -q '^MINIO_IDENTITY_OPENID_ROLE_POLICY=' /etc/default/minio"
  check_remote nimbus-s3 "pg-backups retention default" \
    "sudo HOME=/root /usr/local/bin/mc.minio --no-color --config-dir /root/.mc.minio retention info --default local/pg-backups | grep -qi 'COMPLIANCE'"
  check_remote nimbus-rds "Postgres ready" "pg_isready -h 127.0.0.1 -p 5432 >/dev/null"
  check_remote nimbus-iam "Keycloak realm discovery" \
    "curl -kfsS https://127.0.0.1:8443/realms/$REALM/.well-known/openid-configuration >/dev/null"
  check_remote nimbus-vault "Vault health" \
    "code=\$(curl -ksS -o /dev/null -w '%{http_code}' https://127.0.0.1:8200/v1/sys/health); case \"\$code\" in 200|429|472|473) exit 0;; *) echo \"vault health HTTP \$code\"; exit 1;; esac"
  check_remote nimbus-aio "AIO containers healthy" \
    "docker inspect -f '{{.Name}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' nextcloud-aio-apache nextcloud-aio-nextcloud nextcloud-aio-mastercontainer | grep -vq unhealthy"
  check_remote nimbus-aio "AIO login backend" "curl -fsS -o /dev/null http://127.0.0.1:11000/login"
}

main() {
  log_section "Nimbus Smoke Test"
  echo "Started: $(date)"
  echo "SSH user: $ADMIN_USER"
  echo "AIO user: $AIO_USER"
  if [[ -n "$SSH_JUMP" ]]; then
    echo "SSH jump: $SSH_JUMP"
  fi

  if ! have_cmd curl; then
    fail "curl is required"
  fi
  if ! have_cmd ssh; then
    fail "ssh is required"
  fi
  if [[ "$FAIL" -gt 0 ]]; then
    exit 2
  fi

  external_checks
  dns_checks
  ssh_checks

  log_section "Summary"
  echo "Pass: $PASS"
  echo "Warn: $WARN"
  echo "Skip: $SKIP"
  echo "Fail: $FAIL"

  if [[ "$FAIL" -gt 0 ]]; then
    printf '\nFailed checks:\n'
    printf '  - %s\n' "${FAILED_CHECKS[@]}"
    exit 1
  fi

  echo "Smoke test passed."
}

main "$@"
