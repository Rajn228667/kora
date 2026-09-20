# KORA — Disaster Recovery

Backup policy, restore runbooks, and RTO/RPO targets. Postgres is the only
system of record that cannot be rebuilt; everything else degrades or
regenerates.

## 1. RTO / RPO targets

| Tier | Scenario | RPO | RTO |
|------|----------|-----|-----|
| Postgres | Logical corruption / accidental delete | ≤5 min (WAL archive) | ≤2 h (PITR restore) |
| Postgres | Instance loss | ≤5 min | ≤1 h (replica promote / managed failover) |
| Redis | Full loss | n/a — ephemeral (rebuild; OTP/WS pause) | ≤15 min |
| S3 media | Bucket loss | 0 (versioning + replication) | ≤4 h (re-point endpoint) |
| Whole region | Region outage | ≤15 min | ≤8 h (cold restore to secondary region) |

## 2. Backup policy

### PostgreSQL

- **Base backups:** nightly `pg_dump` (custom format, compressed) → off-site
  S3 bucket `kora-backups`, **30-day retention**, lifecycle-expired.
- **PITR:** continuous WAL archiving (managed PG feature or wal-g) → same
  bucket, 30-day window. Enables restore to any second in the window.
- **Verification:** monthly automated restore to a throwaway instance +
  `pg_restore --list` sanity + row-count checks on `orders`, `payments`,
  `users`. A backup that has never been restored is not a backup.
- Encryption at rest (S3 SSE); access limited to the ops role; bucket is
  not public and not lifecycle-coupled to app buckets.

### Redis

- AOF/RDB snapshots enabled, but **treated as rebuildable**: OTP keys expire
  on TTL anyway; rate limits and pub/sub are ephemeral; caches regenerate.
  No restore runbook beyond "start fresh instance" (§5).

### S3 media (`kora-media`)

- Bucket **versioning** on; object-lock/deletion protection on prod.
- Cross-region replication to the DR bucket.
- Media keys are referenced from Postgres (`media_url`s, chat attachments,
  delivery proofs) — restore ordering matters: Postgres first, then verify
  keys exist (missing objects surface as 404 on signed GET — acceptable
  degradation, log & repair).

## 3. Restore runbook — Postgres

### 3a. Point-in-time recovery (PITR) — preferred for corruption

```bash
# 1. Freeze writes: scale api+workers to 0 (or put LB into maintenance)
kubectl scale deploy/api --replicas=0 -n kora-prod
kubectl scale deploy/worker --replicas=0 -n kora-prod

# 2. Restore to a NEW instance at target timestamp T (managed console or wal-g)
#    e.g. wal-g backup-fetch + recovery_target_time='2026-09-20 09:55:00+05'

# 3. Validate on restored instance
psql "$RESTORED_URL" -c "SELECT count(*) FROM orders WHERE created_at > now() - interval '1 day';"
psql "$RESTORED_URL" -c "SELECT max(created_at) FROM payments;"   # ≈ T

# 4. Repoint DATABASE_URL secret → rollout restart
# 5. Scale services back; verify /ready, run smoke order
```

### 3b. Logical restore from nightly dump

```bash
pg_restore --clean --if-exists --no-owner \
  --dbname="$DATABASE_URL" backup-YYYYMMDD.dump
# Then: npx prisma migrate deploy  (catch up migrations since dump)
```

### 3c. Single-table surgical restore

Restore dump to scratch instance → `pg_dump -t orders -t payments` of the
affected window → restore into prod with conflict handling. Prefer PITR when
the blast radius is unclear.

## 4. Migration rollback procedure

Migrations are expand/contract (see DEPLOYMENT.md §3), so rollback is usually
a code rollback. If a migration must be reversed:

1. **Expand phase** — safe: roll back code; new columns/tables stay unused.
2. **Contract phase** — the old shape is gone; recovery requires restore:
   PITR to just before the contract migration, then replay/accept data gap
   (communicate: orders created in the gap may need manual reconciliation
   from payment-provider records + audit log).
3. Always capture `pg_dump` of affected tables immediately before a contract
   migration runs.

## 5. Redis rebuild

```bash
# Provision fresh instance, update REDIS_URL secret, rollout restart.
# Post-checks:
#  - OTP: request + verify one challenge (new codes work; old ones are gone
#    — acceptable, users re-request)
#  - WS fanout: send a test order.status_changed, confirm delivery
#  - Rate limits: confirm counters fresh (brief abuse window — monitor)
```

## 6. Media restore

- Deleted object with versioning: restore previous version via S3 console/API.
- Bucket loss: fail over `S3_ENDPOINT`/bucket to the replicated DR bucket;
  objects missing (replication gap) render as 404s — run the reconciliation
  script (scan `media` references → list missing keys → mark records or
  re-upload from sources where available).
- Delivery proofs are the highest-value media (dispute evidence) — verify
  `proofs/` prefix integrity first.

## 7. Whole-region failover (cold DR)

1. Restore latest base backup + WAL to secondary region Postgres.
2. Provision Redis + S3 (replica bucket already warm).
3. Re-create k8s/workloads from IaC; repopulate secrets.
4. DNS cutover (`api.kora.kz` → DR ingress); Kaspi webhook URL update in
   merchant console (or use a stable webhook domain fronted by failover).
5. Expected state: all data to ≤15 min ago; in-flight orders may have
   inconsistent payment state — reconcile `pending_payment` orders via
   provider `status()` poller.

## 8. DR drill schedule

- Quarterly: PITR restore to scratch + app smoke against it.
- Annually: full region failover tabletop + timed restore.
- After every incident: update this runbook.
