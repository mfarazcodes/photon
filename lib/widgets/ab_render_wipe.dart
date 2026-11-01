import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// Interactive before/after wipe: raw Monte Carlo samples on the left of the
/// curtain, the denoised render on the right.
///
/// [render] is the clean render surface (Pass B). Pass A is the engine's
/// `raw_frame` when one has arrived; otherwise it is [render] under synthetic
/// path-tracing noise that fades as the render converges.
///
/// [imageWrapper] wraps only the image layers (e.g. false color) so the
/// curtain and its badges are never tinted.
///
/// The curtain follows the pointer's exact X from the moment of the press, so
/// fast movement cannot outrun it. A double tap (judged from raw pointer
/// events, so it never delays the drag) resets it to the middle.
class AbRenderWipe extends StatefulWidget {
  const AbRenderWipe({
    super.key,
    required this.studio,
    required this.render,
    this.imageWrapper,
    this.showCurtain = true,
    this.badgeTop = 10,
    this.onCurtainPointerDown,
  });

  final StudioController studio;
  final Widget render;
  final Widget Function(Widget passes)? imageWrapper;

  /// Told which pointer the curtain claimed, so an enclosing listener (the
  /// stage's focus double-tap) can ignore it. The curtain sees a press first and
  /// may already have moved by the time the enclosing listener runs.
  final ValueChanged<int>? onCurtainPointerDown;

  /// False for the loupe's magnified copy, which must not carry the handle.
  final bool showCurtain;
  final double badgeTop;

  /// Width of the draggable zone around the divider.
  static const double hitZoneWidth = 56;
  static const Key curtainKey = ValueKey('ab-curtain');

  @override
  State<AbRenderWipe> createState() => _AbRenderWipeState();
}

class _AbRenderWipeState extends State<AbRenderWipe> {
  final FastDoubleTap _doubleTap = FastDoubleTap();
  bool _pressed = false;

  StudioController get _studio => widget.studio;

  /// Moves the curtain to the pointer's X within the stage.
  void _splitTo(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.width <= 0) return;
    _studio.setAbSplit(box.globalToLocal(globalPosition).dx / box.size.width);
  }

  void _onDown(PointerDownEvent e) {
    widget.onCurtainPointerDown?.call(e.pointer);
    setState(() => _pressed = true);
    if (_doubleTap.down(e)) {
      _studio.resetAbSplit();
    } else {
      _splitTo(e.position);
    }
  }

  void _onMove(PointerMoveEvent e) {
    _doubleTap.move(e);
    _splitTo(e.position);
  }

  void _onUp(PointerUpEvent e) {
    _doubleTap.up(e);
    setState(() => _pressed = false);
  }

  void _onCancel(PointerCancelEvent e) {
    _doubleTap.cancel();
    setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return ValueListenableBuilder<double>(
          valueListenable: _studio.abSplit,
          builder: (context, split, _) {
            final splitX = w * split;
            final passes = Stack(
              fit: StackFit.expand,
              children: [
                widget.render,
                ClipRect(
                  clipper: _LeftOfClipper(splitX),
                  child: _RawPass(studio: _studio, render: widget.render),
                ),
              ],
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                widget.imageWrapper?.call(passes) ?? passes,
                if (widget.showCurtain) ..._curtain(context, w: w, split: split, splitX: splitX),
              ],
            );
          },
        );
      },
    );
  }

  List<Widget> _curtain(
    BuildContext context, {
    required double w,
    required double split,
    required double splitX,
  }) {
    final t = context.photon;
    final violet = t.colors.violet;
    final label = t.text.mono(size: 8, weight: FontWeight.w600, height: 1.2, color: Colors.white);
    const halo = AbRenderWipe.hitZoneWidth / 2;

    Widget badge(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E10).withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(PhotonRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(text, style: label),
    );

    return [
      // 1.5px divider with a caustic glow.
      Positioned(
        left: splitX - 0.75,
        top: 0,
        bottom: 0,
        width: 1.5,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: violet,
              boxShadow: [BoxShadow(color: violet.withValues(alpha: _pressed ? 0.9 : 0.55), blurRadius: _pressed ? 14 : 8)],
            ),
          ),
        ),
      ),
      // Badges sit just off the divider; they drop out when there is no room.
      if (splitX > 84)
        Positioned(
          right: w - splitX + 10,
          top: widget.badgeTop,
          child: IgnorePointer(child: badge('RAW PT')),
        ),
      if (w - splitX > 120)
        Positioned(
          left: splitX + 10,
          top: widget.badgeTop,
          child: IgnorePointer(child: badge('OIDN DENOISED')),
        ),
      // Full-height hit zone: dragging it moves the curtain, never the camera.
      Positioned(
        left: splitX - halo,
        top: 0,
        bottom: 0,
        width: AbRenderWipe.hitZoneWidth,
        child: Semantics(
          slider: true,
          label: 'A/B render wipe',
          value: '${(split * 100).round()} percent',
          increasedValue: '${((split + 0.05).clamp(0.05, 0.95) * 100).round()} percent',
          decreasedValue: '${((split - 0.05).clamp(0.05, 0.95) * 100).round()} percent',
          onIncrease: () => _studio.setAbSplit(split + 0.05),
          onDecrease: () => _studio.setAbSplit(split - 0.05),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              onPointerCancel: _onCancel,
              // The Listener sets the position; this recognizer exists to win
              // the gesture arena so the stage's orbit pan never also fires.
              child: GestureDetector(
                key: AbRenderWipe.curtainKey,
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: (_) {},
                onPanUpdate: (_) {},
                onPanEnd: (_) {},
                child: Center(child: _Handle(violet: violet, pressed: _pressed)),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

class _LeftOfClipper extends CustomClipper<Rect> {
  const _LeftOfClipper(this.x);

  final double x;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, x, size.height);

  @override
  bool shouldReclip(_LeftOfClipper old) => old.x != x;
}

/// 24x36 Matte Carbon pill with micro-arrows; lights up while pressed.
class _Handle extends StatelessWidget {
  const _Handle({required this.violet, required this.pressed});

  final Color violet;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      width: 24,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: pressed ? Color.alphaBlend(violet.withValues(alpha: 0.35), const Color(0xFF0E0E10)) : const Color(0xFF0E0E10),
        borderRadius: BorderRadius.circular(PhotonRadius.pill),
        border: Border.all(color: violet),
        boxShadow: [
          BoxShadow(
            color: violet.withValues(alpha: pressed ? 0.7 : 0.35),
            blurRadius: pressed ? 18 : 10,
            spreadRadius: pressed ? 2 : -2,
          ),
        ],
      ),
      child: Text(
        '◄|►',
        maxLines: 1,
        softWrap: false,
        style: t.text.mono(size: 7, weight: FontWeight.w700, height: 1, color: Colors.white),
      ),
    );
  }
}

/// Pass A: the engine's raw frame, or the render under synthetic noise.
class _RawPass extends StatelessWidget {
  const _RawPass({required this.studio, required this.render});

  final StudioController studio;
  final Widget render;

  @override
  Widget build(BuildContext context) {
    Widget synthetic() => Semantics(
      label: 'Raw Monte Carlo pass (synthetic noise)',
      child: Stack(
        fit: StackFit.expand,
        children: [
          render,
          IgnorePointer(
            child: CustomPaint(painter: MonteCarloNoisePainter(studio: studio), size: Size.infinite),
          ),
        ],
      ),
    );

    return ValueListenableBuilder<Uint8List?>(
      valueListenable: studio.rawFrame,
      builder: (context, raw, _) {
        if (raw == null) return synthetic();
        return Image.memory(
          raw,
          gaplessPlayback: true,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          semanticLabel: 'Raw Monte Carlo pass',
          errorBuilder: (_, _, _) => synthetic(),
        );
      },
    );
  }
}

/// Deterministic speckle and fireflies that stand in for unfiltered Monte
/// Carlo samples. The pattern is a pure function of the sample count, so it
/// holds still once the render converges, and it fades as convergence rises.
class MonteCarloNoisePainter extends CustomPainter {
  MonteCarloNoisePainter({required this.studio}) : super(repaint: studio.samples);

  final StudioController studio;

  /// Speckle tint layers: color and base opacity.
  static const _layers = <(Color, double)>[
    (Color(0xFFFFFFFF), 0.55),
    (Color(0xFFFFB27A), 0.50),
    (Color(0xFFFF4FD8), 0.45),
    (Color(0xFF4FE0FF), 0.45),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final strength = 1.0 - studio.convergence * 0.75;
    final total = (size.width * size.height / 90).clamp(0, 6000).round();
    final perLayer = total ~/ _layers.length;
    // Re-roll every few samples so accumulation reads as shimmer.
    var state = ((studio.samples.value ~/ 3) * 0x9E3779B1 + 0x85EBCA6B) & 0xFFFFFFFF;
    double next() {
      state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
      return state / 4294967296.0;
    }

    Float32List scatter(int count) {
      final points = Float32List(count * 2);
      for (var i = 0; i < points.length; i += 2) {
        points[i] = next() * size.width;
        points[i + 1] = next() * size.height;
      }
      return points;
    }

    for (final (color, alpha) in _layers) {
      canvas.drawRawPoints(
        PointMode.points,
        scatter(perLayer),
        Paint()
          ..color = color.withValues(alpha: alpha * strength)
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.square,
      );
    }
    // Sparse bright fireflies.
    canvas.drawRawPoints(
      PointMode.points,
      scatter((total / 60).round()),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9 * strength)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.square,
    );
  }

  @override
  bool shouldRepaint(MonteCarloNoisePainter old) => old.studio != studio;
}
