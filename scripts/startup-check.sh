#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MACHINE_ID="${MACHINE_ID:-server01}"
ENV_FILE="${REPO_ROOT}/env/${MACHINE_ID}.env"
N8N_ENV_FILE="${REPO_ROOT}/runtime/${MACHINE_ID}/secrets/n8n.env"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/notify-discord.sh"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

if [[ -f "${N8N_ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${N8N_ENV_FILE}"
  set +a
fi

log_step() { echo "▶ $1"; }
log_info() { echo "• $1"; }
log_success() { echo "✓ $1"; }
log_warn() { echo "⚠ $1"; }
log_error() { echo "✗ $1"; }

emit_n8n_event() {
  local severity="$1"
  local title="$2"
  local message="$3"

  if [[ -z "${N8N_EVENT_WEBHOOK_URL:-}" ]]; then
    log_warn "N8N_EVENT_WEBHOOK_URL is not set; skipping n8n event"
    return 0
  fi

  if [[ ! -x "${SCRIPT_DIR}/emit-event.sh" ]]; then
    log_warn "emit-event.sh is missing or not executable; skipping n8n event"
    return 0
  fi

  if ! "${SCRIPT_DIR}/emit-event.sh" \
    "docker-services" \
    "startup-check" \
    "${severity}" \
    "${title}" \
    "${message}" \
    "docker"; then
    log_warn "Failed to emit n8n event"
  else
    log_info "Emitted n8n event successfully"
  fi
}

if [[ ! -f "${ENV_FILE}" ]]; then
  log_error "Missing ${ENV_FILE}"
  emit_n8n_event \
    "error" \
    "Startup Check Failed" \
    "docker-services startup check could not find env file: ${ENV_FILE}"
  exit 1
fi

cd "${REPO_ROOT}"

log_step "Validating docker-compose configuration..."
"${REPO_ROOT}/dc" --profile apps config >/dev/null
log_success "docker-compose configuration is valid"

log_step "Checking service state..."
status_lines="$(
  "${REPO_ROOT}/dc" --profile apps ps --all --orphans=false --format json \
  | jq -r '
      if type == "array" then .[] else . end
      | [
          (.Name // .Service // "unknown"),
          (.State // .Status // "unknown"),
          (
            if (.Health // "") == ""
            then "none"
            else .Health
            end
          )
        ]
      | @tsv
    '
)"

if [[ -z "${status_lines}" ]]; then
  log_error "No docker compose services found"
  send_discord_error \
    "Startup Check Failed" \
    "docker-services startup check found no services." \
    "docker-startup-check"
  emit_n8n_event \
    "error" \
    "Startup Check Failed" \
    "docker-services startup check found no services."
  exit 1
fi

bad_lines=""
summary_lines=""

while IFS=$'\t' read -r name state health; do
  [[ -z "${name}" ]] && continue

  summary_lines+="${name}: state=${state}, health=${health}"$'\n'

  case "${state}" in
    exited|dead|restarting)
      bad_lines+="${name}: state=${state}, health=${health}"$'\n'
      ;;
    *)
      if [[ "${health}" == "unhealthy" ]]; then
        bad_lines+="${name}: state=${state}, health=${health}"$'\n'
      fi
      ;;
  esac
done <<< "${status_lines}"

if [[ -n "${bad_lines}" ]]; then
  log_warn "Some services are not healthy"
  printf '%s' "${bad_lines}"

  send_discord_warning \
    "Startup Check Warning" \
    "docker-services startup check found services not fully healthy.\n\n${bad_lines}" \
    "docker-startup-check"

  emit_n8n_event \
    "warning" \
    "Startup Check Warning" \
    "docker-services startup check found services not fully healthy.\n\n${bad_lines}"

  exit 1
fi

log_success "All detected services are running acceptably"

send_discord_success \
  "Startup Check Passed" \
  "docker-services startup check passed.\n\n${summary_lines}" \
  "docker-startup-check"

emit_n8n_event \
  "ok" \
  "Startup Check Passed" \
  "docker-services startup check passed.\n\n${summary_lines}"
