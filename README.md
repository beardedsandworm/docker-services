# docker-services

Declarative Docker Compose deployment for the services currently hosted on **Arrakis** (`server01`). The repository owns Compose definitions, proxy and application configuration intended for version control, encrypted secret sources, and host-side monitoring units. It does **not** make mutable application data recoverable by itself.

## Current deployment

Live state verified on Arrakis on 2026-08-22:

- host: `arrakis`, Ubuntu 24.04 LTS;
- repository: `/home/lightweight/docker-services`, branch `master`;
- Compose configuration validates with the live `env/server01.env`;
- the four Docker monitoring timers and the Pi-hole host shim are enabled and active;
- 14 declared services are running;
- `esphome` is stopped because the configured `/dev/ttyACM0` device is absent;
- an old, stopped `beszel` container remains as a Compose orphan. Beszel Agent runs separately under `/opt/beszel-agent`.

The snapshot above describes observed state, not a promise that every service is healthy forever. Use the verification commands below for current state.

## Services

| Service | Purpose | Network / exposure | Persistent state |
|---|---|---|---|
| `pihole` | Primary containerized DNS filter | macvlan address on the home network | `config/pihole/etc-pihole` |
| `caddy` | Internal reverse proxy and TLS | host ports 80/443; `proxy_network` | `config/caddy/{data,config}` |
| `searxng` | Private metasearch | Caddy / `proxy_network` | `config/searxng` |
| `postgres` | Database for n8n and related workflows | internal only | `config/postgres/data` |
| `n8n` | Automation, event normalization, incident routing | Caddy / `proxy_network` | `config/n8n/data` |
| `mosquitto` | MQTT broker | host port 1883 | `config/mosquitto` |
| `zigbee2mqtt` | Zigbee coordinator and bridge | host port 8080; USB serial device | `config/zigbee2mqtt/data` |
| `esphome` | ESPHome Device Builder | Caddy / `proxy_network`; optional local USB | `config/esphome` |
| `homeassistant` | Home orchestration | host networking and DBus | `config/homeassistant` |
| `matter-server` | Matter controller backend | host networking | `config/matter-server/data` |
| `grocy` | Pantry and household inventory | `apps` profile; Caddy | `config/grocy` |
| `monkeytype-*` | Self-hosted Monkeytype frontend, backend, MongoDB, and Redis | `apps` profile; Caddy | `config/monkeytype` |

Home Assistant remains on Arrakis deliberately. IX owns the LLM/agent runtime through the separate `llm-services` repository; VPS services are defined in `vps-services`.

## Repository boundary

### Versioned here

- `compose.yaml` and the custom Caddy image;
- Caddy routes and authored application configuration;
- ESPHome device YAML and shared packages;
- monitoring scripts and systemd units;
- SOPS-encrypted secret sources under `secrets/server01/`;
- secret templates and the non-secret environment example.

### Local runtime state

The following are intentionally not Git authority:

- decrypted secrets under `runtime/server01/secrets/`;
- the live environment file `env/server01.env`;
- databases, logs, certificates, caches, generated ESPHome builds, and application-owned configuration under `config/`;
- monitor state under `runtime/server01/monitor/`.

A clean Git tree only proves that tracked deployment files match Git. It does not prove that ignored databases and application configuration are backed up. Recovery still requires approved backups of mutable state and the SOPS/age key needed to decrypt secret sources.

## Networks

- `home_network` is a macvlan used by Pi-hole. The host-side shim is installed as `pihole-host-shim.service` so Arrakis can reach the macvlan service.
- `proxy_network` is the internal bridge shared by Caddy and proxied services.
- Home Assistant and Matter Server use host networking for discovery and local integrations.
- Postgres is intentionally not published to the host network.

Internal DNS must point service hostnames at Arrakis, and Caddy must have a valid Cloudflare API token for DNS-based certificate work.

## Secrets

Encrypted sources are committed with SOPS:

```text
secrets/server01/*.enc
```

Decryption writes runtime material to:

```text
runtime/server01/secrets/
```

Do not commit decrypted files. To create the live runtime material:

```bash
./scripts/decrypt-secrets.sh
```

`N8N_ENCRYPTION_KEY` must be preserved across rebuilds or stored n8n credentials become unreadable.

## Deployment

Host bootstrap is owned by [`linux-environments`](https://github.com/beardedsandworm/linux-environments). On an already bootstrapped Arrakis:

```bash
git clone git@github.com:beardedsandworm/docker-services.git ~/docker-services
cd ~/docker-services
cp env/server01.env.example env/server01.env
# Fill non-secret host settings, provision the age key, then:
./scripts/decrypt-secrets.sh
./scripts/validate.sh
./scripts/up-apps.sh
sudo ./scripts/install-monitoring-units.sh
```

Start the containers before installing the monitoring units: the installer immediately smoke-tests the startup checker and will fail when no Compose services exist. The current installer does not install the Pi-hole macvlan shim; recovery must separately install `scripts/pihole-host-shim.sh` as `/usr/local/sbin/pihole-host-shim`, install `systemd/pihole-host-shim.service`, then reload systemd and enable the unit.

Use `./scripts/up.sh` when the `apps` profile (`grocy` and Monkeytype) is intentionally excluded.

Common lifecycle commands:

```bash
./scripts/validate.sh       # render and validate Compose configuration
./scripts/up.sh             # start core services
./scripts/up-apps.sh        # start core plus apps-profile services
./scripts/down.sh           # stop the project
```

## Monitoring

System-level timers run:

| Unit | Purpose |
|---|---|
| `docker-services-startup-check.timer` | Validate Compose and inspect all declared services after boot |
| `docker-services-monitor.timer` | Detect declared container state/health changes every minute |
| `docker-services-disk-check.timer` | Report disk pressure |
| `docker-services-image-check.timer` | Report image update state |

Monitoring emits structured events through `scripts/emit-event.sh` when an n8n event webhook is configured. n8n owns deduplication, suppression, incident persistence, escalation, and alert routing. The intended policy is **silence is success**: routine state should not generate attention unless something changed or failed.

The container checks deliberately include stopped declared services and exclude old Compose orphans. Inspect orphans separately during maintenance.

## Verification

```bash
cd ~/docker-services

# Repository and deployment intent
git status --short --branch
./scripts/validate.sh

# Declared services, including stopped containers but excluding orphans
docker compose --env-file env/server01.env --profile apps \
  ps --all --orphans=false

# Orphans and other historical containers
docker compose --env-file env/server01.env --profile apps ps --all

# Monitoring units
systemctl status \
  docker-services-startup-check.timer \
  docker-services-monitor.timer \
  docker-services-disk-check.timer \
  docker-services-image-check.timer \
  pihole-host-shim.service

journalctl -u docker-services-monitor.service -n 50 --no-pager
```

## Known operational gaps

- `esphome` currently cannot start while `/dev/ttyACM0` is absent. Either restore the expected USB device/path or make local USB passthrough optional before restarting it.
- A clean clone cannot recreate the full MQTT/Zigbee/Monkeytype stack: the Mosquitto password file, Zigbee2MQTT data/config, and Monkeytype Firebase service-account JSON have no complete encrypted-source/provisioning path.
- `env/server01.env.example` does not currently define every variable required by Compose, including ESPHome and n8n settings, and its SearXNG hostname differs from the live Caddy route. Treat it as a starting point, not a sufficient deployment manifest.
- The monitoring systemd units hard-code the `lightweight` account and `/home/lightweight/docker-services`; the installer is not portable to another checkout owner/path.
- `image-check.sh` suppresses `docker compose pull --dry-run` errors and can therefore report “up to date” after a pull/auth/network failure.
- The stopped orphaned `beszel` container should be removed after confirming no migration rollback depends on it.
- Mutable data and live Home Assistant configuration remain ignored local state; off-host backup coverage must be verified independently.
- Several images use floating tags such as `latest`, `stable`, or a broad version variable. This eases updates but weakens deterministic rebuilds; pin digests or tested versions where rollback certainty matters.

## Related repositories

- [`linux-environments`](https://github.com/beardedsandworm/linux-environments) — host bootstrap, package snapshots, dotfiles, and host maintenance timers.
- [`llm-services`](https://github.com/beardedsandworm/llm-services) — Hermes/LLM deployment on IX.
- [`vps-services`](https://github.com/beardedsandworm/vps-services) — public VPS services on Heighliner.
- [`wormlogic-gitops`](https://github.com/beardedsandworm/wormlogic-gitops) — Kubernetes/Talos/Flux work.

## Author

Matthew Garry
