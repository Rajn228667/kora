import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/env.dart';
import '../storage/token_storage.dart';

/// WS event envelope: `{type, data, ts}`.
class RealtimeEvent {
  const RealtimeEvent({
    required this.type,
    required this.data,
    required this.ts,
  });

  final String type;
  final Map<String, dynamic> data;
  final DateTime ts;

  factory RealtimeEvent.fromJson(Map<String, dynamic> j) => RealtimeEvent(
        type: j['type'] as String? ?? '',
        data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        ts: DateTime.tryParse(j['ts'] as String? ?? '') ??
            DateTime.now().toUtc(),
      );
}

abstract class RealtimeClient {
  Stream<RealtimeEvent> get events;
  Stream<bool> get connected;
  Future<void> connect();
  void send(String type, [Map<String, dynamic>? data]);
  Future<void> dispose();
}

/// WebSocket client with auth, auto-reconnect (backoff) and resync hook.
class WsRealtimeClient implements RealtimeClient {
  WsRealtimeClient({required TokenStorage tokens}) : _tokens = tokens;

  final TokenStorage _tokens;
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _disposed = false;
  int _attempt = 0;
  String? lastEventId;

  /// App may subscribe to re-fetch missed state after reconnect.
  void Function()? onResync;

  @override
  Stream<RealtimeEvent> get events => _events.stream;
  @override
  Stream<bool> get connected => _connected.stream;

  @override
  Future<void> connect() async {
    if (_disposed) return;
    try {
      final token = await _tokens.readAccess();
      final uri = Uri.parse(
        '${AppEnv.wsBase}${token != null ? '?token=$token' : ''}',
      );
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        _onData,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
      _attempt = 0;
      _connected.add(true);
      if (lastEventId != null) onResync?.call();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onData(dynamic raw) {
    try {
      final j = jsonDecode(raw as String) as Map<String, dynamic>;
      lastEventId = j['id'] as String? ?? lastEventId;
      _events.add(RealtimeEvent.fromJson(j));
    } catch (_) {/* malformed frame — ignore */}
  }

  void _scheduleReconnect() {
    _connected.add(false);
    if (_disposed) return;
    _attempt++;
    final delay = Duration(
      seconds: (1 << _attempt.clamp(0, 5)) + (_attempt % 3),
    );
    Future.delayed(delay, () {
      if (!_disposed) connect();
    });
  }

  @override
  void send(String type, [Map<String, dynamic>? data]) {
    _channel?.sink
        .add(jsonEncode({'type': type, if (data != null) 'data': data}));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    await _channel?.sink.close();
    await _events.close();
    await _connected.close();
  }
}

/// In-app event bus used in mock mode — simulates the backend pushing
/// order progression, courier GPS and chat events on a timer.
class MockRealtimeClient implements RealtimeClient {
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  final _timers = <Timer>[];

  @override
  Stream<RealtimeEvent> get events => _events.stream;
  @override
  Stream<bool> get connected => _connected.stream;

  @override
  Future<void> connect() async {
    _connected.add(true);
  }

  void emit(String type, [Map<String, dynamic> data = const {}]) {
    if (_events.isClosed) return;
    _events.add(
      RealtimeEvent(type: type, data: data, ts: DateTime.now().toUtc()),
    );
  }

  /// Schedule a sequence of events — used to simulate order lifecycle.
  void schedule(
    Iterable<(Duration, String, Map<String, dynamic>)> steps,
  ) {
    for (final (delay, type, data) in steps) {
      _timers.add(Timer(delay, () => emit(type, data)));
    }
  }

  @override
  void send(String type, [Map<String, dynamic>? data]) {
    // Mock: loop back chat typing/echo scenarios if needed.
    if (type == 'chat.typing') emit('chat.typing', data ?? const {});
  }

  @override
  Future<void> dispose() async {
    for (final t in _timers) {
      t.cancel();
    }
    await _events.close();
    await _connected.close();
  }
}
