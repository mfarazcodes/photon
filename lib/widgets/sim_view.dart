import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../models/desktop_node.dart';
import '../models/sim_params.dart';
import '../painters/vfx_sims.dart';

final SimParams _defaultParams = SimParams();

/// Hosts a [VfxSim] with its own ticker. When [interactive] is true the sim
/// receives hover position, press state and drag deltas.
///
/// [params] are the live shader parameters (re-read every frame, so a slider
/// change shows immediately; [SimParams.timeScale] scales time and
/// [SimParams.dispersion] splits the RGB channels). [playback] adds a
/// transport: pause, scrubbable clock, seed, sub-mode and a measured FPS.
class SimView extends StatefulWidget {
  const SimView({
    super.key,
    required this.kind,
    this.thumb = false,
    this.interactive = false,
    this.hoverReactive = false,
    this.speed = 1,
    this.params,
    this.playback,
  });

  final SimKind kind;
  final bool thumb;
  final bool interactive;

  /// Forward hover (but not clicks or drags) to the sim, for thumbnails that
  /// live inside draggable desktop icons.
  final bool hoverReactive;
  final double speed;
  final SimParams? params;
  final Playback? playback;

  @override
  State<SimView> createState() => _SimViewState();
}

class _SimViewState extends State<SimView> with SingleTickerProviderStateMixin {
  late VfxSim _sim = createSim(widget.kind, thumb: widget.thumb);
  final ValueNotifier<int> _frame = ValueNotifier(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  Duration _fpsMark = Duration.zero;
  int _fpsFrames = 0;
  Size _size = Size.zero;
  bool _skip = false;

  SimParams get _params => widget.params ?? _defaultParams;

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
    // A long gap (the ticker was muted behind an overlay) must not become one
    // giant physics step.
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;

    final pb = widget.playback;
    final params = _params;
    _sim
      ..params = params
      ..seed = pb?.seed ?? _sim.seed
      ..mode = pb?.mode ?? _sim.mode;

    final step = (pb?.playing ?? true) ? dt * widget.speed * params.timeScale : 0.0;
    _sim.step(step, _size);
    if (pb != null) {
      pb.advance(step);
      // Keep the sim clock on the timeline so scrubbing re-poses analytic sims.
      _sim.t = pb.clock;
      _fpsFrames++;
      final span = elapsed - _fpsMark;
      if (span >= const Duration(milliseconds: 500)) {
        pb.reportFps((_fpsFrames / (span.inMicroseconds / 1e6)).round().clamp(1, 240));
        _fpsFrames = 0;
        _fpsMark = elapsed;
      }
    }
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
        painter: _SimPainter(_sim, _frame, _params, allowDispersion: !widget.thumb),
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
  _SimPainter(this.sim, Listenable frame, this.params, {required this.allowDispersion})
      : super(repaint: frame);

  final VfxSim sim;
  final SimParams params;
  final bool allowDispersion;

  final Paint _bg = Paint();

  // One colour-matrix paint per channel; `plus` adds the three passes back
  // together, so an offset between them shows as chromatic dispersion.
  static final List<Paint> _channels = [
    for (var c = 0; c < 3; c++)
      Paint()
        ..blendMode = BlendMode.plus
        ..colorFilter = ColorFilter.matrix([
          if (c == 0) ...[1, 0, 0, 0, 0] else ...[0, 0, 0, 0, 0],
          if (c == 1) ...[0, 1, 0, 0, 0] else ...[0, 0, 0, 0, 0],
          if (c == 2) ...[0, 0, 1, 0, 0] else ...[0, 0, 0, 0, 0],
          0, 0, 0, 1, 0,
        ]),
  ];

  void _scene(Canvas canvas, Size size) {
    _bg.color = sim.background;
    canvas.drawRect((Offset.zero & size).inflate(24), _bg);
    sim.paint(canvas, size);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.clipRect(rect);
    final d = allowDispersion ? params.dispersion : 0.0;
    if (d < 0.03) {
      _scene(canvas, size);
      return;
    }
    final shift = d * 7;
    canvas.saveLayer(rect, Paint());
    for (var c = 0; c < 3; c++) {
      canvas.saveLayer(rect, _channels[c]);
      canvas.translate((c - 1) * shift, 0);
      _scene(canvas, size);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SimPainter old) => old.sim != sim || old.params != params;
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
