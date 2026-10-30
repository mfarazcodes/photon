import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/desktop_node.dart';
import '../painters/glyph_painters.dart';
import '../state/workspace_controller.dart';
import '../theme/photon_theme.dart';
import 'sim_view.dart';

/// Anchors the render dropdown card directly beneath the Render Queue pill.
final LayerLink renderPillLink = LayerLink();

const double kPillHeight = 52;

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.child,
    this.onTap,
    this.dark = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool dark;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: kPillHeight,
          padding: padding,
          decoration: BoxDecoration(
            color: dark ? PC.ink : PC.white,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: dark ? PC.ink : PC.hairline),
            boxShadow: PC.floatShadow,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [child]),
        ),
      ),
    );
  }
}

class TopPillBar extends StatelessWidget {
  const TopPillBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final showTelemetry = w >= 1180;
      final compactTelemetry = w < 1420;
      final showRender = w >= 880;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Pill(
              onTap: () => ws.openOverlay(StudioOverlay.about),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                'PHOTON VFX STUDIO®',
                style: PT.label(size: 15, weight: FontWeight.w700, spacing: 1.4),
              ),
            ),
            const Spacer(),
            if (showRender) ...[
              CompositedTransformTarget(
                link: renderPillLink,
                child: const RenderQueuePill(),
              ),
              const SizedBox(width: 8),
            ],
            const GravityPill(),
            if (showTelemetry) ...[
              const SizedBox(width: 8),
              TelemetryPill(compact: compactTelemetry),
            ],
            const SizedBox(width: 8),
            Pill(
              dark: true,
              onTap: () => ws.openOverlay(StudioOverlay.promptDrawer),
              child: Row(
                children: [
                  Text('New Prompt',
                      style: PT.label(size: 17, color: PC.white, weight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  const Icon(Icons.north_east_rounded, size: 18, color: PC.white),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

// -----------------------------------------------------------------------------
// Render Queue
// -----------------------------------------------------------------------------
class RenderQueuePill extends StatelessWidget {
  const RenderQueuePill({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    final queue = ws.renderQueue;
    return Pill(
      onTap: ws.toggleRenderDropdown,
      padding: const EdgeInsets.only(left: 7, right: 12),
      child: ListenableBuilder(
        listenable: queue,
        builder: (context, _) => Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                width: 38,
                height: 38,
                child: SimView(
                  key: ValueKey(queue.current.sim),
                  kind: queue.current.sim,
                  thumb: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text('Render Queue', style: PT.label(size: 17, weight: FontWeight.w500)),
            const SizedBox(width: 10),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                value: queue.progress,
                strokeWidth: 2,
                backgroundColor: PC.hairline,
                color: queue.paused ? PC.amber : PC.blue,
              ),
            ),
            const SizedBox(width: 4),
            _IconTap(
              icon: Icons.skip_next_rounded,
              tooltip: 'Next job',
              onTap: queue.skip,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 24, color: PC.ink),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// Floating card that drops beneath the Render Queue pill.
class RenderDropdownLayer extends StatelessWidget {
  const RenderDropdownLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    final open = ws.renderDropdownOpen;
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: renderPillLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        offset: const Offset(0, 10),
        child: IgnorePointer(
          ignoring: !open,
          child: AnimatedSlide(
            offset: open ? Offset.zero : const Offset(0, -0.05),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: open ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: const _RenderCard(),
            ),
          ),
        ),
      ),
    );
  }
}

class _RenderCard extends StatelessWidget {
  const _RenderCard();

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    final q = ws.renderQueue;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: 372,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: PC.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PC.hairline),
          boxShadow: PC.windowShadow,
        ),
        child: ListenableBuilder(
          listenable: q,
          builder: (context, _) {
            final job = q.current;
            final eta = q.eta;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: SimView(key: ValueKey(job.sim), kind: job.sim, thumb: true),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(job.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PT.label(size: 15, weight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('${job.device} • ${q.vram}% VRAM • ${q.fps} FPS',
                              style: PT.mono(size: 12, color: PC.muted)),
                          const SizedBox(height: 6),
                          _StatusChip(paused: q.paused),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      children: [
                        const Positioned.fill(child: ColoredBox(color: Color(0xFFEDEDED))),
                        FractionallySizedBox(
                          widthFactor: q.progress.clamp(0.0, 1.0),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFFEF4444), PC.blue],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Flexible(
                      child: Text('FRAME ${q.frame.toString().padLeft(3, '0')} / ${job.frames}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PT.mono(size: 11.5, color: PC.muted)),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('${(q.progress * 100).toStringAsFixed(1)}%  ·  ETA ${_two(eta.inMinutes)}:${_two(eta.inSeconds % 60)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PT.mono(size: 11.5, color: PC.muted)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Pill(
                      dark: true,
                      onTap: q.togglePause,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(q.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                              size: 20, color: PC.white),
                          const SizedBox(width: 6),
                          Text(q.paused ? 'Resume' : 'Pause',
                              style: PT.label(size: 15, color: PC.white, weight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _IconTap(icon: Icons.skip_next_rounded, tooltip: 'Skip job', onTap: q.skip),
                    const Spacer(),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => ws.openFinder(FinderView.renderLibrary),
                        child: Row(
                          children: [
                            Text('Library', style: PT.label(size: 15, color: PC.blue)),
                            const SizedBox(width: 4),
                            const Icon(Icons.open_in_new_rounded, size: 16, color: PC.blue),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.paused});

  final bool paused;

  @override
  Widget build(BuildContext context) {
    final color = paused ? PC.amber : PC.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(paused ? 'PAUSED' : 'RENDERING',
          style: PT.mono(size: 10.5, color: color, weight: FontWeight.w700)),
    );
  }
}

// -----------------------------------------------------------------------------
// Gravity
// -----------------------------------------------------------------------------
class GravityPill extends StatelessWidget {
  const GravityPill({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    return Pill(
      onTap: () => ws.setGravity(!ws.gravity),
      child: Row(
        children: [
          CustomPaint(
            size: const Size(26, 18),
            painter: GravityGlyphPainter(on: ws.gravity),
          ),
          const SizedBox(width: 10),
          Text('Gravity', style: PT.label(size: 17)),
          const SizedBox(width: 12),
          PhotonToggle(value: ws.gravity),
        ],
      ),
    );
  }
}

/// iOS-style switch rendered in Photon blue.
class PhotonToggle extends StatelessWidget {
  const PhotonToggle({super.key, required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 50,
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? PC.blue : const Color(0xFFE3E3E8),
        borderRadius: BorderRadius.circular(15),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
            color: PC.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2))],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Telemetry
// -----------------------------------------------------------------------------
class TelemetryPill extends StatefulWidget {
  const TelemetryPill({super.key, this.compact = false});

  final bool compact;

  @override
  State<TelemetryPill> createState() => _TelemetryPillState();
}

class _TelemetryPillState extends State<TelemetryPill>
    with SingleTickerProviderStateMixin {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  late final Ticker _ticker;
  late final Timer _clock;
  DateTime _now = DateTime.now();
  int _frames = 0;
  Duration _window = Duration.zero;
  int _fps = 60;
  final ValueNotifier<double> _pulse = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  void _onTick(Duration elapsed) {
    _frames++;
    _pulse.value = (elapsed.inMilliseconds % 1600) / 1600;
    if (elapsed - _window >= const Duration(milliseconds: 500)) {
      final secs = (elapsed - _window).inMicroseconds / 1e6;
      _fps = (_frames / secs).round().clamp(1, 240);
      _frames = 0;
      _window = elapsed;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.cancel();
    _pulse.dispose();
    super.dispose();
  }

  String get _stamp {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    return '${_days[_now.weekday - 1]} ${_months[_now.month - 1]} ${_now.day}, $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Pill(
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: ValueListenableBuilder<double>(
              valueListenable: _pulse,
              builder: (context, p, _) => Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 8 + 10 * p,
                    height: 8 + 10 * p,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: PC.blue.withValues(alpha: 0.35 * (1 - p)),
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: PC.blue),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(_stamp, style: PT.label(size: 17)),
          const SizedBox(width: 10),
          Text(
            widget.compact ? '• $_fps FPS' : '• Engine Ready | $_fps FPS',
            style: PT.mono(size: 13, color: PC.muted),
          ),
        ],
      ),
    );
  }
}
