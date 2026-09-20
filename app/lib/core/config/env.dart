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

  /// `mock` — fully standalone app with simulated backend (default).
  /// `api`  — talk to a real KORA backend over HTTP/WS.
  static const String mode =
      String.fromEnvironment('APP_MODE', defaultValue: 'mock');

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
    defaultValue: '2gis',
  );

  static bool get isMock => mode == 'mock';
  static bool get isDev => env == 'development';
  static String get apiBase => '$apiUrl/v1';
  static String get wsBase => '$wsUrl/v1/ws';
}
