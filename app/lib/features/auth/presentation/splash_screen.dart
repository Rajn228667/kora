import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import 'auth_providers.dart';

/// Launch sequence: plays the brand video (`kora_splash.mp4`) muted and
/// full-bleed, then routes to auth/home. If the asset can't initialize
/// (or reduce-motion is on), falls back to the static animated logo.
/// A hard timeout guarantees navigation even if playback stalls.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _video;
  bool _videoReady = false;
  bool _videoFailed = false;
  bool _navigated = false;
  Timer? _failsafe;
  AnimationController? _fallback;

  @override
  void initState() {
    super.initState();
    // Never hang on the splash — 6 s max regardless of video state.
    _failsafe = Timer(const Duration(seconds: 6), _tryNavigate);
    _initVideo();
  }

  void _runFallback(Duration d) {
    final c = _fallback ??= AnimationController(vsync: this, duration: d)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _tryNavigate();
      });
    if (!c.isAnimating && !c.isCompleted) unawaited(c.forward());
  }

  Future<void> _initVideo() async {
    try {
      final c = VideoPlayerController.asset('assets/brand/kora_splash.mp4');
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      unawaited(c.setVolume(0));
      unawaited(c.setLooping(false));
      c.addListener(_onVideoTick);
      setState(() {
        _video = c;
        _videoReady = true;
      });
      await c.play();
    } catch (_) {
      _videoFailed = true;
      _runFallback(const Duration(milliseconds: 1400));
      if (mounted) setState(() {});
    }
  }

  void _onVideoTick() {
    final v = _video?.value;
    if (v != null && v.isInitialized && !v.isPlaying && v.position >= v.duration) {
      _tryNavigate();
    }
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
    _video?.removeListener(_onVideoTick);
    _video?.dispose();
    _fallback?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppAnimations.reduceMotion(context);

    // Reduce-motion or failed video → static mark, quick route.
    if (reduced || _videoFailed) {
      _runFallback(Duration(milliseconds: reduced ? 250 : 1400));
      return Scaffold(
        backgroundColor: KoraColors.background,
        body: const SafeArea(child: Center(child: _StaticMark())),
      );
    }

    return Scaffold(
      backgroundColor: KoraColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_videoReady && _video != null)
            GestureDetector(
              // Tap anywhere skips the intro.
              onTap: _tryNavigate,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _video!.value.size.width,
                  height: _video!.value.size.height,
                  child: VideoPlayer(_video!),
                ),
              ),
            )
          else
            const Center(child: _StaticMark()),
        ],
      ),
    );
  }
}

/// Static brand mark — shown while the video buffers or as the
/// reduced-motion/no-video fallback.
class _StaticMark extends StatelessWidget {
  const _StaticMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/brand/kora_logo_k.png',
          width: 104,
          height: 104,
        ),
        const SizedBox(height: AppSpacing.xl),
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
    );
  }
}
