import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import 'auth_providers.dart';

/// KORA launch sequence (~1.2 s): logo fades+scales in, "KORA" rises,
/// "MARKET" tracks in, then routes to auth/home.
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
      duration: const Duration(milliseconds: 1100),
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
    // If reduce-motion is requested, show the static mark and route fast.
    final reduced = AppAnimations.reduceMotion(context);
    if (reduced && _c.duration != Duration.zero) {
      _c.duration = const Duration(milliseconds: 200);
    }

    final logo = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack),
    );
    final title = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.35, 0.75, curve: AppAnimations.ease),
    );
    final market = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.6, 1.0, curve: AppAnimations.ease),
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
                  scale: logo,
                  child: Image.asset(
                    'assets/brand/kora_logo_k.png',
                    width: 120,
                    height: 120,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FadeTransition(
                opacity: title,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(title),
                  child: Text(
                    'KORA',
                    style: AppTypography.displayLarge.copyWith(
                      color: KoraTheme.dark
                          ? KoraColors.darkTextPrimary
                          : KoraColors.brandNavy,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              FadeTransition(
                opacity: market,
                child: Text(
                  S.t('splash.market'),
                  style: AppTypography.overline.copyWith(
                    color: KoraColors.primary,
                    fontSize: 13,
                    letterSpacing: 8,
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
