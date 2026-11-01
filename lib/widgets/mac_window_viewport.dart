import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/render_socket.dart';
import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// The centerpiece floating window: `SCENE_VIEWPORT.rt`.
///
/// Shows engine frames when the WebSocket is streaming and the bundled Stitch
/// caustic render otherwise. Dragging across it orbits the camera; dropping a
/// `Draggable<String>` asset on it loads that asset.
class MacWindowViewport extends StatefulWidget {
  const MacWindowViewport({super.key, this.stageAspectRatio});

  /// Fixes the stage to this aspect ratio (companion layout). When null the
  /// stage fills the available height.
  final double? stageAspectRatio;

  static const String fallbackAsset = 'assets/images/caustic_wave.jpg';

  @override
  State<MacWindowViewport> createState() => _MacWindowViewportState();
}

class _MacWindowViewportState extends State<MacWindowViewport> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    final t = context.photon;
    final c = t.colors;

    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => studio.loadAsset(details.data),
      builder: (context, candidate, rejected) {
        final dropping = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: c.substrate,
            borderRadius: BorderRadius.circular(PhotonRadius.window),
            border: Border.all(color: dropping ? c.violet : c.border),
            boxShadow: dropping ? t.causticGlow : t.level2,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: widget.stageAspectRatio == null ? MainAxisSize.max : MainAxisSize.min,
            children: [
              MacTitlebar(
                title: 'SCENE_VIEWPORT.rt',
                titleSuffix: _LinkChip(link: studio.link),
              ),
              if (widget.stageAspectRatio != null)
                AspectRatio(
                  aspectRatio: widget.stageAspectRatio!,
                  child: _Stage(studio: studio, spin: _spin, dropAsset: dropping ? candidate.first : null),
                )
              else
                Expanded(
                  child: _Stage(studio: studio, spin: _spin, dropAsset: dropping ? candidate.first : null),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Titlebar status chip: LIVE (streaming) or PREVIEW (bundled render).
class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.link});

  final RenderLink link;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final live = link == RenderLink.live;
    final color = live ? t.colors.violetInk : t.colors.textMuted;
    return PillCapsule(
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm - 1),
      background: (live ? t.colors.violet : t.colors.textMuted).withValues(alpha: live ? 0.1 : 0.08),
      borderColor: Colors.transparent,
      shadow: false,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FlashingPip(color: color, size: 4, flash: live),
          const SizedBox(width: 4),
          Text(
            live ? 'LIVE' : 'PREVIEW',
            style: t.text.labelCaps.copyWith(fontSize: 8, color: color),
          ),
        ],
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({required this.studio, required this.spin, required this.dropAsset});

  final StudioController studio;
  final Animation<double> spin;
  final String? dropAsset;

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => studio.orbitBy(d.delta.dx, d.delta.dy),
        child: ClipRect(
          child: ColoredBox(
            color: c.viewportMatte,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _RenderSurface(studio: studio),
                IgnorePointer(child: _ProbeCrosshair(studio: studio, spin: spin)),
                Positioned(left: 10, top: 10, child: IgnorePointer(child: _TopLeftHud(studio: studio))),
                Positioned(right: 10, top: 10, child: IgnorePointer(child: _TelemetryStrip(studio: studio))),
                const Positioned(left: 10, bottom: 10, child: IgnorePointer(child: _ResolutionTag())),
                Positioned(right: 10, bottom: 10, child: IgnorePointer(child: _ConvergenceGauge(studio: studio))),
                if (dropAsset != null) IgnorePointer(child: _DropOverlay(asset: dropAsset!)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Engine frame when streaming, bundled caustic render otherwise.
class _RenderSurface extends StatelessWidget {
  const _RenderSurface({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    // Daylight fills the window; grading mode letterboxes on the gray matte.
    final fit = studio.darkGrading ? BoxFit.contain : BoxFit.cover;

    Widget fallback() => ValueListenableBuilder<Offset>(
      valueListenable: studio.orbit,
      builder: (context, orbit, child) => Transform.translate(
        // Orbiting nudges the still render so the preview responds to input.
        offset: Offset(-orbit.dx * 0.15, -orbit.dy * 0.15),
        child: Transform.scale(scale: 1.08, child: child),
      ),
      child: Image.asset(
        MacWindowViewport.fallbackAsset,
        fit: fit,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Path-traced refractive liquid glass and chrome caustics',
      ),
    );

    return ValueListenableBuilder<Uint8List?>(
      valueListenable: studio.frame,
      builder: (context, bytes, _) {
        if (bytes == null) return fallback();
        return Image.memory(
          bytes,
          gaplessPlayback: true,
          fit: fit,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => fallback(),
        );
      },
    );
  }
}

/// Frosted-dark HUD surface. Always dark: it sits on top of the render.
class _Hud extends StatelessWidget {
  const _Hud({required this.child, this.pill = false, this.padding});

  final Widget child;
  final bool pill;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.symmetric(horizontal: PhotonSpace.md - 2, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFF0E0E10).withValues(alpha: 0.74),
      borderRadius: BorderRadius.circular(pill ? PhotonRadius.pill : PhotonRadius.window),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
    ),
    child: child,
  );
}

class _TelemetryStrip extends StatelessWidget {
  const _TelemetryStrip({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final style = t.text.telemetrySm.copyWith(color: Colors.white.withValues(alpha: 0.78));
    Widget sep() => Container(
      width: 1,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm),
      color: Colors.white.withValues(alpha: 0.25),
    );
    return _Hud(
      pill: true,
      child: ValueListenableBuilder<double>(
        valueListenable: studio.fps,
        builder: (context, fps, _) {
          final live = studio.link == RenderLink.live && fps > 0;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                live ? '${fps.round()} FPS' : 'PREVIEW',
                style: style.copyWith(
                  color: live ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                  fontWeight: FontWeight.w500,
                ),
              ),
              sep(),
              Text('${studio.maxBounces} BOUNCES', style: style),
              sep(),
              Text('UNIDIRECTIONAL PT', style: style.copyWith(color: const Color(0xFFEFDBFF))),
            ],
          );
        },
      ),
    );
  }
}

class _TopLeftHud extends StatelessWidget {
  const _TopLeftHud({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final loaded = studio.loadedAsset;
    final live = studio.link == RenderLink.live;
    final style = t.text.labelCaps.copyWith(color: Colors.white.withValues(alpha: 0.85));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!live)
          _Hud(
            pill: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Pip(color: Color(0xFFFBBF24), size: 5),
                const SizedBox(width: PhotonSpace.sm - 2),
                Text('ENGINE OFFLINE · PREVIEW RENDER', style: style),
              ],
            ),
          ),
        if (loaded != null) ...[
          const SizedBox(height: PhotonSpace.xs + 2),
          _Hud(
            pill: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(loaded.icon, size: 10, color: const Color(0xFFDCB8FF)),
                const SizedBox(width: PhotonSpace.sm - 2),
                Text(loaded.fileName, style: style),
              ],
            ),
          ),
        ],
        ValueListenableBuilder<String?>(
          valueListenable: studio.toast,
          builder: (context, message, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: message == null
                ? const SizedBox.shrink(key: ValueKey('no-toast'))
                : Padding(
                    key: ValueKey(message),
                    padding: const EdgeInsets.only(top: PhotonSpace.xs + 2),
                    child: _Hud(
                      pill: true,
                      child: Text(message, style: style.copyWith(color: const Color(0xFFDCB8FF))),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Rotating optical probe at the center with a live IOR read-out.
class _ProbeCrosshair extends StatelessWidget {
  const _ProbeCrosshair({required this.studio, required this.spin});

  final StudioController studio;
  final Animation<double> spin;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final violet = t.colors.violet;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RotationTransition(
                  turns: spin,
                  child: CustomPaint(
                    size: const Size.square(32),
                    painter: _DashedRingPainter(color: violet.withValues(alpha: 0.7)),
                  ),
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: violet,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: violet, blurRadius: 8)],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: PhotonSpace.xs),
          _Hud(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              'λ: 540nm | IOR: ${studio.param('ior').toStringAsFixed(3)}',
              style: t.text.mono(size: 8, height: 1.2, color: const Color(0xFFEFDBFF)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Offset.zero & size;
    const dashes = 14;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect.deflate(0.5), i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => old.color != color;
}

class _ResolutionTag extends StatelessWidget {
  const _ResolutionTag();

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return _Hud(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Pip(color: Color(0xFF22D3EE), size: 6),
              const SizedBox(width: PhotonSpace.sm - 2),
              Text(
                '3840×2160 (4K DCI)',
                style: t.text.telemetrySm.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'ACESCG / LINEAR SPACE',
            style: t.text.labelCaps.copyWith(fontSize: 8, color: const Color(0xFFC8C6C8)),
          ),
        ],
      ),
    );
  }
}

/// Sample-convergence gauge with a live sample counter.
class _ConvergenceGauge extends StatelessWidget {
  const _ConvergenceGauge({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return SizedBox(
      width: 152,
      child: _Hud(
        child: ValueListenableBuilder<int>(
          valueListenable: studio.samples,
          builder: (context, samples, _) {
            final pct = studio.convergence;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CONVERGENCE',
                      style: t.text.labelCaps.copyWith(fontSize: 8, color: const Color(0xFFC8C6C8)),
                    ),
                    Text(
                      '${(pct * 100).round()}%',
                      style: t.text.telemetrySm.copyWith(
                        color: const Color(0xFFEFDBFF),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(PhotonRadius.pill),
                  child: Stack(
                    children: [
                      Container(height: 4, color: Colors.white.withValues(alpha: 0.2)),
                      FractionallySizedBox(
                        widthFactor: pct,
                        child: Container(
                          height: 4,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF8A2BE2), Color(0xFFE879F9)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$samples / ${studio.targetSamples} SPP',
                  style: t.text.telemetrySm.copyWith(
                    fontSize: 9,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return ColoredBox(
      color: t.colors.violet.withValues(alpha: 0.14),
      child: Center(
        child: _Hud(
          pill: true,
          padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.lg, vertical: PhotonSpace.sm),
          child: Text(
            'DROP TO LOAD  $asset',
            style: t.text.labelCaps.copyWith(color: Colors.white, fontSize: 10),
          ),
        ),
      ),
    );
  }
}
