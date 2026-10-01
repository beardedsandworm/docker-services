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

Databases, certificates, application databases, generated state, Home Assistant configuration, and other mutable runtime data require separate backup coverage.

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
│   └── server01.env
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
│       └── *.enc
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

Generated runtime state belongs under `runtime/` or the application's own data directory and is not Git authority.

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
* media-management applications declared by the current Compose stack

The Compose file remains the authoritative inventory for what Arrakis currently deploys.

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

The deployment workflow installs and enables this unit.

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
pihole_web_password.txt.enc
postgres.env.enc
n8n.env.enc
mqtt.env.enc
monkeytype-db.env.enc
homepage-personal-ical.txt.enc
homepage-birthdays-ical.txt.enc
...
```

The exact inventory may evolve with the stack.

Secrets are encrypted with **SOPS + Arrakis's age identity**.

The machine age identity itself is recovered by `linux-environments`.

---

## Runtime Secrets

Encrypted sources are materialized into:

```text
runtime/server01/secrets/
```

using:

```bash
./scripts/decrypt-secrets.sh
```

These decrypted files are runtime material only.

They must never be committed.

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

The deploy script owns the complete application reconciliation path for Arrakis.

Current flow:

```text
validate repository
        ↓
decrypt service secrets
        ↓
build Caddy
        ↓
./dc up -d
        ↓
install monitoring units
        ↓
install Pi-hole host shim
        ↓
create / verify docker-services deploy key
        ↓
bind Git repository to deploy key
        ↓
display public deploy key
        ↓
Press Enter to continue
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

The intended Arrakis recovery path is:

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
register deploy key if new
        ↓
Press Enter
        ↓
capture credentials
```

The long-term goal is for `linux-environments` to orchestrate that handoff automatically while leaving application deployment logic here.

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

## Runtime Secrets

List materialized secret filenames without exposing their contents:

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
declarative application deployment + encrypted secrets

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
* **Decrypted secrets live only under runtime state.**
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
* 🔄 a repeatable recovery path
* 🧱 an explicit boundary between Git state and mutable backups

The goal is simple:

> **Arrakis should be rebuildable from known state, not reconstructed from memory.**

---

## 🧑‍💻 Author

Matthew J Garry
