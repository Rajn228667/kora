# KORA — Privacy Policy

*Last updated: [DATE — set before publication]. Applies to the KORA mobile
app and api.kora.kz.*

> **Placeholders:** `[Company legal name]`, `[legal address]`,
> `[privacy@kora.kz]`, `[support phone]` — replace before store submission.
> This document must be reviewed by Kazakhstan counsel for compliance with
> the Law of the Republic of Kazakhstan "On Personal Data and Its
> Protection" (No. 94-V, 21.05.2013).

KORA ("we", "the Service") is a food and marketplace delivery platform
operating in Kazakhstan. This policy describes what personal data we
collect, why, how long we keep it, and your rights.

## 1. Data we collect

| Category | Data | Purpose | Legal basis |
|----------|------|---------|-------------|
| Account | Phone number (+7…), name, role | Registration via OTP, authentication, account identification | Contract |
| Orders | Order contents, delivery address, delivery notes, order history, ratings | Fulfilling and delivering orders, support, dispute resolution | Contract |
| Location — customers | Delivery coordinates you enter; approximate device location (with permission) | Showing nearby stores, delivery to your address | Contract / Consent |
| Location — couriers | Precise GPS during online status and active deliveries | Dispatching, customer tracking, delivery verification | Contract / Consent |
| Communications | Chat messages between customer↔store, customer↔courier, support tickets and attachments | Operating the service, safety, dispute resolution | Contract / Legitimate interest |
| Calls | Call metadata (parties, time, duration); content is not recorded unless disclosed in-app | Connecting parties, dispute evidence | Contract |
| Payments | Payment status, amounts in tiyn, provider transaction references. **We never see or store card numbers** — card data is processed by Kaspi | Processing payments, refunds, fraud prevention | Contract / Legal obligation |
| Device | Push tokens (FCM/APNs), device model, OS, app version | Delivering notifications, diagnostics | Legitimate interest |
| Usage | App events, crash logs, IP address, request logs | Reliability, security, abuse prevention | Legitimate interest |

## 2. What we never do

- Never log or store OTP codes in plaintext, authentication tokens, payment
  credentials, chat message bodies in application logs, or precise GPS in
  logs (logged location is reduced-precision).
- Never sell personal data.
- Never share courier/customer live location outside the parties of the
  active delivery.

## 3. Sharing

| Recipient | Data | Why |
|-----------|------|-----|
| Stores/managers | Customer name, order contents, delivery address, masked phone | Order fulfilment |
| Couriers | Customer first name, delivery address, masked phone, delivery notes | Delivery |
| Customers | Courier first name, masked phone, live location during delivery | Tracking |
| Kaspi | Order amount, reference | Payment processing |
| SMS provider | Phone number | OTP delivery |
| Push providers (FCM/APNs) | Device token, notification payload | Notifications |
| Maps provider (Yandex) | Coordinates for geocoding/routing | Maps & routing |
| Authorities | As required by Kazakhstan law | Legal obligation |

Phone numbers are masked between parties — in-app chat/calls replace direct
phone contact.

## 4. Retention

| Data | Retention |
|------|-----------|
| Account data | Until account deletion + 90 days (backups) |
| Orders & payment records | 5 years (tax/accounting obligations under KZ law) |
| Courier location history | 90 days rolling, then deleted/aggregated |
| Chat messages | 12 months after thread closure |
| Delivery proof photos | 12 months |
| Support tickets | 24 months |
| Logs | 90 days (aggregated thereafter) |
| Device tokens | Until uninstalled/logged out + 90 days |

## 5. Your rights

Subject to KZ law you may: access your data, correct inaccuracies,
**delete your account and data**, withdraw consent (which may limit
features, e.g. location), and lodge a complaint with the competent
authority.

- **In-app deletion:** Profile → Delete account. This starts deletion of
  personal data; order/payment records are anonymized and retained as
  required by law.
- Requests: `[privacy@kora.kz]` — we respond within the statutory period.
- Location can be revoked in OS settings; the courier role requires it
  while online.

## 6. Security

TLS in transit, encryption at rest, hashed OTPs and refresh tokens,
short-lived access tokens, RBAC, signed media URLs, audit logging. Details
in our internal security documentation.

## 7. Children

KORA is not directed at children under 18. Accounts are for adults placing
or fulfilling orders.

## 8. International transfers

Data is hosted in Kazakhstan or jurisdictions providing adequate
protection; transfers, if any, comply with KZ localization requirements.

## 9. Changes

Material changes are notified in-app before taking effect. Continued use
after notice constitutes acceptance where permitted by law.

## 10. Contact

- Controller: `[Company legal name]`, `[legal address]`, Kazakhstan
- Privacy: `[privacy@kora.kz]` · Support: `[support@kora.kz]` / `[phone]`
