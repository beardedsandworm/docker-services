#!/usr/bin/env bash
set -euo pipefail

MACHINE_ID="${MACHINE_ID:-server01}"
SECRETS_DIR="./secrets/${MACHINE_ID}"
RUNTIME_DIR="./runtime/${MACHINE_ID}/secrets"

SECRETS=(
  "pihole_web_password.txt"
  "cloudflare_api_token.txt"
  "postgres.env"
  "monkeytype-db.env"
  "n8n.env"
  "esphome-secrets.yaml"
  "mqtt.env"
  "homepage-personal-ical.txt"
  "nextcloud_db_password.txt"
)

mkdir -p "${RUNTIME_DIR}"

for secret in "${SECRETS[@]}"; do
  sops --decrypt \
    --output "${RUNTIME_DIR}/${secret}" \
    "${SECRETS_DIR}/${secret}.enc"

  chmod 600 "${RUNTIME_DIR}/${secret}"
done

echo "Decrypted secrets to ${RUNTIME_DIR}"
