import 'package:flutter/material.dart';

import 'photon_primitives.dart';

/// The studio theme switch: a minimal, hardware-style 76x28 optical toggle.
///
/// A matte capsule track with two etched 1px glyphs, an aperture ring on the
/// left (Daylight) and an eclipse slit on the right (Dark Grading), and a
/// precision disc for a thumb. The disc slides across in 220ms on an
/// overshoot curve (`Curves.easeOutBack`) while the track and disc recolour.
/// Nothing animates while it is at rest: no idle ticker.
///
/// Tapping the switch toggles it. The two invisible `DAYLIGHT` / `DARK GRADING`
/// labels at either end set that mode directly (and keep the switch addressable
/// by text, for assistive tech and tests).
class ShaderThemeSwitch extends StatefulWidget {
  const ShaderThemeSwitch({super.key, required this.dark, required this.onChanged});

  /// True for Dark Grading, false for Daylight.
  final bool dark;
  final ValueChanged<bool> onChanged;

  static const double width = 76;
  static const double height = 28;
  static const double thumb = 22;
  static const double _inset = 3;

  /// The slide, and the recolour that goes with it.
  static const Duration duration = Duration(milliseconds: 220);

  @override
  State<ShaderThemeSwitch> createState() => _ShaderThemeSwitchState();
}

class _ShaderThemeSwitchState extends State<ShaderThemeSwitch> with SingleTickerProviderStateMixin {
  /// 0 is Dark Grading, 1 is Daylight. Runs only while the switch moves.
  late final AnimationController _toggle = AnimationController(
    vsync: this,
    duration: ShaderThemeSwitch.duration,
    value: widget.dark ? 0 : 1,
  );

  @override
  void didUpdateWidget(ShaderThemeSwitch old) {
    super.didUpdateWidget(old);
    if (old.dark != widget.dark) _toggle.animateTo(widget.dark ? 0 : 1);
  }

  @override
  void dispose() {
    _toggle.dispose();
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
                      child: CustomPaint(painter: _TrackPainter(toggle: _toggle, hovered: hovered)),
                    ),
                  ),
                  _zone(left: 2, label: 'DAYLIGHT', dark: false),
                  _zone(left: ShaderThemeSwitch.width - 28, label: 'DARK GRADING', dark: true),
                  AnimatedBuilder(
                    animation: _toggle,
                    builder: (context, _) {
                      final mix = _toggle.value.clamp(0.0, 1.0);
                      // easeOutBack runs past its end stop before settling:
                      // that overshoot is the thumb's spring.
                      final travel = ShaderThemeSwitch.width - ShaderThemeSwitch.thumb - ShaderThemeSwitch._inset * 2;
                      final x = ShaderThemeSwitch._inset + travel * (1 - Curves.easeOutBack.transform(mix));
                      return Positioned(
                        left: x,
                        top: (ShaderThemeSwitch.height - ShaderThemeSwitch.thumb) / 2,
                        width: ShaderThemeSwitch.thumb,
                        height: ShaderThemeSwitch.thumb,
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            key: const ValueKey('shader-theme-thumb'),
                            child: CustomPaint(painter: _ThumbPainter(mix)),
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

/// The capsule: matte fill, 1px border, and the two etched glyphs.
class _TrackPainter extends CustomPainter {
  _TrackPainter({required this.toggle, required this.hovered}) : super(repaint: toggle);

  final Animation<double> toggle;
  final bool hovered;

  static const _darkFill = Color(0xFF121215);
  static const _darkEdge = Color(0xFF2A2B30);
  static const _darkGlyph = Color(0xFF4A4B55);
  static const _lightFill = Color(0xFFEAEAEF);
  static const _lightEdge = Color(0xFFD4D4DC);
  static const _lightGlyph = Color(0xFFA5A5AE);

  /// Spectral Violet's deep end: the dark track warms toward it on the right.
  static const _violetDeep = Color(0xFF4C1D95);

  @override
  void paint(Canvas canvas, Size size) {
    final light = Curves.easeInOut.transform(toggle.value.clamp(0.0, 1.0));
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2));
    final fill = _mix(_darkFill, _lightFill, light);

    // Dark: obsidian, brightening slightly toward violet on the right. The
    // tint fades out as the track turns to Daylight, which is flat alabaster.
    final tintedEnd = _mix(_darkFill, _violetDeep, 0.5 * (1 - light));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          colors: [fill, fill, _mix(fill, tintedEnd, 1 - light)],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect),
    );

    // The glyphs: an aperture ring on the left, an eclipse slit on the right.
    final glyph = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _mix(_darkGlyph, _lightGlyph, light);
    final y = size.height / 2;
    final ringCentre = Offset(ShaderThemeSwitch._inset + ShaderThemeSwitch.thumb / 2, y);
    final slitX = size.width - ShaderThemeSwitch._inset - ShaderThemeSwitch.thumb / 2;
    canvas.drawCircle(ringCentre, 4.5, glyph);
    canvas.drawLine(Offset(slitX, y - 5), Offset(slitX, y + 5), glyph);

    final edge = _mix(_darkEdge, _lightEdge, light);
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = hovered ? _mix(edge, const Color(0xFF8A2BE2), 0.5) : edge,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.hovered != hovered;
}

/// The thumb: a precision disc with a ring and a centre pip. Violet on a dark
/// disc in Dark Grading; carbon on alabaster in Daylight.
class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.light);

  final double light;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeInOut.transform(light);
    final centre = size.center(Offset.zero);
    final radius = size.width / 2;
    canvas.drawCircle(centre, radius, Paint()..color = _mix(const Color(0xFF1E1F24), const Color(0xFFFFFFFF), t));
    canvas.drawCircle(
      centre,
      radius - 0.75,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _mix(const Color(0xFF8A2BE2), const Color(0xFF0E0E10), t),
    );
    canvas.drawCircle(centre, 2, Paint()..color = _mix(const Color(0xFFB57BFF), const Color(0xFF0E0E10), t));
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => old.light != light;
}
