import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/misc.dart';

/// In-app call screen. Signaling goes through WS events
/// (call.created/accepted/ended); RTC transport plugs into
/// `CallService` — UI is complete regardless.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.peerName});

  final String peerName;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _timer;
  int _seconds = 0;
  bool _connected = false;
  bool _muted = false;
  bool _speaker = false;

  @override
  void initState() {
    super.initState();
    // Simulate connection after ring.
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _connected = true);
      _timer = Timer.periodic(
          const Duration(seconds: 1), (_) => setState(() => _seconds++),);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _duration =>
      '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoraColors.deepPurple,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const KoraAvatar(radius: 52, initials: 'K'),
            const SizedBox(height: AppSpacing.lg),
            Text(
              widget.peerName,
              style: AppTypography.headline
                  .copyWith(color: KoraColors.white),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _connected ? _duration : S.t('call.ringing'),
              style: AppTypography.bodySecondary
                  .copyWith(color: KoraColors.lightPurple),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CallButton(
                  icon: _muted ? AppIcons.micOff : AppIcons.mic,
                  label: _muted ? S.t('call.mic_on') : S.t('call.mic'),
                  active: _muted,
                  onTap: () => setState(() => _muted = !_muted),
                ),
                _CallButton(
                  icon: AppIcons.callEnd,
                  label: S.t('call.end'),
                  color: KoraColors.error,
                  onTap: () => context.pop(),
                ),
                _CallButton(
                  icon: AppIcons.volumeUp,
                  label: S.t('call.speaker'),
                  active: _speaker,
                  onTap: () => setState(() => _speaker = !_speaker),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.huge),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color ??
                  (active
                      ? KoraColors.white
                      : KoraColors.white.withValues(alpha: 0.15)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color != null
                  ? KoraColors.white
                  : (active ? KoraColors.primary : KoraColors.white),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.caption
              .copyWith(color: KoraColors.lightPurple),
        ),
      ],
    );
  }
}
