import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// The studio theme switch: a 76x28 pill whose track is a shader gradient.
///
/// Dark Grading is an obsidian-to-violet night with twinkling photon dots and a
/// crescent orb on the right. Daylight Cyclorama is a warm sky with caustic
/// rings and a solar orb on the left. The orb is the thumb; it glides across
/// with an overshoot spring (`Curves.easeOutBack`) while the track cross-fades.
///
/// Tapping the switch toggles it. The two invisible `DAYLIGHT` / `DARK GRADING`
/// labels at either end set that mode directly (and keep the switch addressable
/// by text, for assistive tech and tests).
class ShaderThemeSwitch extends StatefulWidget {
  const ShaderThemeSwitch({super.key, required this.dark, required this.onChanged, this.animate = true});

  /// True for Dark Grading, false for Daylight.
  final bool dark;
  final ValueChanged<bool> onChanged;

  /// False freezes the starfield and caustic shimmer (tests); the toggle
  /// itself still animates.
  final bool animate;

  static const double width = 76;
  static const double height = 28;
  static const double thumb = 22;
  static const double _inset = 3;

  @override
  State<ShaderThemeSwitch> createState() => _ShaderThemeSwitchState();
}

class _ShaderThemeSwitchState extends State<ShaderThemeSwitch> with TickerProviderStateMixin {
  /// 0 is Dark Grading, 1 is Daylight.
  late final AnimationController _toggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: widget.dark ? 0 : 1,
  );
  late final AnimationController _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
    value: 0.3,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _twinkle.repeat();
  }

  @override
  void didUpdateWidget(ShaderThemeSwitch old) {
    super.didUpdateWidget(old);
    if (old.dark != widget.dark) _toggle.animateTo(widget.dark ? 0 : 1);
    if (widget.animate && !_twinkle.isAnimating) {
      _twinkle.repeat();
    } else if (!widget.animate && _twinkle.isAnimating) {
      _twinkle.stop();
    }
  }

  @override
  void dispose() {
    _toggle.dispose();
    _twinkle.dispose();
    super.dispose();
  }

  Widget _zone({required double left, required String label, required bool dark}) {
    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      width: 26,
      child: Semantics(
        button: true,
        selected: widget.dark == dark,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onChanged(dark),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(fontSize: 7, color: Colors.transparent, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    return Tooltip(
      message: widget.dark ? 'Switch to Daylight Lab' : 'Switch to Dark Grading',
      child: Semantics(
        toggled: widget.dark,
        label: 'Studio theme',
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onChanged(!widget.dark),
            child: SizedBox(
              width: ShaderThemeSwitch.width,
              height: ShaderThemeSwitch.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _TrackPainter(toggle: _toggle, twinkle: _twinkle, hovered: hovered, edge: c.border),
                      ),
                    ),
                  ),
                  _zone(left: 2, label: 'DAYLIGHT', dark: false),
                  _zone(left: ShaderThemeSwitch.width - 28, label: 'DARK GRADING', dark: true),
                  AnimatedBuilder(
                    animation: _toggle,
                    builder: (context, _) {
                      final mix = _toggle.value.clamp(0.0, 1.0);
                      // The overshoot is the spring: easeOutBack runs past 1
                      // before settling, and the thumb follows it.
                      final travel = ShaderThemeSwitch.width - ShaderThemeSwitch.thumb - ShaderThemeSwitch._inset * 2;
                      final x = ShaderThemeSwitch._inset + travel * (1 - Curves.easeOutBack.transform(mix));
                      final halo = Color.lerp(const Color(0xFF8A2BE2), const Color(0xFFF59E0B), mix)!;
                      return Positioned(
                        left: x,
                        top: (ShaderThemeSwitch.height - ShaderThemeSwitch.thumb) / 2,
                        width: ShaderThemeSwitch.thumb,
                        height: ShaderThemeSwitch.thumb,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            key: const ValueKey('shader-theme-thumb'),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: halo.withValues(alpha: hovered ? 0.8 : 0.6), blurRadius: hovered ? 14 : 10),
                                // Daylight carries a second, violet halo.
                                BoxShadow(
                                  color: const Color(0xFF8A2BE2).withValues(alpha: 0.28 * mix),
                                  blurRadius: 16,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: CustomPaint(painter: _OrbPainter(mix)),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

class _TrackPainter extends CustomPainter {
  _TrackPainter({required this.toggle, required this.twinkle, required this.hovered, required this.edge})
    : super(repaint: Listenable.merge([toggle, twinkle]));

  final Animation<double> toggle;
  final Animation<double> twinkle;
  final bool hovered;
  final Color edge;

  static const _night = [Color(0xFF0E0E10), Color(0xFF1E1035), Color(0xFF4C1D95)];
  static const _day = [Color(0xFFE0F2FE), Color(0xFFF3E8FF), Color(0xFFFEF3C7)];

  // Fixed star positions (fraction of width, fraction of height, phase offset).
  static const _stars = [
    (0.10, 0.30, 0.0),
    (0.19, 0.72, 0.8),
    (0.27, 0.22, 1.7),
    (0.34, 0.60, 2.4),
    (0.43, 0.34, 3.1),
    (0.50, 0.78, 3.9),
    (0.57, 0.20, 4.6),
    (0.14, 0.52, 5.3),
    (0.38, 0.84, 5.9),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final light = Curves.easeInOut.transform(toggle.value.clamp(0.0, 1.0));
    final phase = twinkle.value * 2 * math.pi;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2));

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [for (var i = 0; i < 3; i++) _mix(_night[i], _day[i], light)],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(rect),
    );

    // Dark: twinkling photon dots.
    final starAlpha = 1 - light;
    if (starAlpha > 0.01) {
      final paint = Paint();
      for (final (fx, fy, offset) in _stars) {
        final tw = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(phase * 2 + offset));
        paint.color = Colors.white.withValues(alpha: 0.85 * tw * starAlpha);
        canvas.drawCircle(Offset(fx * size.width, fy * size.height), 0.7 + 0.5 * tw, paint);
      }
    }

    // Light: radiant caustic rings around the solar orb on the left.
    if (light > 0.01) {
      final center = Offset(3 + ShaderThemeSwitch.thumb / 2, size.height / 2);
      for (var i = 0; i < 3; i++) {
        final shimmer = 0.6 + 0.4 * math.sin(phase + i * 1.7);
        canvas.drawCircle(
          center,
          15.0 + i * 8.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1
            ..color = _mix(const Color(0xFFF59E0B), const Color(0xFF8A2BE2), i / 2.0).withValues(alpha: 0.26 * shimmer * light),
        );
      }
    }
    canvas.restore();

    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _mix(
          Colors.white.withValues(alpha: hovered ? 0.3 : 0.14),
          _mix(edge, const Color(0xFF8A2BE2), hovered ? 0.6 : 0.2),
          light,
        ),
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.hovered != hovered || old.edge != edge;
}

/// The thumb: a crescent moon that opens into a sun as [light] goes 0 to 1.
class _OrbPainter extends CustomPainter {
  _OrbPainter(this.light);

  final double light;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 1;
    final disc = Path()..addOval(Rect.fromCircle(center: center, radius: r));

    // Moon: a pale disc with a bite taken out of its upper right.
    final moonAlpha = 1 - light;
    if (moonAlpha > 0.01) {
      final bite = Path()..addOval(Rect.fromCircle(center: center + Offset(r * 0.5, -r * 0.32), radius: r * 0.82));
      canvas.drawPath(
        Path.combine(PathOperation.difference, disc, bite),
        Paint()..color = const Color(0xFFEDE9FE).withValues(alpha: moonAlpha),
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = const Color(0xFFB57BFF).withValues(alpha: 0.5 * moonAlpha),
      );
    }

    // Sun: a crisp aperture orb with short rays.
    if (light > 0.01) {
      final rect = Rect.fromCircle(center: center, radius: r);
      canvas.drawCircle(
        center,
        r * 0.72,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFFBEB).withValues(alpha: light),
              const Color(0xFFFDE68A).withValues(alpha: light),
              const Color(0xFFF59E0B).withValues(alpha: light),
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(rect),
      );
      final ray = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.1
        ..color = const Color(0xFFF59E0B).withValues(alpha: light);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final dir = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(center + dir * (r * 0.84), center + dir * r, ray);
      }
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.light != light;
}
