# KORA — приложение доставки (Flutter)

Marketplace + delivery для Казахстана (стартовый город — **Шымкент**).
Одна кодовая база: **Android + iOS**.
Бренд: **WHITE + PURPLE** (`lib/core/theme/kora_colors.dart`), светлая и
тёмная темы, локализация **RU / KK / EN** (`lib/core/l10n/app_strings.dart`).

## Быстрый старт

```powershell
# 1) Установите Flutter (stable >= 3.29) и добавьте в PATH
# 2) Сгенерируйте платформенные папки внутри app/
cd C:\Users\User\kora\app
flutter create . --platforms android,ios --org kz.kora --project-name kora
flutter pub get
```

### Запуск без бэкенда (mock-режим, только явно в development)

```powershell
flutter run --dart-define=APP_MODE=mock
```

Всё работает автономно: каталог, корзина, checkout, оплата (симуляция),
статусы заказа, курьер на карте, чат, роли.

**Тестовые роли** — номер телефона при входе:

| Номер | Роль |
|---|---|
| любой `+7 …` | Customer |
| `+7 …0002` | Manager |
| `+7 …0003` | Courier |
| `+7 …0004` | Admin |

OTP: `123456` (dev-код показывается на экране).

### Запуск против реального бэкенда

```powershell
flutter run --dart-define=APP_MODE=api `
  --dart-define=API_URL=http://localhost:3000 `
  --dart-define=WS_URL=ws://localhost:3000
```

## Архитектура

```
lib/
  main.dart, app.dart          # entry, MaterialApp.router, offline banner, WS→snackbar
  core/
    theme/                     # KoraColors, typography, metrics, animations, icons, ThemeData
    widgets/                   # KoraButton/Field/Card/Skeleton/… (единая дизайн-система)
    models/models.dart         # доменные модели + enum'ы контракта
    network/                   # ApiClient (Dio, JWT + refresh) + ApiException
    storage/token_storage.dart # secure storage + fallback
    realtime/realtime.dart     # WsRealtimeClient / MockRealtimeClient (envelope {type,data,ts})
    maps/map_provider.dart     # KoraMap — функциональная карта (pan/zoom/markers/route)
    maps/map_engine.dart       # MapEngine: StubMapEngine ↔ TwoGisMapEngine (2GIS key)
    l10n/app_strings.dart      # RU/KK/EN, S.t(key), S.keys() для тестов
    settings/                  # themeMode + язык (SharedPreferences)
    media/                     # KoraImage + BlurHash-декодер (woltapp/blurhash, MIT)
    mock/                      # MockApiClient — автономный бэкенд по контракту /v1
    router/                    # go_router + role gating + AppShell
  features/
    auth/        # +7 OTP → JWT → профиль → биометрия
    home/        # greeting, search, banners, categories, stores
    catalog/     # store, product, search, category, favorites
    cart/        # корзина, промокод, итоги
    checkout/    # адрес / точка на карте, комментарий, Kaspi, validate
    orders/      # список, детали, таймлайн, live tracking
    chat/        # чат по заказу (WS, optimistic send, typing, read)
    calls/       # экран звонка (signaling через WS)
    profile/     # профиль, адреса, избранное, сессии, безопасность, legal
    support/     # FAQ + обращения
    notifications/
    manager/     # дашборд, заказы (accept/reject/ready/assign), товары, карта
    courier/     # online/offline, офферы, GPS-публикация при доставке
    admin/       # пользователи, заказы, платежи, audit log
```

Слои внутри feature: `data/` (models, repository, providers) → `presentation/` (screens).
Репозитории зависят от `ApiClient` — в mock-режиме подменяется `MockApiClient`,
контракт `/v1` одинаковый.

## Permissions (добавить после `flutter create`)

**AndroidManifest.xml**
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
```

**Info.plist**
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Поделитесь точкой доставки, чтобы курьер смог вас найти</string>
<key>NSCameraUsageDescription</key>
<string>Камера нужна для фото в чате и аватара</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Доступ к фото для отправки в чат</string>
<key>NSFaceIDUsageDescription</key>
<string>Быстрый вход в KORA по Face ID</string>
<key>UIBackgroundModes</key><array><string>fetch</string></array>
```

Background location — **не включать** для клиента; только курьерский
workflow (обоснование для модерации задокументировано в `../docs/STORE_RELEASE.md`).

## Интеграционные точки (нужны внешние credentials)

| Функция | Что подключить |
|---|---|
| Карты | **2GIS Mobile SDK** — ключ на https://dev.2gis.com, `--dart-define=MAP_API_KEY=...`, раскомментировать `dgis_mobile_sdk` в pubspec. См. `core/maps/map_engine.dart` |
| Оплата | Kaspi merchant API — `PaymentProvider`, deeplink из `clientPayload` |
| Push | FCM (Android) / APNs (iOS) → `POST /notifications/devices` |
| SMS OTP | SMS-провайдер на бэкенде (в mock — `devOtp`) |
| Медиа | S3 signed uploads → `POST /media/uploads` |
| Звонки | WebRTC transport поверх WS-signaling (`call.*`) |

## Тесты

```powershell
flutter test
```

## Тема и язык

- **Settings → Appearance**: Light / Dark / System — сохраняется в
  SharedPreferences, применяется без перезапуска.
- **Settings → Language**: Русский / Қазақша / English — мгновенное
  переключение, все строки через `S.t('key')`.
- Карта в тёмной теме: `KoraTheme.dark` синхронизирует stub-рендерер;
  при подключении 2GIS применять `MapTheme.dark` (см. map_engine.dart).

## Чеклист перед релизом

- [ ] `APP_MODE=api` + боевые `API_URL`/`WS_URL`
- [ ] Убрать dev-подсказки (devOtp banner, dev phones) — `AppEnv.isDev`
- [ ] `MAP_API_KEY` от 2GIS + `dgis_mobile_sdk`, Kaspi merchant
- [x] Иконка/splash из `assets/brand/kora_logo.png` (v1.0.2: adaptive icon + native splash, iOS AppIcon/LaunchImage)
- [ ] ProGuard/R8, signing (см. `../docs/STORE_RELEASE.md`)
