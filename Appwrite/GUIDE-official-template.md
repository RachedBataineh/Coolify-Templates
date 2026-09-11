# Appwrite 2.0 Official Coolify Template — Deployment Guide

Deploy [Appwrite](https://appwrite.io) 2.0 on [Coolify](https://coolify.io) using the official template, with the two required fixes for first-deploy success.

## What you get

- Full Appwrite 2.0 platform (Console IV, API, realtime, functions, sites, auth, storage)
- PostgreSQL 18 + Redis 7.4 + ClickHouse 26.4 (all bundled, passwordless, auto-generated credentials)
- Combined worker topology (one worker, one scheduler — recommended for most installs)
- Assistant (Console AI) — works out of the box with an OpenAI API key

## Requirements

- A Coolify server (Docker Compose resource type)
- ~2 GB RAM free; 4 GB recommended
- A DNS record pointing your domain at the server
- (Optional) An OpenAI API key for the Console AI assistant

## Deploy in 4 steps

### Step 1 — Create the resource

Coolify → New Resource → Docker Compose → paste this file → **Save** (don't deploy yet).

### Step 2 — Fill the required `_APP_DOMAIN` field

The template marks `_APP_DOMAIN` as **required** (Coolify deploy `:?` syntax), so it appears as a mandatory field and deploy is blocked until it's set:

```
_APP_DOMAIN=your.hostname.com
```

Set it to your **bare hostname only** — no `https://`, no path, no port. There is deliberately no default: the `$SERVICE_FQDN_APPWRITE` magic variable carries path pollution (`/v1/realtime` from the realtime service) that breaks registration with "Invalid Origin." Everything else (`functions.your.hostname.com`, `sites.your.hostname.com`) derives from it automatically via nested interpolation (`functions.${_APP_DOMAIN}`).

### Step 3 — Configure the three domains + Keep prefixes

Set the same hostname on all three routed services:

| Service | Domain | Purpose |
|---|---|---|
| Appwrite | `https://your.hostname.com/v1` | API |
| Appwrite Console | `https://your.hostname.com` | Dashboard |
| Appwrite Realtime | `https://your.hostname.com/v1/realtime` | Websockets |

Then on the **Appwrite** and **Appwrite Realtime** services:
**Advanced → Path prefixes → Keep prefixes** (not the default "Strip prefixes").

> Without Keep prefixes, every API request returns 404 because Coolify strips `/v1` before forwarding.

### Step 4 — (Optional) Add the OpenAI key, then Deploy

```
_APP_ASSISTANT_OPENAI_API_KEY=sk-your-key-here
```

Without a key, the assistant container restart-loops (it has `exclude_from_hc: true` so it won't affect the stack badge). With a key, the Console AI works fully.

Click **Deploy**.

## Verify

```
https://your.hostname.com/v1/health/version
```

Must return `{"version":"2.0.0"}` as JSON. Then open the console, register the first user (it becomes the admin), and check the Usage tab — it should show data flowing.

## Before the first site/function build

The template auto-detects the builds volume using `${COMPOSE_PROJECT_NAME}_appwrite-builds`, so **no manual fix is needed** — this is already handled.

If builds still fail with "Build produced no output artifact", check on the server:

```bash
docker volume ls | grep builds
```

Compare with the value of `COMPOSE_PROJECT_NAME` in the env tab.

## Known noise (safe to ignore)

| Log line | Why |
|---|---|
| `ERROR: relation "logsV1__metadata" already exists` | Idempotent boot on redeploys — Appwrite catches it |
| `WARNING: there is no transaction in progress` | Benign usage-stats commit pattern |
| `Logging errors to /var/log/clickhouse-server/...` | ClickHouse startup info, not an actual error |
| `max_connection is exceed the maximum value, it's reset to 1024` | Realtime ulimit cap (harmless below ~1000 concurrent websockets) |
| `You must set a valid security email address (_APP_EMAIL_CERTIFICATES)` | A project custom-domain certificate job ran with no email set. Not fatal — the worker keeps all queues running. Set `_APP_EMAIL_CERTIFICATES` or remove the custom domain |
| Orchestrator `WARN: API authentication disabled ... no API_KEY configured` | Official-template behavior: orchestrator's internal API accepts unauthenticated calls, but it has no published port and is only reachable inside the Docker network |
| Assistant: `Initializing search index...` then ~90s of silence | Assistant builds its local search index on boot; slow but normal, and it's excluded from health checks so the stack badge stays green |
| Realtime `realtime.close` events every 20s with `subscriptions_before_close 0` | Coolify's healthcheck opening and closing a websocket — expected rhythm, not client traffic |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Login/register popup: "Invalid Origin" | `_APP_DOMAIN` empty or polluted | Set `_APP_DOMAIN=your.hostname` (bare hostname), redeploy |
| Every API request returns 404 | Coolify stripped `/v1` prefix | Advanced → Path prefixes → **Keep prefixes** on Appwrite + Realtime |
| API returns 502 | Wrong backend port | Ensure the Port field is empty on the Appwrite service domain |
| Console loads but no data | API routing broken | Check both fixes above; verify `/v1/health/version` returns JSON |
| Assistant restart-loops | No OpenAI key set | Add `_APP_ASSISTANT_OPENAI_API_KEY` or ignore (badge-safe) |

## Optional upgrades

- **Autogravity** — smart image cropping (see `PLAN-autogravity.md`)
- **Realtime ulimits** — add `ulimits: nofile: 65536` to the realtime service for >1000 concurrent websockets
- **SMTP** — set `_APP_SMTP_*` variables before inviting team members

## Credits

- [Appwrite](https://appwrite.io) — the platform (BSD-3-Clause)
- [Coolify](https://coolify.io) — the deployment platform
