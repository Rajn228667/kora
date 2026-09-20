import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/media/kora_image.dart' as kora_media;
import '../../../core/models/models.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/chat_repository.dart';

/// Order chat: bubbles, typing indicator, read receipts, location
/// messages, attachment actions (photo/voice/location).
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    _input.clear();
    await ref.read(chatRoomProvider(widget.orderId).notifier).sendText(text);
    _scrollDown();
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(chatRoomProvider(widget.orderId));
    final myId = switch (ref.watch(authControllerProvider)) {
      Authenticated(user: final u) => u.id,
      _ => 'me',
    };

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: room.maybeWhen(
          data: (r) => Text(
              r.peerName ?? (r.title.isEmpty ? S.t('chat.title') : r.title),),
          orElse: () => Text(S.t('chat.title')),
        ),
      ),
      body: room.when(
        loading: () => const KoraLoadingState(),
        error: (_, __) => KoraErrorState(
          message: S.t('chat.load_error'),
          onRetry: () => ref.invalidate(chatRoomProvider(widget.orderId)),
        ),
        data: (r) {
          _scrollDown();
          return Column(
            children: [
              Expanded(
                child: r.messages.isEmpty
                    ? KoraEmptyState(
                        icon: AppIcons.chatOut,
                        title: S.t('chat.first'),
                        message: S.t('chat.first_sub'),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: r.messages.length,
                        itemBuilder: (_, i) => _Bubble(
                          message: r.messages[i],
                          mine: r.messages[i].senderId == myId ||
                              r.messages[i].senderId == 'me',
                        ),
                      ),
              ),
              if (r.peerTyping)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child:
                        Text(S.t('chat.typing'), style: AppTypography.caption),
                  ),
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: S.t('chat.attach'),
                        icon: const Icon(AppIcons.add,
                            color: KoraColors.primary,),
                        onPressed: () => _attach(context, r.id),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _input,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: S.t('chat.hint'),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      _SendButton(onTap: _send),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _attach(BuildContext context, String roomId) {
    KoraBottomSheet.show<void>(
      context,
      child: SafeArea(
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AttachTile(
                icon: AppIcons.gallery,
                label: S.t('chat.photo'),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await ImagePicker()
                      .pickImage(source: ImageSource.gallery);
                  if (file != null && mounted) {
                    await ref
                        .read(chatRoomProvider(widget.orderId).notifier)
                        .sendImage('file://${file.path}');
                    _scrollDown();
                  }
                },
              ),
              _AttachTile(
                icon: AppIcons.locationOut,
                label: S.t('chat.location'),
                onTap: () async {
                  Navigator.pop(context);
                  double lat = 42.3417;
                  double lng = 69.5901;
                  try {
                    var perm = await Geolocator.checkPermission();
                    if (perm == LocationPermission.denied) {
                      perm = await Geolocator.requestPermission();
                    }
                    if (perm != LocationPermission.denied &&
                        perm != LocationPermission.deniedForever) {
                      final pos = await Geolocator.getCurrentPosition();
                      lat = pos.latitude;
                      lng = pos.longitude;
                    }
                  } catch (_) {/* fall back to city center */}
                  if (!mounted) return;
                  await ref
                      .read(chatRoomProvider(widget.orderId).notifier)
                      .sendLocation(lat, lng);
                  _scrollDown();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          gradient: KoraColors.primaryGradient,
          shape: BoxShape.circle,
        ),
        child: const Icon(AppIcons.send,
            color: KoraColors.white, size: 20,),
      ),
    );
  }
}

class _AttachTile extends StatelessWidget {
  const _AttachTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: KoraColors.surfaceAlt,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: KoraColors.primary, size: 20),
      ),
      title: Text(label, style: AppTypography.label),
      onTap: onTap,
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(message.at);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          gradient: mine ? KoraColors.primaryGradient : null,
          color: mine ? null : KoraColors.surfaceAlt,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadius.lg),
            topRight: const Radius.circular(AppRadius.lg),
            bottomLeft: Radius.circular(mine ? AppRadius.lg : 4),
            bottomRight: Radius.circular(mine ? 4 : AppRadius.lg),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.type == ChatMessageType.image)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: kora_media.KoraImage(
                  url: message.mediaUrl,
                  width: 220,
                  height: 160,
                  borderRadius: AppRadius.md,
                ),
              )
            else if (message.type == ChatMessageType.location)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.location,
                      size: 16,
                      color: mine
                          ? KoraColors.white
                          : KoraColors.primary,),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    S.t('chat.geo'),
                    style: AppTypography.label.copyWith(
                      color: mine
                          ? KoraColors.white
                          : KoraColors.textPrimaryC,
                    ),
                  ),
                ],
              )
            else
              Text(
                message.text ?? '',
                style: AppTypography.body.copyWith(
                  color:
                      mine ? KoraColors.white : KoraColors.textPrimaryC,
                ),
              ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.failed)
                  const Icon(AppIcons.error,
                      size: 12, color: KoraColors.error,),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: mine
                        ? KoraColors.lightPurple
                        : KoraColors.placeholderC,
                  ),
                ),
                if (mine) ...[
                  const SizedBox(width: 2),
                  Icon(
                    message.sending ? AppIcons.clock : AppIcons.checkAll,
                    size: 12,
                    color: message.read
                        ? KoraColors.white
                        : KoraColors.lightPurple,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
