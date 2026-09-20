import 'package:flutter/material.dart';

/// Central animation durations & curves. Every animation honors the
/// system "reduce motion" setting via [AppAnimations.of].
abstract final class AppAnimations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration emphasis = Duration(milliseconds: 300);

  static const Curve ease = Curves.easeOutCubic;
  static const Curve enter = Curves.easeOut;
  static const Curve exit = Curves.easeIn;
  static const Curve spring = Curves.easeOutBack;

  /// True when the OS asks to reduce motion (accessibility).
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Duration scaled to zero when reduce-motion is on.
  static Duration duration(BuildContext context, Duration d) =>
      reduceMotion(context) ? Duration.zero : d;
}

/// Fade+slide page transition used by the router.
class KoraPageTransition {
  const KoraPageTransition._();

  static Widget page(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppAnimations.reduceMotion(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppAnimations.ease,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// Scale-on-press wrapper for buttons and tappable cards.
class KoraPressable extends StatefulWidget {
  const KoraPressable({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.97,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;
  final String? semanticLabel;

  @override
  State<KoraPressable> createState() => _KoraPressableState();
}

class _KoraPressableState extends State<KoraPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppAnimations.fast,
    lowerBound: widget.scaleDown,
    upperBound: 1,
    value: 1,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) => _controller.animateTo(widget.scaleDown);
  void _up([_]) => _controller.animateTo(1, curve: AppAnimations.spring);

  @override
  Widget build(BuildContext context) {
    final child = ScaleTransition(scale: _controller, child: widget.child);
    return Semantics(
      label: widget.semanticLabel,
      button: widget.onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: widget.onTap == null ? null : _down,
        onTapUp: widget.onTap == null ? null : _up,
        onTapCancel: widget.onTap == null ? null : _up,
        child: child,
      ),
    );
  }
}
