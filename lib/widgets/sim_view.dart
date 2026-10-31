import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../models/desktop_node.dart';
import '../models/sim_params.dart';
import '../models/vfx_dna.dart';
import '../painters/generative_vfx_painter.dart';
import '../painters/vfx_sims.dart';

final SimParams _defaultParams = SimParams();

/// Hosts a [VfxSim] with its own ticker. When [interactive] is true the sim
/// receives hover position, press state and drag deltas.
///
/// A non-null [dna] (any effect generated from a prompt) replaces the preset
/// sim for [kind] with a [GenerativeVfxPainter]; [kind] then only matters as
/// a fallback. The built-in [SimKind] sims are for the default desktop files.
///
/// [params] are the live shader parameters (re-read every frame, so a slider
/// change shows immediately; [SimParams.timeScale] scales time and
/// [SimParams.dispersion] splits the RGB channels). [playback] adds a
/// transport: pause, scrubbable clock, seed, sub-mode and a measured FPS.
class SimView extends StatefulWidget {
  const SimView({
    super.key,
    required this.kind,
    this.dna,
    this.thumb = false,
    this.interactive = false,
    this.hoverReactive = false,
    this.speed = 1,
    this.params,
    this.playback,
  });

  final SimKind kind;
  final VfxDna? dna;
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
  // Exactly one of these is set: the preset sim, or the generative painter.
  VfxSim? _sim;
  GenerativeVfxPainter? _gen;
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
    _rebuildSim();
    _ticker = createTicker(_onTick)..start();
  }

  void _rebuildSim() {
    final dna = widget.dna;
    if (dna == null) {
      _gen = null;
      _sim = createSim(widget.kind, thumb: widget.thumb);
    } else {
      _sim = null;
      _gen = GenerativeVfxPainter(
        dna: dna,
        params: _params,
        playback: widget.playback,
        repaint: _frame,
        thumb: widget.thumb,
      );
    }
  }

  void _setPointer(Offset? p) {
    _sim?.pointer = p;
    _gen?.mouse =
        (p == null || _size.isEmpty) ? null : Offset(p.dx / _size.width, p.dy / _size.height);
  }

  void _setPressed(bool down) {
    _sim?.pressed = down;
    _gen?.pressed = down;
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
    final sim = _sim, gen = _gen;
    final speed = widget.speed * params.timeScale * (widget.dna?.speed ?? 1);
    final step = (pb?.playing ?? true) ? dt * speed : 0.0;
    if (gen != null) {
      gen
        ..params = params
        ..playback = pb
        ..step(step, _size);
    } else if (sim != null) {
      sim
        ..params = params
        ..seed = pb?.seed ?? sim.seed
        ..mode = pb?.mode ?? sim.mode
        ..step(step, _size);
    }
    if (pb != null) {
      pb.advance(step);
      // Keep the sim clock on the timeline so scrubbing re-poses analytic sims.
      if (gen != null) {
        gen.time = pb.clock;
      } else {
        sim?.t = pb.clock;
      }
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
    if (old.kind != widget.kind ||
        old.thumb != widget.thumb ||
        !identical(old.dna, widget.dna)) {
      _rebuildSim();
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
        painter: _gen ?? _SimPainter(_sim!, _frame, _params, allowDispersion: !widget.thumb),
        size: Size.infinite,
      );
      if (widget.interactive) {
        child = Listener(
          onPointerDown: (e) {
            _setPressed(true);
            _setPointer(e.localPosition);
          },
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          onPointerMove: (e) {
            _setPointer(e.localPosition);
            final sim = _sim;
            if (sim != null && sim.pressed) sim.drag(e.delta);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.precise,
            onHover: (e) => _setPointer(e.localPosition),
            onExit: (_) => _setPointer(null),
            child: child,
          ),
        );
      }
      if (!widget.interactive && widget.hoverReactive) {
        child = MouseRegion(
          onHover: (e) => _setPointer(e.localPosition),
          onExit: (_) => _setPointer(null),
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
    paintChannelSplit(canvas, rect, d * 7, () => _scene(canvas, size));
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
