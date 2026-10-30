import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../models/desktop_node.dart';
import '../painters/vfx_sims.dart';

/// Hosts a [VfxSim] with its own ticker. When [interactive] is true the sim
/// receives hover position, press state and drag deltas.
class SimView extends StatefulWidget {
  const SimView({
    super.key,
    required this.kind,
    this.thumb = false,
    this.interactive = false,
    this.hoverReactive = false,
    this.speed = 1,
  });

  final SimKind kind;
  final bool thumb;
  final bool interactive;

  /// Forward hover (but not clicks or drags) to the sim, for thumbnails that
  /// live inside draggable desktop icons.
  final bool hoverReactive;
  final double speed;

  @override
  State<SimView> createState() => _SimViewState();
}

class _SimViewState extends State<SimView> with SingleTickerProviderStateMixin {
  late VfxSim _sim = createSim(widget.kind, thumb: widget.thumb);
  final ValueNotifier<int> _frame = ValueNotifier(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  Size _size = Size.zero;
  bool _skip = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    // Thumbnails animate at a GIF-like 30 fps to halve their cost.
    if (widget.thumb) {
      _skip = !_skip;
      if (_skip) return;
    }
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _sim.step(dt * widget.speed, _size);
    _frame.value++;
  }

  @override
  void didUpdateWidget(SimView old) {
    super.didUpdateWidget(old);
    if (old.kind != widget.kind || old.thumb != widget.thumb) {
      _sim = createSim(widget.kind, thumb: widget.thumb);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _size = constraints.biggest;
      Widget child = CustomPaint(
        painter: _SimPainter(_sim, _frame),
        size: Size.infinite,
      );
      if (widget.interactive) {
        child = Listener(
          onPointerDown: (e) {
            _sim.pressed = true;
            _sim.pointer = e.localPosition;
          },
          onPointerUp: (_) => _sim.pressed = false,
          onPointerCancel: (_) => _sim.pressed = false,
          onPointerMove: (e) {
            _sim.pointer = e.localPosition;
            if (_sim.pressed) _sim.drag(e.delta);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.precise,
            onHover: (e) => _sim.pointer = e.localPosition,
            onExit: (_) => _sim.pointer = null,
            child: child,
          ),
        );
      }
      if (!widget.interactive && widget.hoverReactive) {
        child = MouseRegion(
          onHover: (e) => _sim.pointer = e.localPosition,
          onExit: (_) => _sim.pointer = null,
          child: child,
        );
      }
      return RepaintBoundary(child: child);
    });
  }
}

class _SimPainter extends CustomPainter {
  _SimPainter(this.sim, Listenable frame) : super(repaint: frame);

  final VfxSim sim;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = sim.background);
    sim.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _SimPainter old) => old.sim != sim;
}

/// Exposes a monotonically increasing clock (seconds) to painters.
class TimeBuilder extends StatefulWidget {
  const TimeBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, ValueListenable<double> time) builder;

  @override
  State<TimeBuilder> createState() => _TimeBuilderState();
}

class _TimeBuilderState extends State<TimeBuilder>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _time = ValueNotifier(0);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => _time.value = e.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _time);
}
