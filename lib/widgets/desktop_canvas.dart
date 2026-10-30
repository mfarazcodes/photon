import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../models/desktop_node.dart';
import '../painters/photon_floaters.dart';
import '../painters/photon_wordmark_painter.dart';
import '../physics/gravity_engine.dart';
import '../state/workspace_controller.dart';
import '../theme/photon_theme.dart';
import 'desktop_icon.dart';

/// Layout constants of the explore dock, shared with the physics obstacle.
const double kDockHeight = 76;
const double kDockBottomGap = 18;
const double kDockMaxWidth = 690;

/// The spatial desktop: studio backdrop, wordmark, nodes and the engine card.
/// Nodes are rigid bodies owned by a [GravityEngine].
class DesktopCanvas extends StatefulWidget {
  const DesktopCanvas({super.key});

  @override
  State<DesktopCanvas> createState() => _DesktopCanvasState();
}

class _DesktopCanvasState extends State<DesktopCanvas>
    with SingleTickerProviderStateMixin {
  final GravityEngine _engine = GravityEngine();
  final GlobalKey _stackKey = GlobalKey();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool? _gravity;
  WorkspaceController? _ws;

  /// Mouse position normalised to -1..1, eased each frame. Feeds the
  /// wordmark and floaters so the centerpiece tilts toward the cursor.
  final ValueNotifier<Offset> _parallax = ValueNotifier(Offset.zero);
  Offset _parallaxTarget = Offset.zero;

  @override
  void initState() {
    super.initState();
    for (final node in kDesktopNodes) {
      _engine.body(node.id, kIconBox);
    }
    _engine.body(kCoreCardId, kCoreCardBox);
    _ticker = createTicker(_tick)..start();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _engine.step(dt);

    final k = 1 - math.exp(-dt.clamp(0.0, 0.1) * 6);
    final next = _parallax.value + (_parallaxTarget - _parallax.value) * k;
    if ((next - _parallax.value).distanceSquared > 1e-6) _parallax.value = next;
  }

  bool _typing() {
    final focus = FocusManager.instance.primaryFocus;
    return focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Global shortcuts: Space toggles gravity, Ctrl+N toggles the prompt
  /// drawer, Escape closes the topmost window or overlay.
  bool _onKey(KeyEvent event) {
    final ws = _ws;
    if (ws == null || event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (key == LogicalKeyboardKey.escape) {
      ws.escape();
      return true;
    }
    if (ctrl && key == LogicalKeyboardKey.keyN) {
      ws.togglePromptDrawer();
      return true;
    }
    if (key == LogicalKeyboardKey.space && !ctrl && !_typing()) {
      ws.setGravity(!ws.gravity);
      return true;
    }
    return false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ws = WorkspaceScope.of(context);
    _ws = ws;
    final on = ws.gravity;
    if (_gravity != null && on != _gravity) {
      on ? _engine.drop() : _engine.lift();
    }
    _gravity = on;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _ticker.dispose();
    _engine.dispose();
    _parallax.dispose();
    super.dispose();
  }

  /// Docked position of a body. [halfW] includes the label overhang so long
  /// file names never clip off-screen, and icons above the dock stay clear.
  Offset _home(String id, Offset fraction, Size size, Size box, double halfW) {
    final f = _engine.pinned[id] ?? fraction;
    double fit(double v, double lo, double hi) =>
        hi < lo ? (lo + hi) / 2 : math.min(hi, math.max(lo, v));
    final x = fit(f.dx * size.width, halfW + 8, size.width - halfW - 8);
    var maxY = size.height - box.height / 2 - 8;
    final dockHalf = math.min(kDockMaxWidth, size.width - 32) / 2;
    if ((x - size.width / 2).abs() < dockHalf + halfW) {
      maxY = math.min(
          maxY, size.height - kDockBottomGap - kDockHeight - 10 - box.height / 2);
    }
    return Offset(x, fit(f.dy * size.height, box.height / 2 + 84, maxY));
  }

  static double _labelHalf(DesktopNode node) =>
      math.max(kIconBox.width / 2, node.label.length * 4.4 + 10);

  Offset _toCanvas(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      // Live window size drives the floor, walls and the dock obstacle.
      _engine.setBounds(size);
      final dockW = math.min(kDockMaxWidth, size.width - 32);
      _engine.obstacles
        ..clear()
        ..add(Rect.fromLTWH((size.width - dockW) / 2,
            size.height - kDockBottomGap - kDockHeight, dockW, kDockHeight));

      for (final node in ws.nodes) {
        _engine.body(node.id, kIconBox);
        _engine.setHome(
            node.id, _home(node.id, node.home, size, kIconBox, _labelHalf(node)));
      }
      _engine.setHome(
        kCoreCardId,
        _home(kCoreCardId, const Offset(0.5, 0.49), size, kCoreCardBox,
            kCoreCardBox.width / 2),
      );

      return MouseRegion(
        onHover: (e) => _parallaxTarget = Offset(
          (e.localPosition.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
          (e.localPosition.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
        ),
        onExit: (_) => _parallaxTarget = Offset.zero,
        child: Stack(
          key: _stackKey,
          children: [
            // Flat studio floor; tapping it clears the selection.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ws.select(null),
                child: const ColoredBox(color: PC.canvasTop),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(child: PhotonWordmark(parallax: _parallax)),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(child: PhotonFloaters(parallax: _parallax)),
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _engine,
                builder: (context, _) => Stack(
                  children: [
                    for (final node in ws.nodes)
                      _body(
                        node.id,
                        onTap: () => ws.openNode(node),
                        child: RepaintBoundary(
                          child: DesktopIcon(
                            key: ValueKey(node.id),
                            node: node,
                            selected: ws.selectedId == node.id,
                          ),
                        ),
                      ),
                    _body(
                      kCoreCardId,
                      onTap: ws.openInspector,
                      child: const RepaintBoundary(
                        child: CoreCard(key: ValueKey(kCoreCardId)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _body(String id, {required VoidCallback onTap, required Widget child}) {
    final b = _engine.bodies[id]!;
    final ws = WorkspaceScope.read(context);
    return Positioned(
      key: ValueKey('body:$id'),
      left: b.pos.dx - b.size.width / 2,
      top: b.pos.dy - b.size.height / 2,
      width: b.size.width,
      height: b.size.height,
      child: Transform.rotate(
        angle: b.angle,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onTap,
          onPanStart: (d) {
            ws.select(id);
            _engine.beginDrag(id, _toCanvas(d.globalPosition));
          },
          onPanUpdate: (d) => _engine.updateDrag(id, _toCanvas(d.globalPosition)),
          // Throw: pointer velocity + spin go straight into the rigid body.
          onPanEnd: (d) => _engine.endDrag(id, d.velocity.pixelsPerSecond),
          onPanCancel: () => _engine.endDrag(id, Offset.zero),
          child: MouseRegion(
            cursor: _engine.phase == GravityPhase.falling
                ? SystemMouseCursors.grab
                : SystemMouseCursors.click,
            child: child,
          ),
        ),
      ),
    );
  }
}
