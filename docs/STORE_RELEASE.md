# KORA — Store Release Checklist

Google Play and Apple App Store release runbook. Complete every item before
submission; checkboxes are designed to be copied into a release ticket.

## 1. Versioning & build

- [ ] `versionName` follows semver (`1.2.0`); `versionCode`/`CFBundleVersion`
      monotonically increasing (use CI build number — never reuse).
- [ ] Release notes drafted (ru/kk/en as applicable).
- [ ] `flutter build appbundle --release` produces signed `.aab` (Play requires AAB).
- [ ] `flutter build apk --release` for internal/direct distribution QA.
- [ ] iOS: `flutter build ipa --release` via Xcode archive on macOS runner.
- [ ] Build flags set: `--dart-define API_URL=https://api.kora.kz
      --dart-define WS_URL=wss://api.kora.kz --dart-define APP_ENV=production`.
- [ ] **R8/ProGuard:** enabled (`minifyEnabled`, `shrinkResources`); rules keep
      Flutter/plugin entry points and any serialized models; mapping file
      uploaded to crash reporting.
- [ ] iOS symbols (dSYM) uploaded to crash reporting.

## 2. Signing

### Android

- [ ] Release keystore generated once (`keytool -genkey -v -keystore
      kora-release.keystore ...`), stored in the team secret vault —
      **never in git** (`*.keystore`, `key.properties` gitignored).
- [ ] **Play App Signing enrolled** — Google holds the app-signing key; our
      keystore is the *upload* key (recoverable if lost).
- [ ] `android/key.properties` provided via CI secrets (storeFile, storePassword,
      keyAlias, keyPassword).
- [ ] SHA-256 cert fingerprints registered with Yandex Maps / Kaspi console
      if they bind keys to app signatures.

### iOS

- [ ] Distribution certificate + App Store provisioning profile for
      `kz.kora.kora` (`APNS_BUNDLE_ID`) in the Apple Developer account.
- [ ] Xcode "Automatically manage signing" or match/fastlane; certs stored
      in secret vault, never committed.
- [ ] APNs key (`.p8`) configured — same key used for `APNS_KEY_ID` backend env.
- [ ] Capabilities enabled: Push Notifications, Background Modes
      (location — courier build only, VoIP if calls), associated domains if
      using universal links.

## 3. Permissions justification

Declare only what is used; provide in-app usage descriptions
(`NSUsageDescription` strings, Android runtime prompts) in ru/kk/en.

| Permission | Who | Purpose | Justification text |
|------------|-----|---------|--------------------|
| Location (while-in-use) | Customer | delivery address, nearby stores | "To show stores near you and place your delivery address" |
| Location (always / background) | **Courier role only** | live tracking during active delivery | "To share your position with the customer while you deliver" — gated behind courier role; Google requires background-location declaration video |
| Microphone | calls feature | in-app customer↔courier calls | "To make voice calls to the courier/customer" |
| Camera | chat photos, delivery proof, avatar | photo capture | "To send photos in chat and attach delivery proof" |
| Photos/Gallery | chat, avatar | attach existing images | "To attach photos from your gallery" |
| Notifications | all | order status, chat | "To notify you about order status and messages" (Android 13+ `POST_NOTIFICATIONS`) |
| Bluetooth/network | — | none — do not declare | — |

- [ ] No permission is requested before its feature is used.
- [ ] Background location NOT declared in the customer-facing build config
      (courier role gates the feature; justify in Play declaration).

## 4. Store listing assets

- [ ] App icon (adaptive icon for Android; 1024×1024 for App Store).
- [ ] Splash (Android 12+ splash API / iOS launch screen) — KORA brand.
- [ ] Screenshots: Play — min 2, phone + 7" tablet recommended; App Store —
      6.7" and 6.5" required sets; capture on production-like data.
- [ ] Feature graphic (Play 1024×500).
- [ ] Short + full description (ru/kk/en), category: Food & Drink /
      Shopping; contact email + website; privacy policy URL →
      `docs/PRIVACY_POLICY.md` hosted copy.

## 5. Data safety & privacy declarations

Fill consoles exactly per [DATA_SAFETY.md](DATA_SAFETY.md) — the tables there
are the source of truth for both Google Play **Data Safety** and Apple
**App Privacy** nutrition labels. Highlights reviewers trip on:

- Precise location collected (courier during delivery) — disclose.
- Phone number used for identity — disclose.
- Chat content — disclose as collected, not shared.
- Payment status (not card numbers — Kaspi handles card data) — disclose
  accurately as "purchase history".

## 6. Content rating & compliance

- [ ] IARC/ESRB questionnaire (Play) — no gambling/UGC issues beyond chat;
      chat disclosed as "Users Interact".
- [ ] Apple age rating questionnaire — matches content.
- [ ] Kazakhstan legal entity details, address, support contacts in console.
- [ ] Export compliance (Apple): standard HTTPS — `ITSAppUsesNonExemptEncryption=NO` if applicable.

## 7. Review notes (paste into both consoles)

```
Demo accounts (OTP flows — use fixed codes if SMS unreachable):
  Customer: +7 700 000 00 01   OTP: provided on request / test backend
  Manager:  +7 700 000 00 02
  Courier:  +7 700 000 00 03
  Admin:    +7 700 000 00 04
Demo store "KORA Demo" is pre-seeded on staging; the customer flow:
register → browse store → checkout (Kaspi sandbox payment) → track order.
Courier flow requires location permission for live tracking.
Background location is used ONLY by courier role during active deliveries.
Contact: support@kora.kz (placeholder — replace before submission).
```

## 8. Pre-release scrub — mandatory

- [ ] No `localhost`, `10.0.2.2`, staging URLs in release build (`APP_ENV=production` refuses http/ws).
- [ ] `OTP_DEV_CODE` unset in production backend; SMS_PROVIDER=real.
- [ ] Mock payment provider disabled — `KASPI_*` production creds set.
- [ ] Debug screens/flags (`showDebugBanner`, dev menu, logging overlays) off.
- [ ] Log verbosity sane; no token/OTP logging anywhere.
- [ ] `flutter analyze` clean, tests green, CI release build green.
- [ ] Crash reporting + analytics wired to **production** projects.
- [ ] App requests review-listed permissions only; no leftover debug entitlements.
- [ ] Legal: privacy policy + terms URLs live and matching in-app copies.

## 9. Rollout

- [ ] Play: internal → closed testing → **phased production rollout
      10% → 50% → 100%** with halt criteria (crash-free <99.5%, ANR spike).
- [ ] App Store: TestFlight beta → production release (manual release
      preferred, phased release enabled).
- [ ] Monitor: crash-free users, ANRs, order funnel, webhook failures,
      WS connect success — for 48 h at each stage.
- [ ] Rollback plan: halt rollout in console; hotfix branch from release tag.
