#!/usr/bin/env bash
set -euo pipefail

MACHINE_ID="${MACHINE_ID:-server01}"
SECRETS_DIR="./secrets/${MACHINE_ID}"
RUNTIME_DIR="./runtime/${MACHINE_ID}/secrets"

mkdir -p "${RUNTIME_DIR}"

sops --decrypt \
  --output "${RUNTIME_DIR}/pihole_web_password.txt" \
  "${SECRETS_DIR}/pihole_web_password.txt.enc"

sops --decrypt \
  --output "${RUNTIME_DIR}/cloudflare_api_token.txt" \
  "${SECRETS_DIR}/cloudflare_api_token.txt.enc"

sops --decrypt \
  --output "${RUNTIME_DIR}/postgres.env" \
  "${SECRETS_DIR}/postgres.env.enc"

sops --decrypt \
  --output "${RUNTIME_DIR}/monkeytype-db.env" \
  "${SECRETS_DIR}/monkeytype-db.env.enc"

sops --decrypt \
  --output "${RUNTIME_DIR}/n8n.env" \
  "${SECRETS_DIR}/n8n.env.enc"

sops --decrypt \
  --output "${RUNTIME_DIR}/esphome-secrets.yaml" \
  "${SECRETS_DIR}/esphome-secrets.yaml.enc"

sops --decrypt \
  --output "${RUNTIME_DIR}/mqtt.env" \
  "${SECRETS_DIR}/mqtt.env.enc"

chmod 600 "${RUNTIME_DIR}/mqtt.env"
chmod 600 "${RUNTIME_DIR}/esphome-secrets.yaml"
chmod 600 "${RUNTIME_DIR}/n8n.env"
chmod 600 "${RUNTIME_DIR}/monkeytype-db.env"
chmod 600 "${RUNTIME_DIR}/pihole_web_password.txt"
chmod 600 "${RUNTIME_DIR}/cloudflare_api_token.txt"
chmod 600 "${RUNTIME_DIR}/postgres.env"

echo "Decrypted secrets to ${RUNTIME_DIR}"
