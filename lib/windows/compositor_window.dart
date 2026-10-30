import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../painters/pass_painter.dart';
import '../theme/photon_theme.dart';
import '../widgets/sim_view.dart';

/// RENDER_PASSES.comp: five render passes as an accordion of vertical slices.
/// Hovering widens a slice; clicking focuses it full-frame with a diagonal
/// halftone wipe.
class CompositorContent extends StatefulWidget {
  const CompositorContent({super.key});

  @override
  State<CompositorContent> createState() => _CompositorContentState();
}

class _CompositorContentState extends State<CompositorContent>
    with SingleTickerProviderStateMixin {
  int? _hover;
  int? _focus;
  int _from = 0;
  late final AnimationController _wipe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  void _focusPass(int i) {
    setState(() {
      _from = _focus ?? (i == 0 ? 4 : 0);
      _focus = i;
    });
    _wipe.forward(from: 0);
  }

  @override
  void dispose() {
    _wipe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(
          color: const Color(0xFF0A0A0A),
          child: TimeBuilder(
            builder: (context, time) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: _focus == null ? _accordion(time) : _focused(time),
            ),
          ),
        ),
      ),
    );
  }

  Widget _accordion(ValueListenable<double> time) {
    return Padding(
      key: const ValueKey('accordion'),
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(builder: (context, c) {
        const gap = 6.0;
        final n = kPassNames.length;
        final avail = c.maxWidth - gap * (n - 1);
        final weights = [for (var i = 0; i < n; i++) _hover == i ? 2.8 : 1.0];
        final sum = weights.reduce((a, b) => a + b);
        return Row(
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              AnimatedContainer(
                duration: const Duration(milliseconds: 460),
                curve: Curves.easeOutCubic,
                width: avail * weights[i] / sum,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _hover = i),
                  onExit: (_) => setState(() => _hover = _hover == i ? null : _hover),
                  child: GestureDetector(
                    onTap: () => _focusPass(i),
                    child: _Slice(index: i, time: time, active: _hover == i),
                  ),
                ),
              ),
            ],
          ],
        );
      }),
    );
  }

  Widget _focused(ValueListenable<double> time) {
    final focus = _focus!;
    return Column(
      key: const ValueKey('focused'),
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: PassPainter(pass: _from, time: time)),
              ),
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _wipe,
                  builder: (context, child) => ClipPath(
                    clipper: HalftoneWipeClipper(Curves.easeInOutCubic.transform(_wipe.value)),
                    child: child,
                  ),
                  child: CustomPaint(painter: PassPainter(pass: focus, time: time)),
                ),
              ),
              Positioned(
                left: 18,
                top: 16,
                child: _PassTitle(index: focus, big: true),
              ),
              Positioned(
                right: 14,
                top: 14,
                child: _RoundButton(
                  icon: Icons.view_week_rounded,
                  tooltip: 'Back to passes',
                  onTap: () => setState(() {
                    _focus = null;
                    _hover = null;
                  }),
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 74,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          color: const Color(0xFF050505),
          child: Row(
            children: [
              for (var i = 0; i < kPassNames.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: i == focus ? null : () => _focusPass(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: i == focus ? PC.blue : const Color(0xFF2A2A2A),
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(painter: PassPainter(pass: i, time: time)),
                              ),
                              Positioned(
                                left: 6,
                                bottom: 4,
                                child: Text(
                                  '${(i + 1).toString().padLeft(2, '0')} ${kPassNames[i]}',
                                  style: PT.mono(size: 10.5, color: PC.white, weight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Slice extends StatelessWidget {
  const _Slice({required this.index, required this.time, required this.active});

  final int index;
  final ValueListenable<double> time;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: PassPainter(pass: index, time: time))),
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Colors.black.withValues(alpha: active ? 0.55 : 0.75), Colors.transparent],
                ),
                border: Border.all(
                  color: active ? const Color(0x99FFFFFF) : Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Positioned(left: 12, top: 12, child: _PassTitle(index: index, big: false)),
          Positioned(
            left: 10,
            bottom: 14,
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                kPassNames[index].toUpperCase(),
                style: PT.label(size: 15, color: PC.white, weight: FontWeight.w700, spacing: 1.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PassTitle extends StatelessWidget {
  const _PassTitle({required this.index, required this.big});

  final int index;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final number = (index + 1).toString().padLeft(2, '0');
    if (!big) {
      return Text(number, style: PT.mono(size: 13, color: PC.white, weight: FontWeight.w700));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Text('$number  ${kPassNames[index].toUpperCase()}',
          style: PT.mono(size: 13, color: PC.white, weight: FontWeight.w700)),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, required this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(color: PC.white, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: PC.ink),
          ),
        ),
      ),
    );
  }
}

/// Reveals its child with halftone dots that grow along the diagonal.
class HalftoneWipeClipper extends CustomClipper<Path> {
  HalftoneWipeClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    if (progress >= 0.999) return Path()..addRect(Offset.zero & size);
    final path = Path();
    if (progress <= 0) return path;
    const cell = 22.0;
    final cols = (size.width / cell).ceil() + 1;
    final rows = (size.height / cell).ceil() + 1;
    final span = size.width + size.height;
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final x = i * cell, y = j * cell;
        final diag = (x + y) / span;
        final k = ((progress * 1.5 - diag) * 3.2).clamp(0.0, 1.0);
        if (k <= 0) continue;
        final r = cell * 0.76 * math.sqrt(k);
        path.addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
      }
    }
    return path;
  }

  @override
  bool shouldReclip(covariant HalftoneWipeClipper old) => old.progress != progress;
}
