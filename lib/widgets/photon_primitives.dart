import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/photon_theme.dart';

/// Rebuilds with the pointer-hover state of its region.
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.basic,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.cursor,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(context, _hovered),
  );
}

/// Status pip that fades in and out (the 4px "computing" indicator).
class FlashingPip extends StatefulWidget {
  const FlashingPip({super.key, required this.color, this.size = 4, this.flash = true});

  final Color color;
  final double size;
  final bool flash;

  @override
  State<FlashingPip> createState() => _FlashingPipState();
}

class _FlashingPipState extends State<FlashingPip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.flash) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(FlashingPip old) {
    super.didUpdateWidget(old);
    if (widget.flash && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.flash && _c.isAnimating) {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_c),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Static round pip.
class Pip extends StatelessWidget {
  const Pip({super.key, required this.color, this.size = 6, this.glow = false});

  final Color color;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: glow ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)] : null,
    ),
  );
}

/// HUD capsule: full pill radius, hairline border, Level-2 shadow.
class PillCapsule extends StatelessWidget {
  const PillCapsule({
    super.key,
    required this.child,
    this.height = 28,
    this.padding = const EdgeInsets.symmetric(horizontal: PhotonSpace.md),
    this.background,
    this.borderColor,
    this.shadow = true,
  });

  final Widget child;
  final double height;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Color? borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Container(
      height: height,
      padding: padding,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? t.colors.substrate,
        borderRadius: BorderRadius.circular(PhotonRadius.pill),
        border: Border.all(color: borderColor ?? t.colors.border),
        boxShadow: shadow ? t.level2 : null,
      ),
      child: child,
    );
  }
}

/// Primary studio action: Matte Carbon fill, hover lift, 0.98 press scale.
class PhotonButton extends StatefulWidget {
  const PhotonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.trailing,
    this.height = 28,
    this.radius = PhotonRadius.pill,
    this.mono = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? trailing;
  final double height;
  final double radius;

  /// Label-caps styling (HUD buttons) rather than Geist 12px medium.
  final bool mono;

  @override
  State<PhotonButton> createState() => _PhotonButtonState();
}

class _PhotonButtonState extends State<PhotonButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final fill = _hover
        ? Color.alphaBlend(c.onCarbon.withValues(alpha: 0.14), c.carbon)
        : c.carbon;
    final style = widget.mono
        ? t.text.labelCaps.copyWith(color: c.onCarbon, fontWeight: FontWeight.w600)
        : t.text.buttonLabel.copyWith(color: c.onCarbon);
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _down ? 0.98 : 1,
            duration: const Duration(milliseconds: 90),
            child: Container(
              height: widget.height,
              padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(widget.radius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.label.toUpperCase(), style: style),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: PhotonSpace.xs),
                    widget.trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The three macOS window-control pips, wired to window actions.
///
/// Red resets the panel, yellow collapses it to its titlebar, green maximizes
/// it. As on macOS, the glyphs appear when the pointer is over the group. A
/// pip with no callback is inert. [id] namespaces the test keys
/// (`pip-close-<id>`, `pip-minimize-<id>`, `pip-zoom-<id>`).
class MacWindowPips extends StatelessWidget {
  const MacWindowPips({
    super.key,
    this.id = 'window',
    this.size = 12,
    this.onClose,
    this.onMinimize,
    this.onZoom,
  });

  final String id;
  final double size;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onZoom;

  static const _close = Color(0xFFFF5F56);
  static const _minimize = Color(0xFFFFBD2E);
  static const _zoom = Color(0xFF27C93F);

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (context, hovered) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WindowPip(
            key: ValueKey('pip-close-$id'),
            color: _close,
            glyph: '×',
            tooltip: 'Reset panel',
            size: size,
            showGlyph: hovered,
            onTap: onClose,
          ),
          _WindowPip(
            key: ValueKey('pip-minimize-$id'),
            color: _minimize,
            glyph: '−',
            tooltip: 'Collapse / expand panel',
            size: size,
            showGlyph: hovered,
            onTap: onMinimize,
          ),
          _WindowPip(
            key: ValueKey('pip-zoom-$id'),
            color: _zoom,
            glyph: '+',
            tooltip: 'Maximize / focus panel',
            size: size,
            showGlyph: hovered,
            onTap: onZoom,
          ),
        ],
      ),
    );
  }
}

/// One pip. The hit area is the pip plus its share of the gap, and the full
/// titlebar height, so neighbouring pips leave no dead space.
class _WindowPip extends StatelessWidget {
  const _WindowPip({
    super.key,
    required this.color,
    required this.glyph,
    required this.tooltip,
    required this.size,
    required this.showGlyph,
    required this.onTap,
  });

  final Color color;
  final String glyph;
  final String tooltip;
  final double size;
  final bool showGlyph;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black.withValues(alpha: 0.12), width: 0.5),
                ),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 90),
                  opacity: showGlyph && enabled ? 1 : 0,
                  child: Text(
                    glyph,
                    style: TextStyle(
                      fontSize: size * 0.8,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Photon mark: a relativistic prism and caustic aperture.
///
/// On a squircle tile, a tilted photon ring (violet, magenta, rose, cyan; razor
/// thin at the upper left, fattest on the Doppler-beamed lower right) holds a
/// diamond prism. Collimated light enters it from the upper left and leaves as
/// a fanned spectral wedge, and a four-point specular starburst marks the focal
/// nexus.
///
/// It follows the studio theme: in Dark Studio the tile is Matte Carbon with a
/// soft obsidian depth; in Daylight Lab it is alabaster inside a hairline
/// bezel, with carbon ink. Pass [isDark] to force one.
class PhotonLogoMark extends StatelessWidget {
  const PhotonLogoMark({super.key, this.size = 22, this.semanticLabel, this.isDark});

  final double size;
  final String? semanticLabel;
  final bool? isDark;

  @override
  Widget build(BuildContext context) {
    final dark = isDark ?? Theme.of(context).brightness == Brightness.dark;
    final mark = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _PhotonLogoPainter(isDark: dark)),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: mark);
    return Semantics(label: semanticLabel, image: true, child: mark);
  }
}

class _PhotonLogoPainter extends CustomPainter {
  const _PhotonLogoPainter({required this.isDark});

  final bool isDark;

  static const _carbon = Color(0xFF0E0E10);
  static const _obsidian = Color(0xFF1B1C24);
  static const _violet = Color(0xFF8A2BE2);
  static const _magenta = Color(0xFFE879F9);
  static const _rose = Color(0xFFFF2D78);
  static const _cyan = Color(0xFF22D3EE);
  static const _alabaster = Color(0xFFF9F9FB);
  static const _bezel = Color(0xFFE2E2E6);

  /// The photon ring is tilted this far (radians): a relativistic disk seen
  /// from a little above the plane.
  static const double _tilt = -25 * math.pi / 180;

  /// The intersection of the ray `origin + t * dir` with the segment `a`-`b`,
  /// or null when they do not meet.
  static Offset? _hit(Offset origin, Offset dir, Offset a, Offset b) {
    final e = b - a;
    final denom = dir.dx * e.dy - dir.dy * e.dx;
    if (denom.abs() < 1e-9) return null;
    final w = a - origin;
    final t = (w.dx * e.dy - w.dy * e.dx) / denom;
    final u = (w.dx * dir.dy - w.dy * dir.dx) / denom;
    if (t < 0 || u < 0 || u > 1) return null;
    return origin + dir * t;
  }

  /// A four-point anisotropic starburst: long horizontal arms, shorter vertical
  /// ones, concave sides, and tips that taper to a razor point.
  static Path _star(Offset c, double rx, double ry, double waist) => Path()
    ..moveTo(c.dx, c.dy - ry)
    ..quadraticBezierTo(c.dx + waist, c.dy - waist, c.dx + rx, c.dy)
    ..quadraticBezierTo(c.dx + waist, c.dy + waist, c.dx, c.dy + ry)
    ..quadraticBezierTo(c.dx - waist, c.dy + waist, c.dx - rx, c.dy)
    ..quadraticBezierTo(c.dx - waist, c.dy - waist, c.dx, c.dy - ry)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    Offset p(double x, double y) => Offset(x * s, y * s);
    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final hair = math.max(1.0, s * 0.03);
    final ink = isDark ? Colors.white : _carbon;

    // Squircle chassis. Dark: Matte Carbon with a soft obsidian depth behind
    // the mark. Daylight: alabaster inside a 1px bezel.
    final tile = RRect.fromRectAndRadius(
      Rect.fromLTRB(0.03 * s, 0.03 * s, 0.97 * s, 0.97 * s),
      Radius.circular(0.22 * s),
    );
    canvas.drawRRect(tile, Paint()..color = isDark ? _carbon : _alabaster);
    if (isDark) {
      canvas.drawRRect(
        tile,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, -0.1),
            radius: 0.8,
            colors: [_obsidian.withValues(alpha: 0.95), _carbon.withValues(alpha: 0)],
          ).createShader(tile.outerRect),
      );
    } else {
      canvas.drawRRect(tile.deflate(0.5), stroke(_bezel, 1));
    }

    final focal = p(0.5, 0.5);

    // The photon ring: a tilted annulus whose inner edge is pushed toward the
    // upper left, so it is a razor-thin line there and fattest on the
    // Doppler-beamed lower-right crescent. A sweep gradient takes it through
    // violet, magenta, rose and cyan.
    canvas.save();
    canvas.translate(focal.dx, focal.dy);
    canvas.rotate(_tilt);
    final outer = Path()..addOval(Rect.fromCenter(center: Offset.zero, width: 0.70 * s, height: 0.46 * s));
    final inner = Path()
      ..addOval(Rect.fromCenter(center: Offset(-0.048 * s, -0.030 * s), width: 0.56 * s, height: 0.368 * s));
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, inner),
      Paint()
        ..isAntiAlias = true
        ..shader = SweepGradient(
          // Rose sits at about 65 degrees in the ring's own frame: lower right.
          transform: const GradientRotation(65 * math.pi / 180),
          colors: const [_rose, _cyan, _violet, _magenta, _rose],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 0.35 * s)),
    );
    canvas.restore();

    // The prism: a diamond facet core.
    final top = p(0.50, 0.385);
    final right = p(0.585, 0.50);
    final bottom = p(0.50, 0.615);
    final left = p(0.415, 0.50);
    final prism = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(left.dx, left.dy)
      ..close();

    // Incoming collimated light: three parallel rays meeting the left faces.
    const dir = Offset(1, 0.42);
    for (var k = -1; k <= 1; k++) {
      final start = p(0.05, 0.27 + k * 0.05);
      final hit = _hit(start, dir, top, left) ?? _hit(start, dir, left, bottom);
      if (hit == null) continue;
      canvas.drawLine(start, hit, stroke(ink.withValues(alpha: k == 0 ? 0.95 : 0.4), k == 0 ? hair * 1.2 : hair * 0.8));
    }

    canvas.drawPath(prism, Paint()..color = (isDark ? Colors.white : _violet).withValues(alpha: isDark ? 0.1 : 0.08));
    canvas.drawPath(prism, stroke(ink.withValues(alpha: 0.92), hair));
    // Facets: a lit upper-left face and the table line across the middle.
    canvas.drawPath(
      Path()
        ..moveTo(top.dx, top.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(focal.dx, focal.dy)
        ..close(),
      Paint()..color = (isDark ? Colors.white : _violet).withValues(alpha: isDark ? 0.22 : 0.16),
    );
    canvas.drawLine(left, right, stroke(ink.withValues(alpha: 0.5), hair * 0.7));

    // The beam leaves the right face as a fanned spectral wedge.
    final exit = Offset.lerp(top, right, 0.5)!;
    final fanTop = p(0.91, 0.36);
    final fanBottom = p(0.93, 0.76);
    final wedge = Path()
      ..moveTo(exit.dx, exit.dy)
      ..lineTo(fanTop.dx, fanTop.dy)
      ..lineTo(fanBottom.dx, fanBottom.dy)
      ..close();
    canvas.drawPath(
      wedge,
      Paint()
        ..shader = ui.Gradient.linear(
          fanTop,
          fanBottom,
          [_rose, _magenta, _violet, _cyan].map((c) => c.withValues(alpha: 0.9)).toList(),
          const [0.0, 0.34, 0.68, 1.0],
        ),
    );
    for (var i = 0; i < 4; i++) {
      final end = Offset.lerp(fanTop, fanBottom, (i + 0.5) / 4)!;
      canvas.drawLine(exit, end, stroke(Colors.white.withValues(alpha: isDark ? 0.55 : 0.7), hair * 0.5));
    }

    // The focal nexus: a glow, and a crisp 4-point specular starburst.
    final glow = isDark ? const Color(0xFFD9A6FF) : _violet;
    canvas.drawCircle(
      focal,
      0.17 * s,
      Paint()
        ..shader = RadialGradient(
          colors: [glow.withValues(alpha: isDark ? 0.65 : 0.4), glow.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: focal, radius: 0.17 * s)),
    );
    canvas.drawPath(_star(focal, 0.21 * s, 0.15 * s, 0.022 * s), Paint()..color = ink..isAntiAlias = true);
    canvas.drawCircle(focal, math.max(0.8, 0.028 * s), Paint()..color = isDark ? _carbon : Colors.white);
  }

  @override
  bool shouldRepaint(_PhotonLogoPainter old) => old.isDark != isDark;
}

/// Double-tap detection from raw pointer events.
///
/// Flutter's `DoubleTapGestureRecognizer` holds a pointer in the gesture arena
/// until the second tap can no longer arrive, which delays drags that share the
/// widget. This watches pointers directly instead, so nothing is held back.
///
/// Only a press that stayed put and was released quickly counts as a tap, so a
/// drag followed straight away by another drag is never mistaken for a double
/// tap. Timestamps come from the pointer events themselves.
class FastDoubleTap {
  static const Duration window = Duration(milliseconds: 260);
  static const double slop = 8;

  Duration? _lastTapUp;
  Duration? _downAt;
  Offset? _downPosition;
  bool _moved = false;
  bool _completedDouble = false;

  /// Call on pointer-down. Returns true when this press completes a double tap.
  bool down(PointerDownEvent event) {
    final last = _lastTapUp;
    _lastTapUp = null;
    _downAt = event.timeStamp;
    _downPosition = event.position;
    _moved = false;
    _completedDouble = last != null && event.timeStamp - last <= window;
    return _completedDouble;
  }

  void move(PointerMoveEvent event) {
    final origin = _downPosition;
    if (origin != null && (event.position - origin).distance > slop) _moved = true;
  }

  void up(PointerUpEvent event) {
    final at = _downAt;
    if (!_completedDouble && !_moved && at != null && event.timeStamp - at <= window) {
      _lastTapUp = event.timeStamp;
    }
    _downAt = null;
  }

  void cancel() => _downAt = null;
}

/// 32px floating-window titlebar with a 1px hairline divider underneath.
class MacTitlebar extends StatelessWidget {
  const MacTitlebar({super.key, required this.title, this.leading, this.trailing, this.titleSuffix});

  final String title;
  final Widget? leading;
  final Widget? trailing;
  final Widget? titleSuffix;

  static const double height = 32;

  /// Space reserved either side of the title: the three pips plus a margin.
  static const double titleClearance = 70;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.colors.border)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: leading ?? const MacWindowPips(),
          ),
          // Kept clear of the pips on the left (and a matching margin on the
          // right): in a narrow window the title scales down instead of
          // sliding over the window controls.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: titleClearance),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: t.text.telemetrySm.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  if (titleSuffix != null) ...[
                    const SizedBox(width: PhotonSpace.sm),
                    titleSuffix!,
                  ],
                ],
              ),
            ),
          ),
          if (trailing != null) Align(alignment: Alignment.centerRight, child: trailing),
        ],
      ),
    );
  }
}
