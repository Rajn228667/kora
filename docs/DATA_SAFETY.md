# KORA — Data Safety Declarations

Source of truth for the **Google Play Data Safety** form and the **Apple
App Privacy** nutrition labels. Keep this file and the consoles in sync —
review before every release.

## 1. Google Play — Data Safety

| Data type | Collected | Shared | Purpose | Required/Optional | Encrypted in transit | User can delete |
|-----------|-----------|--------|---------|-------------------|----------------------|-----------------|
| **Personal info — Phone number** | Yes | Yes (stores/couriers see masked; SMS provider for OTP) | Account management, app functionality | Required | Yes | Yes |
| **Personal info — Name** | Yes | Yes (order parties see first name) | App functionality, delivery | Required | Yes | Yes |
| **Location — Precise (courier)** | Yes (courier role, while online/on delivery) | Yes (active order's customer) | App functionality (dispatch, tracking) | Required for couriers | Yes | No (retained 90 d) |
| **Location — Precise/Approx (customer)** | Yes (delivery address; device location with permission) | Yes (courier/store for fulfilment; Yandex for geocoding) | App functionality | Required for delivery | Yes | Yes |
| **Financial info — Purchase history** | Yes (orders, amounts in tiyn, payment status) | Yes (Kaspi processes payment) | App functionality, analytics | Required | Yes | No (legal retention 5 y) |
| **Financial info — Payment card** | **No** — processed entirely by Kaspi | — | — | — | — | — |
| **Messages — In-app chat** | Yes | Yes (thread participants) | App functionality, support | Optional (feature use) | Yes | On request (12 mo retention) |
| **Photos & videos** | Yes (chat attachments, avatars, delivery proof) | Yes (thread/order parties) | App functionality | Optional | Yes | Yes (proofs: 12 mo) |
| **Audio — voice calls** | Metadata only; content not stored | Call parties | App functionality | Optional | Yes | Metadata retained per policy |
| **App activity — in-app actions** | Yes (order funnel, feature usage) | No | Analytics, app functionality | Required | Yes | Yes |
| **App info & performance — crash logs** | Yes | No (crash vendor processes) | Analytics | Required | Yes | No |
| **Device or other IDs — push token, device id** | Yes | Yes (FCM/APNs) | App functionality (notifications) | Required for push | Yes | Yes |

- **Data shared with third parties:** Kaspi (payments), SMS provider (OTP),
  Yandex (maps), FCM/APNs (push) — declared as service providers.
- **Security practices:** encrypted in transit; data deletion available in-app
  (Profile → Delete account); committed to Play families policy n/a.
- **Optional vs required:** account/orders/location-for-delivery are required;
  chat media, camera attachments, notifications are optional features.

## 2. Apple — App Privacy (nutrition labels)

| Data type | Linked to user | Used to track | Purpose | Detail |
|-----------|----------------|---------------|---------|--------|
| Contact Info — Phone Number | Yes | **No** | App functionality | Registration/auth |
| Contact Info — Name | Yes | No | App functionality | Orders, delivery |
| Location — Precise Location | Yes | No | App functionality | Customer: delivery; Courier: live tracking while delivering |
| Purchases — Purchase History | Yes | No | App functionality | Order history |
| User Content — Messages/Photos | Yes | No | App functionality | Chat, delivery proof |
| Identifiers — User ID, Device ID | Yes | No | App functionality, analytics | Account, push tokens |
| Diagnostics — Crash Data | Yes (device-level) | No | App functionality | Crash reporting |
| Usage Data — Product Interaction | Yes | No | Analytics | Feature usage |

**Tracking:** KORA does **not** track users across apps/websites and does not
use data for advertising attribution → **no App Tracking Transparency prompt
is required** (verify per release if analytics SDKs change).

**Not collected:** health, browsing history, contacts, search history outside
app, biometric data, government IDs (unless courier onboarding requires —
declare then).

## 3. Consistency rules

- If a feature adds a new data type, update this file **and** both consoles
  in the same release.
- Backend log policy (SECURITY.md §7) must stay consistent with what is
  declared here — e.g., we declare chat as collected, but we still never
  write bodies to logs.
- Retention numbers above must match [PRIVACY_POLICY.md](PRIVACY_POLICY.md)
  §4 — they do; update both together.
