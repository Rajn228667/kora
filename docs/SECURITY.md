# KORA — Security

Threat model, authentication/authorization design, and security controls.
This document is the security contract: implementation must match it, and
reviewers must check code against it.

## 1. Authentication

### Phone OTP login

- Identifier: phone in E.164 `+7XXXXXXXXXX`.
- Flow: `POST /v1/auth/otp/request` → SMS with 6-digit code →
  `POST /v1/auth/otp/verify` → JWT pair.

OTP protections:

| Control | Value |
|---------|-------|
| Code | 6 digits, CSPRNG |
| Storage | SHA-256 hash in Redis (`otp:{phone}`), never plaintext, never logged |
| TTL | 5 minutes |
| Attempts | ≤5 per challenge, then challenge invalidated |
| Resend | ≥60 s cooldown, ≤5 requests/hour per phone |
| Rate limit | `/otp/request`: 10/h per phone AND per IP; `/otp/verify`: 10/h per IP |
| Lockout | 15 min after repeated failures; escalating for abusive numbers |
| Dev bypass | `OTP_DEV_CODE` honoured **only** when `APP_ENV=development` and `SMS_PROVIDER=dev` |

### JWT model

- **Access token:** 15 min (`JWT_ACCESS_TTL`), HS256 with `JWT_SECRET`
  (≥32 chars), claims: `sub`, `role`, `iat`, `exp`, `jti`.
- **Refresh token:** 30 d (`JWT_REFRESH_TTL`), opaque random 256-bit, stored
  as SHA-256 hash with a `familyId`, `device` metadata and `revokedAt`.
- **Rotation:** every `/v1/auth/refresh` issues a new pair and marks the
  presented refresh token consumed.
- **Reuse detection:** presenting an already-consumed refresh token means
  theft → the entire token family is revoked (`REFRESH_REUSE_DETECTED`),
  all sessions of that family die, and a security audit event is written.
- `logout` revokes one token; `logout-all` revokes the family.
- Passwords do not exist; there is nothing to breach on that axis.

## 2. Authorization (RBAC)

Roles: `CUSTOMER`, `MANAGER`, `COURIER`, `ADMIN`. Enforcement is **always
server-side**: a Fastify `rbac` guard checks role, and services additionally
check ownership (tenant scoping) on every read/write.

### RBAC matrix (role × resource)

| Resource | CUSTOMER | MANAGER | COURIER | ADMIN |
|----------|----------|---------|---------|-------|
| Own profile/addresses | RW | RW | RW | RW |
| Other users' profiles | — | — | — | RW |
| Store catalogue (read) | R | R | R | R |
| Own store + menu | — | RW | — | RW |
| Other stores | R | — | — | RW |
| Own cart/checkout | RW | — | — | — |
| Own orders | R (+cancel window, rate) | — | — | RW + force-status |
| Store orders | — | RW (transitions) | — | RW |
| Assigned deliveries | R (tracking) | R | RW (status, location) | R |
| Payment intents | create own | — | — | R + refund |
| Chat threads | own | own store threads | own delivery threads | all |
| Support tickets | own RW | own RW | own RW | all RW |
| Promotions | validate | — | — | RW |
| Audit log | — | — | — | R |
| RBAC changes | — | — | — | RW |

`-` = denied at guard level. Ownership rules (e.g. `order.customerId ===
user.id`, `store.managerId === user.id`, `order.courierId === user.id`) are
checked in the service layer — IDOR by ID guessing must return `404`, not
`403`, to avoid leaking existence.

## 3. Input validation & injection

- Every route declares a JSON Schema (Fastify/TypeBox); unknown fields are
  stripped, `additionalProperties:false` on write bodies.
- Prisma parameterised queries everywhere — no raw SQL with interpolation;
  any `$queryRaw` must use tagged templates and pass review.
- XSS: API returns JSON only; the app escapes nothing because Flutter renders
  text, not HTML — but support/admin web surfaces (if any) must sanitize.
- Mass assignment: DTOs are allow-lists; `role`, `id`, `status` are never
  accepted from client bodies except on dedicated admin endpoints.
- File uploads: only via presigned S3 PUT with `Content-Type` allowlist
  (jpeg/png/webp), max 10 MB, server-side content sniffing on read path via
  CDN/S3 metadata, randomized object keys.

## 4. Transport & headers

- TLS everywhere outside localhost (`https`/`wss`); HSTS on the API domain.
- Security headers (via `@fastify/helmet` or proxy): `X-Content-Type-Options:
  nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`,
  restrictive `Content-Security-Policy` on `/docs`.
- CORS: allowlist from `CORS_ORIGINS`; credentials not allowed; dev defaults
  to same-origin only.
- Request body limit: 1 MB JSON (except media upload URLs which are direct
  to S3).
- Global rate limit + stricter per-route limits on auth, OTP, webhook,
  location ingest.

## 5. Media & storage

- Bucket `kora-media` is **private**; reads go through short-lived (≤15 min)
  presigned GET URLs issued to authorized users only.
- Upload via presigned PUT; keys `media/{uuid}` / `chat/{threadId}/{uuid}` /
  `proofs/{orderId}/{uuid}`.
- Delivery-proof photos readable only by order parties + admin/support.

## 6. Secrets management

- Secrets only via env vars / secret manager (never in repo, never in
  client). `.env*` gitignored; `.env.example` holds placeholders only.
- `JWT_SECRET` ≥32 chars, unique per environment; rotating it invalidates all
  access tokens (refresh tokens unaffected — acceptable).
- `KASPI_*`, `SMS_API_KEY`, `S3_*`, `APNS_*` stored in the deployment secret
  store (k8s Secrets / cloud SM); access audited.
- CI runs **gitleaks** on every PR to catch committed secrets.

## 7. Logging policy

Structured JSON logs with `requestId`. **Never logged:**

- OTP codes (plaintext or hash)
- JWT access/refresh tokens, `Authorization` headers
- Kaspi credentials, webhook secrets, card/payment details
- Chat message bodies (log `messageId`, `threadId`, `type` only)
- Exact GPS coordinates — log geohash precision ≤6 (~600 m) or cell only
- Full phone numbers in INFO logs — mask as `+7••••••123`

## 8. Audit log

Append-only `AuditLog` for: order status transitions, refunds, promo
creation/redemption anomalies, role changes, store/courier approve-suspend,
admin force-status, `logout-all`, refresh-reuse revocations, support ticket
access by admins. Fields: `actorId, action, entity, entityId, before, after,
ip, requestId, createdAt`. Retention ≥1 year.

## 9. Threat notes & mitigations

| Threat | Mitigation |
|--------|------------|
| IDOR (order/user/chat access by id) | Ownership checks in service layer; `404` on foreign resources; UUID ids; API tests assert cross-user 404s |
| Role escalation | `role` mutable only via `/admin/users/{id}`; server ignores `role` in self-update DTOs; admin routes guarded |
| Webhook forgery | `KASPI_WEBHOOK_SECRET` signature verification on raw body; `providerRef` idempotency; amount cross-check before `paid`; source IP allowlist optional |
| Payment replay | Unique constraint `payments.providerRef`; webhook handler idempotent — replays return 200 with no side effects |
| OTP brute force | hash+TTL+attempt cap+per-phone/IP limits+lockout (§1) |
| Token theft / refresh replay | Rotation + family reuse detection (§1); short access TTL |
| Location leakage | Courier location emitted only to the active order's customer; REST tracking gated by order party; masked phone; coarse logging |
| Chat privacy | Threads restricted to participants; bodies never logged; media via signed URLs |
| SQLi | Prisma + schemas (§3) |
| Rate abuse / scraping | Global + route limits; cursor pagination; no email/phone enumeration — OTP responses uniform regardless of account existence |
| SSRF via URLs in payloads | No server-side fetch of user-supplied URLs; webhook URLs fixed |
| WebSocket hijack | JWT required at upgrade; re-auth on expiry; channels implicit server-side, no client-specified topic subscription |

## 10. Mobile security

- **Secure storage:** refresh token + session keys in
  `flutter_secure_storage` (Keychain on iOS, EncryptedSharedPreferences/
  Keystore on Android). Access tokens may live in memory only.
- **TLS:** HTTPS/WSS only in staging/prod builds; `APP_ENV=production`
  refuses `http://`/`ws://` endpoints.
- **Certificate pinning:** planned for production via `dio`
  `CertificatePinningInterceptor` (pins published in release pipeline; keep
  a backup pin for rotation).
- **Biometrics:** optional app-lock is a *local-only* convenience gate; it
  never replaces server auth and never creates sessions.
- **No secrets in app:** Kaspi/SMS keys never ship in the binary; only
  public identifiers (S3 bucket name, maps key restricted by package/app
  signature).
- Root/jailbreak detection: nice-to-have warning, not a hard gate.
