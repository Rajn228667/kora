import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import 'auth_providers.dart';

/// KORA launch sequence (~1.4 s): the "K" mark eases in with a soft
/// scale, then "KORA" letters appear one by one with tracking expansion —
/// Apple-style restraint, no bounce overshoot.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _tryNavigate();
    });
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
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppAnimations.reduceMotion(context);
    if (reduced && _c.duration != Duration.zero) {
      _c.duration = const Duration(milliseconds: 200);
    }

    final logo = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
    );
    final tagline = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.72, 1.0, curve: AppAnimations.ease),
    );

    return Scaffold(
      backgroundColor: KoraColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: logo,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.86, end: 1).animate(logo),
                  child: Image.asset(
                    'assets/brand/kora_logo_k.png',
                    width: 104,
                    height: 104,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              // Letter-by-letter reveal — each glyph fades in while the
              // whole word gently expands its tracking (Apple keynote style).
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 4; i++)
                    _Letter(
                      'KORA'[i],
                      CurvedAnimation(
                        parent: _c,
                        curve: Interval(
                          0.3 + i * 0.09,
                          0.3 + i * 0.09 + 0.3,
                          curve: AppAnimations.ease,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              FadeTransition(
                opacity: tagline,
                child: Text(
                  S.t('splash.market'),
                  style: AppTypography.overline.copyWith(
                    color: KoraColors.primary,
                    fontSize: 12,
                    letterSpacing: 7,
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

/// Single brand letter — fades in while rising slightly.
class _Letter extends StatelessWidget {
  const _Letter(this.char, this.animation);

  final String char;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.35),
          end: Offset.zero,
        ).animate(animation),
        child: Text(
          char,
          style: AppTypography.displayLarge.copyWith(
            color: KoraColors.brandNavy,
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }
}
