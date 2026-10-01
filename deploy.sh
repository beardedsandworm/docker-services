#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MACHINE_ID="server01"
REPO_NAME="docker-services"

DEPLOY_KEY="${HOME}/.ssh/id_ed25519_git_${REPO_NAME}"
DEPLOY_KEY_PUB="${DEPLOY_KEY}.pub"

DOCKER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/docker-services"
DOCKER_WEBHOOK_FILE="${DOCKER_CONFIG_DIR}/discord-webhook"

PIHOLE_SHIM_SERVICE="pihole-host-shim.service"

cd "$REPO_ROOT"

die() {
    printf '✗ %s\n' "$*" >&2
    exit 1
}

step() {
    printf '\n==================================================\n'
    printf '%s\n' "$*"
    printf '==================================================\n'
}

require_file() {
    [[ -f "$1" ]] || die "Required file not found: $1"
}


# --------------------------------------------------
# Validate repository
# --------------------------------------------------

step "Validating docker-services repository"

require_file "$REPO_ROOT/scripts/decrypt-secrets.sh"
require_file "$REPO_ROOT/scripts/install-monitoring-units.sh"
require_file "$REPO_ROOT/systemd/$PIHOLE_SHIM_SERVICE"
require_file "$REPO_ROOT/dc"
require_file "$REPO_ROOT/compose.yaml"

git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "$REPO_ROOT is not a Git repository"

printf '✓ Repository: %s\n' "$REPO_ROOT"


# --------------------------------------------------
# Secrets
# --------------------------------------------------

step "Decrypting service secrets"

bash "$REPO_ROOT/scripts/decrypt-secrets.sh"

printf '✓ Secrets materialized\n'


# --------------------------------------------------
# Caddy
# --------------------------------------------------

step "Building Caddy"

"$REPO_ROOT/dc" build caddy

printf '✓ Caddy built\n'


# --------------------------------------------------
# Docker services
# --------------------------------------------------

step "Starting docker-services"

"$REPO_ROOT/dc" up -d

printf '✓ Docker services started\n'

"$REPO_ROOT/dc" ps


# --------------------------------------------------
# Monitoring
# --------------------------------------------------

step "Installing docker-services monitoring"

if [[ -f "$DOCKER_WEBHOOK_FILE" ]]; then
    printf '✓ Existing Docker monitoring webhook found\n'
    printf '  %s\n' "$DOCKER_WEBHOOK_FILE"

    NON_INTERACTIVE=true \
        bash "$REPO_ROOT/scripts/install-monitoring-units.sh"
else
    printf '• No Docker monitoring webhook exists yet\n'
    printf '• Monitoring installer will prompt for one\n'

    bash "$REPO_ROOT/scripts/install-monitoring-units.sh"
fi

printf '✓ Monitoring services and timers installed\n'


# --------------------------------------------------
# Pi-hole host shim
# --------------------------------------------------

step "Installing Pi-hole host shim"

sudo install -m 0644 \
    "$REPO_ROOT/systemd/$PIHOLE_SHIM_SERVICE" \
    "/etc/systemd/system/$PIHOLE_SHIM_SERVICE"

sudo systemctl daemon-reload
sudo systemctl enable --now "$PIHOLE_SHIM_SERVICE"

if ! sudo systemctl is-active --quiet "$PIHOLE_SHIM_SERVICE"; then
    sudo systemctl status "$PIHOLE_SHIM_SERVICE" --no-pager || true
    die "$PIHOLE_SHIM_SERVICE failed to start"
fi

printf '✓ %s installed and active\n' "$PIHOLE_SHIM_SERVICE"


# --------------------------------------------------
# Repository deploy key
# --------------------------------------------------

step "Configuring GitHub deploy key"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

DEPLOY_KEY_CREATED=0

if [[ ! -f "$DEPLOY_KEY" ]]; then
    printf '• No docker-services deploy key found; generating one\n'

    ssh-keygen \
        -t ed25519 \
        -N '' \
        -C "${MACHINE_ID}:github:${REPO_NAME}" \
        -f "$DEPLOY_KEY"

    DEPLOY_KEY_CREATED=1
else
    printf '✓ Existing deploy key found: %s\n' "$DEPLOY_KEY"
fi

chmod 600 "$DEPLOY_KEY"

if [[ ! -f "$DEPLOY_KEY_PUB" ]]; then
    ssh-keygen -y -f "$DEPLOY_KEY" > "$DEPLOY_KEY_PUB"
fi

chmod 644 "$DEPLOY_KEY_PUB"


# --------------------------------------------------
# Ensure GitHub origin uses SSH
# --------------------------------------------------

ORIGIN_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"

[[ -n "$ORIGIN_URL" ]] || die "Git remote 'origin' is not configured"

case "$ORIGIN_URL" in
    git@github.com:*)
        printf '✓ Git origin already uses SSH: %s\n' "$ORIGIN_URL"
        ;;

    https://github.com/*)
        SSH_ORIGIN="$(
            printf '%s\n' "$ORIGIN_URL" |
            sed -E 's#^https://github\.com/(.+)$#git@github.com:\1#'
        )"

        git -C "$REPO_ROOT" remote set-url origin "$SSH_ORIGIN"

        printf '✓ Converted Git origin to SSH\n'
        printf '  %s\n' "$SSH_ORIGIN"
        ;;

    *)
        die "Unexpected Git origin: $ORIGIN_URL"
        ;;
esac


# --------------------------------------------------
# Bind this repository to its deploy key
# --------------------------------------------------

git -C "$REPO_ROOT" config --local \
    core.sshCommand \
    "ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes"

printf '✓ %s is bound to its repo-specific deploy key\n' "$REPO_NAME"

FINAL_ORIGIN="$(git -C "$REPO_ROOT" remote get-url origin)"

case "$FINAL_ORIGIN" in
    git@github.com:*)
        printf '✓ SSH is the default Git transport for origin\n'
        ;;
    *)
        die "Git origin is not using SSH after configuration: $FINAL_ORIGIN"
        ;;
esac


# --------------------------------------------------
# Deployment summary
# --------------------------------------------------

step "Arrakis deployment complete"

printf 'Repository:          %s\n' "$REPO_ROOT"
printf 'Machine:             %s\n' "$MACHINE_ID"
printf 'Git origin:          %s\n' "$FINAL_ORIGIN"
printf 'Deploy private key:  %s\n' "$DEPLOY_KEY"
printf 'Deploy public key:   %s\n' "$DEPLOY_KEY_PUB"
printf '\n'

if (( DEPLOY_KEY_CREATED )); then
    printf 'A new GitHub deploy key was generated.\n'
    printf 'Add this key to the docker-services repository as a deploy key with write access:\n\n'
else
    printf 'Current docker-services GitHub deploy key:\n\n'
fi

cat "$DEPLOY_KEY_PUB"

printf '\n\n'

if [[ -t 0 ]]; then
    read -r -p "Press Enter after capturing/registering the deploy key to continue..."
    printf '\n'
fi

printf '✓ deploy.sh complete\n'
