import 'dart:ui';

import 'package:flutter/material.dart';

/// Full-screen overlay host. Animates a blurred scrim over the desktop and
/// hands the same animation to [builder] so panels can slide in sync.
/// Unmounts its content once fully closed so the blur costs nothing.
class OverlayShell extends StatefulWidget {
  const OverlayShell({
    super.key,
    required this.open,
    required this.onDismiss,
    required this.builder,
    this.blur = 12,
    this.scrim = const Color(0x14000000),
    this.duration = const Duration(milliseconds: 520),
  });

  final bool open;
  final VoidCallback onDismiss;
  final Widget Function(BuildContext context, Animation<double> animation) builder;
  final double blur;
  final Color scrim;

  /// Opening time; closing is a little quicker.
  final Duration duration;

  @override
  State<OverlayShell> createState() => _OverlayShellState();
}

class _OverlayShellState extends State<OverlayShell> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    reverseDuration: widget.duration * 0.62,
    value: widget.open ? 1 : 0,
  )..addStatusListener((_) => setState(() {}));
  late final Animation<double> _curve =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);

  @override
  void didUpdateWidget(OverlayShell old) {
    super.didUpdateWidget(old);
    if (widget.open != old.open) {
      widget.open ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_c.isDismissed) return const SizedBox.shrink();
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: AnimatedBuilder(
              animation: _curve,
              builder: (context, _) {
                final t = _curve.value;
                final tint = ColoredBox(
                  color: widget.scrim.withValues(alpha: widget.scrim.a * t),
                );
                if (widget.blur <= 0) return tint;
                return BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: widget.blur * t, sigmaY: widget.blur * t),
                  child: tint,
                );
              },
            ),
          ),
        ),
        Positioned.fill(child: widget.builder(context, _curve)),
      ],
    );
  }
}
