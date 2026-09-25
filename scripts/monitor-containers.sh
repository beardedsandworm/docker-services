#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MACHINE_ID="${MACHINE_ID:-server01}"
ENV_FILE="${REPO_ROOT}/env/${MACHINE_ID}.env"
N8N_ENV_FILE="${REPO_ROOT}/runtime/${MACHINE_ID}/secrets/n8n.env"
STATE_DIR="${REPO_ROOT}/runtime/${MACHINE_ID}/monitor"
STATE_FILE="${STATE_DIR}/state.tsv"
TMP_FILE="$(mktemp)"

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

log_info() { echo "• $1"; }
log_warn() { echo "⚠ $1"; }
log_error() { echo "✗ $1"; }
log_success() { echo "✓ $1"; }

emit_n8n_event() {
  local severity="$1"
  local title="$2"
  local message="$3"
  local service="${4:-docker}"

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
    "container-monitor" \
    "${severity}" \
    "${title}" \
    "${message}" \
    "${service}"; then
    log_warn "Failed to emit n8n event for ${service}"
  else
    log_info "Emitted n8n event successfully for ${service}"
  fi
}

cleanup() {
  rm -f "${TMP_FILE}"
}
trap cleanup EXIT

mkdir -p "${STATE_DIR}"

if [[ ! -f "${ENV_FILE}" ]]; then
  log_error "Missing ${ENV_FILE}"
  emit_n8n_event \
    "error" \
    "Container Monitor Failed" \
    "docker-services container monitor could not find env file: ${ENV_FILE}" \
    "docker"
  exit 1
fi

cd "${REPO_ROOT}"

"${REPO_ROOT}/dc" ps --all --orphans=false --format json \
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
    ' \
  | sort > "${TMP_FILE}"

if [[ ! -f "${STATE_FILE}" ]]; then
  cp "${TMP_FILE}" "${STATE_FILE}"

  send_discord_info \
    "Monitor Initialized" \
    "docker-services monitor initialized successfully." \
    "docker-monitor"

  emit_n8n_event \
    "info" \
    "Monitor Initialized" \
    "docker-services monitor initialized successfully." \
    "docker"

  exit 0
fi

join -t $'\t' -a1 -a2 -e "missing" -o '0,1.2,1.3,2.2,2.3' \
  <(sort "${STATE_FILE}") \
  <(sort "${TMP_FILE}") \
  | while IFS=$'\t' read -r name old_state old_health new_state new_health; do

    if [[ "${old_state}" == "${new_state}" && "${old_health}" == "${new_health}" ]]; then
      continue
    fi

    if [[ "${new_state}" == "running" && "${new_health}" == "healthy" ]]; then
      send_discord_success \
        "Container Recovered" \
        "${name} recovered.\n\nOld: state=${old_state}, health=${old_health}\nNew: state=${new_state}, health=${new_health}" \
        "docker-monitor"

      emit_n8n_event \
        "ok" \
        "Container Recovered" \
        "${name} recovered.\n\nOld: state=${old_state}, health=${old_health}\nNew: state=${new_state}, health=${new_health}" \
        "${name}"

    elif [[ "${new_state}" == "running" && "${new_health}" == "unhealthy" ]]; then
      send_discord_error \
        "Container Unhealthy" \
        "${name} became unhealthy.\n\nOld: state=${old_state}, health=${old_health}\nNew: state=${new_state}, health=${new_health}" \
        "docker-monitor"

      emit_n8n_event \
        "error" \
        "Container Unhealthy" \
        "${name} became unhealthy.\n\nOld: state=${old_state}, health=${old_health}\nNew: state=${new_state}, health=${new_health}" \
        "${name}"

    elif [[ "${new_state}" == "exited" || "${new_state}" == "dead" ]]; then
      send_discord_error \
        "Container Stopped" \
        "${name} stopped.\n\nOld: state=${old_state}, health=${old_health}\nNew: state=${new_state}, health=${new_health}" \
        "docker-monitor"

      emit_n8n_event \
        "error" \
        "Container Stopped" \
        "${name} stopped.\n\nOld: state=${old_state}, health=${old_health}\nNew: state=${new_state}, health=${new_health}" \
        "${name}"

    elif [[ "${new_state}" == "restarting" ]]; then
      send_discord_warning \
        "Container Restarting" \
        "${name} is restarting.\n\nOld: state=${old_state}, health=${old_health}\nNew: state=${new_state}, health=${new_health}" \
        "docker-monitor"

      emit_n8n_event \
        "warning" \
        "Container Restarting" \
        "${name} is restarting.\n\nOld: state=${old_state}, health=${old_health}\nNew: state=${new_state}, health=${new_health}" \
        "${name}"

    elif [[ "${new_state}" == "missing" ]]; then
      send_discord_warning \
        "Container Missing" \
        "${name} disappeared from docker-services." \
        "docker-monitor"

      emit_n8n_event \
        "warning" \
        "Container Missing" \
        "${name} disappeared from docker-services." \
        "${name}"

    elif [[ "${old_state}" == "missing" ]]; then
      send_discord_success \
        "Container Added" \
        "${name} appeared.\n\nState=${new_state}, health=${new_health}" \
        "docker-monitor"

      emit_n8n_event \
        "ok" \
        "Container Added" \
        "${name} appeared.\n\nState=${new_state}, health=${new_health}" \
        "${name}"

    else
      send_discord_info \
        "Container State Changed" \
        "${name} changed.\n\nOld: state=${old_state}, health=${old_health}\nNew: state=${new_state}, health=${new_health}" \
        "docker-monitor"

      emit_n8n_event \
        "info" \
        "Container State Changed" \
        "${name} changed.\n\nOld: state=${old_state}, health=${old_health}\nNew: state=${new_state}, health=${new_health}" \
        "${name}"
    fi
done

cp "${TMP_FILE}" "${STATE_FILE}"
