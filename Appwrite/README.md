# Appwrite 2.0 for Coolify

A single-file Docker Compose template that runs [Appwrite](https://appwrite.io) 2.0 on [Coolify](https://coolify.io) — adapted from the official [Appwrite 2.0.0 compose file](https://github.com/appwrite/appwrite/blob/2.0.0/docker-compose.yml) and hardened through real-world deployment and debugging.

## Two files in this repo

| File | Use it when |
|---|---|
| `docker-compose-appwrite-include-dbs.yaml` | **Default** — everything on one server (databases included) |
| `docker-compose-appwrite-external-dbs.yaml` | **Production split** — no local PostgreSQL/Redis/ClickHouse/MongoDB; you point Appwrite at your own database servers (private network). Required env vars: `_APP_DOMAIN`, `_APP_DB_HOST`, `_APP_REDIS_HOST`, `_APP_CLICKHOUSE_HOST`, `_APP_USAGE_PASS`, plus your DB credentials (`_APP_DB_USER`, `_APP_DB_PASS`, `_APP_REDIS_USER`/`_APP_REDIS_PASS`). One-time on the Postgres server: `CREATE DATABASE appwrite;` (must match `_APP_DB_SCHEMA` — the bundled template's postgres container creates it automatically, an external server won't), then connected to that database `CREATE COLLATION IF NOT EXISTS public.utf8_ci_ai (provider = icu, locale = 'und-u-ks-level1', deterministic = false);` — Appwrite's SQL requires this collation, which the bundled `appwrite/postgres` image ships pre-created but a plain server lacks. Everything else in this README applies to both files. |

## What you get

- **Full Appwrite 2.0 platform** — Console IV, API, realtime, functions, sites, auth, storage
- **PostgreSQL 18** as the database (Appwrite 2.0 default), plus Redis and ClickHouse
- **Coolify-native**: no exposed ports, Coolify's proxy handles TLS, all credentials auto-generated with magic variables
- **One combined worker + scheduler** by default (lowest overhead), with a full per-queue topology, MongoDB (DocumentsDB) and an embeddings server included behind optional compose profiles
- **Failure-loud**: the API healthcheck also asserts the origin allowlist, so a misconfigured domain turns the service red within ~1 minute instead of producing cryptic console errors later

## Requirements

- A Coolify server (Docker Compose resource type)
- ~2 GB RAM free for the stack; 4 GB recommended for headroom
- A DNS record pointing your domain at the server

## Server prep (once per host)

These cannot be set from a compose file — run them on the server before or after the first deploy:

```bash
# Required by Redis (avoids startup warning and failed background saves):
echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf && sysctl -p

# Optional on small/shared servers — swap absorbs memory spikes
# instead of triggering the OOM killer:
fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile \
  && swapon /swapfile && echo '/swapfile none swap sw 0 0' >> /fstab
```

## Deploy in 5 steps

1. **Create**: Coolify → New Resource → Docker Compose → paste `docker-compose-appwrite-include-dbs.yaml` → Deploy. One shared domain and all secrets are generated automatically.
2. **Domains**: set the same hostname on all three routed services, keeping their paths:

   | Service | Domain | Purpose |
   |---|---|---|
   | Appwrite | `https://your.hostname/v1` | API (port 80, pinned) |
   | Appwrite Console | `https://your.hostname` | Dashboard (port 3000) |
   | Appwrite Realtime | `https://your.hostname/v1/realtime` | Websockets |

3. **Environment tab** — set the one required variable (Coolify blocks deploy until filled, shown with a red border):
   ```
   _APP_DOMAIN=your.hostname
   ```
   These derive from it automatically — override only for custom names:
   ```
   _APP_DOMAIN_FUNCTIONS  ->  functions.your.hostname
   _APP_DOMAIN_SITES      ->  sites.your.hostname
   ```
4. **Path prefixes**: on the Appwrite **and** Appwrite Realtime services → Advanced → "Path prefixes" → **Keep prefixes**. (Coolify defaults to "Strip prefixes", which removes `/v1` before forwarding — the API then 404s every request.)
5. **Deploy again**, then register the first user — it becomes the admin.

### Verify

`https://your.hostname/v1/health/version` must return `{"version":"2.0.0"}` as JSON. The Appwrite service healthcheck also asserts the origin allowlist: if it turns red after a deploy, `_APP_DOMAIN` is missing or wrong — set it and redeploy.

## Before the first site/function build

Coolify renames every stack volume to `<stack-uuid>_<name>`, but Appwrite's build jobs mount the volume named in `_APP_BUILDS_VOLUME` (default: `appwrite-builds`). Fix once per stack:

```bash
# On the server, find your stack's real builds volume:
docker volume ls | grep builds
# e.g. w012oohu7wqjy6cwstrrkzkz_appwrite-builds
```

Then set in the env tab and redeploy:

```
_APP_BUILDS_VOLUME=<stack-uuid>_appwrite-builds
```

**Symptom when unset**: builds finish but deployments fail with `Build produced no output artifact.`

## Making sites reachable

Site URLs are `<site-name>.<sites-domain>`. Two options:

**Option A — wildcard certificate (recommended for many sites)**

1. Cloudflare → SSL/TLS → Edge Certificates → enable **Advanced Certificate Manager** (~$10/mo) and order a certificate for `*.sites.your.hostname` (+ the apex form).
2. DNS: wildcard record `*.sites.your.hostname` → your server (proxied).
3. Coolify: add `https://*.sites.your.hostname` as a second domain on the **Appwrite** service → Deploy.

**Option B — free, per-site custom domain**

Use hostnames one level deep (covered by Cloudflare's free Universal SSL):

1. DNS: `sitename.your-main-domain` (proxied) → your server
2. Coolify: add `https://sitename.your-main-domain` to the Appwrite service → Deploy
3. Appwrite console: Sites → your site → Settings → Domains → add it

## Compose profiles

Set the `COMPOSE_PROFILES` env var in Coolify:

| Profile | Effect |
|---|---|
| `combined` | One worker — recommended, cheapest |
| `timers` | Scheduler + maintenance + interval timers |
| `separate` | 19 dedicated workers/schedulers for per-queue scaling |
| `mongodb` | Adds MongoDB for DocumentsDB (also set `_APP_DOCUMENTSDB=enabled`) |
| `embedding` | Adds the local embeddings server (also set `_APP_EMBEDDING=enabled`) |
| `assistant` | Console AI assistant (also set `_APP_ASSISTANT_OPENAI_API_KEY`, otherwise it exits with "OpenAI API key not found" and restart-loops) |

- Single-node default: `COMPOSE_PROFILES=combined,timers`
- Per-queue scaling on one node: `COMPOSE_PROFILES=separate,timers`
- Combine freely with the optional services: `separate,timers,mongodb`

`separate` automatically disables the combined worker — queues and timers are never processed twice. This mirrors Appwrite's official worker-topologies doctrine: combined is the recommended default, and running both topologies at once is explicitly unsupported because jobs race between consumers ([official announcement](https://appwrite.io/blog/post/announcing-worker-topologies) · [topologies docs](https://appwrite.io/docs/advanced/self-hosting/configuration/topologies)). The `timers` split on top of it is this template's addition for multi-node scaling (see the guide). Parked profile services carry `exclude_from_hc: true` so the stack status badge ignores them (the timers intentionally do *not* carry it — they must be monitored wherever they run). Remove that flag on any optional service you activate.

## Multi-node horizontal scaling

Appwrite officially supports horizontal scaling: stateless functions/worker containers can be replicated behind a load balancer, while the database and Redis are the stateful parts to cluster/externalize ([official scaling docs](https://appwrite.io/docs/advanced/self-hosting/production/scaling)). The API, console, realtime and workers are stateless; all state lives in PostgreSQL, Redis, ClickHouse and S3.

**Full step-by-step guide: [GUIDE-horizontal-scaling.md](GUIDE-horizontal-scaling.md)** — prerequisites, per-node env differences, load balancer setup (Cloudflare LB / Hetzner LB / HAProxy), verification, rolling upgrades, and troubleshooting. Quick summary:

1. **Prerequisite**: databases and storage externalized (see production notes) and reachable by every node over a private network.
2. **Node A (primary)**: deploy this file unchanged, `COMPOSE_PROFILES=combined,timers` (default).
3. **Node B, C, ... (workers)**: deploy the **same file**, set `COMPOSE_PROFILES=combined` — no timers, so scheduled tasks never fire twice. Workers compete for the same Redis queues by design.
4. **Secrets must be identical across nodes** — see the full guide for the list and procedure.
5. **Same `_APP_VERSION` on every node.**
6. **Load balancer** in front of all nodes — no sticky sessions needed (sessions live in PostgreSQL, realtime fans out over Redis pub/sub).
7. Functions/builds execute on the node whose worker picks the queue message, via that node's own executor.

## Scaling

- **API, realtime and the combined worker** are stateless/queue-competing and carry no `container_name`: replicate freely (`deploy.replicas` or `docker compose up --scale appwrite=2`), or add whole nodes (see multi-node below).
- Raise `_APP_WORKER_MAX_COROUTINES` (default 78) for more worker throughput.
- `_APP_WORKER_PER_CORE` (default 6) tunes worker processes per CPU core — it affects the API, realtime and executor containers; adjust to your hardware per the [official scaling docs](https://appwrite.io/docs/advanced/self-hosting/production/scaling).
- Timers run in the `timers` profile — keep them at exactly **one** instance across your whole deployment (timers must not fire twice).
- Never scale the executor, orchestrator or the databases.
- Executor and orchestrator mount `/var/run/docker.sock`: they spawn function and build containers on the host, as upstream intends.

## Upgrading & notes

- **Patch upgrades** (2.0.0 → 2.0.1): bump `_APP_VERSION` in the Coolify UI and redeploy. Check the [release notes](https://github.com/appwrite/appwrite/releases) — a migration is only required if they say so.
- **Minor/major upgrades** (2.0 → 2.1): after bumping and redeploying, run the migration once from the server terminal:
  ```bash
  docker compose -f /data/coolify/services/<stack-uuid>/docker-compose.yml exec appwrite migrate
  ```
  (Or: `docker exec -it <appwrite-container> migrate`.) Back up the database first, and step through each minor version rather than skipping (per the [official update guide](https://appwrite.io/docs/advanced/self-hosting/production/updates)).
- **Fresh PostgreSQL installs only.** For existing Appwrite installations, follow the official Appwrite upgrade docs — do not reuse old volumes with this file. (MariaDB installs: swap the `postgresql` service for `mariadb` and set `_APP_DB_ADAPTER=mariadb`.)
- Set `_APP_SMTP_*` before inviting users (emails queue until then):
  ```
  _APP_SMTP_HOST=smtp.provider.com
  _APP_SMTP_PORT=587
  _APP_SMTP_SECURE=tls
  _APP_SMTP_USERNAME=...
  _APP_SMTP_PASSWORD=...
  ```
- Never rotate `_APP_OPENSSL_KEY_V1` casually: it signs API/resource tokens and encrypts OAuth2 state, webhook passwords, API keys and encrypted columns (per the [official security guide](https://appwrite.io/docs/advanced/self-hosting/production/security)). Back it up offline; losing it makes encrypted data unrecoverable.
- Backups (per the [official backup guide](https://appwrite.io/docs/advanced/self-hosting/production/backups)): at minimum the `appwrite-postgresql` volume (all project data) plus uploads/functions/builds/certificates volumes, an offline copy of your environment variables, and — since the official guide only ships MariaDB/MongoDB commands — PostgreSQL directly:
  ```bash
  # Dump (from the server):
  docker exec <appwrite-postgresql-container> sh -c \
    'exec pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' > appwrite-$(date +%F).sql

  # Restore (fresh install only):
  docker exec -i <appwrite-postgresql-container> sh -c \
    'exec psql -U "$POSTGRES_USER" "$POSTGRES_DB"' < appwrite-2026-09-07.sql
  ```
  Test a restore periodically (official best practice: quarterly). Follow the 3-2-1 rule: 3 copies, 2 media, 1 offsite.

## Service status meanings (Coolify)

| Status | Meaning |
|---|---|
| Running (healthy) | Has a healthcheck, and it passes — proven working |
| Running (unknown) | Running but no healthcheck defined (workers, schedulers — by upstream design; they prove life by processing) |
| Exited | Parked behind a compose profile — expected for the 19 separate workers, MongoDB and Embeddings unless you enabled their profile |

## Troubleshooting

Every entry below was hit and verified in a real deployment.

| Symptom | Cause | Fix |
|---|---|---|
| Console loads, but login/register popup: `Invalid Origin. Register your new client...` | `_APP_DOMAIN` missing/wrong — API only allows that hostname | Set `_APP_DOMAIN=your.hostname`, redeploy |
| `https://…/v1/*` returns 502 (Bad Gateway) | Backend port wrong — Coolify's port auto-detection picked a wrong port | The template pins ports via `SERVICE_URL_APPWRITE_80` / `_3000`; ensure the domain editor's Port field is empty |
| `/v1` returns 404 JSON on every request | Coolify's "Strip prefixes" removed `/v1` before forwarding | Advanced → Path prefixes → **Keep prefixes** on Appwrite + Realtime |
| Site/function builds finish but deployment fails: `Build produced no output artifact.` | Build jobs mounted the wrong volume (Coolify prefixes stack volume names) | Set `_APP_BUILDS_VOLUME=<stack-uuid>_appwrite-builds` (see above) |
| Executor crash-loops: `Own container not found` | Coolify renames containers; the executor locates its own container by hostname | Already handled: `hostname: openruntimes-executor`, no `container_name` — don't re-add one |
| Creating a site fails: `Invalid domain param: Value must be a valid domain` | Sites domain polluted with a path (e.g. `/v1/realtime`) — derived from a routing-artifact variable | Keep `_APP_DOMAIN` a bare hostname; `_APP_DOMAIN_SITES` derives cleanly from it |
| Site URL fails TLS handshake at Cloudflare | Wildcard cert only covers one level; `*.sites.x.y.z` is two levels | Option A (Advanced Certificate) or Option B (one-level custom domain) |
| Redis warning: `Memory overcommit must be enabled` | Kernel setting (host-level) | Server prep command above, then restart Redis |
| Every service logs `Connection refused` to a DB host (external-DB variant) | Database server unreachable: port not published, bound to localhost, or firewalled | Publish the port on the DB stack (`<port>:<port>`), verify from the app server with `nc -zv <host> <port>` |
| Boot fails: `FATAL: database "appwrite" does not exist` (external-DB variant) | Plain external Postgres has no `appwrite` database — the bundled image creates it via `POSTGRES_DB` | `CREATE DATABASE appwrite;` on the external server (prerequisites block in the file header) |
| Boot fails: `ERROR: collation "utf8_ci_ai" for encoding "UTF8" does not exist` | Plain external Postgres lacks Appwrite's custom collation (the `appwrite/postgres` image ships it pre-created) | `CREATE COLLATION IF NOT EXISTS public.utf8_ci_ai (provider = icu, locale = 'und-u-ks-level1', deterministic = false);` — run inside the `appwrite` database |
| Usage/executions schema never ready: `Port 9000 is for clickhouse-client program` | ClickHouse port mapping swapped — host 8123 forwards to the container's native port 9000 | Map `8123:8123`, verify `curl http://<host>:8123/ping` returns `Ok.`, restart the stack |
| `appwrite-assistant` restart-loops: `OpenAI or Azure OpenAI API key not found` | Assistant enabled without `_APP_ASSISTANT_OPENAI_API_KEY` (upstream runs it always-on) | Add the key, or leave the `assistant` profile off — the default doesn't start it |

## Differences from the upstream 2.0.0 compose

Intentional adaptations, all verified against upstream:

- Coolify's proxy replaces Appwrite's own Traefik (no ports exposed, no traefik service/network)
- Coolify magic variables generate all credentials and routing; domains are managed in the Coolify UI
- The docker-run setup wizard (hostname / database engine / topology prompts) is replaced by this file plus Coolify's UI: engine = Postgres (fixed), topology = `COMPOSE_PROFILES`, secrets = magic variables, domain = Coolify domains + `_APP_DOMAIN`
- `restart: unless-stopped` normalized across all services; log rotation on all services (from upstream, applied everywhere)
- Executor: no `container_name`, `hostname: openruntimes-executor` (Coolify renames containers; the executor finds itself by hostname)
- Internal hostnames use compose service names (`openruntimes-executor`, not `exc1`) for the same reason
- Worker topology behind profiles (combined default, separate opt-in); profile-parked services excluded from the stack status badge
- API healthcheck extended with an Origin-allowlist assertion (custom addition)
- `mariadb` service removed (PostgreSQL default for fresh installs)
- Assistant behind the optional `assistant` profile (upstream runs it always-on; it exits with an error when no OpenAI key is set)
- Includes `appwrite-autogravity` (image focal-point previews), added upstream on `main` after the 2.0.0 tag — consumed by platform images newer than 2.0.0 via `_APP_AUTOGRAVITY_HOST`; on 2.0.0 it runs idle with no side effects
- MongoDB helper scripts inlined as compose `configs` (single-file template)

## Credits

- [Appwrite](https://appwrite.io) — the platform (BSD-3-Clause); this template derives from their official 2.0.0 compose file
- [Coolify](https://coolify.io) — the deployment platform this is built for
