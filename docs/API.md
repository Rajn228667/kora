# KORA — API Reference

Base URL: `/v1` (e.g. `http://localhost:3000/v1`). Interactive OpenAPI:
`GET /docs` (Swagger UI); machine spec: `GET /docs/json`.

## Conventions

- **Auth:** `Authorization: Bearer <access-token>` unless marked `public`.
  Roles: `CUSTOMER`, `MANAGER`, `COURIER`, `ADMIN`.
- **IDs:** UUIDv4/v7. **Timestamps:** ISO-8601 UTC (`2026-09-20T10:00:00Z`).
- **Money:** integer **tiyn** (1 KZT = 100 tiyn). Field names end in `Tiyn`
  (e.g. `totalTiyn`, `deliveryFeeTiyn`). Never floats.
- **Geo:** `{lat, lng}` decimal degrees; addresses carry a display `address`
  string plus `lat/lng`.
- **Phone:** E.164 Kazakhstan format `+7XXXXXXXXXX`.

### Success shapes

```jsonc
// single resource
{ "id": "uuid", "...": "..." }
// list — cursor pagination
{ "items": [ /* ... */ ], "nextCursor": "opaque-string-or-null" }
```

List params: `?limit=1..100` (default 20), `?cursor=<nextCursor>`, plus
group-specific filters noted below.

### Error shape — always

```jsonc
{ "error": { "code": "STRING_CODE", "message": "human readable", "details": { } } }
```

| HTTP | `code` | Meaning |
|------|--------|---------|
| 400 | `VALIDATION_ERROR` | Body/query failed schema; `details` lists fields |
| 401 | `UNAUTHENTICATED` / `TOKEN_EXPIRED` / `TOKEN_INVALID` | Missing/expired/bad JWT |
| 403 | `FORBIDDEN` / `ROLE_REQUIRED` / `NOT_OWNER` | Authenticated but not allowed |
| 404 | `NOT_FOUND` | Resource absent or not visible to caller |
| 409 | `CONFLICT` / `INVALID_STATE` / `ALREADY_EXISTS` | State machine violation, duplicate |
| 410 | `EXPIRED` | OTP/invite/signed URL expired |
| 429 | `RATE_LIMITED` | `details.retryAfterSec` provided |
| 500 | `INTERNAL` | Unhandled; logged with request id |
| 503 | `DEPENDENCY_UNAVAILABLE` | DB/Redis/S3 down (see `/ready`) |

---

## System

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | public | Liveness → `{status:"ok"}` |
| GET | `/ready` | public | Readiness → `{status,checks:{db,redis,s3}}`; 503 if any dependency down |
| GET | `/docs` | public | Swagger UI (disabled in production unless enabled by env) |

## `/auth`

Phone OTP → JWT. All bodies JSON.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/v1/auth/otp/request` | public | Request OTP. Body `{phone:"+7…"}`. → `{challengeId, ttlSec, resendAfterSec}` (dev echoes `devCode` when `SMS_PROVIDER=dev`). 429 on rate limit. |
| POST | `/v1/auth/otp/verify` | public | Verify code. Body `{phone, code:"6 digits"}`. → `{accessToken, refreshToken, expiresInSec, user}` or `401 OTP_INVALID`, `410 EXPIRED`, `429 TOO_MANY_ATTEMPTS` |
| POST | `/v1/auth/refresh` | public | Rotate refresh token. Body `{refreshToken}`. → new `{accessToken, refreshToken, expiresInSec}`. `401 TOKEN_INVALID` / `REFRESH_REUSE_DETECTED` (revokes family) |
| POST | `/v1/auth/logout` | user | Revoke current refresh token. Body `{refreshToken}` → `204` |
| POST | `/v1/auth/logout-all` | user | Revoke all sessions → `204` |
| GET | `/v1/auth/sessions` | user | Active sessions `{items:[{id,device,createdAt,lastSeenAt,current}]}` |
| DELETE | `/v1/auth/sessions/{id}` | user | Revoke one session → `204` |

## `/users`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/users/me` | user | Own profile `{id,phone,role,name,avatarUrl,addresses,createdAt}` |
| PATCH | `/v1/users/me` | user | Update `{name?, avatarUrl?}` → profile |
| DELETE | `/v1/users/me` | user | Delete account (soft-delete + anonymize per privacy policy) → `204` |
| GET | `/v1/users/me/addresses` | user | Saved addresses `{items:[{id,label,address,lat,lng,isDefault}]}` |
| POST | `/v1/users/me/addresses` | user | Create `{label,address,lat,lng}` → address |
| PATCH | `/v1/users/me/addresses/{id}` | user | Update → address |
| DELETE | `/v1/users/me/addresses/{id}` | user | Delete → `204` |
| POST | `/v1/users/me/devices` | user | Register push token `{platform:"android"|"ios", token}` → `204` |
| DELETE | `/v1/users/me/devices/{token}` | user | Unregister → `204` |

## `/stores`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/stores` | public | List open stores. Params `?lat&lng&categoryId&q&cursor` → `{items:[{id,name,logoUrl,rating,deliveryEtaMin,deliveryFeeTiyn,minOrderTiyn,isOpen,distanceM}],nextCursor}` |
| GET | `/v1/stores/{id}` | public | Store detail incl. `categories`, `address`, `hours`, `deliveryZone` |
| POST | `/v1/stores` | ADMIN | Create store `{name,address,lat,lng,phone,hours,deliveryZoneGeoJson}` → store |
| PATCH | `/v1/stores/{id}` | MANAGER(own)/ADMIN | Update fields, `isOpen`, `status` |
| GET | `/v1/stores/{id}/orders` | MANAGER(own)/ADMIN | Store order list, `?status=` filter |

## `/categories`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/stores/{storeId}/categories` | public | `{items:[{id,name,sortOrder,productCount}]}` |
| POST | `/v1/stores/{storeId}/categories` | MANAGER(own)/ADMIN | `{name,sortOrder?}` → category |
| PATCH | `/v1/categories/{id}` | MANAGER(own)/ADMIN | Update |
| DELETE | `/v1/categories/{id}` | MANAGER(own)/ADMIN | Delete (409 if products attached) |

## `/products`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/stores/{storeId}/products` | public | `?categoryId&available&cursor` → `{items:[{id,name,description,priceTiyn,imageUrl,categoryId,modifiers,isAvailable}]}` |
| GET | `/v1/products/{id}` | public | Product detail incl. modifier groups |
| POST | `/v1/stores/{storeId}/products` | MANAGER(own)/ADMIN | `{name,description,priceTiyn,categoryId,modifiers?}` → product |
| PATCH | `/v1/products/{id}` | MANAGER(own)/ADMIN | Update incl. `isAvailable` |
| DELETE | `/v1/products/{id}` | MANAGER(own)/ADMIN | Soft delete |
| POST | `/v1/products/{id}/image` | MANAGER(own)/ADMIN | Get presigned upload URL `{uploadUrl, expiresInSec, key}`; then `PUT` binary to `uploadUrl` |

## `/search`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/search` | public | `?q=&lat&lng&type=store|product|all&cursor` → `{items:[{type:"store"|"product", ...}],nextCursor}` (pg_trgm + unaccent) |
| GET | `/v1/search/suggest` | public | `?q=` → `{items:["query strings"]}` |

## `/cart`

Server-side cart. Prices revalidated at read/checkout — client must display
server-returned totals only.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/cart` | CUSTOMER | `{items:[{id,productId,name,priceTiyn,qty,modifiers,subtotalTiyn}],storeId,subtotalTiyn}` |
| POST | `/v1/cart/items` | CUSTOMER | `{productId,qty,modifiers:[{optionId,qty}],clientMutationId}` → cart. 409 `DIFFERENT_STORE` if cart belongs to another store (pass `replaceCart:true` to reset) |
| PATCH | `/v1/cart/items/{id}` | CUSTOMER | `{qty}` (0 removes) → cart |
| DELETE | `/v1/cart/items/{id}` | CUSTOMER | → cart |
| DELETE | `/v1/cart` | CUSTOMER | Clear → `204` |

## `/checkout`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/v1/checkout/quote` | CUSTOMER | `{addressId|address:{address,lat,lng}, promoCode?}` → `{subtotalTiyn,deliveryFeeTiyn,serviceFeeTiyn,discountTiyn,totalTiyn,etaMin,address}` — prices locked for `quoteTtlSec` |
| POST | `/v1/checkout` | CUSTOMER | `{addressId|address, promoCode?, paymentMethod:"kaspi", note?, idempotencyKey}` → `{order, payment:{intentId,deeplinkUrl,status}}`. Idempotent on `idempotencyKey`. 409 `CART_EMPTY`/`PRICE_CHANGED`/`MIN_ORDER_NOT_MET`/`OUT_OF_ZONE`/`STORE_CLOSED` |

## `/orders`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/orders` | user | Caller-scoped list. `?status&cursor`. CUSTOMER→own; COURIER→assigned; MANAGER→store |
| GET | `/v1/orders/{id}` | party | Full order: `items` snapshot, `deliveryAddress` snapshot, `totals`, `statusHistory`, `payment.status`, `courier{id,name,phoneMasked}` |
| POST | `/v1/orders/{id}/cancel` | CUSTOMER(own)/ADMIN | `{reason}` → order. Only before `accepted`; 409 `INVALID_STATE` after. Refund auto-initiated if paid |
| POST | `/v1/orders/{id}/rate` | CUSTOMER(own) | `{storeRating:1..5,courierRating?,comment?}` → `204` |
| POST | `/v1/orders/{id}/reorder` | CUSTOMER(own) | Rebuild cart from order snapshot → cart |

## `/payments`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/payments/{id}` | party | `{id,orderId,provider,status:pending|succeeded|failed|refunded,amountTiyn,providerRef}` |
| POST | `/v1/payments/{id}/refresh` | CUSTOMER(own) | Poll provider status → payment (reconcile fallback for delayed webhooks) |
| POST | `/v1/payments/webhook/kaspi` | **signature** | Kaspi callback. Raw body + signature header verified with `KASPI_WEBHOOK_SECRET`; idempotent on `providerRef`. Always `200` on replay; `400` on bad signature |
| POST | `/v1/payments/{id}/refund` | ADMIN | `{amountTiyn?,reason}` → payment |

## `/couriers`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/couriers/me` | COURIER | Profile `{id,name,rating,status:offline|online|on_delivery,vehicle}` |
| POST | `/v1/couriers/me/status` | COURIER | `{status:"online"|"offline"}` → profile |
| POST | `/v1/couriers/me/location` | COURIER | `{lat,lng,heading?,speed?,recordedAt}` — rate-limited, batched by app → `204` |
| GET | `/v1/couriers/me/offers` | COURIER | Pending dispatch offers `{items:[{orderId,store,pickup,dropoff,earningsTiyn,expiresAt}]}` |
| POST | `/v1/couriers/me/offers/{orderId}/accept` | COURIER | → `{order}`; 409 `OFFER_EXPIRED` |
| POST | `/v1/couriers/me/offers/{orderId}/decline` | COURIER | → `204` |
| POST | `/v1/orders/{id}/picked-up` | COURIER(assigned) | `{photoProofUrl?}` → order |
| POST | `/v1/orders/{id}/delivered` | COURIER(assigned) | `{photoProofUrl?,pin?}` → order |
| GET | `/v1/couriers/me/earnings` | COURIER | `?from&to` → `{items:[{date,deliveries,earningsTiyn,tipsTiyn}]}` |

## `/tracking`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/tracking/{orderId}` | order party | `{orderId,status,courier:{lat,lng,heading}?,etaMin,route?}` — snapshot; live updates over WS `courier.location_updated` |

## `/chat`

Threads: `customer_store`, `customer_courier` (auto-created per order),
`support`.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/chat/threads` | user | `{items:[{id,type,peer:{name,avatarUrl},lastMessage,unreadCount}],nextCursor}` |
| GET | `/v1/chat/threads/{id}/messages` | participant | `?cursor` → `{items:[{id,senderId,type:"text"|"image",body?,mediaUrl?,clientMutationId,createdAt,readAt}],nextCursor}` |
| POST | `/v1/chat/threads/{id}/messages` | participant | `{type,body?|mediaKey?,clientMutationId}` → message; emits `chat.message_created` |
| POST | `/v1/chat/threads/{id}/read` | participant | `{upToMessageId}` → `204`; emits `chat.message_read` |
| POST | `/v1/chat/media-upload` | participant | Presigned PUT for chat image `{uploadUrl,key}` |

## `/calls`

Signalling metadata for in-app calls (media over provider SDK).

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/v1/calls` | user | `{threadId|orderId, type:"audio"}` → `{callId,sessionToken,peer}`; emits `call.incoming` |
| POST | `/v1/calls/{id}/accept` | callee | → `{callId,sessionToken}`; emits `call.accepted` |
| POST | `/v1/calls/{id}/reject` | callee | → `204`; emits `call.rejected` |
| POST | `/v1/calls/{id}/end` | party | → `204`; emits `call.ended` |

## `/notifications`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/notifications` | user | `{items:[{id,type,title,body,data,createdAt,readAt}],nextCursor}` |
| POST | `/v1/notifications/read` | user | `{ids:[]}` or `{all:true}` → `204` |
| GET | `/v1/notifications/preferences` | user | `{orderUpdates,chat,promotions:bool}` |
| PUT | `/v1/notifications/preferences` | user | Update → preferences |

## `/support`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/v1/support/tickets` | user | `{subject,category:"order"|"payment"|"courier"|"other",orderId?,body}` → ticket `{id,status:"open"}` |
| GET | `/v1/support/tickets` | user | Own tickets `{items,nextCursor}` |
| GET | `/v1/support/tickets/{id}` | owner/ADMIN | Ticket + message thread |
| POST | `/v1/support/tickets/{id}/messages` | owner/ADMIN | `{body}` → message |
| POST | `/v1/support/tickets/{id}/close` | owner/ADMIN | → ticket |

## `/promotions`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/v1/promotions/validate` | CUSTOMER | `{code,storeId}` → `{code,discountType:"percent"|"fixed",value,discountTiyn,eligible}` / 410 `EXPIRED` / 404 |
| GET | `/v1/promotions` | ADMIN | `{items:[{id,code,type,value,minOrderTiyn,usageLimit,usedCount,startsAt,endsAt,active}]}` |
| POST | `/v1/promotions` | ADMIN | Create promo |
| PATCH | `/v1/promotions/{id}` | ADMIN | Update/`active` toggle |

## `/manager` (MANAGER, own store only)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/manager/orders?status=` | Incoming/active orders for owned store |
| POST | `/v1/manager/orders/{id}/accept` | `{prepTimeMin}` → order `accepted` |
| POST | `/v1/manager/orders/{id}/reject` | `{reason}` → `rejected` + refund |
| POST | `/v1/manager/orders/{id}/ready` | → `ready_for_pickup` |
| PATCH | `/v1/manager/store` | Update own store, `isOpen` toggle |
| GET | `/v1/manager/stats?from&to` | `{ordersCount,revenueTiyn,avgPrepTimeMin,avgRating}` |

## `/admin` (ADMIN only)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/admin/users?role&q&cursor` | User list |
| PATCH | `/v1/admin/users/{id}` | Update role (`{role}`), `isBlocked` |
| GET | `/v1/admin/stores?status=` | All stores incl. pending |
| POST | `/v1/admin/stores/{id}/approve` / `suspend` | Store moderation |
| GET | `/v1/admin/couriers?status=` | Courier list; `POST /couriers/{id}/approve|suspend` |
| GET | `/v1/admin/orders?status&storeId&cursor` | All orders |
| POST | `/v1/admin/orders/{id}/force-status` | `{status,reason}` — audited override |
| GET | `/v1/admin/support/tickets?status=` | Support queue; assign/reply |
| GET | `/v1/admin/audit-log?actorId&entity&cursor` | Audit entries `{items:[{id,actorId,action,entity,entityId,before,after,createdAt}]}` |
| GET | `/v1/admin/stats/overview` | `{gmvTiyn,orders,activeCouriers,activeStores}` |

---

## WebSocket protocol

**Endpoint:** `GET /v1/ws?token=<access-token>` → HTTP 101 upgrade.
Invalid/expired token → `401` close. On token expiry mid-session the server
sends `{type:"auth_required"}` and waits ≤30 s for a `{type:"auth",token}`
frame before closing.

### Envelope (server → client)

```jsonc
{
  "id": "uuid",                    // event id
  "seq": 1042381,                  // global monotonically increasing sequence
  "event": "order.status_changed", // event name
  "payload": { /* event-specific */ },
  "ts": "2026-09-20T10:00:00Z"
}
```

### Client → server frames

```jsonc
{ "type": "auth",   "token": "<new-access-token>" }
{ "type": "resync", "lastEventId": "uuid" }        // or {"lastSeq": 1042000}
{ "type": "ping" }                                 // → {"type":"pong"}
{ "type": "chat.typing", "threadId": "uuid" }      // only client-originated event
```

### Events

| Event | Payload | Audience |
|-------|---------|----------|
| `order.created` | `{order}` | store manager, admin |
| `order.status_changed` | `{orderId,status,prevStatus,ts}` | customer, store, assigned courier |
| `courier.assigned` | `{orderId,courier:{id,name,phoneMasked}}` | customer, store |
| `courier.location_updated` | `{orderId,courierId,lat,lng,heading,ts}` | customer tracking that order |
| `order.delivered` | `{orderId,deliveredAt,proofUrl?}` | customer, store |
| `notification.created` | `{notification}` | target user |
| `chat.message_created` | `{threadId,message}` | thread participants |
| `chat.message_read` | `{threadId,readerId,upToMessageId}` | thread participants |
| `chat.typing` | `{threadId,userId}` | thread participants (ephemeral, no seq) |
| `call.incoming` / `call.accepted` / `call.rejected` / `call.ended` | `{callId,...}` | call parties |

### Reconnect & resync

1. Reconnect with exponential backoff (min 1 s, max 30 s, jitter).
2. After upgrade send `{type:"resync", lastEventId:<last received>}` — the
   server replays missed events for this user (up to the outbox retention
   window), then resumes live traffic with correct `seq` ordering.
3. If the gap is beyond the replay window, server replies
   `{type:"resync_required"}` — the client must refetch affected resources
   via REST (active order, threads) using cursor pagination.
4. Ephemeral events (`chat.typing`) are never replayed.
