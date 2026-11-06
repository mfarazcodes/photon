import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'photon_primitives.dart';

/// The studio theme button: one 28px circular icon. Tap it to switch between
/// Dark Grading and Daylight Lab.
///
/// It shows the mode you are in: a crescent Moon in Dark Grading, a Sun with
/// eight beams in Daylight Lab. On a tap the glyph turns a quarter and
/// cross-fades to the other in 220ms while the disc recolours. Nothing animates
/// while it is at rest: no idle ticker.
class ShaderThemeSwitch extends StatefulWidget {
  const ShaderThemeSwitch({super.key, required this.dark, required this.onChanged});

  /// True for Dark Grading, false for Daylight.
  final bool dark;

  /// Called with the mode a tap asks for (the opposite of [dark]).
  final ValueChanged<bool> onChanged;

  static const double size = 28;
  static const double width = size;
  static const double height = size;

  /// The turn and cross-fade, and the recolour that goes with them.
  static const Duration duration = Duration(milliseconds: 220);

  @override
  State<ShaderThemeSwitch> createState() => _ShaderThemeSwitchState();
}

class _ShaderThemeSwitchState extends State<ShaderThemeSwitch> with SingleTickerProviderStateMixin {
  /// 0 is Dark Grading, 1 is Daylight. Runs only while the icon turns.
  late final AnimationController _toggle = AnimationController(
    vsync: this,
    duration: ShaderThemeSwitch.duration,
    value: widget.dark ? 0 : 1,
  );

  @override
  void didUpdateWidget(ShaderThemeSwitch old) {
    super.didUpdateWidget(old);
    if (old.dark != widget.dark) _toggle.animateTo(widget.dark ? 0 : 1, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _toggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.dark ? 'Switch to Daylight Lab' : 'Switch to Dark Grading',
      child: Semantics(
        button: true,
        toggled: widget.dark,
        label: widget.dark ? 'Dark Grading. Switch to Daylight Lab' : 'Daylight Lab. Switch to Dark Grading',
        excludeSemantics: true,
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onChanged(!widget.dark),
            child: SizedBox.square(
              dimension: ShaderThemeSwitch.size,
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('shader-theme-icon'),
                  painter: _IconPainter(toggle: _toggle, hovered: hovered),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

/// A solar disc with eight radial beams, centred on [c] and fitting in a
/// circle of radius [r].
void _paintSun(Canvas canvas, Offset c, double r, Color color) {
  canvas.drawCircle(
    c,
    r * 0.46,
    Paint()
      ..color = color
      ..isAntiAlias = true,
  );
  final beam = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = math.max(1.0, r * 0.16)
    ..isAntiAlias = true;
  for (var i = 0; i < 8; i++) {
    final a = i * math.pi / 4;
    final d = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(c + d * (r * 0.70), c + d * r, beam);
  }
}

/// A sculpted lunar crescent: a disc with a second disc bitten out of it.
void _paintMoon(Canvas canvas, Offset c, double r, Color color) {
  final disc = Path()..addOval(Rect.fromCircle(center: c, radius: r));
  final bite = Path()..addOval(Rect.fromCircle(center: c + Offset(r * 0.52, -r * 0.34), radius: r * 0.82));
  canvas.drawPath(
    Path.combine(PathOperation.difference, disc, bite),
    Paint()
      ..color = color
      ..isAntiAlias = true,
  );
}

/// The disc, its 1px edge, and the glyph of the current mode. Between the two
/// modes the Moon and the Sun turn a quarter and cross-fade.
class _IconPainter extends CustomPainter {
  _IconPainter({required this.toggle, required this.hovered}) : super(repaint: toggle);

  final Animation<double> toggle;
  final bool hovered;

  static const darkFill = Color(0xFF14151B);
  static const darkEdge = Color(0xFF262936);
  static const lightFill = Color(0xFFFFFFFF);
  static const lightEdge = Color(0xFFD8DAE8);
  static const moonInk = Color(0xFFF0F1FA);
  static const sunInk = Color(0xFF1A2FFB);
  static const blue = Color(0xFF1A2FFB);

  @override
  void paint(Canvas canvas, Size size) {
    final t = toggle.value.clamp(0.0, 1.0);
    final centre = size.center(Offset.zero);
    final radius = size.width / 2;
    canvas.drawCircle(centre, radius, Paint()..color = _mix(darkFill, lightFill, t));
    final edge = _mix(darkEdge, lightEdge, t);
    canvas.drawCircle(
      centre,
      radius - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = hovered ? _mix(edge, blue, 0.7) : edge,
    );

    final moonA = (1 - t).clamp(0.0, 1.0), sunA = t.clamp(0.0, 1.0);
    if (moonA > 0.01) {
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(t * math.pi / 2);
      _paintMoon(canvas, Offset.zero, 6.4, moonInk.withValues(alpha: moonA));
      canvas.restore();
    }
    if (sunA > 0.01) {
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate((t - 1) * math.pi / 2);
      _paintSun(canvas, Offset.zero, 6.8, sunInk.withValues(alpha: sunA));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.hovered != hovered;
}
