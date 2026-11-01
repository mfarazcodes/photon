import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/prompt_result.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// The live result of a prompt dispatch or asset ingest, in three stages:
///
/// 1. ROLLER: the five status cells spin like split-flap drums, cycling
///    optical telemetry tokens before each locks on its parsed value.
/// 2. BREAK: a 180ms chromatic fracture (rose and cyan, offset 2px, with a
///    scanline) flashes across the capsule as the buffer re-accumulates.
/// 3. REDUCE: after 1.8s the banner collapses into a compact status pill.
///    Clicking toggles between the two; the `x` dismisses it.
class RollerPromptResult extends StatefulWidget {
  const RollerPromptResult({super.key, required this.result, required this.onDismiss});

  final PromptExecutionResult result;
  final VoidCallback onDismiss;

  /// Roller spin, BREAK pulse, and the hold before REDUCE.
  static const Duration rollerDuration = Duration(milliseconds: 900);
  static const Duration breakDuration = Duration(milliseconds: 180);
  static const Duration holdDuration = Duration(milliseconds: 1800);

  static Duration get total => rollerDuration + breakDuration + holdDuration;

  @override
  State<RollerPromptResult> createState() => _RollerPromptResultState();
}

class _RollerPromptResultState extends State<RollerPromptResult> with SingleTickerProviderStateMixin {
  late final AnimationController _stage = AnimationController(vsync: this, duration: RollerPromptResult.total)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() => _compact = true);
    });

  bool _compact = false;

  @override
  void initState() {
    super.initState();
    _stage.forward();
  }

  @override
  void didUpdateWidget(RollerPromptResult old) {
    super.didUpdateWidget(old);
    // A new result rolls again from the top, expanded.
    if (old.result.id != widget.result.id) {
      _compact = false;
      _stage.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _stage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final result = widget.result;
    final compactLabel = result.kind == PromptResultKind.ingest ? 'ASSET INGESTED' : 'PROMPT ACTIVE';

    final expanded = Column(
      key: const ValueKey('roller-expanded'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('⚡', style: TextStyle(fontSize: 12, color: c.rose, height: 1)),
            const SizedBox(width: PhotonSpace.sm),
            Expanded(
              child: AnimatedBuilder(
                animation: _stage,
                builder: (context, child) {
                  // The headline settles in as the last drum locks.
                  final lock = ((_stage.value * RollerPromptResult.total.inMilliseconds) /
                          RollerPromptResult.rollerDuration.inMilliseconds)
                      .clamp(0.0, 1.0);
                  return Opacity(opacity: Curves.easeIn.transform(((lock - 0.6) / 0.4).clamp(0.0, 1.0)), child: child);
                },
                child: Text(
                  result.headline,
                  key: const Key('roller-headline'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.labelCaps.copyWith(color: c.onDock, fontSize: 9.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: PhotonSpace.sm),
            _DismissButton(onTap: widget.onDismiss),
          ],
        ),
        const SizedBox(height: PhotonSpace.sm),
        AnimatedBuilder(
          animation: _stage,
          builder: (context, _) {
            final ms = _stage.value * RollerPromptResult.total.inMilliseconds;
            final roll = (ms / RollerPromptResult.rollerDuration.inMilliseconds).clamp(0.0, 1.0);
            return Row(
              children: [
                for (var i = 0; i < result.cells.length; i++) ...[
                  if (i > 0) const SizedBox(width: PhotonSpace.xs + 2),
                  Expanded(
                    child: _RollerCellView(
                      key: ValueKey('roller-cell-${result.cells[i].tag}'),
                      cell: result.cells[i],
                      roll: roll,
                      lockAt: 0.42 + i * 0.12,
                      seed: i,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );

    final compact = Row(
      key: const ValueKey('roller-compact'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('⚡', style: TextStyle(fontSize: 11, color: c.rose, height: 1)),
        const SizedBox(width: PhotonSpace.sm - 1),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$compactLabel · CLICK TO EXPAND',
              key: const Key('roller-compact-label'),
              maxLines: 1,
              style: t.text.labelCaps.copyWith(color: c.onDock, fontSize: 9, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: PhotonSpace.sm),
        _DismissButton(onTap: widget.onDismiss),
      ],
    );

    return Semantics(
      container: true,
      liveRegion: true,
      label: result.headline,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _compact = !_compact),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: Container(
                  constraints: BoxConstraints(maxWidth: _compact ? 340 : 560),
                  padding: EdgeInsets.symmetric(
                    horizontal: _compact ? PhotonSpace.md - 2 : PhotonSpace.md,
                    vertical: _compact ? 6 : PhotonSpace.sm + 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.dock.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(_compact ? PhotonRadius.pill : 14),
                    border: Border.all(
                      color: hovered ? c.violet.withValues(alpha: 0.7) : (c.isDark ? Colors.white.withValues(alpha: 0.14) : c.border),
                    ),
                    boxShadow: [
                      BoxShadow(color: c.violet.withValues(alpha: 0.22), blurRadius: 22, spreadRadius: -6),
                      ...t.level2,
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _compact ? compact : expanded,
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _BreakPulsePainter(_stage, radius: _compact ? PhotonRadius.pill : 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    return Tooltip(
      message: 'Dismiss',
      child: Semantics(
        button: true,
        label: 'Dismiss result',
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            key: const Key('dismiss-roller-result'),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hovered ? c.onDock.withValues(alpha: 0.16) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 11, color: c.onDock.withValues(alpha: hovered ? 1 : 0.7)),
            ),
          ),
        ),
      ),
    );
  }
}

/// One split-flap drum. Until [lockAt] (a fraction of the roll) it spins about
/// the X axis through telemetry tokens; then it holds its value.
class _RollerCellView extends StatelessWidget {
  const _RollerCellView({super.key, required this.cell, required this.roll, required this.lockAt, required this.seed});

  final RollerCell cell;
  final double roll;
  final double lockAt;
  final int seed;

  static const _tokens = ['0xF3A', 'λ 532', 'Δ 0.8', 'BVH', 'MIS', 'GGX', 'OIDN', 'VK RT', 'IOR', 'SPP', 'AOV'];

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final locked = roll >= lockAt;
    final s = (roll / lockAt).clamp(0.0, 1.0);

    // Three turns, easing out so the drum settles exactly flat at the lock.
    final angle = locked ? 0.0 : 2 * math.pi * 3 * (1 - math.pow(1 - s, 2));
    final showValue = locked || s > 0.9;
    final text = showValue ? cell.value : _tokens[((s * 24).floor() + seed * 3) % _tokens.length];
    final face = (math.cos(angle)).abs();

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: c.onDock.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(PhotonRadius.control),
        border: Border.all(color: locked ? c.violet.withValues(alpha: 0.5) : c.onDock.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '[${cell.tag}]',
            maxLines: 1,
            style: t.text.labelCaps.copyWith(fontSize: 7, color: c.onDock.withValues(alpha: 0.55), letterSpacing: 0.4),
          ),
          const SizedBox(height: 2),
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.002)
              ..rotateX(angle),
            child: Opacity(
              opacity: (0.25 + 0.75 * face).clamp(0.0, 1.0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  maxLines: 1,
                  style: t.text.mono(
                    size: 10,
                    weight: FontWeight.w700,
                    height: 1.1,
                    color: locked ? c.onDock : c.violetInk,
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

/// BREAK: for the 180ms after the drums lock, a rose and a cyan copy of the
/// capsule outline split apart by 2px, with a scanline sweeping down.
class _BreakPulsePainter extends CustomPainter {
  _BreakPulsePainter(this.stage, {required this.radius}) : super(repaint: stage);

  final Animation<double> stage;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final ms = stage.value * RollerPromptResult.total.inMilliseconds;
    final start = RollerPromptResult.rollerDuration.inMilliseconds.toDouble();
    final b = (ms - start) / RollerPromptResult.breakDuration.inMilliseconds;
    if (b <= 0 || b >= 1) return;
    final intensity = math.sin(b * math.pi);
    final rect = Offset.zero & size;
    RRect shifted(double dx) => RRect.fromRectAndRadius(
      rect.shift(Offset(dx, 0)).deflate(0.5),
      Radius.circular(math.min(radius, size.height / 2)),
    );
    Paint stroke(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.9 * intensity);
    canvas.drawRRect(shifted(2), stroke(const Color(0xFFFF2D78)));
    canvas.drawRRect(shifted(-2), stroke(const Color(0xFF22D3EE)));
    final y = size.height * b;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.5 * intensity),
    );
  }

  @override
  bool shouldRepaint(_BreakPulsePainter old) => old.radius != radius;
}
