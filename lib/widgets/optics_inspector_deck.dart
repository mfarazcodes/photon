import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/render_socket.dart';
import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';
import 'rauno_tick_scrubber.dart';

/// `OPTICS_PARAMETERS`: scrubbers, diagnostic read-outs and the 2px
/// path-tracing scrub track, in a floating window below the viewport.
class OpticsInspectorDeck extends StatelessWidget {
  const OpticsInspectorDeck({super.key});

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    final t = context.photon;
    final c = t.colors;

    return Container(
      decoration: BoxDecoration(
        color: c.substrate,
        borderRadius: BorderRadius.circular(PhotonRadius.window),
        border: Border.all(color: c.border),
        boxShadow: t.level2,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MacTitlebar(
            title: 'OPTICS_PARAMETERS',
            leading: MacWindowPips(
              id: 'optics',
              onClose: studio.resetAllParams,
              onMinimize: studio.toggleOpticsCollapsed,
              onZoom: () => studio.toggleMaximizedPanel('optics'),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HistoryButton(
                  key: const Key('optics-undo-btn'),
                  label: 'UNDO',
                  icon: Icons.undo,
                  enabled: studio.canUndo,
                  onTap: studio.undo,
                ),
                _HistoryButton(
                  key: const Key('optics-redo-btn'),
                  label: 'REDO',
                  icon: Icons.redo,
                  enabled: studio.canRedo,
                  onTap: studio.redo,
                ),
                const SizedBox(width: PhotonSpace.xs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.violet.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(PhotonRadius.control - 2),
                  ),
                  child: Text(
                    'SPECTRAL',
                    style: t.text.labelCaps.copyWith(fontSize: 8, color: c.violetInk),
                  ),
                ),
              ],
            ),
          ),
          // Collapsed: only the titlebar remains.
          if (!studio.opticsCollapsed)
          Padding(
            padding: const EdgeInsets.all(PhotonSpace.md),
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth;
                const gap = PhotonSpace.sm;
                final sideCards = w >= 980;
                final cardsWidth = sideCards ? 300.0 : w;
                final sliderWidth = sideCards ? w - cardsWidth - PhotonSpace.md : w;

                final sliders = _Grid(
                  width: sliderWidth,
                  columns: (sliderWidth / 230).floor().clamp(1, 3),
                  gap: gap,
                  children: [
                    for (final p in kOpticsParams) _ParamScrubber(param: p, studio: studio),
                  ],
                );
                final cards = _Grid(
                  width: cardsWidth,
                  columns: sideCards ? 2 : (w >= 720 ? 4 : 2),
                  gap: gap,
                  children: _diagnosticCards(studio),
                );

                if (sideCards) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sliders,
                      const SizedBox(width: PhotonSpace.md),
                      cards,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [sliders, const SizedBox(height: gap), cards],
                );
              },
            ),
          ),
          if (!studio.opticsCollapsed) _ScrubTrack(studio: studio),
        ],
      ),
    );
  }

  List<Widget> _diagnosticCards(StudioController studio) => [
    const _DiagCard(
      label: 'ABERRATION',
      value: '0.18λ',
      dot: _DiagDot.violet,
      caption: 'Prismatic Dispersion',
    ),
    // Follows the viewport HUD's integrator.
    _DiagCard(
      label: 'CAUSTICS',
      value: studio.integrator.solverCaption,
      valueAccent: true,
      dot: _DiagDot.green,
      caption: 'Spectral Solver',
    ),
    ValueListenableBuilder<int>(
      valueListenable: studio.samples,
      builder: (context, samples, _) => _DiagCard(
        label: 'SAMPLES',
        value: '$samples / ${studio.targetSamples}',
        dot: studio.converged ? _DiagDot.green : _DiagDot.violet,
        caption: studio.converged ? 'Converged' : 'Accumulating',
      ),
    ),
    ValueListenableBuilder<double>(
      valueListenable: studio.fps,
      builder: (context, fps, _) {
        final live = studio.link == RenderLink.live && fps > 0;
        return _DiagCard(
          label: 'FRAME TIME',
          value: live ? '${(1000 / fps).toStringAsFixed(0)}ms' : '—',
          dot: live ? _DiagDot.green : _DiagDot.ghost,
          caption: live ? '${fps.toStringAsFixed(0)} FPS stream' : 'Engine offline',
        );
      },
    ),
  ];
}

/// A subtle UNDO / REDO micro-button for the titlebar. It dims when there is
/// nothing to step to.
class _HistoryButton extends StatelessWidget {
  const _HistoryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Tooltip(
      message: label == 'UNDO' ? 'Undo (Ctrl+Z)' : 'Redo (Ctrl+Y)',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: HoverBuilder(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          builder: (context, hovered) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: enabled && hovered ? c.hoverFill : Colors.transparent,
                  borderRadius: BorderRadius.circular(PhotonRadius.control),
                  border: Border.all(color: enabled && hovered ? c.violet.withValues(alpha: 0.5) : c.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 11, color: enabled ? c.carbon : c.ghost.withValues(alpha: 0.6)),
                    const SizedBox(width: 3),
                    Text(
                      label,
                      style: t.text.labelCaps.copyWith(
                        fontSize: 7.5,
                        color: enabled ? c.carbon : c.ghost.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed-column grid with equal-width cells (a `Wrap` with sized children, so
/// each cell keeps its natural height).
class _Grid extends StatelessWidget {
  const _Grid({
    required this.width,
    required this.columns,
    required this.gap,
    required this.children,
  });

  final double width;
  final int columns;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cell = math.max(0.0, (width - gap * (columns - 1)) / columns);
    return SizedBox(
      width: width,
      child: Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final child in children) SizedBox(width: cell, child: child)],
      ),
    );
  }
}

/// One parameter card: the whole card scrubs (see [RaunoTickScrubber]).
class _ParamScrubber extends StatelessWidget {
  const _ParamScrubber({required this.param, required this.studio});

  final OpticsParam param;
  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    return RaunoTickScrubber(
      key: ValueKey('scrub-${param.id}'),
      param: param,
      value: studio.param(param.id),
      onChanged: (v) => studio.setParam(param.id, v),
    );
  }
}

enum _DiagDot { violet, green, ghost }

class _DiagCard extends StatelessWidget {
  const _DiagCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.dot,
    this.valueAccent = false,
  });

  final String label;
  final String value;
  final String caption;
  final _DiagDot dot;
  final bool valueAccent;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final dotColor = switch (dot) {
      _DiagDot.violet => c.violet,
      _DiagDot.green => const Color(0xFF22C55E),
      _DiagDot.ghost => c.ghost,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm + 2, vertical: PhotonSpace.sm),
      decoration: BoxDecoration(
        color: c.canvas,
        borderRadius: BorderRadius.circular(PhotonRadius.window),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: t.text.labelCaps.copyWith(fontSize: 8)),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.telemetrySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: valueAccent ? c.violetInk : c.carbon,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Pip(color: dotColor, size: 5),
              const SizedBox(width: PhotonSpace.xs + 1),
              Flexible(
                child: Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.telemetrySm.copyWith(fontSize: 9, color: c.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Footer: label row plus the continuous 2px path-tracing scrub track.
class _ScrubTrack extends StatelessWidget {
  const _ScrubTrack({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return ValueListenableBuilder<int>(
      valueListenable: studio.samples,
      builder: (context, samples, _) {
        final pct = studio.convergence;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(PhotonSpace.md, 0, PhotonSpace.md, PhotonSpace.sm - 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('PATH-TRACING SCRUB', style: t.text.labelCaps.copyWith(fontSize: 8)),
                  Text(
                    '$samples / ${studio.targetSamples} SPP · ${(pct * 100).toStringAsFixed(1)}%',
                    style: t.text.telemetrySm.copyWith(fontSize: 9, color: c.textMuted),
                  ),
                ],
              ),
            ),
            Semantics(
              label: 'Path-tracing convergence',
              value: '${(pct * 100).round()} percent',
              child: SizedBox(
                height: 2,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: c.border),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: pct),
                        duration: const Duration(milliseconds: 100),
                        builder: (context, v, _) => FractionallySizedBox(
                          widthFactor: v,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.violet,
                              boxShadow: [
                                BoxShadow(color: c.violet.withValues(alpha: 0.5), blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
