# KORA — Developer Setup

End-to-end guide to run KORA locally: infrastructure, backend, and the
Flutter app.

## 1. Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Docker Desktop | latest | Runs Postgres, Redis, MinIO via `infra/docker-compose.yml` |
| Node.js | **24** (LTS) | Use nvm/nvm-windows or Volta |
| npm | bundled with Node | |
| Flutter SDK | stable (≥3.x) | **Not preinstalled on dev machines — install manually:** <https://docs.flutter.dev/get-started/install>. After install: `flutter doctor` must pass for `android` and/or `ios` targets. |
| Android Studio / Xcode | latest | For emulators & signing (Android SDK + cmdline-tools for Android) |
| Git | any | |

Verify:

```bash
node -v          # v24.x
docker version
flutter --version && flutter doctor
```

## 2. Start infrastructure

From the repo root:

```bash
docker compose -f infra/docker-compose.yml up -d
docker compose -f infra/docker-compose.yml ps    # all healthy
```

Services:

| Service | Port(s) | Purpose |
|---------|---------|---------|
| postgres | 5432 | `postgresql://kora:kora@localhost:5432/kora`; init.sql installs `pg_trgm`, `unaccent`, `pgcrypto` |
| redis | 6379 | `redis://localhost:6379`, appendonly persistence |
| minio | 9000 (S3 API), 9001 (console) | user `kora` / `koraminio`; `minio-init` job auto-creates bucket `kora-media` |

> If the bucket is missing (e.g. volume wiped while minio-init already ran):
> `docker compose -f infra/docker-compose.yml up minio-init`.

## 3. Backend

```bash
# Copy the env template into place. The backend ships its own template
# (backend/.env.example); the canonical full list lives at repo root
# (.env.example). Either way the dev defaults match docker-compose.
cp backend/.env.example backend/.env   # or: cp .env.example backend/.env
cd backend
npm install
npx prisma migrate dev           # create schema + apply migrations
npm run dev                      # Fastify on http://localhost:3000
```

Verify:

```bash
curl http://localhost:3000/health   # {"status":"ok"}
curl http://localhost:3000/ready    # checks db + redis + s3
# OpenAPI UI: http://localhost:3000/docs
```

Useful commands:

```bash
npx prisma studio        # DB browser
npx prisma migrate dev   # new migration after schema change
npx tsc --noEmit         # typecheck
npx vitest run           # tests
npm run lint             # if configured
```

## 4. Flutter app

```bash
cd app
flutter pub get

# One-time only, if android/ and ios/ folders are absent:
flutter create . --platforms android,ios

flutter run \
  --dart-define API_URL=http://localhost:3000 \
  --dart-define WS_URL=ws://localhost:3000 \
  --dart-define APP_ENV=development
```

> **Android emulator:** use `API_URL=http://10.0.2.2:3000` and
> `WS_URL=ws://10.0.2.2:3000` — `localhost` inside the emulator is the
> emulator itself. For a physical device, use your machine's LAN IP.

Dev login: enter any `+7…` phone → OTP is `123456` (`OTP_DEV_CODE`).

## 5. Environment variables

Canonical template: [`.env.example`](../.env.example) at repo root — copy to
`backend/.env`.

| Variable | development | staging | production |
|----------|-------------|---------|------------|
| `APP_ENV` | `development` | `staging` | `production` |
| `PORT` / `HOST` | `3000` / `0.0.0.0` | managed | managed |
| `DATABASE_URL` | `postgresql://kora:kora@localhost:5432/kora` | managed Postgres + TLS | managed Postgres + TLS |
| `REDIS_URL` | `redis://localhost:6379` | managed Redis + TLS | managed Redis + TLS |
| `JWT_SECRET` | any 32+ char string | **secret store** | **secret store** |
| `JWT_ACCESS_TTL` / `JWT_REFRESH_TTL` | `15m` / `30d` | `15m` / `30d` | `15m` / `30d` |
| `OTP_DEV_CODE` | `123456` | **unset** | **unset** |
| `SMS_PROVIDER` / `SMS_API_KEY` | `dev` (logs code) | real provider | real provider |
| `STORAGE_DRIVER` | `s3` | `s3` | `s3` |
| `S3_ENDPOINT` | `http://localhost:9000` | object storage endpoint | object storage endpoint |
| `S3_BUCKET` | `kora-media` | `kora-media-staging` | `kora-media` |
| `S3_ACCESS_KEY` / `S3_SECRET_KEY` | `kora` / `koraminio` (or leave for SDK chain) | secret store | secret store |
| `FCM_SERVER_KEY` | optional | real key | real key |
| `APNS_*` | optional | real creds | real creds |
| `KASPI_*` | empty → **mock provider** | Kaspi sandbox | Kaspi production |
| `MAPS_PROVIDER` / `YANDEX_MAPS_API_KEY` | `yandex` / dev key | `yandex` / real key | `yandex` / real key |
| `CORS_ORIGINS` | empty | admin/manager web origins | admin/manager web origins |
| `LOG_LEVEL` | `info` (or `debug`) | `info` | `info` |

App-side flags (compile-time, `--dart-define`):

| Flag | dev | staging | prod |
|------|-----|---------|------|
| `API_URL` | `http://localhost:3000` | `https://api.staging.kora.kz` | `https://api.kora.kz` |
| `WS_URL` | `ws://localhost:3000` | `wss://api.staging.kora.kz` | `wss://api.kora.kz` |
| `APP_ENV` | `development` | `staging` | `production` |

## 6. Seed data

If `backend/prisma/seed.ts` exists: `npx prisma db seed` (dev only — creates
demo stores, products, a manager and a courier account). Seeding is **never**
run automatically against staging/production.

## 7. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `P1001: Can't reach database` | `docker compose -f infra/docker-compose.yml ps` — postgres must be `healthy`; check port 5432 not taken by a local Postgres |
| Prisma schema drift error | `npx prisma migrate dev` (dev). Never `migrate reset` on shared DBs |
| `/ready` returns 503 | It checks Postgres, Redis, S3 — see the `checks` field in the response for which dependency failed |
| `S3 bucket does not exist` | `docker compose -f infra/docker-compose.yml up minio-init` |
| Redis `NOAUTH` / connection refused | Confirm `REDIS_URL` matches compose (no password in dev) |
| App can't reach API on Android emulator | Use `10.0.2.2` instead of `localhost` |
| WS immediately closes | Check `WS_URL` scheme (`ws://` dev) and that the access token is appended: `/v1/ws?token=…` |
| OTP not arriving | In dev the code is `123456` and/or printed in backend logs when `SMS_PROVIDER=dev` |
| `JWT_SECRET` too short warning | Must be ≥32 chars — generate `openssl rand -base64 48` |
| Port already in use | Change `PORT` or free the port (`netstat -ano \| findstr :3000` on Windows) |
| Flutter: `android/ios folder missing` | `flutter create . --platforms android,ios` inside `app/` |
| Docker volume corrupt | `docker compose -f infra/docker-compose.yml down -v && up -d` (wipes local data) |

## 8. Reset everything

```bash
docker compose -f infra/docker-compose.yml down -v   # drop volumes
docker compose -f infra/docker-compose.yml up -d
cd backend && npx prisma migrate dev && npx prisma db seed
```
