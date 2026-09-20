# KORA

KORA is a Kazakhstan-focused food & marketplace delivery platform. It consists
of a Flutter mobile app (customers, couriers, store managers) and a
Node.js/TypeScript Fastify backend backed by PostgreSQL, Redis and
S3-compatible object storage.

- **Backend:** Node 24 · TypeScript · Fastify v5 · Prisma 6 · PostgreSQL 16 · Redis 7 · MinIO/S3
- **App:** Flutter · Riverpod · go_router · dio
- **Payments:** Kaspi merchant API (mock provider in development)
- **Maps:** 2GIS Mobile SDK (provider abstraction — `app/lib/core/maps/map_engine.dart`)
- **Realtime:** WebSocket at `/v1/ws` for order tracking, chat, courier location

## Architecture

```
                        ┌──────────────────────────────────────────────┐
                        │                 Flutter app                   │
                        │   customer · courier · store manager roles    │
                        └───────┬──────────────────────────┬───────────┘
                                │ HTTPS / REST             │ WSS /v1/ws
                                ▼                          ▼
        ┌───────────────────────────────────────────────────────────┐
        │                    Fastify API (Node 24)                   │
        │  auth (OTP→JWT) · RBAC · orders · payments · chat · admin  │
        │  OpenAPI at /docs · health /health /ready                  │
        └──┬──────────┬──────────┬──────────┬───────────┬───────────┘
           │          │          │          │           │
           ▼          ▼          ▼          ▼           ▼
      ┌─────────┐ ┌───────┐ ┌─────────┐ ┌────────┐ ┌──────────────┐
      │Postgres │ │ Redis │ │ MinIO/S3│ │ Kaspi  │ │ FCM / APNs   │
      │ 16 +    │ │ 7     │ │ media   │ │ payment│ │ push         │
      │Prisma 6 │ │cache/ │ │(signed  │ │ API    │ │              │
      │         │ │pubsub │ │ URLs)   │ │        │ │              │
      └─────────┘ └───────┘ └─────────┘ └────────┘ └──────────────┘
                                       ▲
                        signed webhook /v1/payments/webhook/kaspi

        External: SMS provider (OTP) · Yandex Maps · Push gateways
```

Key design points:

- **Auth:** phone (+7…) OTP → JWT access (15 m) + refresh (30 d, rotation with
  reuse detection). Server-side RBAC: `CUSTOMER` / `MANAGER` / `COURIER` / `ADMIN`.
- **Order lifecycle:** `draft → pending_payment → paid → accepted →
  preparing → ready_for_pickup → courier_assigned → picked_up → delivering →
  delivered` (+ `cancelled` / `rejected`). Payment is verified via the signed
  Kaspi webhook before an order becomes `paid`. Delivery address is stored as
  an immutable snapshot on the order.
- **Dispatch:** courier scoring = distance + availability + current workload.
- **Money:** integer tiyn (1 KZT = 100 tiyn) end-to-end — never floats.
- **Realtime:** WS envelope `{id, type, event, payload, ts}`; clients resync
  with `lastEventId` after reconnect.

## Quickstart

Prerequisites: Docker Desktop, Node 24, Flutter SDK (stable).

```bash
# 1. Start infrastructure (Postgres, Redis, MinIO + bucket)
docker compose -f infra/docker-compose.yml up -d

# 2. Backend
cp backend/.env.example backend/.env  # dev defaults work; root .env.example is the canonical list
cd backend
npm install
npx prisma migrate dev
npm run dev                           # http://localhost:3000 · /docs · /health

# 3. App (new terminal)
cd app
flutter pub get
flutter create . --platforms android,ios   # once, if platform folders missing
flutter run \
  --dart-define API_URL=http://localhost:3000 \
  --dart-define WS_URL=ws://localhost:3000 \
  --dart-define APP_ENV=development
```

Dev login: request OTP for any `+7…` phone, enter `123456`
(`OTP_DEV_CODE` in `.env`).

See [docs/SETUP.md](docs/SETUP.md) for the full guide and troubleshooting.

## Repository layout

```
kora/
├── app/                    # Flutter app (customer / courier / manager)
├── backend/                # Fastify + Prisma API
│   ├── src/                # modules, plugins, ws gateway
│   └── prisma/             # schema + migrations
├── docs/                   # all documentation (see below)
├── infra/
│   ├── docker-compose.yml  # dev: postgres, redis, minio
│   └── db/init.sql         # pg_trgm, unaccent, pgcrypto extensions
├── .github/workflows/      # ci.yml, release.yml
├── .env.example            # canonical backend env template
└── README.md
```

## Documentation

| Doc | Contents |
|-----|----------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, order state machine, dispatch, WS channels, scaling |
| [docs/SETUP.md](docs/SETUP.md) | Prerequisites, local setup, env tables, troubleshooting |
| [docs/API.md](docs/API.md) | REST reference for all route groups + WebSocket protocol |
| [docs/SECURITY.md](docs/SECURITY.md) | Authn/z, JWT rotation, OTP protections, RBAC matrix, threat model |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Staging/prod topology, migrations, blue/green, observability |
| [docs/DISASTER_RECOVERY.md](docs/DISASTER_RECOVERY.md) | Backups, PITR restore runbook, RTO/RPO |
| [docs/STORE_RELEASE.md](docs/STORE_RELEASE.md) | Google Play / App Store checklists, signing, privacy labels |
| [docs/TESTING.md](docs/TESTING.md) | Test pyramid, how to run, E2E checklist |
| [docs/PRIVACY_POLICY.md](docs/PRIVACY_POLICY.md) | Privacy policy |
| [docs/TERMS.md](docs/TERMS.md) | Terms of service (customers, stores, couriers) |
| [docs/DATA_SAFETY.md](docs/DATA_SAFETY.md) | Play Data Safety + Apple App Privacy mapping |

## Testing & CI

```bash
cd backend
npx tsc --noEmit        # typecheck
npx vitest run          # unit/integration tests
cd ../app
flutter analyze
flutter test
```

GitHub Actions (`.github/workflows/ci.yml`) runs backend typecheck+tests,
Flutter analyze+test, gitleaks, npm audit, and a docker-compose smoke check
on every PR and push to `main`.

## Environments

| Environment | Purpose | API base |
|-------------|---------|----------|
| `development` | Local docker-compose + dev OTP `123456`, mock payments | `http://localhost:3000` |
| `staging` | Pre-prod, real SMS + Kaspi sandbox, test data | `https://api.staging.kora.kz` |
| `production` | Live | `https://api.kora.kz` |

---

## Кратко (RU)

KORA — казахстанская платформа доставки еды и маркетплейса. Монорепозиторий:
Flutter-приложение (`app/`) и backend на Fastify/TypeScript (`backend/`), база
PostgreSQL 16, Redis 7, S3-хранилище (MinIO локально). Быстрый старт: поднять
`infra/docker-compose.yml`, затем `npm install && npx prisma migrate dev &&
npm run dev` в `backend/`, затем `flutter run` с `--dart-define` параметрами в
`app/`. В development OTP-код всегда `123456`, платежи — mock-провайдер. Вся
документация — в `docs/`.
