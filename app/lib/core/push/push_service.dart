import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../providers.dart';

/// Push token registration pipeline.
///
/// The backend endpoint `POST /users/me/devices` is live. The FCM token
/// source plugs in via [PushService.attachTokenSource] once the Firebase
/// project files are added (google-services.json / GoogleService-Info.plist
/// + firebase_messaging dependency). Until then this is a safe no-op and
/// in-app notifications keep working over the realtime WebSocket channel.
class PushService {
  PushService({required ApiClient api}) : _api = api;

  final ApiClient _api;
  Future<String?> Function()? _tokenSource;
  String? _registeredToken;

  /// Installs the FCM token source, e.g. `FirebaseMessaging.instance.getToken`.
  void attachTokenSource(Future<String?> Function() source) {
    _tokenSource = source;
  }

  /// Called after sign-in. Registers the device token with the backend;
  /// silently no-ops when no token source is configured yet.
  Future<void> sync() async {
    final source = _tokenSource;
    if (source == null) return;
    try {
      final token = await source();
      if (token == null || token == _registeredToken) return;
      await _api.post('/users/me/devices', body: {
        'token': token,
        'platform': _platform(),
      },);
      _registeredToken = token;
    } catch (_) {
      // Push registration is best-effort; realtime/inbox keep working.
    }
  }

  Future<void> unregister() async {
    final token = _registeredToken;
    _registeredToken = null;
    if (token == null) return;
    try {
      await _api.delete('/users/me/devices/$token');
    } catch (_) {}
  }

  String _platform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isIOS) return 'ios';
    } catch (_) {}
    return 'android';
  }
}

final pushServiceProvider = Provider<PushService>(
  (ref) => PushService(api: ref.watch(apiClientProvider)),
);
