import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// The projects as a pile of loose darkroom prints.
///
/// The active project is the top print; three more fan out underneath at
/// alternating tilts, offsets and scales. Grab the top print and drag it any
/// way: it tilts with the horizontal motion (`dx * 0.0015` rad) and the print
/// below grows toward full size. Let go past 90px, or flick it, and it flies
/// off along its trajectory, the next project becomes active, and the print
/// slides back in at the bottom of the pile. Press and hold to drag a print
/// onto `SCENE_VIEWPORT.rt` instead.
///
/// `PREV` / `NEXT`, the Left and Right arrow keys (while the deck has focus)
/// and `AUTOPLAY` step the same way.
class CardDeckCarousel extends StatefulWidget {
  const CardDeckCarousel({super.key});

  /// How far a release must have travelled, px, to throw the card.
  static const double throwDistance = 90;

  /// Or how fast, px/s.
  static const double throwVelocity = 700;

  static const Duration flyDuration = Duration(milliseconds: 240);
  static const Duration backDuration = Duration(milliseconds: 320);
  static const Duration autoplayInterval = Duration(milliseconds: 3200);

  @override
  State<CardDeckCarousel> createState() => _CardDeckCarouselState();
}

/// Where a print sits in the pile.
@immutable
class _Pose {
  const _Pose(this.rotation, this.dy, this.scale);

  final double rotation;
  final double dy;
  final double scale;

  static _Pose lerp(_Pose a, _Pose b, double t) => _Pose(
    a.rotation + (b.rotation - a.rotation) * t,
    a.dy + (b.dy - a.dy) * t,
    a.scale + (b.scale - a.scale) * t,
  );
}

class _PoseTween extends Tween<_Pose> {
  _PoseTween({required _Pose super.end});

  @override
  _Pose lerp(double t) => _Pose.lerp(begin ?? end!, end!, t);
}

/// Poses by depth: tilts `-3.5, +2.8, -1.8` degrees, offsets `8, 16, 24` px,
/// scales `0.95, 0.90, 0.85`. Depth 4 is the slot a print slides back to.
const List<_Pose> _poses = [
  _Pose(0, 0, 1),
  _Pose(-3.5 * math.pi / 180, 8, 0.95),
  _Pose(2.8 * math.pi / 180, 16, 0.90),
  _Pose(-1.8 * math.pi / 180, 24, 0.85),
  _Pose(2.0 * math.pi / 180, 32, 0.80),
];

class _CardDeckCarouselState extends State<CardDeckCarousel> with TickerProviderStateMixin {
  final FocusNode _focus = FocusNode(debugLabel: 'card-deck');

  /// Top print's displacement while it is held or thrown.
  Offset _drag = Offset.zero;
  bool _dragging = false;

  late final AnimationController _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  late final AnimationController _fly = AnimationController(vsync: this, duration: CardDeckCarousel.flyDuration);
  late final AnimationController _back = AnimationController(vsync: this, duration: CardDeckCarousel.backDuration);
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));

  Offset _settleFrom = Offset.zero;

  /// The print being thrown (and then slid back under the pile).
  StudioProject? _flier;
  Offset _flierStart = Offset.zero;
  Offset _flierDir = const Offset(1, 0);
  Offset _flierEnd = Offset.zero;
  int _flierSlot = 3;

  /// The project that just arrived on top from `PREV`, sliding in.
  String? _enteringId;

  bool _autoplay = false;
  Timer? _autoplayTimer;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      setState(() => _drag = Offset.lerp(_settleFrom, Offset.zero, Curves.easeOutBack.transform(_settle.value))!);
    });
    _fly.addStatusListener((s) {
      if (s == AnimationStatus.completed) _beginBack();
    });
    _back.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _flier = null);
    });
    _enter.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _enteringId = null);
    });
  }

  @override
  void dispose() {
    _autoplayTimer?.cancel();
    _focus.dispose();
    _settle.dispose();
    _fly.dispose();
    _back.dispose();
    _enter.dispose();
    super.dispose();
  }

  bool get _busy => _flier != null;

  List<StudioProject> _order(StudioController studio) {
    final all = studio.projects;
    if (all.isEmpty) return const [];
    final i = all.indexWhere((p) => p.id == studio.activeProjectId);
    final start = i < 0 ? 0 : i;
    return [for (var k = 0; k < all.length; k++) all[(start + k) % all.length]];
  }

  /// Throws the top print along [direction], activating the next project.
  void _throwTop(Offset direction) {
    final studio = StudioScope.read(context);
    final order = _order(studio);
    if (order.length < 2 || _busy) {
      _springBack();
      return;
    }
    final top = order.first;
    _settle.stop();
    _flier = top;
    _flierStart = _drag;
    _flierDir = direction.distance < 1e-6 ? const Offset(1, 0) : direction / direction.distance;
    // The thrown print ends up last in the pile (or off the visible four).
    _flierSlot = math.min(order.length - 1, 4);
    _dragging = false;
    studio.selectProject(order[1].id);
    _back.value = 0;
    _fly.forward(from: 0);
    setState(() {});
  }

  void _beginBack() {
    if (!mounted) return;
    _flierEnd = _flierStart + _flierDir * 520;
    _back.forward(from: 0);
    setState(() {});
  }

  void _springBack() {
    _settleFrom = _drag;
    _dragging = false;
    _settle.forward(from: 0);
  }

  void _next() {
    if (_busy) return;
    _throwTop(const Offset(1, -0.25));
  }

  void _prev() {
    if (_busy) return;
    final studio = StudioScope.read(context);
    final all = studio.projects;
    if (all.length < 2) return;
    final i = all.indexWhere((p) => p.id == studio.activeProjectId);
    final target = all[(i - 1 + all.length) % all.length];
    _drag = Offset.zero;
    _enteringId = target.id;
    studio.selectProject(target.id);
    _enter.forward(from: 0);
    setState(() {});
  }

  void _toggleAutoplay() {
    setState(() => _autoplay = !_autoplay);
    _autoplayTimer?.cancel();
    _autoplayTimer = _autoplay ? Timer.periodic(CardDeckCarousel.autoplayInterval, (_) => _next()) : null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _next();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _prev();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    final t = context.photon;
    final c = t.colors;
    final order = _order(studio);
    if (order.isEmpty) return const SizedBox.shrink();

    final flier = _flier;
    // The thrown print is drawn by itself; everything else is the pile.
    final pile = [for (final p in order) if (p.id != flier?.id) p];
    final visible = pile.take(4).toList();
    final lift = (_drag.distance / 140).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, box) {
        final cardWidth = math.min(box.maxWidth - 20, 172.0);
        final cardHeight = cardWidth * 0.74;
        final stageHeight = cardHeight + _poses[4].dy + 8;

        Widget slot(StudioProject p, int depth) {
          final isTop = depth == 0;
          final base = _poses[depth];
          // The print below the top one grows toward full size as it is dragged.
          final pose = depth == 0 ? base : _Pose.lerp(base, _poses[depth - 1], lift);
          final enter = isTop && p.id == _enteringId ? Curves.easeOutBack.transform(_enter.value) : 1.0;
          Widget card = _DeckCard(project: p, width: cardWidth, height: cardHeight, top: isTop);
          if (isTop) {
            card = _TopCardGestures(
              projectId: p.id,
              width: cardWidth,
              height: cardHeight,
              onPanStart: () {
                _settle.stop();
                _focus.requestFocus();
                setState(() => _dragging = true);
              },
              onPanUpdate: (d) => setState(() => _drag += d),
              onPanEnd: (velocity) {
                final fast = velocity.distance > CardDeckCarousel.throwVelocity;
                if (_drag.distance > CardDeckCarousel.throwDistance || fast) {
                  _throwTop(fast ? velocity : _drag);
                } else {
                  _springBack();
                }
              },
              onTap: () => studio.selectProject(p.id),
              child: card,
            );
            final shift = _drag + Offset((1 - enter) * -220, 0);
            card = Transform.translate(
              offset: shift,
              child: Transform.rotate(angle: _drag.dx * 0.0015, child: card),
            );
          }
          return TweenAnimationBuilder<_Pose>(
            key: ValueKey('deck-slot-${p.id}'),
            tween: _PoseTween(end: pose),
            duration: _dragging ? const Duration(milliseconds: 40) : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (context, v, child) => Transform.translate(
              offset: Offset(0, v.dy),
              child: Transform.rotate(angle: v.rotation, child: Transform.scale(scale: v.scale, child: child)),
            ),
            child: card,
          );
        }

        Widget? flierWidget() {
          if (flier == null) return null;
          final Offset offset;
          final double angle;
          final double scale;
          final double opacity;
          if (_back.isAnimating || _back.value > 0) {
            // Sliding back to the bottom of the pile.
            final u = Curves.easeOutCubic.transform(_back.value);
            final slot = _poses[_flierSlot];
            offset = Offset.lerp(_flierEnd, Offset(0, slot.dy), u)!;
            angle = _flierEnd.dx * 0.0015 + (slot.rotation - _flierEnd.dx * 0.0015) * u;
            scale = 1 + (slot.scale - 1) * u;
            opacity = _flierSlot > 3 ? 1 - u : 1;
          } else {
            final f = Curves.easeIn.transform(_fly.value);
            offset = _flierStart + _flierDir * (520 * f);
            angle = offset.dx * 0.0015;
            scale = 1;
            opacity = 1 - 0.3 * f;
          }
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: offset,
              child: Transform.rotate(
                angle: angle,
                child: Transform.scale(
                  scale: scale,
                  child: _DeckCard(project: flier, width: cardWidth, height: cardHeight, top: false),
                ),
              ),
            ),
          );
        }

        final backing = _back.isAnimating || _back.value > 0;
        final flying = flierWidget();
        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([_fly, _back, _enter]),
                builder: (context, _) => SizedBox(
                  height: stageHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      // Sliding back: under the pile. Flying: over it.
                      if (backing && flying != null) KeyedSubtree(key: const ValueKey('deck-flier'), child: flying),
                      for (var d = visible.length - 1; d >= 0; d--) slot(visible[d], d),
                      if (!backing && flying != null) KeyedSubtree(key: const ValueKey('deck-flier'), child: flying),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: PhotonSpace.xs),
              Row(
                children: [
                  _DeckButton(key: const Key('deck-prev-btn'), label: '◄ PREV', onTap: _prev),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${(studio.projects.indexWhere((p) => p.id == studio.activeProjectId) + 1).toString().padLeft(2, '0')} / ${order.length.toString().padLeft(2, '0')}',
                        key: const Key('deck-counter'),
                        style: t.text.mono(size: 10, weight: FontWeight.w600, height: 1.2, color: c.carbon),
                      ),
                    ),
                  ),
                  _DeckButton(key: const Key('deck-next-btn'), label: 'NEXT ►', onTap: _next),
                ],
              ),
              const SizedBox(height: PhotonSpace.xs + 2),
              _DeckButton(
                key: const Key('deck-autoplay-btn'),
                label: _autoplay ? 'AUTOPLAY · ON' : 'AUTOPLAY',
                onTap: _toggleAutoplay,
                selected: _autoplay,
                expand: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Pan, tap and long-press-to-drag on the top print.
class _TopCardGestures extends StatelessWidget {
  const _TopCardGestures({
    required this.projectId,
    required this.width,
    required this.height,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onTap,
    required this.child,
  });

  final String projectId;
  final double width;
  final double height;
  final VoidCallback onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final ValueChanged<Offset> onPanEnd;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: LongPressDraggable<String>(
        data: projectId,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          type: MaterialType.transparency,
          child: SizedBox(width: width * 0.8, height: height * 0.8, child: Opacity(opacity: 0.9, child: child)),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: child),
        child: GestureDetector(
          key: const Key('deck-top-card'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onPanStart: (_) => onPanStart(),
          onPanUpdate: (d) => onPanUpdate(d.delta),
          onPanEnd: (d) => onPanEnd(d.velocity.pixelsPerSecond),
          child: child,
        ),
      ),
    );
  }
}

/// One print: the preview still with its name, scene and kind.
class _DeckCard extends StatelessWidget {
  const _DeckCard({required this.project, required this.width, required this.height, required this.top});

  final StudioProject project;
  final double width;
  final double height;
  final bool top;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.substrate,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: top ? c.violet.withValues(alpha: 0.6) : c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isDark ? 0.5 : 0.18),
            blurRadius: top ? 14 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            project.previewAsset,
            fit: BoxFit.cover,
            cacheWidth: 400,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => ColoredBox(color: c.hoverFill),
          ),
          // Darken the lower third for the caption.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xCC000000)],
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.mono(size: 10, weight: FontWeight.w700, height: 1.25, color: Colors.white),
                ),
                Text(
                  project.sceneType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.labelCaps.copyWith(fontSize: 7, color: Colors.white.withValues(alpha: 0.72)),
                ),
              ],
            ),
          ),
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(PhotonRadius.control - 1),
              ),
              child: Text(
                project.isDynamic ? '⚡ LIVE' : 'STILL',
                style: t.text.labelCaps.copyWith(fontSize: 6.5, color: Colors.white, letterSpacing: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckButton extends StatelessWidget {
  const _DeckButton({super.key, required this.label, required this.onTap, this.selected = false, this.expand = false});

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 22,
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? c.violet.withValues(alpha: 0.16) : (hovered ? c.hoverFill : Colors.transparent),
              borderRadius: BorderRadius.circular(PhotonRadius.pill),
              border: Border.all(color: selected ? c.violet : (hovered ? c.violet.withValues(alpha: 0.5) : c.border)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: t.text.labelCaps.copyWith(fontSize: 8, color: selected ? c.violetInk : c.textMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
