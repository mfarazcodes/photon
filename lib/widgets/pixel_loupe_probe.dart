import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';

/// Render space the probe reports coordinates in (4K).
const Size kRenderSpace = Size(3840, 2160);

/// The viewport shows the render with `BoxFit.cover`, so the full image is
/// this rect (possibly larger than the stage) centered on the stage.
Rect renderCoverRect(Size stage) {
  final aspect = kRenderSpace.width / kRenderSpace.height;
  final Size fitted = stage.width / stage.height > aspect
      ? Size(stage.width, stage.width / aspect)
      : Size(stage.height * aspect, stage.height);
  return Rect.fromCenter(
    center: stage.center(Offset.zero),
    width: fitted.width,
    height: fitted.height,
  );
}

/// Maps a stage position, normalized 0..1, to render-space UV (0..1).
Offset renderUv(Offset normalized, Size stage) {
  final rect = renderCoverRect(stage);
  final local = Offset(normalized.dx * stage.width, normalized.dy * stage.height);
  return Offset(
    ((local.dx - rect.left) / rect.width).clamp(0.0, 1.0).toDouble(),
    ((local.dy - rect.top) / rect.height).clamp(0.0, 1.0).toDouble(),
  );
}

/// Linear radiance at a probe point.
@immutable
class RadianceSample {
  const RadianceSample(this.r, this.g, this.b);

  final double r;
  final double g;
  final double b;

  double get luminance => 0.2126 * r + 0.7152 * g + 0.0722 * b;

  /// Brightest channel; this is what clips first.
  double get peak => math.max(r, math.max(g, b));

  bool get clipped => peak > 1.0;

  /// Display-referred IRE, allowing the usual 109 IRE headroom.
  int get ire => (luminance.clamp(0.0, 1.09) * 100).round();

  /// Stops relative to 18% gray.
  double get ev => luminance <= 0 ? -9.9 : math.log(luminance / 0.18) / math.ln2;
}

/// Synthesizes a deterministic radiance value for [uv].
///
/// This is not a pixel read-back: it is a smooth field driven by the UV, the
/// IOR and the caustics energy so the probe responds as you move the pointer or
/// scrub those parameters. Swap in real engine sampling when it is available.
RadianceSample sampleRadiance({
  required Offset uv,
  required double ior,
  required double causticsEnergy,
}) {
  double wave(double phase) => 0.5 + 0.5 * math.sin(phase);
  final w1 = wave(uv.dx * 9.0 + uv.dy * 5.0 + ior * 3.0);
  // Energy only scales brightness (via gain). Letting it shift a wave's phase
  // would let more energy darken a pixel, which no caustics control should.
  final w2 = wave(uv.dx * 4.0 - uv.dy * 11.0 + 2.0);
  final w3 = wave((uv.dx + uv.dy) * 7.0 - ior * 1.7);
  final gain = 0.55 + 0.45 * causticsEnergy;
  return RadianceSample(
    (0.08 + 1.20 * math.pow(w1, 1.5)) * gain,
    (0.05 + 0.95 * w2 * w3) * gain,
    (0.10 + 1.15 * math.pow(w3, 1.2)) * gain,
  );
}

/// Anchors of the false-color exposure scale.
abstract final class IreScale {
  static const Color blue = Color(0xFF0000FF);
  static const Color cyanGreen = Color(0xFF00FFB3);
  static const Color yellow = Color(0xFFFFFF02);
  static const Color clip = Color(0xFFFF2D78);

  /// Luma where each anchor sits (0..1 of full scale).
  static const double mid = 0.18;
  static const double high = 0.70;
  static const double clipAt = 0.98;
}

/// Paints [child] in false-color luminance bands.
///
/// Rendered as two chained color-matrix passes rather than a fragment shader,
/// so it works on every renderer (`ImageFilter.shader` is Impeller-only).
/// Pass one turns luma into three clamped ramps; each ramp is one segment of
/// the scale. Pass two mixes the ramps into the anchor colors of [IreScale]:
///
/// * `u1 = clamp(L / 0.18)`, `u2 = clamp((L - 0.18) / 0.52)`,
///   `u3 = clamp((L - 0.70) / 0.28)`
/// * `R = u2`, `G = u1 - 0.8235 u3`, `B = 1 - 0.3 u1 - 0.6922 u2 + 0.4628 u3`
///
/// which runs blue → cyan/green (18%) → yellow (70 IRE) → rose (98+ IRE).
class FalseColorShaderWrapper extends StatelessWidget {
  const FalseColorShaderWrapper({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  static const double _lr = 0.2126;
  static const double _lg = 0.7152;
  static const double _lb = 0.0722;

  /// Pass one: RGB → (u1, u2, u3). Offsets are in 0..255 units.
  static const ColorFilter lumaRamps = ColorFilter.matrix(<double>[
    _lr / 0.18, _lg / 0.18, _lb / 0.18, 0, 0, //
    _lr / 0.52, _lg / 0.52, _lb / 0.52, 0, -0.18 / 0.52 * 255,
    _lr / 0.28, _lg / 0.28, _lb / 0.28, 0, -0.70 / 0.28 * 255,
    0, 0, 0, 1, 0,
  ]);

  /// Pass two: (u1, u2, u3) → anchor colors.
  static const ColorFilter rampsToColor = ColorFilter.matrix(<double>[
    0, 1, 0, 0, 0, //
    1, 0, -0.82353, 0, 0,
    -0.3, -0.69216, 0.46275, 0, 255,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return ColorFiltered(
      colorFilter: rampsToColor,
      child: ColorFiltered(colorFilter: lumaRamps, child: child),
    );
  }
}

/// Bottom-center legend for the false-color scale.
class IreExposureLegend extends StatelessWidget {
  const IreExposureLegend({super.key});

  static const double width = 280;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final label = t.text.mono(size: 8, height: 1.2, color: Colors.white.withValues(alpha: 0.8));

    Widget tick(double fraction, String text) => Positioned(
      left: fraction * width,
      top: 0,
      child: FractionalTranslation(translation: const Offset(-0.5, 0), child: Text(text, style: label)),
    );

    return Semantics(
      label: 'False color exposure scale: 0 IRE blue, 18 percent cyan green, 70 IRE yellow, '
          '100 plus IRE clip rose',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md, vertical: PhotonSpace.sm - 2),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E10).withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(PhotonRadius.window),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(PhotonRadius.pill),
                  gradient: const LinearGradient(
                    colors: [
                      IreScale.blue,
                      IreScale.cyanGreen,
                      IreScale.yellow,
                      IreScale.clip,
                      IreScale.clip,
                    ],
                    stops: [0, IreScale.mid, IreScale.high, IreScale.clipAt, 1],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 11,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(left: 0, top: 0, child: Text('0 IRE', style: label)),
                    tick(IreScale.mid, '18%'),
                    tick(IreScale.high, '70 IRE'),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Text('100+ IRE CLIP', style: label.copyWith(color: IreScale.clip)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 8x magnifier that follows the pointer, with a telemetry read-out.
///
/// [magnifiedContent] must be the stage's image layers laid out at
/// [stageSize]; the lens scales that same subtree, so whatever the stage shows
/// (wipe, false color, parallax) is what the lens shows.
class PixelLoupeOverlay extends StatelessWidget {
  const PixelLoupeOverlay({
    super.key,
    required this.studio,
    required this.stageSize,
    required this.magnifiedContent,
  });

  final StudioController studio;
  final Size stageSize;
  final Widget magnifiedContent;

  static const double lensDiameter = 136;
  static const double zoom = 8;
  static const double readoutWidth = 196;
  static const double readoutHeight = 58;
  static const double gap = 6;
  static const double columnHeight = lensDiameter + gap + readoutHeight;
  static const double cursorOffset = 22;
  static const double margin = 4;

  /// Top-left of the lens column for a pointer at [p], kept inside the stage.
  static Offset placement(Offset p, Size stage) {
    var x = p.dx + cursorOffset;
    if (x + readoutWidth > stage.width - margin) x = p.dx - cursorOffset - readoutWidth;
    var y = p.dy + cursorOffset;
    if (y + columnHeight > stage.height - margin) y = p.dy - cursorOffset - columnHeight;
    return Offset(
      x.clamp(margin, math.max(margin, stage.width - readoutWidth - margin)).toDouble(),
      y.clamp(margin, math.max(margin, stage.height - columnHeight - margin)).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset?>(
      valueListenable: studio.probePosition,
      builder: (context, normalized, _) {
        if (normalized == null) return const SizedBox.shrink();
        final pointer = Offset(normalized.dx * stageSize.width, normalized.dy * stageSize.height);
        final origin = placement(pointer, stageSize);
        final uv = renderUv(normalized, stageSize);
        final sample = sampleRadiance(
          uv: uv,
          ior: studio.param('ior'),
          causticsEnergy: studio.param('caustics_energy'),
        );
        return IgnorePointer(
          child: Stack(
            children: [
              Positioned(
                left: origin.dx,
                top: origin.dy,
                width: readoutWidth,
                child: Column(
                  key: const ValueKey('pixel-loupe'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Lens(pointer: pointer, stageSize: stageSize, content: magnifiedContent),
                    const SizedBox(height: gap),
                    _Readout(uv: uv, sample: sample),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Lens extends StatelessWidget {
  const _Lens({required this.pointer, required this.stageSize, required this.content});

  final Offset pointer;
  final Size stageSize;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    const d = PixelLoupeOverlay.lensDiameter;
    const half = d / 2;
    final matrix = Matrix4.translationValues(half, half, 0) *
        Matrix4.diagonal3Values(PixelLoupeOverlay.zoom, PixelLoupeOverlay.zoom, 1) *
        Matrix4.translationValues(-pointer.dx, -pointer.dy, 0);
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: const Color(0xFF0E0E10), child: const SizedBox.expand()),
            OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: stageSize.width,
              maxWidth: stageSize.width,
              minHeight: stageSize.height,
              maxHeight: stageSize.height,
              child: Transform(transform: matrix, child: content),
            ),
            const CustomPaint(painter: _LoupeGridPainter()),
          ],
        ),
      ),
    );
  }
}

/// 8x8 sub-pixel grid (each cell is one source pixel) and the center reticle.
class _LoupeGridPainter extends CustomPainter {
  const _LoupeGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = PixelLoupeOverlay.zoom;
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    for (var p = 0.0; p <= size.width; p += cell) {
      canvas.drawLine(Offset(p + 0.5, 0), Offset(p + 0.5, size.height), grid);
    }
    for (var p = 0.0; p <= size.height; p += cell) {
      canvas.drawLine(Offset(0, p + 0.5), Offset(size.width, p + 0.5), grid);
    }
    // The cell under the pointer sits at the lens center.
    final mid = size.center(Offset.zero);
    final reticle = Rect.fromCenter(center: mid, width: cell, height: cell);
    canvas.drawRect(
      reticle.inflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.7),
    );
    canvas.drawRect(
      reticle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_LoupeGridPainter old) => false;
}

class _Readout extends StatelessWidget {
  const _Readout({required this.uv, required this.sample});

  final Offset uv;
  final RadianceSample sample;

  static Widget _fit(Widget text) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: text);

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final base = t.text.mono(size: 9, height: 1.25, color: Colors.white.withValues(alpha: 0.9));
    final x = (uv.dx * kRenderSpace.width).round().clamp(0, kRenderSpace.width.toInt() - 1);
    final y = (uv.dy * kRenderSpace.height).round().clamp(0, kRenderSpace.height.toInt() - 1);
    final clipped = sample.clipped;
    final ev = sample.ev;
    final evText = '${ev >= 0 ? '+' : '−'}${ev.abs().toStringAsFixed(1)} EV';
    final exposure = base.copyWith(
      color: clipped ? IreScale.clip : base.color,
      fontWeight: FontWeight.w600,
    );

    return Container(
      width: PixelLoupeOverlay.readoutWidth,
      height: PixelLoupeOverlay.readoutHeight,
      padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E10).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(PhotonRadius.window + 2),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        // Each line scales down rather than overflow if the font is wider
        // than JetBrains Mono (e.g. a fallback while fonts load offline).
        children: [
          Row(
            children: [
              Expanded(child: _fit(Text('XY: ($x, $y)', style: base))),
              // The radiance below is synthesized, not read from the render.
              Text('SYNTH', style: base.copyWith(fontSize: 7, color: Colors.white.withValues(alpha: 0.4))),
            ],
          ),
          _fit(
            Text(
              'R: ${sample.r.toStringAsFixed(2)}  G: ${sample.g.toStringAsFixed(2)}  '
              'B: ${sample.b.toStringAsFixed(2)} cd/m²',
              maxLines: 1,
              style: base,
            ),
          ),
          Row(
            children: [
              Flexible(child: _fit(Text('IRE: ${sample.ire} · $evText', style: exposure))),
              if (clipped) ...[
                const SizedBox(width: PhotonSpace.sm - 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: IreScale.clip.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(PhotonRadius.control - 2),
                    border: Border.all(color: IreScale.clip.withValues(alpha: 0.6)),
                  ),
                  child: Text('CLIP', style: exposure.copyWith(fontSize: 8, height: 1.4)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
