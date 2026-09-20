# KORA — Architecture

This document describes the system design of the KORA delivery platform:
components, data flow, order lifecycle, dispatch, realtime channels, offline
sync, and scaling strategy.

## 1. System overview

```
                          ┌─────────────────────────────────────────┐
                          │        Flutter app (single codebase)     │
                          │   CUSTOMER · COURIER · MANAGER · ADMIN   │
                          │   Riverpod · go_router · dio             │
                          └──────┬─────────────────────┬─────────────┘
                                 │ REST/HTTPS           │ WSS
                                 ▼                      ▼
        ┌────────────────────────────────────────────────────────────┐
        │                  Fastify v5 API  (Node 24, TS)              │
        │                                                            │
        │  plugins: jwt · rbac · rate-limit · cors · sensible · ws     │
        │  modules: auth users stores products cart checkout orders    │
        │           payments couriers tracking chat calls notifs       │
        │           support promotions manager admin                   │
        │  OpenAPI UI: /docs      health: /health  /ready              │
        └─┬───────────┬───────────┬────────────┬───────────┬──────────┘
          │ Prisma 6  │ ioredis   │ S3 SDK     │ HTTP      │ push
          ▼           ▼           ▼            ▼           ▼
     ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────────┐
     │Postgres │ │ Redis 7 │ │MinIO/S3 │ │ Kaspi   │ │ FCM / APNs  │
     │ 16      │ │ cache · │ │ media   │ │merchant │ │ push        │
     │pg_trgm· │ │ OTP ·   │ │(private │ │ API     │ │ gateways    │
     │unaccent │ │ rl ·    │ │ bucket, │ │+ signed │ │             │
     │pgcrypto │ │ pub/sub │ │ signed  │ │webhook  │ │             │
     └─────────┘ └─────────┘ │ URLs)   │ └────┬────┘ └─────────────┘
                            └─────────┘      │
                External: SMS provider · Yandex Maps
```

### Design principles

- **API-first, contract-strict.** All responses use one error shape
  (`{error:{code,message,details}}`), cursor pagination
  (`{items,nextCursor}`), UUID ids, ISO-8601 timestamps, and **integer tiyn**
  for all money values (1 KZT = 100 tiyn). No floats cross the wire.
- **Server-side authority.** RBAC, prices, order state transitions and payment
  status are decided only by the backend. The app renders state; it never
  owns it.
- **Provider abstractions.** SMS, payments, maps, storage, and push are
  interfaces with swappable implementations (dev/mocks for local, real
  vendors in staging/prod).

## 2. Components

### 2.1 Backend modules (`backend/src/modules/`)

| Module | Responsibility |
|--------|----------------|
| `auth` | OTP request/verify, JWT issue/refresh/logout, refresh rotation + reuse detection, session list |
| `users` | Profile CRUD, saved addresses, role assignment (admin), device tokens |
| `stores` | Store CRUD (manager/admin), opening hours, delivery zones, store status |
| `categories` | Store-level product categories, ordering |
| `products` | Product CRUD, modifiers/options, availability, media |
| `search` | Cross-store product/store search (pg_trgm + unaccent), suggestions |
| `cart` | Per-user cart, per-store grouping, price revalidation |
| `checkout` | Quote (items+fees+delivery), promo application, order creation |
| `orders` | Order reads, state transitions, cancellation windows, history |
| `payments` | `PaymentProvider` interface, Kaspi provider, intents, webhook ingest |
| `couriers` | Courier profile, online/offline, location ingest, dispatch offers |
| `tracking` | Order tracking reads, courier position streaming |
| `chat` | Threads (customer↔store, customer↔courier, support), messages, read receipts |
| `calls` | VoIP/session signalling metadata (call.* events) |
| `notifications` | Push + in-app notifications, preferences, device tokens |
| `support` | Tickets, canned replies, escalation |
| `promotions` | Promo codes, campaigns, validation rules |
| `manager` | Store-manager dashboard: incoming orders, accept/reject, prep times, menu availability |
| `admin` | Admin console: users, stores, couriers, orders, promos, audit log |

### 2.2 Cross-cutting (`backend/src/`)

| Layer | Contents |
|-------|----------|
| `plugins/` | fastify-jwt auth guard, `rbac` guard (role+permission check), rate-limit, error handler (single error envelope), request-id, prisma, redis, ws |
| `lib/` | tiyn money helpers, pagination cursors, signed-URL signer, geo utils, event bus |
| `providers/` | `PaymentProvider` (kaspi, mock), `SmsProvider` (dev, vendor), `MapsProvider` (yandex), `StorageDriver` (s3), `PushProvider` (fcm, apns) |
| `ws/` | connection registry, channel router, auth at upgrade (`?token=`), event fanout, `lastEventId` resync |
| `workers/` | outbox dispatcher (WS fanout + push), dispatch matcher, OTP cleanup |

### 2.3 App structure (`app/lib/`)

| Layer | Contents |
|-------|----------|
| `core/` | dio client (interceptors: auth, retry, error mapping), env config via `--dart-define`, secure token storage, connectivity |
| `features/` | auth, catalog, cart, checkout, orders, tracking, chat, calls, notifications, profile, manager, courier, admin — each with `data/` (dto+repo), `application/` (Riverpod providers), `presentation/` (screens/widgets) |
| `router/` | go_router with role-based guards and deep links |
| `l10n/` | ru/kk/en strings |

## 3. Data model highlights

- `User(id uuid, phone unique, role, name, …)` — one account, role set at
  registration or elevated by admin.
- `Store`, `Category`, `Product`, `Modifier` — menu graph owned by a store;
  `Product.priceTiyn int`.
- `Cart`/`CartItem` — server-side cart, revalidated at checkout.
- `Order(id, customerId, storeId, courierId?, status, items jsonb snapshot,
  deliveryAddress jsonb snapshot, totalsTiyn, paymentId?, …)`.
- `Payment(id, orderId, provider, providerRef, status, amountTiyn,
  idempotencyKey, …)`.
- `Courier`, `CourierLocation(time, geo)` — latest position + short history.
- `ChatThread`, `ChatMessage`, `Notification`, `DeviceToken`,
  `RefreshToken(hash, family, revokedAt)`, `OtpChallenge(hash, expiresAt,
  attempts)`, `AuditLog`, `OutboxEvent(seq bigserial, type, payload)`.

**Immutable snapshots:** the order stores its item list and the delivery
address as JSONB snapshots taken at checkout. Later edits to the product
catalogue or the user's address book never mutate historical orders.

## 4. Order lifecycle (state machine)

```
                 customer                 store/manager            courier
                    │                          │                      │
   cart ──checkout──▼                          │                      │
              ┌──────────┐                     │                      │
              │  draft   │  (server-side cart; not yet an order)      │
              └────┬─────┘                                            │
     POST /checkout│ creates Order + Payment intent                   │
                   ▼                                                  │
        ┌───────────────────┐   webhook verified (Kaspi, idempotent)  │
        │  pending_payment  │───────────────┐                         │
        └─────────┬─────────┘               ▼                         │
                  │ timeout/failed      ┌──────┐                      │
                  │ ┌───────────────┐   │ paid │                      │
                  ├►│ cancelled     │   └──┬───┘                      │
                  ▼ │ (payment_     │      │ order.created → store    │
        ┌──────────┐│  failed)      │      ▼                          │
        │ rejected │└───────────────┘ ┌──────────┐                    │
        └──────────┘                  │ accepted │──manager rejects──►│rejected
                    ▲                 └────┬─────┘ (prep time set)    │
        manager rejects                   ▼                          │
        before pickup            ┌──────────────┐                      │
                                 │  preparing   │                      │
                                 └──────┬───────┘                      │
                                        ▼                              │
                              ┌───────────────────┐   dispatch match   │
                              │ ready_for_pickup  │──────────────────► │
                              └────────┬──────────┘                    ▼
                                       │                     ┌──────────────────┐
                                       │ offer accept        │ courier_assigned │
                                       └─────────────────────┴────────┬─────────┘
                                                                      ▼
                              ┌──────────────┐               ┌──────────────┐
                              │  delivered   │◄──────────────│  delivering  │
                              └──────────────┘  proof/confirm└──────┬───────┘
                                                                    ▲
                                                            ┌──────────────┐
                                                            │  picked_up   │
                                                            └──────────────┘
```

Canonical statuses: `draft → pending_payment → paid → accepted → preparing →
ready_for_pickup → courier_assigned → picked_up → delivering → delivered`,
terminal alternatives `cancelled`, `rejected`.

Transition rules enforced server-side:

| Transition | Actor | Guards |
|------------|-------|--------|
| `pending_payment → paid` | payment webhook only | signature valid, amount matches, idempotent on `providerRef` |
| `pending_payment → cancelled` | customer / system | payment not captured |
| `paid → accepted` | MANAGER (store owner) | store open |
| `paid|accepted → rejected` | MANAGER | triggers refund flow |
| `accepted → preparing → ready_for_pickup` | MANAGER | sequential |
| `ready_for_pickup → courier_assigned` | dispatch | courier accepted offer |
| `courier_assigned → picked_up → delivering → delivered` | COURIER (assigned only) | order's courier; delivered may require photo/PIN proof |
| `…→ cancelled` | customer (before `accepted`), support/admin | per-state cancellation policy, refund if paid |

Every transition writes an `AuditLog` row and emits `order.status_changed`
to the customer, the store, and (if assigned) the courier.

## 5. Payments

- `PaymentProvider` interface: `createIntent(order)`, `status(ref)`,
  `refund(ref, amountTiyn?)`, `verifyWebhook(headers, rawBody)`.
- `KaspiPaymentProvider` implements it against the Kaspi merchant API using
  `KASPI_MERCHANT_ID`/`KASPI_API_KEY`/`KASPI_BASE_URL`; a `MockPaymentProvider`
  is wired when credentials are absent (development).
- `POST /v1/payments/webhook/kaspi` is unauthenticated-by-JWT but
  **signature-verified** (`KASPI_WEBHOOK_SECRET`) and **idempotent** — unique
  constraint on `providerRef`; replays return `200` with no side effects.
- The order becomes `paid` **only** inside the webhook handler transaction:
  verify signature → locate payment by `providerRef` → check amount → mark
  payment `succeeded` → transition order → emit events. Client-side payment
  success screens are cosmetic; the webhook is authoritative.
- Refunds are initiated by support/admin and executed through the same
  provider interface.

## 6. Dispatch (courier matching)

When an order reaches `ready_for_pickup` the dispatch worker scores online
couriers within the store's delivery zone:

```
score = w1·(distance_to_store km) + w2·(active_deliveries) + w3·(idle_seconds⁻¹)
offer → lowest score first, sequential offers with 30 s accept window,
        fallback broadcast to zone if N offers expire
```

- **Distance** from courier's last reported location to the store.
- **Availability** — must be `online`, not suspended, order within zone.
- **Workload** — couriers already carrying orders are penalised.
- On accept: `courier.assigned` event; the courier app begins streaming
  `courier.location_updated`; customer tracking screen subscribes.

## 7. Realtime (WebSocket)

- Endpoint: `GET /v1/ws?token=<access-token>` (JWT at upgrade; 401 on
  invalid). The `ws` library is used server-side.
- Envelope: `{id, seq, event, payload, ts}` — `seq` is the global outbox
  sequence; `id` is a UUID.
- Channels are implicit by role and ownership: a user receives events for
  their own orders/chats; a courier for assigned orders; a manager for
  owned stores. No client-controlled channel subscription for sensitive
  topics.
- **Events:** `order.created`, `order.status_changed`, `courier.assigned`,
  `courier.location_updated`, `order.delivered`, `notification.created`,
  `chat.message_created`, `chat.message_read`, `chat.typing`, `call.*`.
- **Delivery path:** domain code writes `OutboxEvent` in the same DB
  transaction as the state change → dispatcher worker publishes to Redis
  pub/sub → each API node's WS gateway fans out to local sockets. This makes
  events survive WS node crashes and enables multi-node scaling.
- **Reconnect/resync:** client sends `{type:"resync", lastEventId}` (or
  `lastSeq`); server replays missed outbox events for that user, then live
  traffic. Cursor-based REST reads (`nextCursor`) fill anything older than
  the replay window.

## 8. Offline sync (app)

- Read-heavy screens cache the last successful response (Riverpod +
  persisted storage) and render stale data with an offline banner.
- Writes are queued: `sendChatMessage`, courier `location_updated` batches,
  and read receipts go into a local outbox; a connectivity listener flushes
  FIFO with idempotency keys (`clientMutationId`).
- Conflict policy: server always wins for order/payment state; chat messages
  are deduplicated by `clientMutationId`.
- On WS reconnect the app resyncs via `lastEventId` and refetches the active
  order.

## 9. Security architecture (summary)

Full detail in [SECURITY.md](SECURITY.md).

- OTP: 6-digit, SHA-256 hashed at rest, 5 min TTL, ≤5 attempts, per-phone and
  per-IP rate limits, progressive lockout.
- JWT: access 15 m, refresh 30 d, rotation with token families; refresh reuse
  revokes the entire family.
- RBAC matrix enforced by the `rbac` plugin on every route; ownership checks
  (`order.customerId == user.id`) in services to prevent IDOR.
- Media: private bucket; short-lived presigned GET/PUT URLs.
- Never logged: OTP codes, tokens, payment credentials, chat bodies, exact
  GPS coordinates.

## 10. Scaling notes

| Tier | Strategy |
|------|----------|
| API | Stateless pods behind L7 LB; horizontal autoscale on CPU/RPS. JWT means no server-side session affinity for REST. |
| WebSocket | Sticky sessions (or token re-auth on reconnect) + Redis pub/sub fanout so any node can serve any user. Connection registry is node-local. |
| Postgres | Primary + read replicas for reporting/search reads; PgBouncer transaction pooling; PITR via WAL archive. |
| Redis | Single primary in dev; managed HA Redis (or Sentinel) in prod. Separate logical DBs/keyspaces for cache vs OTP vs pub/sub is acceptable since pub/sub is ephemeral. |
| Search | pg_trgm is adequate to ~1M products; beyond that, introduce OpenSearch/Typesense behind the same `/v1/search` contract. |
| Media | S3 + CDN in front of presigned GETs; image resizing worker if needed. |
| Workers | Outbox dispatcher, dispatch matcher, push sender run as separate deployables scaled by queue lag. |

## 11. Failure modes

- **Webhook delay** — order stays `pending_payment`; customer sees "awaiting
  payment confirmation"; a poller reconciles stale intents via
  `provider.status(ref)` as a safety net.
- **Redis down** — API degrades: WS fanout stops (REST still works), OTP
  verification fails closed. `/ready` reports Redis dependency down.
- **S3 down** — media uploads fail; order flow unaffected.
- **WS node crash** — clients reconnect (exponential backoff), resync via
  `lastEventId`; outbox guarantees no lost events within the replay window.
