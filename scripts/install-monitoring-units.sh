#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SYSTEMD_DIR="${REPO_ROOT}/systemd"

DOCKER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/docker-services"
DOCKER_WEBHOOK_FILE="${DOCKER_CONFIG_DIR}/discord-webhook"

NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
DOCKER_SERVICES_DISCORD_WEBHOOK_URL="${DOCKER_SERVICES_DISCORD_WEBHOOK_URL:-}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/notify-discord.sh"

INSTALL_SUCCEEDED="false"

log_step() {
  echo "▶ $1"
}

log_info() {
  echo "• $1"
}

log_success() {
  echo "✓ $1"
}

log_warn() {
  echo "⚠ $1"
}

log_error() {
  echo "✗ $1"
}

on_exit() {
  local exit_code="$?"

  if [[ "${INSTALL_SUCCEEDED}" == "true" ]]; then
    send_discord_success \
      "Monitoring Install Succeeded" \
      "docker-services monitoring units installed, enabled, and smoke-tested successfully." \
      "docker-monitor-install"
    exit 0
  fi

  if [[ "${exit_code}" -ne 0 ]]; then
    send_discord_error \
      "Monitoring Install Failed" \
      "docker-services monitoring install failed with exit code ${exit_code}." \
      "docker-monitor-install" || true
  fi

  exit "${exit_code}"
}

trap on_exit EXIT

require_file() {
  local path="${1}"
  if [[ ! -f "${path}" ]]; then
    log_error "Missing required file: ${path}"
    exit 1
  fi
}

write_webhook_file() {
  local webhook_url="${1}"

  mkdir -p "${DOCKER_CONFIG_DIR}"
  chmod 700 "${DOCKER_CONFIG_DIR}"

  printf '%s\n' "${webhook_url}" > "${DOCKER_WEBHOOK_FILE}"
  chmod 600 "${DOCKER_WEBHOOK_FILE}"

  log_success "Wrote dedicated docker-services webhook to ${DOCKER_WEBHOOK_FILE}"
}

prompt_for_webhook() {
  local entered_webhook=""

  echo
  log_info "Enter a Discord webhook URL for docker-services alerts."
  log_info "This should point to a dedicated Docker/containers channel."
  log_info "Leave blank to skip webhook creation."

  read -r -p "Discord webhook URL: " entered_webhook

  if [[ -n "${entered_webhook}" ]]; then
    write_webhook_file "${entered_webhook}"
  else
    log_warn "No webhook entered; installer will continue without creating one."
  fi
}

ensure_webhook() {
  if [[ -n "${DOCKER_SERVICES_DISCORD_WEBHOOK_URL}" ]]; then
    log_info "Using webhook URL provided via environment."
    write_webhook_file "${DOCKER_SERVICES_DISCORD_WEBHOOK_URL}"
    return 0
  fi

  if [[ -f "${DOCKER_WEBHOOK_FILE}" ]]; then
    log_info "Existing docker-services webhook file found at ${DOCKER_WEBHOOK_FILE}"

    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
      log_info "Keeping existing webhook."
      return 0
    fi

    local choice=""
    read -r -p "Keep existing Docker webhook? [Y/n]: " choice
    choice="${choice:-Y}"

    if [[ "${choice}" =~ ^[Nn]$ ]]; then
      prompt_for_webhook
    else
      log_info "Keeping existing webhook."
    fi

    return 0
  fi

  log_info "No dedicated docker-services webhook file found."

  if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    log_warn "NON_INTERACTIVE=true and no webhook provided; continuing without creating one."
    return 0
  fi

  prompt_for_webhook
}

install_unit() {
  local file="${1}"
  sudo cp "${SYSTEMD_DIR}/${file}" /etc/systemd/system/
  log_success "Installed ${file}"
}

run_smoke_test() {
  local service="${1}"

  log_step "Running smoke test for ${service}..."
  sudo systemctl start "${service}"

  if sudo systemctl is-failed --quiet "${service}"; then
    log_error "${service} failed smoke test"
    sudo systemctl status "${service}" --no-pager || true
    sudo journalctl -u "${service}" -n 50 --no-pager || true
    exit 1
  fi

  log_success "${service} passed smoke test"
}

main() {
  require_file "${SYSTEMD_DIR}/docker-services-monitor.service"
  require_file "${SYSTEMD_DIR}/docker-services-monitor.timer"
  require_file "${SYSTEMD_DIR}/docker-services-startup-check.service"
  require_file "${SYSTEMD_DIR}/docker-services-startup-check.timer"
  require_file "${SYSTEMD_DIR}/docker-services-image-check.service"
  require_file "${SYSTEMD_DIR}/docker-services-image-check.timer"

  log_step "Installing docker-services monitoring units..."

  ensure_webhook

  install_unit "docker-services-monitor.service"
  install_unit "docker-services-monitor.timer"
  install_unit "docker-services-startup-check.service"
  install_unit "docker-services-startup-check.timer"
  install_unit "docker-services-image-check.service"
  install_unit "docker-services-image-check.timer"

  log_step "Reloading systemd daemon..."
  sudo systemctl daemon-reload
  log_success "systemd daemon reloaded"

  log_step "Enabling timers..."
  sudo systemctl enable --now docker-services-monitor.timer
  sudo systemctl enable --now docker-services-startup-check.timer
  sudo systemctl enable --now docker-services-image-check.timer
  log_success "Monitoring timers enabled"

  run_smoke_test "docker-services-monitor.service"
  run_smoke_test "docker-services-startup-check.service"
  run_smoke_test "docker-services-image-check.service"

  echo
  log_success "Monitoring timers installed and tested:"
  sudo systemctl status docker-services-monitor.timer --no-pager
  sudo systemctl status docker-services-startup-check.timer --no-pager
  sudo systemctl status docker-services-image-check.timer --no-pager

  INSTALL_SUCCEEDED="true"
}

main "$@"
