# KORA — Deployment

Target topology, environment promotion, migration strategy, release strategy,
observability, and scaling notes for staging and production.

## 1. Topology

### Staging

```
                 ┌──────────────┐        ┌─────────────────────┐
   app/beta ───► │  Ingress/LB  │───────►│ api pods ×2          │
                 │ TLS: *.kora  │  WSS   │ (api+ws same image)  │
                 └──────────────┘        │ worker pods ×1       │
                                         └─────┬───┬────┬───────┘
                                               │   │    │
                                     managed PG│  Redis│  S3
                                               ▼   ▼    ▼
                                         staging instances
```

- Kubernetes (or managed equivalent). Namespaces: `kora-staging`,
  `kora-prod`.
- API and WS served by the same Fastify process — scale together; workers
  (outbox dispatcher, dispatch matcher, push sender) as a separate
  deployment from the same image with a different entrypoint.
- Managed Postgres 16 (HA pair), managed Redis 7, S3-compatible object
  storage. Staging uses Kaspi **sandbox** + real SMS provider.

### Production

Same shape, hardened:

- API: ≥3 replicas across AZs, HPA on CPU+RPS; WS nodes behind an
  L7 LB with **sticky sessions** (or any node acceptable — reconnect +
  `lastEventId` resync makes stickiness an optimisation, not a requirement).
- Postgres: primary + ≥1 read replica, automated backups + WAL archiving
  (PITR). PgBouncer transaction pooling.
- Redis: managed HA (Sentinel/cluster). Pub/sub is ephemeral — no persistence
  needed for correctness (outbox is the source of truth).
- S3: versioned bucket + lifecycle rules + CDN in front for GETs.
- CDN/WAF in front of the API domain; TLS terminated at ingress with HSTS.

## 2. Environment promotion

| Step | Gate |
|------|------|
| `development` → `staging` | CI green (typecheck, tests, gitleaks), migrations reviewable |
| `staging` → `production` | Smoke suite on staging, migration dry-run on prod-like data, manual approval |

- Env vars and secrets live in the platform secret store; `.env.example`
  documents names only. Per-environment values: see SETUP.md §5 table.
- App builds are produced per environment via `--dart-define` (API_URL,
  WS_URL, APP_ENV) — same Dart code, different compile-time config.
- Config is immutable per release: changing a secret = new rollout.

## 3. Database migrations

Prisma Migrate, **expand/contract** only:

1. **Expand:** additive changes (new tables/columns as nullable or with
   defaults, new indexes `CONCURRENTLY`). Deploy code that writes both old
   and new shape.
2. **Backfill:** data migration in a worker/job, chunked, resumable.
3. **Contract:** remove old columns/paths only after all app/backend
   versions in the field no longer use them (app store lag ≥2 weeks for
   mobile → contract phase waits accordingly).

Rules:

- Migrations run as a **pre-deploy job** (`prisma migrate deploy`) — never
  embedded in app start; failing migration blocks the rollout.
- No destructive changes in the same release that introduces them.
- Backwards-incompatible API changes ride alongside schema phases — old app
  versions must keep working (versioned `/v1` prefix helps).
- Rollback: code rollback is always safe during expand; for contract phase,
  restore from backup/PITR — see DISASTER_RECOVERY.md.

## 4. Release strategy — blue/green (or rolling)

- Container image tagged `git-<sha>`; deploy to `green`, run smoke checks
  (`/ready`, login→order happy path with test accounts), then switch ingress
  weight; keep `blue` warm ≥30 min for instant rollback.
- WS: drain connections on shutdown (SIGTERM → stop accepting, send
  `close` with reconnect hint, wait ≤60 s). Clients resync via
  `lastEventId`.
- `release.yml` builds the app artifacts (AAB/APK; IPA on macOS runner);
  store submission is manual/phased (see STORE_RELEASE.md).

## 5. Observability

| Signal | Tool | Details |
|--------|------|---------|
| Logs | pino (JSON) → log aggregator | `requestId` everywhere; redaction per SECURITY.md §7 |
| Metrics | Prometheus `/metrics` (or OTel) | req rate/latency p50/p95/p99 per route, WS conns, outbox lag, dispatch offer→accept time, OTP success rate, webhook failures |
| Tracing | OpenTelemetry | propagate `traceparent` to provider calls; DB spans via Prisma instrumentation |
| Alerts | paging | `/ready` failing >2 min, error rate >1% 5xx, outbox lag >60 s, webhook failure spike, OTP delivery failure spike, PG replication lag |
| Health | `/health` (liveness), `/ready` (readiness: db+redis+s3) | k8s probes wired to both |

## 6. Backup & restore pointers

Policy and runbook live in [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md).
Summary: nightly `pg_dump` + continuous WAL archive for PITR (30 d
retention), Redis treated as rebuildable, S3 versioning + replication.

## 7. Redis & storage notes

- Redis usage: OTP store (TTL keys — must not persist beyond TTL), rate
  limits, WS pub/sub, cache. AOF in dev; prod uses managed HA — losing Redis
  must degrade (OTP/WS pause) not corrupt.
- Pub/sub topics: `events:user:{id}`, `events:store:{id}`,
  `events:courier:{id}` — fanout only; durability via Postgres outbox.
- S3: private bucket, presigned URLs only, lifecycle: delivery proofs and
  chat media retained per privacy policy (§retention), logs bucket separate.

## 8. WebSocket scaling detail

- Sticky sessions at LB preferred (fewer resyncs) but not required.
- Fanout via Redis pub/sub: domain writes `OutboxEvent` (same tx as the
  state change) → dispatcher publishes → every API node checks its local
  connection registry and delivers to connected sockets.
- Capacity target: a node holds ~10–20k idle WS conns; scale WS-bearing pods
  on `ws_connections` metric, not CPU.
- On pod eviction/crash clients reconnect with backoff and `resync` —
  verified by TESTING.md reconnect cases.

## 9. Checklist — new environment bring-up

1. Provision Postgres 16, run `infra/db/init.sql` equivalents (extensions),
   create app user + migration user.
2. Provision Redis 7 (HA in prod), S3 bucket + IAM creds, create bucket.
3. Populate secrets per `.env.example` names (real values in secret store).
4. Deploy migration job → `prisma migrate deploy` → deploy api/ws + workers.
5. Point DNS + TLS, configure `CORS_ORIGINS`, Kaspi webhook URL
   (`/v1/payments/webhook/kaspi`) in merchant console.
6. Smoke: `/ready`, OTP request, order happy path, WS connect, webhook
   signature check with a test payload.
7. Wire alerts + dashboards; verify backup job + one test restore.
