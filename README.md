# 🐳 docker-services

> Declarative, recoverable, and observable Docker services for **Arrakis**.

---

## 💡 Philosophy

> **A service stack should be reproducible from Git, recoverable from encrypted state, observable while running, and explicit about what still requires backup.**

`docker-services` is the application deployment layer for **Arrakis** (`server01`).

It owns:

* 🐳 **Docker Compose service definitions**
* 🌐 **Caddy routing and TLS configuration**
* 🔐 **SOPS-encrypted service secrets**
* 🧩 **Versioned application configuration**
* ⚙️ **Repo-owned deployment automation**
* 📊 **Service monitoring and health checks**
* 🔔 **Incident/event reporting**
* 🛠️ **Host integration required by the containers**

It does **not** pretend that Git alone makes mutable application data recoverable.

Databases, certificates, generated state, Home Assistant configuration, and other mutable runtime data require separate backup coverage.

---

## ⚡ Mental Model

```text
Host ready
    ↓
Recover secrets
    ↓
Build required images
    ↓
Reconcile containers
    ↓
Install monitoring
    ↓
Install host integration
    ↓
Observe continuously
```

Or operationally:

```text
Define → Decrypt → Deploy → Observe → Correct → Recover
```

* **Define** → Compose, Caddy, application configuration
* **Decrypt** → SOPS-encrypted service secrets
* **Deploy** → `deploy.sh` + Docker Compose
* **Observe** → monitoring services and timers
* **Correct** → update Git when desired state changes
* **Recover** → rebuild the stack from repo + encrypted state + backups

---

# 🖥️ Host

`docker-services` is currently owned by:

| Host | ID | OS | Role |
| --- | --- | --- | --- |
| 🏜️ Arrakis | `server01` | Ubuntu | Primary Docker / home-services host |

Host bootstrap, packages, SSH identity, age identity, WireGuard and system-level configuration are owned by:

```text
linux-environments
```

`docker-services` begins where the Arrakis host bootstrap ends.

---

# 🧩 Repository Structure

```text
docker-services/
├── .sops.yaml
├── compose.yaml
├── deploy.sh
├── dc
│
├── config/
│   ├── caddy/
│   ├── esphome/
│   ├── homepage/
│   ├── homeassistant/
│   ├── matter-server/
│   ├── mosquitto/
│   ├── n8n/
│   ├── pihole/
│   ├── postgres/
│   ├── searxng/
│   ├── zigbee2mqtt/
│   └── ...
│
├── env/
│   ├── server01.env.example       # tracked schema / safe defaults
│   └── server01.env               # ignored, decrypted deployment environment
│
├── scripts/
│   ├── decrypt-secrets.sh
│   ├── install-monitoring-units.sh
│   ├── pihole-host-shim.sh
│   ├── image-check.sh
│   ├── emit-event.sh
│   └── ...
│
├── secrets/
│   └── server01/
│       ├── *.enc                  # top-level runtime-secret sources
│       └── env/
│           └── server01.env.enc  # encrypted recovery copy of env/server01.env
│
├── runtime/
│   └── server01/
│       ├── secrets/
│       └── monitor/
│
└── systemd/
    ├── docker-services-monitor.*
    ├── docker-services-startup-check.*
    ├── docker-services-image-check.*
    ├── pihole-host-shim.service
    └── ...
```

Generated runtime state belongs under `runtime/`, an application's own data directory, or an explicitly ignored local path such as `env/server01.env`. Plaintext runtime state is not Git authority.

---

# 🧱 Repository Boundary

## ✅ Versioned Here

The repository owns things that describe **desired service state**, including:

* `compose.yaml`
* custom Caddy build definition
* Caddy routes
* authored Homepage configuration
* ESPHome device YAML and shared packages
* service configuration intended for Git
* monitoring scripts
* systemd units
* deployment scripts
* encrypted SOPS secret sources
* environment examples and other non-secret deployment metadata

---

## 🗄️ Mutable Runtime State

Git is **not** the authority for application-owned mutable data.

Examples include:

* PostgreSQL databases
* Home Assistant state/configuration
* Nextcloud data and database state
* MQTT runtime data
* Zigbee2MQTT runtime state
* Caddy certificates and caches
* generated ESPHome build state
* MongoDB / Redis runtime data
* n8n execution/runtime state
* application logs
* downloaded/generated media metadata
* other service-specific databases and caches

A clean Git tree means:

> **The declarative deployment matches Git.**

It does **not** mean:

> **Every byte required for disaster recovery is safely backed up.**

Mutable state requires its own approved backup strategy.

---

# 🐳 Services

Arrakis hosts the core home-services stack.

Major service groups include:

## 🌐 Infrastructure

* **Pi-hole** — primary DNS filtering
* **Caddy** — reverse proxy and TLS
* **PostgreSQL** — shared application database backend
* **Mosquitto** — MQTT broker
* **Homepage** — unified Wormlogic dashboard
* **Glance** — embedded/news dashboard content
* **Beszel integration** — host/service monitoring

---

## 🏠 Home Automation

* **Home Assistant**
* **ESPHome**
* **Zigbee2MQTT**
* **Matter Server**
* **Mosquitto**

Home Assistant deliberately remains on Arrakis rather than moving into the Kubernetes cluster.

---

## 🧰 Applications

Examples include:

* **SearXNG**
* **Grocy**
* **n8n**
* **Monkeytype**
* **Nextcloud**
* remote media-service links/integrations exposed through Homepage or reverse-proxy configuration

The Compose file remains the authoritative inventory for what Arrakis actually deploys. Remote media-management services linked from Arrakis are integrations, not Arrakis-owned Compose workloads unless they explicitly appear in `compose.yaml`.

To inspect that inventory:

```bash
./dc config --services
```

---

# 🌐 Networking

Several networking models coexist intentionally.

## `proxy_network`

Internal bridge shared by Caddy and reverse-proxied services.

```text
client
  ↓
Caddy
  ↓
proxy_network
  ↓
application
```

Services should generally talk to one another across the LAN or their Docker network rather than using WireGuard addresses when both hosts are on the same physical network.

---

## Pi-hole macvlan

Pi-hole uses a macvlan attachment so it can exist directly on the network.

Because a Linux host cannot normally communicate directly with its own macvlan child, Arrakis also requires the host-side shim:

```text
pihole-host-shim.service
```

The deployment workflow installs:

```text
scripts/pihole-host-shim.sh
        ↓
/usr/local/sbin/pihole-host-shim

systemd/pihole-host-shim.service
        ↓
/etc/systemd/system/pihole-host-shim.service
```

It then reloads systemd, enables the unit, starts it, and fails deployment if the service is not active.

---

## Host Networking

Services such as Home Assistant and Matter Server use host networking where local discovery and multicast behavior require it.

---

# 🔐 Secrets

Encrypted secret authority lives under:

```text
secrets/server01/
```

Examples include:

```text
cloudflare_api_token.txt.enc
esphome-secrets.yaml.enc
pihole_web_password.txt.enc
postgres.env.enc
n8n.env.enc
mqtt.env.enc
monkeytype-db.env.enc
homepage-personal-ical.txt.enc
env/server01.env.enc
...
```

The exact inventory may evolve with the stack.

Secrets are encrypted with **SOPS + Arrakis's age identity**.

The machine age identity itself is recovered by `linux-environments`.

---

## Runtime Secrets and Compose Environment

Top-level encrypted service-secret sources are materialized into:

```text
runtime/server01/secrets/
```

using:

```bash
./scripts/decrypt-secrets.sh
```

That script intentionally handles the top-level `secrets/server01/*.enc` runtime-secret inventory.

The Compose environment follows a separate recovery path so it is not swept into `runtime/server01/secrets/`:

```text
secrets/server01/env/server01.env.enc
        ↓
SOPS binary decrypt in deploy.sh
        ↓
env/server01.env
```

`env/server01.env.example` is the tracked schema and safe example. `env/server01.env` is the real ignored deployment environment and may contain credentials.

`deploy.sh` requires the encrypted env recovery artifact, restores `env/server01.env` with mode `0600`, validates the required runtime-secret files, and renders `./dc config` before building or starting services.

All decrypted credential material is local runtime/deployment state and must never be committed.

---

## Important Persistent Secrets

Some service secrets are identity-bearing rather than disposable.

For example:

```text
N8N_ENCRYPTION_KEY
```

must survive rebuilds or previously stored n8n credentials become unreadable.

The same principle applies to any service credential that encrypts or identifies persistent application state.

---

# 🔑 Repository Deploy Key

Arrakis uses a repository-specific GitHub deploy key for `docker-services`:

```text
~/.ssh/id_ed25519_git_docker-services
```

Example comment:

```text
server01:github:docker-services
```

The repository is locally bound to this key through Git's `core.sshCommand`.

This keeps Git access for `docker-services` independent from:

* the host SSH identity
* `linux-environments`
* other service repositories

The normal `linux-environments` scheduled credential capture will discover and preserve the deploy key after it is created.

---

# 🚀 Deployment

The primary deployment entry point is:

```bash
./deploy.sh
```

The deploy script owns the reproducible configuration/secrets reconciliation path for the Arrakis application stack. It does not yet restore mutable application data.

Current flow:

```text
validate repository + required encrypted sources
        ↓
decrypt top-level runtime secrets
        ↓
restore env/server01.env from secrets/server01/env/server01.env.enc
        ↓
validate required decrypted files
        ↓
render ./dc config
        ↓
build Caddy
        ↓
./dc up -d
        ↓
install monitoring units
        ↓
install Pi-hole shim script + systemd unit
        ↓
verify Pi-hole shim is active
        ↓
create / verify docker-services deploy key
        ↓
bind Git repository to deploy key
        ↓
display public deploy key
        ↓
prompt only when running interactively
```

---

## Monitoring Webhook Setup

The monitoring installer manages its dedicated Discord webhook.

If:

```text
~/.config/docker-services/discord-webhook
```

already exists, it is preserved.

If it does not exist, the installer interactively asks for a webhook.

This lets a new recovery remain simple without requiring the webhook to be embedded in `deploy.sh`.

---

# 🔄 Recovery Flow

The current Arrakis configuration/secrets recovery path is:

```text
clone linux-environments
        ↓
bootstrap Arrakis host
        ↓
recover age / SSH / WireGuard
        ↓
reboot
        ↓
clone docker-services
        ↓
./deploy.sh
        ↓
decrypt runtime secrets + restore server01.env
        ↓
validate recovered configuration
        ↓
reconcile containers + host integration
        ↓
register deploy key if newly generated
        ↓
scheduled host credential capture preserves the deploy key
```

The deploy-key pause occurs only when `deploy.sh` has an interactive stdin.

This is not yet a complete Arrakis disaster-recovery workflow. Configuration and encrypted credentials are recoverable, but mutable application state still requires backup and restore coverage.

The long-term goal is for `linux-environments` to orchestrate the host → service-repository handoff automatically while leaving application deployment logic here.

---

# 🛠️ `dc` Wrapper

Use the repo wrapper rather than repeatedly spelling out the machine-specific Compose invocation.

Examples:

```bash
./dc ps
./dc logs
./dc pull
./dc build
./dc up -d
./dc down
```

Service-specific operations work normally:

```bash
./dc logs homepage
./dc restart homeassistant
./dc up -d --force-recreate homepage
```

Remember:

```text
restart ≠ recreate
```

A container **restart** does not apply changed:

* environment variables
* bind mounts
* Compose configuration
* image definitions

When Compose configuration changes, reconcile with:

```bash
./dc up -d
```

or explicitly:

```bash
./dc up -d --force-recreate <service>
```

---

# 🔨 Caddy

Caddy is built locally because the Wormlogic deployment requires its DNS provider integration.

The deployment script performs:

```bash
./dc build caddy
```

before reconciling the stack.

Caddy uses the encrypted Cloudflare token materialized from the server01 secret store.

Routing configuration belongs in Git.

Caddy's generated certificates and runtime data do not.

---

# 📊 Monitoring

`docker-services` owns monitoring for the application stack running on Arrakis.

Current monitoring includes:

| Unit | Purpose |
| --- | --- |
| `docker-services-monitor.timer` | Detect service state / health changes |
| `docker-services-startup-check.timer` | Validate the stack after startup |
| `docker-services-image-check.timer` | Check container image update state |
| `pihole-host-shim.service` | Maintain Arrakis ↔ Pi-hole macvlan reachability |

The monitoring installer:

```bash
scripts/install-monitoring-units.sh
```

copies the units into systemd, enables their timers and immediately smoke-tests the corresponding services.

That makes installation itself part of verification.

`image-check.sh` follows the **silence is success** policy:

* image updates available → notify;
* check/registry failure → notify;
* no updates → write the clean result locally/journal only, with no Discord success message.

---

# 🔔 Event Reporting

Monitoring can emit structured events into the Wormlogic automation pipeline.

```text
docker-services
      ↓
emit-event.sh
      ↓
n8n
      ↓
normalization / persistence / routing
      ↓
Discord
```

The intended monitoring policy is:

> **Silence is success.**

Healthy steady state should not constantly demand attention.

Notifications should primarily represent:

* failures
* state changes
* degraded health
* disk pressure
* image availability
* recovery/install failures
* other actionable conditions

n8n owns higher-level concerns such as:

* deduplication
* suppression
* incident persistence
* escalation
* routing

---

# 🧪 Verification

## Repository

```bash
git status --short --branch
```

---

## Compose

```bash
./dc config
./dc config --services
./dc ps
```

Include stopped services when needed:

```bash
./dc ps --all
```

---

## Monitoring

```bash
systemctl status \
  docker-services-monitor.timer \
  docker-services-startup-check.timer \
  docker-services-image-check.timer \
  pihole-host-shim.service
```

Recent monitor activity:

```bash
journalctl \
  -u docker-services-monitor.service \
  -n 50 \
  --no-pager
```

---

## Recovered Environment and Runtime Secrets

Verify that the Compose environment exists without printing its contents:

```bash
test -s env/server01.env &&
  echo "server01.env present"
```

Verify Compose can consume the recovered environment:

```bash
./dc config >/dev/null &&
  echo "Compose configuration valid"
```

List materialized runtime-secret filenames without exposing their contents:

```bash
find runtime/server01/secrets \
  -maxdepth 1 \
  -type f \
  -printf '%f\n' \
  | sort
```

---

# 🧱 Backup Boundary

A complete Arrakis recovery depends on three layers:

```text
1. linux-environments
   ↓
host + machine credentials

2. docker-services
   ↓
declarative application deployment + encrypted secrets/configuration

3. mutable-state backups
   ↓
databases + application-owned data
```

None of the three replaces the others.

The repository should make it obvious which category any important state belongs to.

---

# 🧠 Design Rules

A few rules keep Arrakis manageable:

* **Host configuration belongs in `linux-environments`.**
* **Docker/application deployment belongs here.**
* **Secrets are encrypted with SOPS at rest.**
* **Decrypted mounted secrets live under `runtime/`; the recovered Compose environment lives at ignored `env/server01.env`.**
* **Each repository gets its own GitHub deploy key.**
* **Mutable application state is not disguised as Git-managed configuration.**
* **Deployment scripts should be safe to rerun.**
* **Monitoring installation should verify itself.**
* **Container state should reconcile from Compose rather than manual Docker commands.**
* **Internal Docker/LAN traffic should use the appropriate local network, not WireGuard unnecessarily.**
* **Generated runtime directories do not become accidental repository structure.**
* **Recovery paths are infrastructure and should be tested like infrastructure.**

---

# 🗺️ Repository Ownership

The main Wormlogic infrastructure repositories have distinct responsibilities:

| Repository | Responsibility |
| --- | --- |
| 🧠 `linux-environments` | Host bootstrap, packages, credentials, networking and host automation |
| 🐳 `docker-services` | Arrakis application stack |
| 🤖 `llm-services` | IX / Hermes / agent stack |
| 🚀 `vps-services` | Heighliner VPS application stack |
| 🪱 `wormlogic-gitops` | Shai-Hulud Talos / Flux / Kubernetes state |

The boundary is intentional:

```text
linux-environments
        ↓
prepare host

service repository
        ↓
deploy workload
```

A service repository should not duplicate host bootstrap logic, and the host bootstrap should not duplicate application deployment logic.

---

# 🔭 Future Direction

The remaining recovery work is largely about closing the gap around **mutable state**.

The desired end state is:

```text
host dies
   ↓
rebuild host
   ↓
recover identities
   ↓
deploy docker-services
   ↓
restore mutable application state
   ↓
services return
```

At that point, losing Arrakis should be inconvenient rather than catastrophic.

---

# 📌 Summary

`docker-services` is the declarative deployment and operational layer for the services hosted on Arrakis.

It provides:

* 🐳 Compose-managed application deployment
* 🌐 Caddy proxy and TLS configuration
* 🔐 SOPS-encrypted service secrets
* 🔑 repository-specific GitHub authentication
* 🏠 home-automation infrastructure
* 📊 service monitoring and startup validation
* 🔔 structured incident reporting
* 🛠️ required host/container integration
* 🔄 a repeatable configuration/credential recovery path
* 🧱 an explicit boundary between Git state and mutable backups

The goal is simple:

> **Arrakis should be rebuildable from known state, not reconstructed from memory.**

---

## 🧑‍💻 Author

Matthew J Garry
