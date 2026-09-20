import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/feedback.dart';

// ---------------------------------------------------------------------------
// Notifications — realtime feed + persisted preferences. Push wiring
// (FCM/APNs) attaches to the same endpoints later — UI doesn't change.
// ---------------------------------------------------------------------------

final notificationsProvider =
    FutureProvider<List<AppNotification>>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/notifications')
      as Map<String, dynamic>;
  return (res['items'] as List)
      .map((j) => AppNotification(
            id: j['id'] as String,
            title: j['title'] as String? ?? '',
            body: j['body'] as String? ?? '',
            kind: j['kind'] as String? ?? 'info',
            at: DateTime.tryParse(j['at'] as String? ?? '') ??
                DateTime.now(),
            read: j['read'] as bool? ?? false,
            orderId: j['orderId'] as String?,
          ),)
      .toList();
});

final notifPrefsProvider =
    AsyncNotifierProvider<NotifPrefs, Map<String, bool>>(NotifPrefs.new);

class NotifPrefs extends AsyncNotifier<Map<String, bool>> {
  @override
  Future<Map<String, bool>> build() async {
    final res = await ref
        .watch(apiClientProvider)
        .get('/notifications/preferences') as Map<String, dynamic>;
    final p = (res['preferences'] as Map?)?.cast<String, dynamic>() ?? {};
    return {
      'orders': p['orders'] as bool? ?? true,
      'chat': p['chat'] as bool? ?? true,
      'promos': p['promos'] as bool? ?? true,
    };
  }

  Future<void> set(String key, bool value) async {
    final next = {...(state.value ?? {}), key: value};
    state = AsyncData(next);
    await ref
        .read(apiClientProvider)
        .post('/notifications/preferences', body: next);
  }
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    // New notifications pushed over realtime refresh the feed.
    _sub = ref.read(realtimeProvider).events.listen((e) {
      if (e.type == 'notification.created') {
        ref.invalidate(notificationsProvider);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _markAllRead() async {
    await ref
        .read(apiClientProvider)
        .post('/notifications/read', body: const {});
    ref.invalidate(notificationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(notificationsProvider);
    final prefs = ref.watch(notifPrefsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('notif.title')),
        actions: [
          IconButton(
            onPressed: _markAllRead,
            icon: const Icon(AppIcons.checkAll),
            tooltip: S.t('notif.mark_read'),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: KoraColors.primary,
        onRefresh: () async => ref.invalidate(notificationsProvider),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            feed.when(
              loading: () => const Column(children: [
                KoraCardSkeleton(),
                KoraCardSkeleton(),
              ],),
              error: (_, __) => KoraErrorState(
                message: S.t('home.load_error'),
                onRetry: () => ref.invalidate(notificationsProvider),
              ),
              data: (items) => items.isEmpty
                  ? KoraEmptyState(
                      icon: AppIcons.notificationOut,
                      title: S.t('notif.empty'),
                      message: S.t('notif.empty_sub'),
                    )
                  : Column(
                      children: [
                        for (final n in items) _NotifTile(n: n),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(S.t('notif.settings'), style: AppTypography.title),
            const SizedBox(height: AppSpacing.sm),
            KoraCard(
              padding: EdgeInsets.zero,
              child: prefs.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (p) => Column(
                  children: [
                    _prefTile('orders', S.t('notif.order'), p),
                    _prefTile('chat', S.t('notif.chat'), p),
                    _prefTile('promos', S.t('notif.promo'), p),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _prefTile(String key, String title, Map<String, bool> p) {
    return SwitchListTile(
      value: p[key] ?? true,
      onChanged: (v) => ref.read(notifPrefsProvider.notifier).set(key, v),
      title: Text(title, style: AppTypography.label),
      activeThumbColor: KoraColors.primary,
    );
  }
}

class _NotifTile extends StatelessWidget {
  const _NotifTile({required this.n});
  final AppNotification n;

  @override
  Widget build(BuildContext context) {
    final icon = switch (n.kind) {
      'price_drop' => AppIcons.promo,
      'order' => AppIcons.orders,
      'chat' => AppIcons.chat,
      _ => AppIcons.notificationOut,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: KoraCard(
        onTap: n.orderId != null
            ? () => context.push('/orders/${n.orderId}')
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: KoraColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: KoraColors.primary, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(n.title, style: AppTypography.label),
                      ),
                      if (!n.read)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: KoraColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(n.body, style: AppTypography.caption),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    DateFormat('d MMM, HH:mm', S.lang.name).format(n.at),
                    style: AppTypography.caption
                        .copyWith(color: KoraColors.placeholderC),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
