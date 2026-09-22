#!/usr/bin/env bash
set -euo pipefail

SHIM_NAME="${PIHOLE_SHIM_NAME:-pihole-shim}"
PARENT_INTERFACE="${PIHOLE_SHIM_PARENT:-eno1}"
SHIM_CIDR="${PIHOLE_SHIM_CIDR:-10.42.20.100/32}"
PIHOLE_IP="${PIHOLE_IPV4_ADDRESS:-10.42.20.11}"

SHIM_IP="${SHIM_CIDR%/*}"

up() {
    # Create the macvlan interface if it does not already exist.
    if ! ip link show "${SHIM_NAME}" >/dev/null 2>&1; then
        ip link add "${SHIM_NAME}" \
            link "${PARENT_INTERFACE}" \
            type macvlan mode bridge
    fi

    # Ensure the shim has the desired address.
    ip addr replace "${SHIM_CIDR}" dev "${SHIM_NAME}"

    # Bring it up.
    ip link set "${SHIM_NAME}" up

    # Route only the local Pi-hole through the shim.
    ip route replace "${PIHOLE_IP}/32" \
        dev "${SHIM_NAME}" \
        src "${SHIM_IP}"
}

down() {
    ip route del "${PIHOLE_IP}/32" dev "${SHIM_NAME}" 2>/dev/null || true
    ip link del "${SHIM_NAME}" 2>/dev/null || true
}

status() {
    echo "Interface:"
    ip addr show "${SHIM_NAME}"
    echo
    echo "Pi-hole route:"
    ip route get "${PIHOLE_IP}"
}

case "${1:-}" in
    up)
        up
        ;;
    down)
        down
        ;;
    restart)
        down
        up
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {up|down|restart|status}" >&2
        exit 2
        ;;
esac
