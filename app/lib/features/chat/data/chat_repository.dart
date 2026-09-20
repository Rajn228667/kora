import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/realtime/realtime.dart';

class ChatRepository {
  ChatRepository(this._api);

  final ApiClient _api;

  Future<ChatRoom> roomForOrder(String orderId) async {
    final res = await _api.get('/chat/rooms', query: {'orderId': orderId})
        as Map<String, dynamic>;
    final items = res['items'] as List;
    if (items.isEmpty) {
      return ChatRoom(id: 'room-$orderId', orderId: orderId);
    }
    final j = items.first as Map<String, dynamic>;
    return ChatRoom(
      id: j['id'] as String,
      orderId: j['orderId'] as String?,
      title: j['title'] as String? ?? S.t('chat.title'),
      peerName: j['peerName'] as String?,
      unread: (j['unread'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<ChatMessage>> messages(String roomId) async {
    final res = await _api.get('/chat/rooms/$roomId/messages')
        as Map<String, dynamic>;
    return (res['items'] as List)
        .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> send(String roomId,
      {String? text,
      ChatMessageType type = ChatMessageType.text,
      String? mediaUrl,
      double? lat,
      double? lng,}) async {
    final res = await _api.post('/chat/rooms/$roomId/messages', body: {
      'type': switch (type) {
        ChatMessageType.image => 'image',
        ChatMessageType.voice => 'voice',
        ChatMessageType.location => 'location',
        _ => 'text',
      },
      if (text != null) 'text': text,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    },) as Map<String, dynamic>;
    return ChatMessage.fromJson(res);
  }

  Future<void> markRead(String roomId) =>
      _api.post('/chat/rooms/$roomId/read');

  Future<void> typing(String roomId) =>
      _api.post('/chat/rooms/$roomId/typing');
}

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(apiClientProvider)),
);

/// Room state for a given order: history + live messages.
final chatRoomProvider = AsyncNotifierProvider.family<ChatController,
    ChatRoom, String>(ChatController.new);

class ChatController extends FamilyAsyncNotifier<ChatRoom, String> {
  StreamSubscription<RealtimeEvent>? _sub;

  @override
  Future<ChatRoom> build(String orderId) async {
    final repo = ref.watch(chatRepositoryProvider);
    final room = await repo.roomForOrder(orderId);
    final msgs = await repo.messages(room.id);
    unawaited(repo.markRead(room.id).catchError((_) {}));
    unawaited(_sub?.cancel());
    _sub = ref.watch(realtimeProvider).events.listen(_onEvent);
    ref.onDispose(() => _sub?.cancel());
    return room.copyWith(messages: msgs, unread: 0);
  }

  void _onEvent(RealtimeEvent e) {
    final room = state.value;
    if (room == null) return;
    if (e.type == 'chat.message_created' &&
        e.data['roomId'] == room.id) {
      final msg = ChatMessage.fromJson(
          (e.data['message'] as Map).cast<String, dynamic>(),);
      state = AsyncData(room.copyWith(
        messages: [...room.messages, msg],
        peerTyping: false,
      ),);
    } else if (e.type == 'chat.typing' && e.data['roomId'] == room.id) {
      state = AsyncData(room.copyWith(peerTyping: true));
      Future.delayed(const Duration(seconds: 3), () {
        final r = state.value;
        if (r != null) state = AsyncData(r.copyWith(peerTyping: false));
      });
    }
  }

  Future<void> sendText(String text) async {
    final room = state.value;
    if (room == null || text.trim().isEmpty) return;
    final optimistic = ChatMessage(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      roomId: room.id,
      senderId: 'me',
      type: ChatMessageType.text,
      at: DateTime.now(),
      text: text.trim(),
      sending: true,
    );
    state = AsyncData(
        room.copyWith(messages: [...room.messages, optimistic]),);
    try {
      final sent = await ref
          .read(chatRepositoryProvider)
          .send(room.id, text: text.trim());
      final r = state.value!;
      state = AsyncData(r.copyWith(
        messages: r.messages
            .map((m) => m.id == optimistic.id ? sent : m)
            .toList(),
      ),);
    } catch (_) {
      final r = state.value!;
      state = AsyncData(r.copyWith(
        messages: r.messages
            .map((m) => m.id == optimistic.id
                ? m.copyWith(sending: false, failed: true)
                : m,)
            .toList(),
      ),);
    }
  }

  Future<void> sendLocation(double lat, double lng) async {
    final room = state.value;
    if (room == null) return;
    await ref
        .read(chatRepositoryProvider)
        .send(room.id, type: ChatMessageType.location, lat: lat, lng: lng);
    ref.invalidateSelf();
  }

  Future<void> sendImage(String mediaUrl) async {
    final room = state.value;
    if (room == null) return;
    await ref
        .read(chatRepositoryProvider)
        .send(room.id, type: ChatMessageType.image, mediaUrl: mediaUrl);
    ref.invalidateSelf();
  }
}
