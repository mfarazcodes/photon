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

/// The Photon mark: a frosted glass prism bending a pale blue beam into a
/// flowing orange-and-coral spectrum, on a deep navy squircle.
///
/// The artwork is `assets/images/photon_logo.png` (a transparent PNG). Its
/// pastels are light, so the tile behind it is dark and saturated: a navy that
/// deepens toward the edges, which makes the blue, coral and amber glow. The
/// beam and the ribbon run off the tile's edges, so the tile crops the artwork
/// in a little ([PhotonLogo.zoom]) to keep the prism large at 16px.
///
/// It is the app's identity, so it does not follow the studio theme: the same
/// tile in Dark Grading and in Daylight Lab, and the same picture as the
/// Windows app icon ([PhotonLogo.paint] draws both).
class PhotonLogoMark extends StatelessWidget {
  const PhotonLogoMark({super.key, this.size = 22, this.semanticLabel});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(PhotonLogo.radius * size);
    // The artwork is laid out [PhotonLogo.zoom] times the tile's side, centred,
    // and the tile clips it: a crop, with no transform layer.
    final art = size * (1 - 2 * PhotonLogo.inset) * PhotonLogo.zoom;
    final mark = SizedBox.square(
      dimension: size,
      child: Padding(
        padding: EdgeInsets.all(PhotonLogo.inset * size),
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: radius, gradient: PhotonLogo.background),
          child: ClipRRect(
            borderRadius: radius,
            child: OverflowBox(
              minWidth: art,
              maxWidth: art,
              minHeight: art,
              maxHeight: art,
              child: Image.asset(
                PhotonLogo.asset,
                width: art,
                height: art,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                // Never a stray error box in a corner of the chrome.
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: mark);
    return Semantics(label: semanticLabel, image: true, child: mark);
  }
}

/// The Photon mark's drawing: one set of numbers for the widget and for the
/// Windows icon, so the two cannot drift apart.
abstract final class PhotonLogo {
  /// The artwork, a transparent PNG.
  static const String asset = 'assets/images/photon_logo.png';

  /// How far the artwork is scaled up inside the tile, about its centre (the
  /// prism's centre), so the prism stays large at 16px.
  static const double zoom = 1.75;

  /// The squircle tile: inset from the canvas edge, and corner radius, as
  /// fractions of the canvas side.
  static const double inset = 0.03;
  static const double radius = 0.22;

  /// Deep navy behind the pastel artwork: lighter behind the prism, darker at
  /// the corners, so the tile has depth without a hard edge.
  static const Color navyCentre = Color(0xFF1B2250);
  static const Color navyEdge = Color(0xFF080A16);

  static const RadialGradient background = RadialGradient(
    center: Alignment(0, 0.05),
    radius: 0.85,
    colors: [navyCentre, navyEdge],
  );

  /// Draws the whole mark at [size], with [art] the decoded artwork.
  static void paint(Canvas canvas, Size size, ui.Image art) {
    final s = size.shortestSide;
    final tile = RRect.fromRectAndRadius(
      Rect.fromLTRB(inset * s, inset * s, (1 - inset) * s, (1 - inset) * s),
      Radius.circular(radius * s),
    );
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = background.createShader(tile.outerRect)
        ..isAntiAlias = true,
    );
    canvas.save();
    canvas.clipRRect(tile, doAntiAlias: true);
    canvas.drawImageRect(
      art,
      Rect.fromLTWH(0, 0, art.width.toDouble(), art.height.toDouble()),
      Rect.fromCenter(center: tile.outerRect.center, width: tile.width * zoom, height: tile.height * zoom),
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true,
    );
    canvas.restore();
  }
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
