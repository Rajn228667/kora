import 'package:flutter/material.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/feedback.dart';

/// Notification feed + local prefs. Push wiring (FCM/APNs) attaches
/// to the same provider later — UI doesn't change.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Feed is realtime-driven; in mock mode notifications arrive via WS
    // events and are surfaced as snackbars by the app shell.
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('notif.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          KoraEmptyState(
            icon: AppIcons.notificationOut,
            title: S.t('notif.empty'),
            message: S.t('notif.empty_sub'),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(S.t('notif.settings'), style: AppTypography.title),
          const SizedBox(height: AppSpacing.sm),
          KoraCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _PrefTile(title: S.t('notif.order'), value: true),
                _PrefTile(title: S.t('notif.chat'), value: true),
                _PrefTile(title: S.t('notif.promo'), value: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrefTile extends StatefulWidget {
  const _PrefTile({required this.title, required this.value});

  final String title;
  final bool value;

  @override
  State<_PrefTile> createState() => _PrefTileState();
}

class _PrefTileState extends State<_PrefTile> {
  late bool _v = widget.value;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: _v,
      onChanged: (v) => setState(() => _v = v),
      title: Text(widget.title, style: AppTypography.label),
      activeThumbColor: KoraColors.primary,
    );
  }
}
