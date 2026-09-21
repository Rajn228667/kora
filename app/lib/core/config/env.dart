/// Build-time configuration via --dart-define.
///
/// Run examples:
///   flutter run --dart-define=APP_MODE=mock
///   flutter run --dart-define=APP_MODE=api \
///     --dart-define=API_URL=http://localhost:3000 \
///     --dart-define=WS_URL=ws://localhost:3000
abstract final class AppEnv {
  static const String env =
      String.fromEnvironment('APP_ENV', defaultValue: 'development');

  /// `api` is the safe default. Mock mode must always be opted into explicitly
  /// with `--dart-define=APP_MODE=mock` and is forbidden in production.
  static const String mode =
      String.fromEnvironment('APP_MODE', defaultValue: 'api');

  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://localhost:3000',
  );

  /// 2GIS Mobile SDK key (https://dev.2gis.com). When empty the app
  /// renders the built-in stylized map — delivery flows still work.
  static const String mapApiKey =
      String.fromEnvironment('MAP_API_KEY', defaultValue: '');

  /// Map provider id: `2gis` (default) | `none`.
  static const String mapProvider = String.fromEnvironment(
    'MAP_PROVIDER',
    defaultValue: 'tiles',
  );

  /// XYZ tile endpoint. Production may point this at the contracted map
  /// provider without changing feature code.
  static const String mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  static bool get isMock => mode == 'mock';
  static bool get isDev => env == 'development';
  static bool get isProduction => env == 'production';
  static String get apiBase => '$apiUrl/v1';
  static String get wsBase => '$wsUrl/v1/ws';

  /// Fails before application startup when a release could expose demo data,
  /// plaintext traffic, or localhost endpoints.
  static void validate() {
    if (!const {'development', 'staging', 'production'}.contains(env)) {
      throw StateError('Unsupported APP_ENV: $env');
    }
    if (!const {'mock', 'api'}.contains(mode)) {
      throw StateError('Unsupported APP_MODE: $mode');
    }
    if (isProduction && isMock) {
      throw StateError('APP_MODE=mock is forbidden in production');
    }
    if (isProduction &&
        (!apiUrl.startsWith('https://') || !wsUrl.startsWith('wss://'))) {
      throw StateError('Production API_URL/WS_URL must use HTTPS/WSS');
    }
    if (isProduction &&
        (apiUrl.contains('localhost') || wsUrl.contains('localhost'))) {
      throw StateError('Localhost endpoints are forbidden in production');
    }
  }
}
