import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';

/// Neutral hairline gray for micro instrumentation.
const Color kRaunoGray = Color(0xFF8F8F8F);

/// A whole parameter card that scrubs: no handle to find, no dead zone.
///
/// * Dragging anywhere on the card moves the value by
///   `(max - min) * dx / cardWidth`; holding Shift drops that to 0.1x for
///   vernier control.
/// * Double-tap resets to [OpticsParam.initial].
/// * A 25-tick ruler along the bottom swells (4px to 12px, violet) around the
///   current value, with a 2px needle at the exact position.
/// * Arrow keys nudge it when focused (Shift for fine), and it exposes slider
///   semantics.
class RaunoTickScrubber extends StatefulWidget {
  const RaunoTickScrubber({
    super.key,
    required this.param,
    required this.value,
    required this.onChanged,
  });

  final OpticsParam param;
  final double value;
  final ValueChanged<double> onChanged;

  static const double rulerHeight = 18;

  @override
  State<RaunoTickScrubber> createState() => _RaunoTickScrubberState();
}

class _RaunoTickScrubberState extends State<RaunoTickScrubber> {
  final FocusNode _focus = FocusNode(debugLabel: 'param-scrubber');
  bool _hovered = false;
  bool _dragging = false;
  bool _fine = false;
  bool _focused = false;

  /// Unrounded value accumulated during a drag, so integer parameters still
  /// respond to sub-step movement.
  double _dragValue = 0;

  OpticsParam get _p => widget.param;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  double get _normalized => ((widget.value - _p.min) / (_p.max - _p.min)).clamp(0.0, 1.0).toDouble();

  void _onDragStart(DragStartDetails _) {
    _dragValue = widget.value;
    _focus.requestFocus();
    setState(() {
      _dragging = true;
      _fine = HardwareKeyboard.instance.isShiftPressed;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final width = context.size?.width ?? 0;
    if (width <= 0) return;
    final fine = HardwareKeyboard.instance.isShiftPressed;
    _dragValue = (_dragValue + (_p.max - _p.min) * (d.delta.dx / width) * (fine ? 0.1 : 1.0))
        .clamp(_p.min, _p.max)
        .toDouble();
    if (fine != _fine) setState(() => _fine = fine);
    widget.onChanged(_p.clamp(_dragValue));
  }

  void _onDragEnd([Object? _]) => setState(() {
    _dragging = false;
    _fine = false;
  });

  /// Keyboard and accessibility step: one unit for integers, 1% of the range
  /// otherwise (0.1% when [fine]).
  double _step({bool fine = false}) =>
      _p.integer ? 1.0 : (_p.max - _p.min) / 100 * (fine ? 0.1 : 1.0);

  void _nudge(int direction, {required bool fine}) {
    widget.onChanged(_p.clamp(widget.value + direction * _step(fine: fine)));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final fine = HardwareKeyboard.instance.isShiftPressed;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _nudge(1, fine: fine);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _nudge(-1, fine: fine);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final borderColor = (_dragging || _hovered)
        ? c.violet
        : _focused
        ? c.carbon
        : c.border;

    final header = Row(
      children: [
        Flexible(
          child: Tooltip(
            message: _p.hint ?? _p.label,
            child: Text(
              _p.label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.text.labelCaps,
            ),
          ),
        ),
        if (_dragging && _fine) ...[
          const SizedBox(width: PhotonSpace.sm - 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: c.violet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(PhotonRadius.control - 2),
            ),
            child: Text(
              'FINE ×0.1',
              style: t.text.labelCaps.copyWith(fontSize: 7, color: c.violetInk),
            ),
          ),
        ],
        const Spacer(),
        Text(
          _p.format(widget.value),
          textAlign: TextAlign.right,
          style: t.text.telemetryMd.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );

    final ruler = SizedBox(
      height: RaunoTickScrubber.rulerHeight,
      // Ticks ease toward the value; the needle never lags it.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _normalized),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        builder: (context, smoothed, _) => CustomPaint(
          painter: _RaunoTickRulerPainter(
            value: _normalized,
            smoothed: smoothed,
            tickColor: c.ghost,
            activeColor: c.violet,
          ),
        ),
      ),
    );

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.fromLTRB(PhotonSpace.sm, PhotonSpace.sm - 2, PhotonSpace.sm, 3),
      decoration: BoxDecoration(
        color: c.substrate,
        borderRadius: BorderRadius.circular(PhotonRadius.control),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, const SizedBox(height: 4), ruler],
      ),
    );

    return Focus(
      focusNode: _focus,
      onFocusChange: (focused) => setState(() => _focused = focused),
      onKeyEvent: _onKey,
      child: Semantics(
        container: true,
        slider: true,
        label: _p.label,
        value: _p.format(widget.value),
        increasedValue: _p.format(_p.clamp(widget.value + _step())),
        decreasedValue: _p.format(_p.clamp(widget.value - _step())),
        onIncrease: () => _nudge(1, fine: false),
        onDecrease: () => _nudge(-1, fine: false),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          // Focus on pointer-down: a tap recognizer would wait out its press
          // deadline first, and the card should answer at once.
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _focus.requestFocus(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              onHorizontalDragCancel: _onDragEnd,
              onDoubleTap: () => widget.onChanged(_p.initial),
              child: card,
            ),
          ),
        ),
      ),
    );
  }
}

/// 25 hairline ticks with a Gaussian swell around the value, plus the needle.
class _RaunoTickRulerPainter extends CustomPainter {
  const _RaunoTickRulerPainter({
    required this.value,
    required this.smoothed,
    required this.tickColor,
    required this.activeColor,
  });

  /// Exact normalized value (needle).
  final double value;

  /// Eased normalized value (tick swell).
  final double smoothed;
  final Color tickColor;
  final Color activeColor;

  static const int tickCount = 25;
  static const double restHeight = 4;
  static const double peakHeight = 12;

  /// Gaussian width in normalized units (about three ticks).
  static const double sigma = 0.09;

  @override
  void paint(Canvas canvas, Size size) {
    final tick = Paint()..strokeWidth = 1;
    for (var i = 0; i < tickCount; i++) {
      final t = i / (tickCount - 1);
      final falloff = math.exp(-math.pow((t - smoothed) / sigma, 2));
      final height = restHeight + (peakHeight - restHeight) * falloff;
      // Snap to the pixel grid so 1px ticks stay crisp.
      final x = (t * (size.width - 1)).roundToDouble() + 0.5;
      tick.color = Color.lerp(tickColor, activeColor, falloff)!;
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - height), tick);
    }

    final nx = (value * (size.width - 2)).roundToDouble() + 1;
    final needle = Paint()..color = activeColor;
    canvas.drawRect(Rect.fromLTRB(nx - 1, 4, nx + 1, size.height), needle);
    canvas.drawCircle(Offset(nx, 3), 2.5, needle);
  }

  @override
  bool shouldRepaint(_RaunoTickRulerPainter old) =>
      old.value != value ||
      old.smoothed != smoothed ||
      old.tickColor != tickColor ||
      old.activeColor != activeColor;
}

/// 56x20 bird's-eye of the camera: a frame with micro cross-ticks and a 1px
/// tracker that follows the orbit. A click recenters the camera.
///
/// It listens for a single tap rather than also a double tap: a double-tap
/// recognizer would hold every first click back to see if a second follows,
/// and a double click fires the (idempotent) reset twice anyway.
class RaunoViewportMinimap extends StatelessWidget {
  const RaunoViewportMinimap({super.key, required this.studio});

  final StudioController studio;

  static const Size size = Size(56, 20);

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    return Tooltip(
      message: 'Recenter camera',
      child: Semantics(
        button: true,
        label: 'Recenter camera',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: studio.resetOrbit,
            child: SizedBox.fromSize(
              size: size,
              child: CustomPaint(
                painter: _MinimapPainter(orbit: studio.orbit, tracker: c.violet),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({required this.orbit, required this.tracker}) : super(repaint: orbit);

  final ValueNotifier<Offset> orbit;
  final Color tracker;

  static const Size trackerSize = Size(12, 6);

  /// Matches the controller's orbit clamp.
  static const double orbitRange = 240;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = kRaunoGray
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final frame = (Offset.zero & size).deflate(0.5);
    canvas.drawRect(frame, line);

    // Micro cross-ticks: a center cross and inward ticks at the edge midpoints.
    final mid = size.center(Offset.zero);
    canvas.drawLine(Offset(mid.dx - 3, mid.dy), Offset(mid.dx + 3, mid.dy), line);
    canvas.drawLine(Offset(mid.dx, mid.dy - 3), Offset(mid.dx, mid.dy + 3), line);
    canvas.drawLine(Offset(0.5, mid.dy), Offset(3.5, mid.dy), line);
    canvas.drawLine(Offset(size.width - 3.5, mid.dy), Offset(size.width - 0.5, mid.dy), line);
    canvas.drawLine(Offset(mid.dx, 0.5), Offset(mid.dx, 3.5), line);
    canvas.drawLine(Offset(mid.dx, size.height - 3.5), Offset(mid.dx, size.height - 0.5), line);

    // The tracker travels inside the frame and shifts with the orbit.
    final travel = Offset(
      (size.width - trackerSize.width) / 2 - 2,
      (size.height - trackerSize.height) / 2 - 2,
    );
    final o = orbit.value;
    final center = mid + Offset(o.dx / orbitRange * travel.dx, o.dy / orbitRange * travel.dy);
    // Snapped, then inset half a pixel, so the 1px stroke lands on one row.
    final snapped = Offset(center.dx.roundToDouble(), center.dy.roundToDouble());
    canvas.drawRect(
      Rect.fromCenter(center: snapped, width: trackerSize.width, height: trackerSize.height).deflate(0.5),
      Paint()
        ..color = tracker
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_MinimapPainter old) => old.tracker != tracker || old.orbit != orbit;
}
