import 'dart:math' as math;

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

/// Minimal Photon mark: a Matte Carbon tile, a violet hexagonal aperture ring,
/// an incoming white photon ray from the top-left, and a refracted rose and
/// violet dispersion exiting from a glowing focal point.
///
/// The geometry matches `windows/runner/resources/app_icon.ico`.
///
/// It follows the studio theme: in Dark Studio the tile is Matte Carbon with a
/// white ray; in Daylight Lab the tile inverts to alabaster inside a hairline
/// bezel, with a carbon aperture ring and ray, and saturated violet and rose
/// dispersion. Pass [isDark] to force one.
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
  static const _violet = Color(0xFF8A2BE2);
  static const _beamViolet = Color(0xFFB57BFF);
  static const _rose = Color(0xFFFF2D78);
  static const _alabaster = Color(0xFFF9F9FB);
  static const _bezel = Color(0xFFE2E2E6);

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

    // Tile; in daylight it is framed by a 1px bezel.
    final tile = RRect.fromRectAndRadius(
      Rect.fromLTRB(0.03 * s, 0.03 * s, 0.97 * s, 0.97 * s),
      Radius.circular(0.22 * s),
    );
    canvas.drawRRect(tile, Paint()..color = isDark ? _carbon : _alabaster);
    if (!isDark) {
      canvas.drawRRect(tile.deflate(0.5), stroke(_bezel, 1));
    }

    // Ink for the ring, the incoming ray and the focal core.
    final ink = isDark ? Colors.white : _carbon;

    // Hexagonal aperture ring (flat-top), 1.5px at the default size.
    final ring = Path();
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      final pt = p(0.5 + 0.30 * math.cos(a), 0.5 + 0.30 * math.sin(a));
      i == 0 ? ring.moveTo(pt.dx, pt.dy) : ring.lineTo(pt.dx, pt.dy);
    }
    ring.close();
    canvas.drawPath(ring, stroke(isDark ? _violet : _carbon, math.max(1.5, s * 0.06)));

    final focal = p(0.5, 0.5);
    final beam = math.max(1.0, s * 0.035);
    canvas.drawLine(focal, p(0.87, 0.82), stroke((isDark ? _beamViolet : _violet).withValues(alpha: 0.95), beam));
    canvas.drawLine(focal, p(0.93, 0.58), stroke(_rose.withValues(alpha: 0.95), beam));
    canvas.drawLine(p(0.12, 0.16), focal, stroke(ink, math.max(1.0, s * 0.04)));

    // Focal glow and core.
    final glow = isDark ? const Color(0xFFD9A6FF) : _violet;
    canvas.drawCircle(
      focal,
      0.15 * s,
      Paint()
        ..shader = RadialGradient(
          colors: [glow.withValues(alpha: isDark ? 0.7 : 0.45), glow.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: focal, radius: 0.15 * s)),
    );
    canvas.drawCircle(focal, math.max(1.0, 0.04 * s), Paint()..color = ink);
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
