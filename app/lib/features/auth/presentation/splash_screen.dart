import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import 'auth_providers.dart';

/// Launch sequence: the K mark scales in while the KORA wordmark fades
/// up, then routes immediately. No video — the whole intro is ~900 ms.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _navigated = false;
  Timer? _failsafe;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) _tryNavigate();
      });
    // Never hang on the splash.
    _failsafe = Timer(const Duration(seconds: 3), _tryNavigate);
    _c.forward();
  }

  void _tryNavigate() {
    if (_navigated || !mounted) return;
    _navigated = true;
    final auth = ref.read(authControllerProvider);
    if (auth is Authenticated && !auth.needsProfile) {
      context.go('/home');
    } else if (auth is Authenticated) {
      context.go('/auth/profile');
    } else {
      context.go('/welcome');
    }
  }

  @override
  void dispose() {
    _failsafe?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppAnimations.reduceMotion(context);
    final mark = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.6, curve: Curves.easeOutBack),
    );
    final word = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.3, 1, curve: Curves.easeOut),
    );

    return Scaffold(
      backgroundColor: KoraColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: reduced
                    ? const AlwaysStoppedAnimation(1)
                    : Tween(begin: 0.6, end: 1.0).animate(mark),
                child: FadeTransition(
                  opacity: reduced
                      ? const AlwaysStoppedAnimation(1)
                      : Tween(begin: 0.0, end: 1.0).animate(mark),
                  child: Image.asset(
                    'assets/brand/kora_logo_k.png',
                    width: 104,
                    height: 104,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FadeTransition(
                opacity: reduced
                    ? const AlwaysStoppedAnimation(1)
                    : Tween(begin: 0.0, end: 1.0).animate(word),
                child: SlideTransition(
                  position: reduced
                      ? const AlwaysStoppedAnimation(Offset.zero)
                      : Tween(
                          begin: const Offset(0, 0.25),
                          end: Offset.zero,
                        ).animate(word),
                  child: Column(
                    children: [
                      Text(
                        'KORA',
                        style: AppTypography.displayLarge.copyWith(
                          color: KoraColors.brandNavy,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        S.t('splash.market'),
                        style: AppTypography.overline.copyWith(
                          color: KoraColors.primary,
                          fontSize: 12,
                          letterSpacing: 7,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
