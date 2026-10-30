import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/desktop_node.dart';
import '../models/sim_params.dart';
import '../painters/vfx_sims.dart' show kLiquidModes;
import '../state/workspace_controller.dart';
import '../theme/photon_theme.dart';
import '../widgets/sim_view.dart';

/// Interactive procedural preview for `.vfx`, `.frag` and `.obj` nodes, with a
/// floating playback bar. Generated nodes start from their prompt's seed and
/// shader parameters; built-in nodes follow the inspector's live sliders.
class VfxViewportContent extends StatefulWidget {
  const VfxViewportContent({super.key, required this.node});

  final DesktopNode node;

  @override
  State<VfxViewportContent> createState() => _VfxViewportContentState();
}

class _VfxViewportContentState extends State<VfxViewportContent> {
  late final Playback _playback = Playback(seed: widget.node.seed ?? 884213);

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final params = WorkspaceScope.read(context).paramsFor(node);
    final fg = node.darkTile ? PC.white : PC.ink;
    final chipBg = node.darkTile ? const Color(0x33FFFFFF) : const Color(0x14000000);
    final liquid = node.sim == SimKind.liquid;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: SimView(
                kind: node.sim ?? SimKind.core,
                interactive: true,
                params: params,
                playback: _playback,
              ),
            ),
            Positioned(
              left: 14,
              top: 14,
              right: liquid ? 400 : 170,
              child: IgnorePointer(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Chip(text: node.solver.toUpperCase(), fg: fg, bg: chipBg),
                    _Chip(text: 'LIVE', fg: PC.white, bg: PC.blue),
                    if (node.prompt != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: _Chip(text: node.prompt!, fg: fg, bg: chipBg, ellipsis: true),
                      ),
                  ],
                ),
              ),
            ),
            if (liquid)
              Positioned(
                right: 170,
                top: 14,
                child: ListenableBuilder(
                  listenable: _playback,
                  builder: (context, _) => _ModeToggle(
                    selected: _playback.mode,
                    onSelect: _playback.setMode,
                  ),
                ),
              ),
            Positioned(
              right: 14,
              top: 14,
              child: _ScopeHud(playback: _playback, params: params),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Center(child: _PlaybackBar(playback: _playback)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.fg, required this.bg, this.ellipsis = false});

  final String text;
  final Color fg;
  final Color bg;
  final bool ellipsis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Text(
        text,
        maxLines: 1,
        overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.clip,
        style: PT.mono(size: 11, color: fg, weight: FontWeight.w700),
      ),
    );
  }
}

/// SPHERE / SPLASH / TYPE switch for LIQUID_MORPH.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xCC0A0A0A),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < kLiquidModes.length; i++)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: i == selected ? PC.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    kLiquidModes[i].toUpperCase(),
                    style: PT.mono(
                      size: 11,
                      color: i == selected ? PC.ink : PC.white,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Floating transport: play/pause, scrubbable 240-frame timeline, seed
/// randomize and a live FPS readout.
class _PlaybackBar extends StatelessWidget {
  const _PlaybackBar({required this.playback});

  final Playback playback;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xE60A0A0A),
          borderRadius: BorderRadius.circular(100),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6)),
          ],
        ),
        child: ListenableBuilder(
          listenable: playback,
          builder: (context, _) => Row(
            children: [
              _RoundButton(
                icon: playback.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                tooltip: playback.playing ? 'Pause' : 'Play',
                onTap: playback.togglePlay,
              ),
              const SizedBox(width: 6),
              Expanded(child: _Timeline(playback: playback)),
              const SizedBox(width: 10),
              SizedBox(
                width: 62,
                child: Text(
                  '${(playback.frame + 1).toString().padLeft(3, '0')}/${Playback.frames}',
                  style: PT.mono(size: 11.5, color: PC.white),
                ),
              ),
              _RoundButton(
                icon: Icons.casino_outlined,
                tooltip: 'Randomize seed (${playback.seed})',
                onTap: playback.reroll,
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0x26FFFFFF),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${playback.measuredFps} FPS',
                  style: PT.mono(size: 11.5, color: PC.white, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // No Tooltip: the playback bar rebuilds every frame, which makes hover
    // tooltips assert (target needs layout). Semantics label keeps a11y.
    return Semantics(
      label: tooltip,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, color: PC.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// 240-frame scrub bar. Click or drag anywhere on it to jump.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.playback});

  final Playback playback;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      void scrub(double dx) {
        final f = (dx / width).clamp(0.0, 1.0);
        playback.scrubTo((f * (Playback.frames - 1)).round());
      }

      final progress = playback.frame / (Playback.frames - 1);
      return MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => scrub(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => scrub(d.localPosition.dx),
          child: SizedBox(
            height: 38,
            child: CustomPaint(painter: _TimelinePainter(progress)),
          ),
        ),
      );
    });
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final x = progress * size.width;
    final track = Paint()
      ..color = const Color(0x40FFFFFF)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = PC.blue
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    // Second ticks along the 10 s loop (one per 24 frames).
    final tick = Paint()..color = const Color(0x55FFFFFF);
    for (var s = 0; s <= Playback.frames ~/ 24; s++) {
      final tx = s * 24 / (Playback.frames - 1) * size.width;
      canvas.drawRect(Rect.fromLTWH(tx - 0.5, y - 7, 1, 4), tick);
    }
    canvas.drawLine(Offset(0, y), Offset(size.width, y), track);
    canvas.drawLine(Offset(0, y), Offset(x, y), fill);
    canvas.drawCircle(Offset(x, y), 6.5, Paint()..color = PC.white);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) => old.progress != progress;
}

class _ScopeHud extends StatelessWidget {
  const _ScopeHud({required this.playback, required this.params});
  final Playback playback;
  final SimParams params;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xCC0A0A0A),
        borderRadius: BorderRadius.circular(100),
      ),
      child: ListenableBuilder(
        listenable: playback,
        builder: (context, _) => Row(
          children: [
            Expanded(
              child: CustomPaint(
                painter: _ScopePainter(
                  time: playback.clock,
                  turb: params.turbulence,
                  coh: params.coherence,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              playback.playing ? '16.6ms' : 'PAUSED',
              style: PT.mono(size: 10, color: playback.playing ? PC.white : PC.muted, weight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScopePainter extends CustomPainter {
  _ScopePainter({required this.time, required this.turb, required this.coh});
  final double time;
  final double turb;
  final double coh;

  @override
  void paint(Canvas canvas, Size size) {
    final colors = [const Color(0xFFFF3B30), const Color(0xFF34C759), const Color(0xFF007AFF)];
    for (var c = 0; c < 3; c++) {
      final path = Path();
      for (var i = 0; i <= 40; i++) {
        final x = i / 40 * size.width;
        final phase = time * (3 + c + turb * 5) + (x * (0.05 + coh * 0.1)) + c * 2.0;
        final y = size.height / 2 + math.sin(phase) * (size.height * 0.3 * (0.5 + turb));
        if (i == 0) path.moveTo(x, y);
        else path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[c].withOpacity(0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..blendMode = BlendMode.screen
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScopePainter old) => old.time != time || old.turb != turb || old.coh != coh;
}
