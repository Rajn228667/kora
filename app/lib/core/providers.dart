import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/env.dart';
import 'mock/mock_api.dart';
import 'network/api_client.dart';
import 'realtime/realtime.dart';
import 'storage/token_storage.dart';

/// Dependency wiring. In `APP_MODE=mock` the whole backend is
/// simulated in-process; `APP_MODE=api` uses Dio + WebSocket.
final tokenStorageProvider = Provider<TokenStorage>((_) => TokenStorage());

final realtimeProvider = Provider<RealtimeClient>((ref) {
  if (AppEnv.isMock) return MockRealtimeClient();
  return WsRealtimeClient(tokens: ref.watch(tokenStorageProvider));
});

final apiClientProvider = Provider<ApiClient>((ref) {
  if (AppEnv.isMock) {
    final rt = ref.watch(realtimeProvider);
    return MockApiClient(realtime: rt is MockRealtimeClient ? rt : null);
  }
  final client = DioApiClient(tokens: ref.watch(tokenStorageProvider));
  return client;
});
