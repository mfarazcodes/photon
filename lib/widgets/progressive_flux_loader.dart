import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/photon_theme.dart';

/// Text that flies in one character at a time: each glyph rises from +10px,
/// fades from 0 and un-blurs from 4px, 18ms after the one before it. Giving it
/// new [text] plays the whole line again.
class StaggeredLetterText extends StatefulWidget {
  const StaggeredLetterText({
    super.key,
    required this.text,
    required this.style,
    this.stagger = const Duration(milliseconds: 18),
    this.letterDuration = const Duration(milliseconds: 260),
  });

  final String text;
  final TextStyle style;

  /// Delay between one character starting and the next.
  final Duration stagger;

  /// How long each character takes to settle.
  final Duration letterDuration;

  /// Total time for [text] to finish.
  Duration get totalDuration => stagger * math.max(0, text.length - 1) + letterDuration;

  @override
  State<StaggeredLetterText> createState() => _StaggeredLetterTextState();
}

class _StaggeredLetterTextState extends State<StaggeredLetterText> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.totalDuration)..forward();

  @override
  void didUpdateWidget(StaggeredLetterText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _c.duration = widget.totalDuration;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chars = widget.text.characters.toList();
    final totalMs = widget.totalDuration.inMilliseconds.toDouble();
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final nowMs = _c.value * totalMs;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < chars.length; i++)
                _letter(chars[i], ((nowMs - i * widget.stagger.inMilliseconds) / widget.letterDuration.inMilliseconds).clamp(0.0, 1.0)),
            ],
          );
        },
      ),
    );
  }

  Widget _letter(String ch, double raw) {
    final p = Curves.easeOutCubic.transform(raw);
    Widget glyph = Text(ch, style: widget.style, softWrap: false);
    final blur = 4 * (1 - p);
    if (blur > 0.05) {
      glyph = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: glyph);
    }
    return Opacity(
      opacity: p,
      child: Transform.translate(offset: Offset(0, 10 * (1 - p)), child: glyph),
    );
  }
}

/// A floating HUD card for ingest and compile work: a plasma-gradient progress
/// bar with a bright photon flare at its tip and a shimmer wave across the
/// fill, the current phase flying in letter by letter, and tabular readouts.
class ProgressiveFluxLoader extends StatelessWidget {
  const ProgressiveFluxLoader({
    super.key,
    required this.fileName,
    required this.progress,
    required this.phaseLabel,
    required this.phaseIndex,
    required this.phaseCount,
    this.sizeMb,
    this.animate = true,
  });

  final String fileName;

  /// 0 to 1.
  final double progress;
  final String phaseLabel;
  final int phaseIndex;
  final int phaseCount;
  final double? sizeMb;

  /// False freezes the shimmer wave (tests).
  final bool animate;

  /// Spectral Violet, Magenta, Caustic Rose, Cyan.
  static const List<Color> fluxColors = [Color(0xFF8A2BE2), Color(0xFFE879F9), Color(0xFFFF2D78), Color(0xFF22D3EE)];

  static const double width = 440;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final percent = (progress.clamp(0.0, 1.0) * 100).floor();
    final label = '${percent.toString().padLeft(2, '0')}%';
    final done = progress >= 1.0;

    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Ingesting $fileName, $percent percent. $phaseLabel',
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(PhotonSpace.md, PhotonSpace.md - 2, PhotonSpace.md, PhotonSpace.md),
        decoration: BoxDecoration(
          color: c.dock.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.isDark ? Colors.white.withValues(alpha: 0.14) : c.border),
          boxShadow: [
            BoxShadow(color: fluxColors[0].withValues(alpha: 0.28), blurRadius: 30, spreadRadius: -8),
            ...t.level2,
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Flexible(
                  child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: fluxColors[0].withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(PhotonRadius.control),
                    border: Border.all(color: fluxColors[0].withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.insert_drive_file_outlined, size: 10, color: c.violetInk),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          fileName,
                          key: const Key('flux-file-badge'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.text.labelCaps.copyWith(fontSize: 8.5, color: c.violetInk, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (sizeMb != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${sizeMb!.toStringAsFixed(1)} MB',
                          style: t.text.labelCaps.copyWith(fontSize: 8, color: c.onDock.withValues(alpha: 0.6)),
                        ),
                      ],
                    ],
                  ),
                  ),
                ),
                const SizedBox(width: PhotonSpace.sm),
                Flexible(
                  child: Text(
                    '1.42 GB/s · PCIe 5.0 DMA',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.labelCaps.copyWith(fontSize: 8, color: c.onDock.withValues(alpha: 0.55)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: PhotonSpace.md - 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: StaggeredLetterText(
                        key: const Key('flux-phase-label'),
                        text: phaseLabel,
                        style: t.text.labelCaps.copyWith(fontSize: 10, color: c.onDock, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: PhotonSpace.sm),
                Text(
                  label,
                  key: const Key('flux-percent'),
                  style: t.text.mono(size: 18, weight: FontWeight.w700, height: 1, color: done ? fluxColors[3] : c.onDock),
                ),
              ],
            ),
            const SizedBox(height: PhotonSpace.sm),
            _FluxBar(progress: progress, animate: animate),
            const SizedBox(height: PhotonSpace.sm - 1),
            Row(
              children: [
                Text(
                  'PHASE ${phaseIndex + 1}/$phaseCount',
                  style: t.text.labelCaps.copyWith(fontSize: 7.5, color: c.onDock.withValues(alpha: 0.5)),
                ),
                const Spacer(),
                Text(
                  done ? 'FIRST LIGHT READY' : 'STREAMING TO GPU',
                  style: t.text.labelCaps.copyWith(fontSize: 7.5, color: c.onDock.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FluxBar extends StatefulWidget {
  const _FluxBar({required this.progress, required this.animate});

  final double progress;
  final bool animate;

  @override
  State<_FluxBar> createState() => _FluxBarState();
}

class _FluxBarState extends State<_FluxBar> with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
    value: 0.4,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _shimmer.repeat();
  }

  @override
  void didUpdateWidget(_FluxBar old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_shimmer.isAnimating) {
      _shimmer.repeat();
    } else if (!widget.animate && _shimmer.isAnimating) {
      _shimmer.stop();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    const barHeight = 8.0;
    return SizedBox(
      height: 20,
      child: LayoutBuilder(
        builder: (context, box) {
          // The fill glides between the controller's 100ms steps.
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(end: widget.progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 140),
            builder: (context, p, _) {
              final fillWidth = box.maxWidth * p;
              final tip = Color.lerp(ProgressiveFluxLoader.fluxColors[1], ProgressiveFluxLoader.fluxColors[3], p)!;
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Positioned.fill(
                    child: Center(
                      child: SizedBox(
                        height: barHeight,
                        child: CustomPaint(
                          key: const Key('flux-bar'),
                          size: Size(box.maxWidth, barHeight),
                          painter: _FluxBarPainter(
                            progress: p,
                            shimmer: _shimmer,
                            trackColor: c.onDock.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // The leading-edge photon flare.
                  if (p > 0.005)
                    Positioned(
                      left: fillWidth - 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [BoxShadow(color: tip, blurRadius: 16, spreadRadius: 2)],
                        ),
                        child: const SizedBox(width: 4, height: 10),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _FluxBarPainter extends CustomPainter {
  _FluxBarPainter({required this.progress, required this.shimmer, required this.trackColor}) : super(repaint: shimmer);

  final double progress;
  final Animation<double> shimmer;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, radius), Paint()..color = trackColor);
    final fillWidth = size.width * progress;
    if (fillWidth <= 0.5) return;

    final fill = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fillWidth, size.height), radius);
    canvas.save();
    canvas.clipRRect(fill);
    canvas.drawRect(
      fill.outerRect,
      Paint()
        ..shader = const LinearGradient(
          colors: ProgressiveFluxLoader.fluxColors,
          stops: [0.0, 0.38, 0.7, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, fillWidth, size.height)),
    );

    // Diagonal shimmer wave travelling along the fill.
    const band = 36.0;
    final x = -band + (fillWidth + band * 2) * shimmer.value;
    final wave = Path()
      ..moveTo(x, size.height)
      ..lineTo(x + band * 0.5, size.height)
      ..lineTo(x + band * 0.5 + size.height, 0)
      ..lineTo(x + size.height, 0)
      ..close();
    canvas.drawPath(
      wave,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(x, 0, band * 0.5 + size.height, size.height)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FluxBarPainter old) => old.progress != progress || old.trackColor != trackColor;
}
