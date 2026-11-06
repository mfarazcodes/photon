import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';
import 'project_image.dart';

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

  /// Card height over width.
  static const double _cardAspect = 0.64;

  /// Vertical room the deck needs besides its cards: the pile's fan, and the
  /// PREV / NEXT and AUTOPLAY rows.
  static const double _chromeHeight = 134;

  /// The shortest stage the deck is laid out for: the cards at their smallest,
  /// the pile's fan, and both control rows.
  static const double minDesignHeight = 226;

  /// Decode width for the prints.

  static const int imageWidth = 640;

  static const Duration flyDuration = Duration(milliseconds: 240);
  static const Duration backDuration = Duration(milliseconds: 320);
  static const Duration autoplayInterval = Duration(milliseconds: 3200);

  @override
  State<CardDeckCarousel> createState() => _CardDeckCarouselState();
}

/// Where a print sits in the pile.
@immutable
class _Pose {
  const _Pose(this.rotation, this.dy, this.scale, [this.pitch = 0]);

  /// Z tilt, radians.
  final double rotation;
  final double dy;
  final double scale;

  /// X-axis pitch, radians: the pile leans back into the perspective.
  final double pitch;

  static _Pose lerp(_Pose a, _Pose b, double t) => _Pose(
    a.rotation + (b.rotation - a.rotation) * t,
    a.dy + (b.dy - a.dy) * t,
    a.scale + (b.scale - a.scale) * t,
    a.pitch + (b.pitch - a.pitch) * t,
  );

  // Value equality: the implicit pose animation must see an unchanged target as
  // unchanged, or every rebuild (one per frame while a print flies) would
  // restart it and flatten the spring.
  @override
  bool operator ==(Object other) =>
      other is _Pose && other.rotation == rotation && other.dy == dy && other.scale == scale && other.pitch == pitch;

  @override
  int get hashCode => Object.hash(rotation, dy, scale, pitch);

  /// The pose as a perspective transform about the print's centre.
  Matrix4 get matrix => Matrix4.identity()
    ..setEntry(3, 2, _perspective)
    ..translateByDouble(0, dy, 0, 1)
    ..rotateX(pitch)
    ..rotateZ(rotation)
    ..scaleByDouble(scale, scale, 1, 1);
}

/// Perspective strength of the whole deck.
const double _perspective = 0.0015;

class _PoseTween extends Tween<_Pose> {
  _PoseTween({required _Pose super.end});

  @override
  _Pose lerp(double t) => _Pose.lerp(begin ?? end!, end!, t);
}

/// Poses by depth: a 3D fan with tilts `-4.2, +3.2, -2.2` degrees, offsets
/// `14, 28, 40` px, scales `0.93, 0.86, 0.79` and a growing pitch. Depth 4 is
/// the slot a print slides back to.
const List<_Pose> _poses = [
  _Pose(0, 0, 1),
  _Pose(-4.2 * math.pi / 180, 14, 0.93, 0.05),
  _Pose(3.2 * math.pi / 180, 28, 0.86, 0.08),
  _Pose(-2.2 * math.pi / 180, 40, 0.79, 0.11),
  _Pose(2.0 * math.pi / 180, 50, 0.74, 0.13),
];

class _CardDeckCarouselState extends State<CardDeckCarousel> with TickerProviderStateMixin {
  final FocusNode _focus = FocusNode(debugLabel: 'card-deck');

  /// Top print's displacement while it is held or thrown. A notifier, not
  /// state: a drag moves it dozens of times a second, and only the card stage
  /// listens, so the controls and counter beside it are not rebuilt.
  final ValueNotifier<Offset> _dragNotifier = ValueNotifier(Offset.zero);
  Offset get _drag => _dragNotifier.value;
  set _drag(Offset value) => _dragNotifier.value = value;
  bool _dragging = false;

  /// The cards last built, reused while their project, size and role are
  /// unchanged: Flutter skips rebuilding a widget it is handed again unchanged.
  final Map<String, _DeckCard> _cards = {};

  _DeckCard _card(StudioProject p, double width, double height, bool top) {
    final cached = _cards[p.id];
    if (cached != null && identical(cached.project, p) && cached.width == width && cached.height == height && cached.top == top) {
      return cached;
    }
    return _cards[p.id] = _DeckCard(project: p, width: width, height: height, top: top);
  }

  /// Springs a released print home: slightly under-damped, so it settles with
  /// one small overshoot. Unbounded, so the overshoot is not clamped away.
  late final AnimationController _settle = AnimationController.unbounded(vsync: this);
  static final SpringDescription _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 340, ratio: 0.74);
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
    _settle.addListener(() => _drag = Offset.lerp(_settleFrom, Offset.zero, _settle.value)!);
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
    _dragNotifier.dispose();
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
    // The next print arrives on top where the pile is, not where the thrown
    // one was let go.
    _drag = Offset.zero;
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
    _settle.value = 0;
    _settle.animateWith(SpringSimulation(_spring, 0, 1, 0));
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

    return LayoutBuilder(
      builder: (context, box) {
        // Generous on the centre stage: over half its width, to 520px. It
        // also stays inside the box on a short stage or a narrow window.
        final byWidth = math.min((box.maxWidth * 0.56).clamp(260.0, 520.0), box.maxWidth - 24);
        final byHeight = box.hasBoundedHeight ? (box.maxHeight - CardDeckCarousel._chromeHeight) / CardDeckCarousel._cardAspect : double.infinity;
        final cardWidth = math.max(120.0, math.min(byWidth, byHeight));
        final cardHeight = cardWidth * CardDeckCarousel._cardAspect;
        final stageHeight = cardHeight + _poses[4].dy + 8;

        Widget slot(StudioProject p, int depth) {
          final isTop = depth == 0;
          final base = _poses[depth];
          // The print below the top one grows toward full size as it is dragged.
          final lift = (_drag.distance / 110).clamp(0.0, 1.0);
          final pose = depth == 0 ? base : _Pose.lerp(base, _poses[depth - 1], lift);
          final enter = isTop && p.id == _enteringId ? Curves.easeOutBack.transform(_enter.value) : 1.0;
          Widget card = _card(p, cardWidth, cardHeight, isTop);
          if (!isTop) {
            // A print showing under the top one is one click from the top.
            card = MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: ValueKey('deck-peek-${p.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: _busy ? null : () => studio.selectProject(p.id),
                child: card,
              ),
            );
          }
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
              onPanUpdate: (d) => _drag += d,
              onPanEnd: (velocity) {
                final fast = velocity.distance > CardDeckCarousel.throwVelocity;
                if (_drag.distance > CardDeckCarousel.throwDistance || fast) {
                  _throwTop(fast ? velocity : _drag);
                } else {
                  _springBack();
                }
              },
              onTap: () {
                // Tapping the top print opens that project, full screen.
                studio.selectProject(p.id);
                studio.setDeckView(false);
                studio.setMaximizedPanel('viewport');
              },
              child: card,
            );
            // Bank and yaw with the drag, in perspective.
            card = Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, _perspective)
                ..translateByDouble(_drag.dx + (1 - enter) * -220, _drag.dy, 0, 1)
                ..rotateX(-_drag.dy * 0.001)
                ..rotateY(_drag.dx * 0.0014)
                ..rotateZ(_drag.dx * 0.0018),
              child: card,
            );
          }
          return TweenAnimationBuilder<_Pose>(
            key: ValueKey('deck-slot-${p.id}'),
            tween: _PoseTween(end: pose),
            duration: _dragging ? const Duration(milliseconds: 40) : const Duration(milliseconds: 320),
            // The print surfacing to the front pops with a little overshoot.
            curve: _dragging ? Curves.easeOutCubic : Curves.easeOutBack,
            builder: (context, v, child) => Transform(
              alignment: Alignment.center,
              transform: v.matrix,
              child: child,
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
          var arcLift = 0.0, yaw = 0.0, pitch = 0.0;
          if (_back.isAnimating || _back.value > 0) {
            // Sliding back to the bottom of the pile.
            final u = Curves.easeOutCubic.transform(_back.value);
            final slot = _poses[_flierSlot];
            offset = Offset.lerp(_flierEnd, Offset(0, slot.dy), u)!;
            angle = _flierEnd.dx * 0.0018 + (slot.rotation - _flierEnd.dx * 0.0018) * u;
            scale = 1 + (slot.scale - 1) * u;
            opacity = _flierSlot > 3 ? 1 - u : 1;
            yaw = _flierEnd.dx * 0.0014 * (1 - u);
            pitch = slot.pitch * u;
          } else {
            // An arcing 3D throw: fast off the hand, then easing out.
            final f = Curves.easeOutExpo.transform(_fly.value);
            offset = _flierStart + _flierDir * (520 * f);
            arcLift = -math.sin(math.pi * f) * 36;
            angle = offset.dx * 0.0018;
            yaw = offset.dx * 0.0014;
            scale = 1;
            opacity = 1 - 0.3 * f;
          }
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, _perspective)
                ..translateByDouble(offset.dx, offset.dy + arcLift, 0, 1)
                ..rotateX(pitch)
                ..rotateY(yaw)
                ..rotateZ(angle)
                ..scaleByDouble(scale, scale, 1, 1),
              child: _card(flier, cardWidth, cardHeight, false),
            ),
          );
        }

        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          // The controls are as wide as the cards, not the whole stage.
          child: SizedBox(
            width: cardWidth + 24,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([_fly, _back, _enter, _dragNotifier]),
                builder: (context, _) {
                  // Read the flight's controllers here, per frame: this is the
                  // only part of the deck that rebuilds while a print flies.
                  final backing = _back.isAnimating || _back.value > 0;
                  final flying = flierWidget();
                  return SizedBox(
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
                  );
                },
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
    // Its own layer: dragging or flying the print recomposites a cached
    // texture and never repaints the image or the caption.
    return RepaintBoundary(
      child: Container(
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
          ProjectImage(project: project, cacheWidth: CardDeckCarousel.imageWidth, iconSize: 28),
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
          if (top)
            Positioned(
              right: 6,
              top: 6,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: math.max(0.0, width - 70)),
                child: Container(
                  key: const Key('deck-open-hint'),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: c.violet.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(PhotonRadius.control - 1),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'TAP TO OPEN FULLSCREEN · SWIPE TO CYCLE',
                      maxLines: 1,
                      style: t.text.labelCaps.copyWith(fontSize: 6.5, color: Colors.white, letterSpacing: 0.4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
