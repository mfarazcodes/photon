import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/render_socket.dart';
import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'ab_render_wipe.dart';
import 'photon_primitives.dart';
import 'pixel_loupe_probe.dart';
import 'rauno_tick_scrubber.dart';

/// The centerpiece floating window: `SCENE_VIEWPORT.rt`.
///
/// Shows engine frames when the WebSocket is streaming and the bundled Stitch
/// caustic render otherwise. Dragging across it orbits the camera; dropping a
/// `Draggable<String>` asset on it loads that asset. The titlebar carries the
/// viewport tools: A/B wipe, pixel loupe, false color and the camera minimap.
class MacWindowViewport extends StatefulWidget {
  const MacWindowViewport({super.key, this.stageAspectRatio});

  /// Fixes the stage to this aspect ratio (companion layout). When null the
  /// stage fills the available height.
  final double? stageAspectRatio;

  static const String fallbackAsset = 'assets/images/caustic_wave.jpg';

  /// Below this window width the tools move from the titlebar to a strip
  /// under it, so they never collide with the centered title.
  static const double compactWidth = 800;

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
        final stage = _Stage(studio: studio, spin: _spin, dropAsset: dropping ? candidate.first : null);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: c.substrate,
            borderRadius: BorderRadius.circular(PhotonRadius.window),
            border: Border.all(color: dropping ? c.violet : c.border),
            boxShadow: dropping ? t.causticGlow : t.level2,
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, box) {
              final compact = box.maxWidth < MacWindowViewport.compactWidth;
              final collapsed = studio.viewportCollapsed;
              return Column(
                mainAxisSize: (widget.stageAspectRatio == null && !collapsed) ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  MacTitlebar(
                    title: 'SCENE_VIEWPORT.rt',
                    titleSuffix: _LinkChip(link: studio.link),
                    leading: MacWindowPips(
                      id: 'viewport',
                      onClose: studio.resetViewportStage,
                      onMinimize: studio.toggleViewportCollapsed,
                      onZoom: () => studio.toggleMaximizedPanel('viewport'),
                    ),
                    trailing: (compact || collapsed) ? null : _ViewportTools(studio: studio),
                  ),
                  // Collapsed: only the titlebar remains.
                  if (!collapsed) ...[
                    if (compact) _ToolStrip(studio: studio),
                    if (widget.stageAspectRatio != null)
                      AspectRatio(aspectRatio: widget.stageAspectRatio!, child: stage)
                    else
                      Expanded(child: stage),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// A/B WIPE, LOUPE and FALSE COLOR toggles plus the camera minimap.
class _ViewportTools extends StatelessWidget {
  const _ViewportTools({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToolToggle(
          label: 'A/B WIPE',
          selected: studio.abWipeEnabled,
          onTap: () => studio.setAbWipeEnabled(!studio.abWipeEnabled),
        ),
        _ToolToggle(label: 'LOUPE', selected: studio.loupeEnabled, onTap: studio.toggleLoupe),
        _ToolToggle(label: 'FALSE COLOR', selected: studio.falseColorEnabled, onTap: studio.toggleFalseColor),
        const SizedBox(width: PhotonSpace.sm),
        RaunoViewportMinimap(studio: studio),
      ],
    );
  }
}

/// The same tools on their own row, for narrow windows.
class _ToolStrip extends StatelessWidget {
  const _ToolStrip({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Align(alignment: Alignment.centerRight, child: _ViewportTools(studio: studio)),
    );
  }
}

/// Titlebar toggle. Its hit area is the full bar height and the toggles abut,
/// so there is no dead space between them.
class _ToolToggle extends StatelessWidget {
  const _ToolToggle({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Semantics(
      button: true,
      toggled: selected,
      label: label,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? c.violet.withValues(alpha: 0.12) : (hovered ? c.hoverFill : Colors.transparent),
                borderRadius: BorderRadius.circular(PhotonRadius.pill),
                border: Border.all(
                  color: selected
                      ? c.violet
                      : hovered
                      ? c.violet.withValues(alpha: 0.4)
                      : c.border,
                ),
              ),
              child: Text(
                label,
                style: t.text.labelCaps.copyWith(fontSize: 8, color: selected ? c.violetInk : c.textMuted),
              ),
            ),
          ),
        ),
      ),
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

class _Stage extends StatefulWidget {
  const _Stage({required this.studio, required this.spin, required this.dropAsset});

  final StudioController studio;
  final Animation<double> spin;
  final String? dropAsset;

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  /// Holding Alt opens the loupe without the toggle.
  bool _altHeld = HardwareKeyboard.instance.isAltPressed;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final alt = HardwareKeyboard.instance.isAltPressed;
    if (alt != _altHeld && mounted) setState(() => _altHeld = alt);
    return false;
  }

  void _probe(Offset local, Size size) {
    if (size.isEmpty) return;
    widget.studio.probePosition.value = Offset(
      (local.dx / size.width).clamp(0.0, 1.0).toDouble(),
      (local.dy / size.height).clamp(0.0, 1.0).toDouble(),
    );
  }

  /// Everything that is image: the render, the wipe passes, false color.
  /// The loupe builds a second copy of it, magnified and without the curtain.
  Widget _imageLayers({required bool magnified, required double badgeTop}) {
    final studio = widget.studio;
    final render = _RenderSurface(studio: studio, magnified: magnified);
    Widget falseColor(Widget child) =>
        FalseColorShaderWrapper(enabled: studio.falseColorEnabled, child: child);
    if (!studio.abWipeEnabled) return falseColor(render);
    return AbRenderWipe(
      studio: studio,
      render: render,
      imageWrapper: falseColor,
      showCurtain: !magnified,
      badgeTop: badgeTop,
    );
  }

  @override
  Widget build(BuildContext context) {
    final studio = widget.studio;
    final c = context.photon.colors;

    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final narrow = size.width < 560;
        final loupeOn = studio.loupeEnabled || _altHeld;
        final badgeTop = narrow ? 40.0 : 10.0;

        return MouseRegion(
          cursor: loupeOn ? SystemMouseCursors.precise : SystemMouseCursors.grab,
          onHover: (e) => _probe(e.localPosition, size),
          onExit: (_) => studio.probePosition.value = null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Orbit from the first pixel of movement, not after the touch slop.
            dragStartBehavior: DragStartBehavior.down,
            onPanUpdate: (d) {
              studio.orbitBy(d.delta.dx, d.delta.dy);
              _probe(d.localPosition, size);
            },
            child: ClipRect(
              child: ColoredBox(
                color: c.viewportMatte,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _imageLayers(magnified: false, badgeTop: badgeTop),
                    IgnorePointer(child: _ProbeCrosshair(studio: studio, spin: widget.spin)),
                    Positioned(left: 10, top: 10, child: IgnorePointer(child: _TopLeftHud(studio: studio))),
                    // Interactive (bounces, integrator, reconnect), so no IgnorePointer.
                    Positioned(
                      right: 10,
                      top: 10,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: math.max(0, size.width - 20)),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: _TelemetryStrip(studio: studio),
                        ),
                      ),
                    ),
                    const Positioned(left: 10, bottom: 10, child: IgnorePointer(child: _ResolutionTag())),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: IgnorePointer(child: _ConvergenceGauge(studio: studio)),
                    ),
                    if (studio.falseColorEnabled)
                      Positioned(
                        left: 0,
                        right: 0,
                        // Clear of the corner HUDs when the stage is narrow.
                        bottom: narrow ? 62 : 10,
                        child: const IgnorePointer(child: Center(child: IreExposureLegend())),
                      ),
                    if (widget.dropAsset != null) IgnorePointer(child: _DropOverlay(asset: widget.dropAsset!)),
                    if (loupeOn)
                      PixelLoupeOverlay(
                        studio: studio,
                        stageSize: size,
                        magnifiedContent: SizedBox.fromSize(
                          size: size,
                          child: _imageLayers(magnified: true, badgeTop: badgeTop),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Engine frame when one is held, bundled caustic render otherwise.
///
/// Always `BoxFit.cover`, in both studio modes, so toggling Dark Grading never
/// crops differently or shifts the pixel under the loupe.
class _RenderSurface extends StatelessWidget {
  const _RenderSurface({required this.studio, required this.magnified});

  final StudioController studio;

  /// The loupe's copy samples without smoothing so pixels stay square.
  final bool magnified;

  @override
  Widget build(BuildContext context) {
    final quality = magnified ? FilterQuality.none : FilterQuality.medium;

    Widget fallback() => ValueListenableBuilder<Offset>(
      valueListenable: studio.orbit,
      builder: (context, orbit, child) => Transform.translate(
        // Orbiting nudges the still render so the preview responds to input.
        offset: Offset(-orbit.dx * 0.15, -orbit.dy * 0.15),
        child: Transform.scale(scale: 1.08, child: child),
      ),
      child: Image.asset(
        MacWindowViewport.fallbackAsset,
        fit: BoxFit.cover,
        filterQuality: quality,
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
          fit: BoxFit.cover,
          filterQuality: quality,
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

/// Top-right HUD: stream status, bounce depth and integrator. All three are
/// controls: the status reconnects, the bounce pill steps/scrolls/drags, and
/// the integrator pill cycles the path-tracing algorithm.
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
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: Colors.white.withValues(alpha: 0.25),
    );
    return _Hud(
      pill: true,
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: studio.fps,
            builder: (context, fps, _) {
              final live = studio.link == RenderLink.live && fps > 0;
              return _HudPill(
                key: const Key('hud-link-pill'),
                tooltip: 'Reconnect / refresh render stream',
                onTap: () {
                  studio.socket.connect();
                  studio.resetFrames();
                },
                child: Text(
                  live ? '${fps.round()} FPS' : 'PREVIEW',
                  style: style.copyWith(
                    color: live ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            },
          ),
          sep(),
          _BouncesPill(studio: studio, style: style),
          sep(),
          _HudPill(
            key: const Key('hud-integrator-pill'),
            tooltip: 'Click to cycle path-tracing integrator',
            glow: true,
            onTap: studio.cycleIntegrator,
            child: Text(
              studio.integrator.label,
              style: style.copyWith(color: const Color(0xFFEFDBFF)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A HUD control: hover-highlighted capsule with a tooltip. [glow] adds the
/// violet halo on hover.
class _HudPill extends StatelessWidget {
  const _HudPill({
    super.key,
    required this.child,
    required this.onTap,
    required this.tooltip,
    this.glow = false,
    this.onHorizontalDrag,
    this.onDragEnd,
  });

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;
  final bool glow;
  final ValueChanged<double>? onHorizontalDrag;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final violet = context.photon.colors.violet;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onHorizontalDragUpdate: onHorizontalDrag == null ? null : (d) => onHorizontalDrag!(d.delta.dx),
            onHorizontalDragEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm + 1, vertical: 4),
              decoration: BoxDecoration(
                color: hovered ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(PhotonRadius.pill),
                boxShadow: (glow && hovered)
                    ? [BoxShadow(color: violet.withValues(alpha: 0.55), blurRadius: 12, spreadRadius: -1)]
                    : null,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// `12 BOUNCES`: tap steps through 4/8/12/16/24/32, the wheel adjusts by one,
/// and a horizontal drag scrubs it.
class _BouncesPill extends StatefulWidget {
  const _BouncesPill({required this.studio, required this.style});

  final StudioController studio;
  final TextStyle style;

  @override
  State<_BouncesPill> createState() => _BouncesPillState();
}

class _BouncesPillState extends State<_BouncesPill> {
  /// Pixels of drag per bounce.
  static const double _pxPerBounce = 10;
  double _dragAccumulator = 0;

  void _onDrag(double dx) {
    _dragAccumulator += dx;
    while (_dragAccumulator.abs() >= _pxPerBounce) {
      final step = _dragAccumulator.sign.toInt();
      widget.studio.nudgeMaxBounces(step);
      _dragAccumulator -= step * _pxPerBounce;
    }
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Claim the wheel so an enclosing scroll view does not also scroll.
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final scroll = e as PointerScrollEvent;
      if (scroll.scrollDelta.dy == 0) return;
      widget.studio.nudgeMaxBounces(scroll.scrollDelta.dy < 0 ? 1 : -1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onSignal,
      child: _HudPill(
        key: const Key('hud-bounces-pill'),
        tooltip: 'Click to step bounce depth · scroll or drag to adjust',
        onTap: widget.studio.cycleMaxBounces,
        onHorizontalDrag: _onDrag,
        onDragEnd: () => _dragAccumulator = 0,
        child: Text('${widget.studio.maxBounces} BOUNCES', style: widget.style),
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
