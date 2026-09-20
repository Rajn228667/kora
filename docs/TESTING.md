# KORA — Testing

Test strategy, how to run each suite, and the E2E checklist used for release
sign-off.

## 1. Test pyramid

```
        ┌─────────────────────┐
        │   E2E (manual+auto) │   register → order → delivery, per release
        ├─────────────────────┤
        │  API integration    │   vitest + testcontainers/real dev services
        │  security tests     │   authz matrix, webhook forgery, IDOR
        ├─────────────────────┤
        │  widget tests       │   Flutter screens/components
        │  integration_test   │   app↔backend on staging
        ├─────────────────────┤
        │      unit tests     │   vitest (backend) · flutter test (app)
        └─────────────────────┘
```

## 2. How to run

### Backend (`backend/`)

```bash
npm install
npx prisma migrate dev        # tests use the dev DB or a test schema
npx vitest run                # all unit + integration tests
npx vitest run --coverage     # coverage report
npx tsc --noEmit              # typecheck (CI gate)
```

Conventions:

- Unit tests colocated: `*.test.ts` next to the module.
- Integration tests boot Fastify with `inject()` — no real HTTP port needed;
  external providers (Kaspi, SMS, S3) are mocked/stubbed via the provider
  interfaces.
- Redis-dependent tests use the dev Redis or an injected fakeredis.
- Webhook tests sign fixtures with `KASPI_WEBHOOK_SECRET` and assert
  idempotent replays.

### App (`app/`)

```bash
flutter pub get
flutter analyze               # static analysis (CI gate)
flutter test                  # unit + widget tests
flutter test --coverage
flutter test integration_test # device/emulator required
```

### CI

`.github/workflows/ci.yml` runs: backend (npm ci → prisma validate →
tsc → vitest), app (flutter pub get → analyze → test), security (gitleaks,
npm audit), and a docker-compose smoke check on every PR and push to `main`.

## 3. Coverage priorities

Backend unit coverage targets: money math (tiyn), order state machine
transitions, dispatch scoring, JWT rotation/reuse, OTP attempt/lockout
logic, promo validation, cursor pagination, signed-URL issuing.

## 4. Security test cases (must exist)

- OTP: >5 verify attempts → challenge dead; resend cooldown enforced;
  per-phone + per-IP rate limits return `429`.
- JWT: expired access → `401 TOKEN_EXPIRED`; refresh reuse → family revoked
  (`REFRESH_REUSE_DETECTED`); `logout-all` kills all sessions.
- RBAC/IDOR: CUSTOMER cannot read another user's order/address/chat (expect
  `404`); COURIER cannot transition a non-assigned order; MANAGER cannot
  touch a non-owned store; client-supplied `role` in self-update ignored.
- Webhook: bad signature → `400`; replayed valid event → `200` with no
  duplicate effects; amount mismatch → rejected.
- State machine: illegal transitions (e.g. `delivered` before `picked_up`)
  → `409 INVALID_STATE`; cancel after `accepted` → `409`.
- Rate limits on auth/checkout/chat endpoints.
- Signed URLs: expired → 403; wrong user → never issued.

## 5. E2E checklist — release sign-off

Run on **staging** with real SMS/Kaspi-sandbox. Each item must pass before
store submission.

### Auth & account

- [ ] Register with `+7` phone → OTP → lands on home as CUSTOMER
- [ ] Wrong OTP ×5 → lockout message; resend cooldown works
- [ ] Kill app → still logged in (refresh); revoke session on second device → first device re-auths
- [ ] Logout → tokens dead; account deletion flow completes

### Order happy path (register → order → delivery)

- [ ] Browse stores → open store → add items with modifiers → cart totals match server quote (tiyn exact)
- [ ] Apply valid promo → discount reflected; expired promo rejected
- [ ] Checkout with saved address → Kaspi (sandbox) pay → order becomes `paid` via webhook
- [ ] Manager accepts → sets prep time → `preparing` → `ready_for_pickup`
- [ ] Courier receives offer → accepts → `courier.assigned` visible to customer
- [ ] Courier `picked_up` → live `courier.location_updated` on customer tracking map
- [ ] `delivered` with proof → customer sees completed order; ratings work
- [ ] Receipt/order history shows immutable snapshot (edit product price afterwards → order unchanged)

### Payment edge cases

- [ ] Abandon at payment → order stays `pending_payment` → auto-cancel after timeout
- [ ] Failed payment → retry works; webhook replay does not double-mark `paid`
- [ ] Manager rejects paid order → refund initiated, order `rejected`

### Chat / calls / notifications

- [ ] Customer↔courier thread opens on assignment; messages deliver via WS; read receipts sync
- [ ] Push notification arrives on `order.status_changed` (foreground + background)
- [ ] Call: initiate → accept → end; events visible on both sides

### Offline / resilience

- [ ] Airplane mode → cached catalog renders with offline banner
- [ ] Queue a chat message offline → sends on reconnect (dedup by `clientMutationId`)
- [ ] Kill WS (toggle network) → reconnect + `resync` with `lastEventId`; no duplicated/missed status events
- [ ] Access token expiry mid-session → silent refresh; WS `auth_required` → re-auth succeeds

### RBAC spot checks

- [ ] Manager sees only own store's orders
- [ ] Courier sees only assigned deliveries; cannot open another courier's order
- [ ] Admin can force-status an order (audit log entry written)

## 6. Performance smoke

- [ ] `/v1/search` p95 < 300 ms at seeded catalog
- [ ] Checkout → `paid` webhook path p95 < 3 s end-to-end
- [ ] WS connect + first event < 1 s; 1k concurrent sockets per node in staging load test
