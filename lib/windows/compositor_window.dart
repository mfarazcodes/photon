import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../painters/pass_painter.dart';
import '../theme/photon_theme.dart';
import '../widgets/sim_view.dart';

/// Slope of the diagonal split line (horizontal px per vertical px).
const double _kTilt = 0.32;

/// RENDER_PASSES.comp: five render passes as an accordion of vertical slices.
/// Hovering widens a slice. Clicking expands it to full view, then it becomes
/// a split-screen against a second pass: a diagonal black-and-white halftone
/// dot wipe sweeps in, and the split handle can be dragged anywhere.
class CompositorContent extends StatefulWidget {
  const CompositorContent({super.key});

  @override
  State<CompositorContent> createState() => _CompositorContentState();
}

class _CompositorContentState extends State<CompositorContent>
    with TickerProviderStateMixin {
  int? _hover;
  int? _focus;
  int _compare = 1;

  /// Position of the split line as a fraction of the width (1 = all of A).
  double _split = 1;

  late final AnimationController _expand = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _wipe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..addListener(() {
      setState(() => _split = 1 - 0.5 * Curves.easeInOutCubic.transform(_wipe.value));
    });

  void _open(int i) {
    setState(() {
      _focus = i;
      _compare = i == 0 ? 1 : 0;
      _split = 1;
    });
    _wipe.value = 0;
    _expand.forward(from: 0).whenComplete(() {
      if (mounted && _focus != null) _wipe.forward(from: 0);
    });
  }

  void _backToSlices() {
    _expand.stop();
    _wipe.stop();
    _expand.value = 0;
    _wipe.value = 0;
    setState(() {
      _focus = null;
      _hover = null;
      _split = 1;
    });
  }

  void _pickCompare(int i) {
    setState(() {
      if (i == _focus) {
        // Swap sides instead of comparing a pass with itself.
        final a = _focus!;
        _focus = _compare;
        _compare = a;
      } else {
        _compare = i;
      }
    });
  }

  @override
  void dispose() {
    _expand.dispose();
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
            builder: (context, time) => AnimatedBuilder(
              animation: _expand,
              builder: (context, _) {
                final splitView = _focus != null && _expand.value >= 1;
                return splitView ? _splitView(time) : _accordion(time);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _accordion(ValueListenable<double> time) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(builder: (context, c) {
        final e = Curves.easeInOutCubic.transform(_expand.value);
        final n = kPassNames.length;
        final gap = 6.0 * (1 - e);
        final avail = c.maxWidth - gap * (n - 1);
        final weights = [
          for (var i = 0; i < n; i++)
            (_hover == i ? 2.8 : 1.0) * (1 - e) + (i == _focus ? 100.0 : 0.0005) * e,
        ];
        final sum = weights.reduce((a, b) => a + b);
        return Row(
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) SizedBox(width: gap),
              AnimatedContainer(
                // Hover resizing eases; the click expansion is driven per frame.
                duration: _focus == null ? const Duration(milliseconds: 460) : Duration.zero,
                curve: Curves.easeOutCubic,
                width: avail * weights[i] / sum,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) {
                    if (_focus == null) setState(() => _hover = i);
                  },
                  onExit: (_) {
                    if (_focus == null) setState(() => _hover = _hover == i ? null : _hover);
                  },
                  child: GestureDetector(
                    onTap: _focus == null ? () => _open(i) : null,
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

  Widget _splitView(ValueListenable<double> time) {
    final a = _focus!, b = _compare;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth, h = c.maxHeight;
            void dragTo(Offset p) {
              _wipe.stop();
              // Undo the diagonal so the line passes through the pointer.
              final s = (p.dx - (p.dy - h / 2) * _kTilt) / w;
              setState(() => _split = s.clamp(0.04, 0.96));
            }

            // The split handle sits where the diagonal crosses mid-height.
            final knobX = _split * w;
            return MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => dragTo(d.localPosition),
                onPanUpdate: (d) => dragTo(d.localPosition),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: PassPainter(pass: a, time: time)),
                    ),
                    Positioned.fill(
                      child: ClipPath(
                        clipper: _DiagonalClipper(_split),
                        child: CustomPaint(painter: PassPainter(pass: b, time: time)),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(painter: _HalftoneBandPainter(_split)),
                    ),
                    Positioned.fill(
                      child: CustomPaint(painter: _SplitLinePainter(_split)),
                    ),
                    Positioned(
                      left: knobX - 22,
                      top: h / 2 - 22,
                      child: const _Knob(),
                    ),
                    Positioned(left: 18, top: 16, child: _PassTitle(index: a)),
                    Positioned(right: 62, top: 16, child: _PassTitle(index: b)),
                    Positioned(
                      right: 14,
                      top: 14,
                      child: _RoundButton(
                        icon: Icons.view_week_rounded,
                        tooltip: 'Back to passes',
                        onTap: _backToSlices,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
        Container(
          height: 74,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          color: const Color(0xFF050505),
          child: Row(
            children: [
              for (var i = 0; i < kPassNames.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: _filmstripCell(i, a, b, time)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _filmstripCell(int i, int a, int b, ValueListenable<double> time) {
    final isA = i == a, isB = i == b;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _pickCompare(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isB ? PC.blue : (isA ? PC.white : const Color(0xFF2A2A2A)),
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
          Positioned(
            left: 12,
            top: 12,
            child: Text(
              (index + 1).toString().padLeft(2, '0'),
              style: PT.mono(size: 13, color: PC.white, weight: FontWeight.w700),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 14,
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                kPassNames[index].toUpperCase(),
                softWrap: false,
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
  const _PassTitle({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Text(
        '${(index + 1).toString().padLeft(2, '0')}  ${kPassNames[index].toUpperCase()}',
        style: PT.mono(size: 13, color: PC.white, weight: FontWeight.w700),
      ),
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

/// Round grip on the split line.
class _Knob extends StatelessWidget {
  const _Knob();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: PC.white,
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: const Icon(Icons.unfold_more_rounded, color: PC.ink, size: 22),
    );
  }
}

/// x position of the split line at height [y]: a line leaning by [_kTilt].
double _lineX(double split, double width, double height, double y) =>
    split * width + (y - height / 2) * _kTilt;

/// Reveals its child to the right of the diagonal split line.
class _DiagonalClipper extends CustomClipper<Path> {
  _DiagonalClipper(this.split);

  final double split;

  @override
  Path getClip(Size size) {
    final top = _lineX(split, size.width, size.height, 0);
    final bottom = _lineX(split, size.width, size.height, size.height);
    return Path()
      ..moveTo(top, 0)
      ..lineTo(size.width + 400, 0)
      ..lineTo(size.width + 400, size.height)
      ..lineTo(bottom, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _DiagonalClipper old) => old.split != split;
}

/// Black-and-white halftone dot matrix hugging the split line: black dots on
/// the A side, white dots on the B side, biggest at the line and shrinking
/// away from it. Rows are staggered like a printed screen.
class _HalftoneBandPainter extends CustomPainter {
  _HalftoneBandPainter(this.split);

  final double split;
  static const double _cell = 13;
  static const double _band = 120;
  static final Paint _black = Paint()..color = const Color(0xFF000000);
  static final Paint _white = Paint()..color = const Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    if (split >= 0.999) return;
    final norm = math.sqrt(1 + _kTilt * _kTilt);
    final rows = (size.height / (_cell * 0.866)).ceil() + 1;
    for (var j = 0; j < rows; j++) {
      final y = j * _cell * 0.866;
      final lineX = _lineX(split, size.width, size.height, y);
      final stagger = j.isOdd ? _cell / 2 : 0.0;
      final first = ((lineX - _band * norm - stagger) / _cell).floor();
      final last = ((lineX + _band * norm - stagger) / _cell).ceil();
      for (var i = first; i <= last; i++) {
        final x = i * _cell + stagger;
        final d = (x - lineX) / norm;
        final k = 1 - d.abs() / _band;
        if (k <= 0) continue;
        canvas.drawCircle(Offset(x, y), _cell * 0.62 * math.sqrt(k), d < 0 ? _black : _white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HalftoneBandPainter old) => old.split != split;
}

class _SplitLinePainter extends CustomPainter {
  _SplitLinePainter(this.split);

  final double split;
  static final Paint _line = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..strokeWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (split >= 0.999) return;
    canvas.drawLine(
      Offset(_lineX(split, size.width, size.height, 0), 0),
      Offset(_lineX(split, size.width, size.height, size.height), size.height),
      _line,
    );
  }

  @override
  bool shouldRepaint(covariant _SplitLinePainter old) => old.split != split;
}
