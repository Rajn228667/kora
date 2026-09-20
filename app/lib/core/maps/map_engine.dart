import '../config/env.dart';
import 'map_provider.dart';

/// Pluggable map engine. `KoraMap` is the widget contract; an engine
/// provides the concrete renderer. Today [StubMapEngine] ships in-app;
/// [TwoGisMapEngine] activates once `MAP_API_KEY` is supplied and the
/// `dgis_mobile_sdk` dependency is enabled in pubspec.yaml.
///
/// 2GIS SDK (https://docs.2gis.com/en/flutter/sdk/overview) supports:
/// markers, camera control, dark style (MapTheme), directory search,
/// routes/navigation — everything KORA needs for KZ.
/// Adding Yandex/Google later = another engine, zero feature changes.
abstract class MapEngine {
  const MapEngine();

  /// Default city: Shymkent, Kazakhstan (KORA launch market).
  static const GeoPoint shymkent = GeoPoint(lat: 42.3417, lng: 69.5901);

  String get id;

  /// Whether the engine has everything needed to render real tiles.
  bool get isReady;
}

/// Built-in stylized renderer (pan/zoom, markers, routes, tap-pick).
/// Always available — used in mock mode and as a graceful fallback.
class StubMapEngine extends MapEngine {
  const StubMapEngine();

  @override
  String get id => 'stub';

  @override
  bool get isReady => true;
}

/// 2GIS Mobile SDK engine.
///
/// Activation checklist (all external — no fake wiring):
///   1. Get an SDK key at https://dev.2gis.com (project → keys).
///   2. Uncomment `dgis_mobile_sdk` in pubspec.yaml.
///   3. `flutter pub get`, then pass
///      `--dart-define=MAP_API_KEY=<key>` to run/build.
///   4. Implement [_TwoGisMapView] — it maps [KoraMarker]s to
///      `MapObjectManager` markers, `route` to `RouteEditor`/`Polyline`,
///      and applies `MapTheme.dark` when [KoraTheme.dark] is set
///      (see docs.2gis.com → "Стиль карты"/themes).
///
/// Until a key exists, [isReady] is false and [engine] falls back
/// to the stub renderer — the app stays fully functional.
class TwoGisMapEngine extends MapEngine {
  const TwoGisMapEngine();

  @override
  String get id => '2gis';

  @override
  bool get isReady =>
      AppEnv.mapProvider == '2gis' && AppEnv.mapApiKey.isNotEmpty;
}

/// Active engine resolution — single place that decides which
/// renderer backs `KoraMap`.
MapEngine get mapEngine =>
    const TwoGisMapEngine().isReady ? const TwoGisMapEngine() : const StubMapEngine();
