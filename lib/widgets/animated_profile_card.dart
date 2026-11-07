import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// Theme-derived colours for the account console: the ink follows the studio
/// theme (off-white in Dark Grading, obsidian in Daylight) and the accent is
/// Lusion Electric Blue (lifted in Dark Grading so it reads on the void).
extension _ConsoleInk on BuildContext {
  Color get ink => photon.colors.carbon;

  Color get accent => photon.colors.violetInk;

  /// A sunken well: black in the dark, a pale cool tint in the light.
  Color sunk(double alpha) => photon.colors.isDark
      ? Colors.black.withValues(alpha: alpha)
      : photon.colors.surface.withValues(alpha: (alpha * 3).clamp(0.0, 1.0));
}

/// The drawer tabs under the card.
enum ProfileTab {
  identity('IDENTITY', 'profile-tab-identity'),
  plan('PLAN & QUOTA', 'profile-tab-plan'),
  auth('AUTH & KEYS', 'profile-tab-auth');

  const ProfileTab(this.label, this.keyName);

  final String label;
  final String keyName;
}

/// The account console: one architectural card that holds the whole account,
/// in the Lusion palette of whichever studio theme is active (a void with a
/// blue-accented hairline in Dark Grading, white-to-lavender in Daylight Lab).
/// A soft blue aurora drifts behind it while the pointer is over the card (which
/// tilts toward the pointer in 3D; nothing is drawn around the cursor), a conic
/// ring turns around the avatar, and a glass curtain
/// drawer opens under the tabs: identity, plan and quota, auth and keys with
/// the active sessions.
///
/// The header carries the verified badge, the workspace id and a close button;
/// the footer reads out the latest action. Hovering the card opens the drawer
/// if it was folded away; clicking the selected tab folds it, clicking another
/// switches to it. The body scrolls when a tab is taller than the window.
class AnimatedBlueProfileCard extends StatefulWidget {
  const AnimatedBlueProfileCard({super.key, this.onClose});

  /// Shows the close button when set.
  final VoidCallback? onClose;

  @override
  State<AnimatedBlueProfileCard> createState() =>
      _AnimatedBlueProfileCardState();
}

class _AnimatedBlueProfileCardState extends State<AnimatedBlueProfileCard>
    with TickerProviderStateMixin {
  /// The card's tilt (x: about the X axis, y: about Y), radians. It follows the
  /// pointer directly, so it is exactly as smooth as the pointer events are:
  /// no tween is built or restarted per move. Only when the pointer leaves does
  /// [_settle] ease it back to flat, once.
  final ValueNotifier<Offset> _tilt = ValueNotifier(Offset.zero);
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Offset _settleFrom = Offset.zero;

  void _onSettle() {
    _tilt.value = Offset.lerp(
      _settleFrom,
      Offset.zero,
      Curves.easeOutCubic.transform(_settle.value),
    )!;
  }

  late final AnimationController _aurora = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
    value: 0.25,
  );

  /// What the aurora paints from: the drift, in steps. The drift takes 14s a
  /// lap, so drawing it 60 times a second would redraw three card-sized
  /// gradients for no visible gain; 20 steps a second is as smooth to the eye.
  final ValueNotifier<double> _drift = ValueNotifier(0.25);
  static const int _driftSteps = 280;

  void _onAurora() {
    final stepped = (_aurora.value * _driftSteps).floor() / _driftSteps;
    if (stepped != _drift.value) _drift.value = stepped;
  }

  @override
  void initState() {
    super.initState();
    _aurora.addListener(_onAurora);
    _settle.addListener(_onSettle);
  }

  ProfileTab _tab = ProfileTab.identity;
  bool _folded = false;
  bool _hovering = false;
  bool _editing = false;
  bool _animating = false;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _org = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation(StudioScope.of(context).animateShader);
  }

  @override
  void dispose() {
    _settle.removeListener(_onSettle);
    _settle.dispose();
    _tilt.dispose();
    _aurora.removeListener(_onAurora);
    _aurora.dispose();
    _drift.dispose();
    _name.dispose();
    _org.dispose();
    super.dispose();
  }

  /// The aurora drift and the avatar ring turn only while the pointer is over
  /// the card (and animation is on); at rest the card is a still image, so an
  /// open console does not keep the app drawing frames.
  void _syncAnimation(bool animate) {
    final run = animate && _hovering;
    if (run == _animating) return;
    _animating = run;
    if (run) {
      _aurora.repeat();
    } else {
      _aurora.stop();
    }
  }

  void _onTab(ProfileTab tab) => setState(() {
    if (tab == _tab && !_folded) {
      _folded = true;
    } else {
      _tab = tab;
      _folded = false;
    }
  });

  void _toggleEdit(StudioController studio) => setState(() {
    _editing = !_editing;
    if (_editing) {
      _name.text = studio.account.displayName;
      _org.text = studio.account.organization;
    }
  });

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    final c = context.photon.colors;
    final a = studio.account;
    final open = !_folded || _hovering;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Hero(account: a, ring: _aurora),
        const SizedBox(height: PhotonSpace.md),
        _TabBar(selected: open ? _tab : null, onSelect: _onTab),
        // Only opening and folding animate the height. Content changes inside
        // an open drawer (editing, a new tab) resize at once, so nothing
        // overlaps it mid-animation.
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: open ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => Offstage(
            offstage: v == 0,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: v,
                child: child,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: PhotonSpace.sm),
            // A quick cross-fade between tabs (a fade only: no size or layout
            // animation, so the quota bars never restart mid-switch).
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: _Drawer(
                  tab: _tab,
                  studio: studio,
                  editing: _editing,
                  onToggleEdit: () => _toggleEdit(studio),
                  nameController: _name,
                  orgController: _org,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    // Header and footer stay put; only the middle scrolls.
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusRow(
          account: a,
          animate: studio.animateShader && _hovering,
          onClose: widget.onClose,
        ),
        const SizedBox(height: PhotonSpace.md),
        Flexible(child: SingleChildScrollView(child: body)),
        const SizedBox(height: PhotonSpace.sm),
        _StatusStrip(studio: studio),
      ],
    );

    return Semantics(
      container: true,
      label: 'Account console: ${a.displayName}',
      child: MouseRegion(
        onEnter: (_) {
          _settle.stop();
          setState(() => _hovering = true);
          _syncAnimation(StudioScope.read(context).animateShader);
        },
        onExit: (_) {
          _settleFrom = _tilt.value;
          if (_settleFrom != Offset.zero) _settle.forward(from: 0);
          setState(() => _hovering = false);
          _syncAnimation(StudioScope.read(context).animateShader);
        },
        onHover: (e) {
          final box = context.findRenderObject();
          if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return;
          final local = box.globalToLocal(e.position);
          // Up to ~3.4 degrees each way. Whole percents of the card: a finer
          // pointer would only repaint for changes of a hundredth of a degree.
          final px =
              ((local.dx / box.size.width).clamp(0.0, 1.0) * 100).round() / 100;
          final py =
              ((local.dy / box.size.height).clamp(0.0, 1.0) * 100).round() /
              100;
          final next = Offset(-(py - 0.5) * 0.12, (px - 0.5) * 0.12);
          if (next != _tilt.value) _tilt.value = next;
        },
        child: ValueListenableBuilder<Offset>(
          valueListenable: _tilt,
          // The card body is built once per state change, not per pointer move,
          // and sits on its own layer: tilting it re-composites a cached texture
          // instead of re-rasterising the 40px shadow, the gradient and the text
          // on every frame.
          child: RepaintBoundary(
            child: Container(
              key: const Key('profile-card-surface'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                // A 1px hairline; Dark Grading adds the Lusion blue to it.
                border: Border.all(
                  color: c.isDark
                      ? Color.alphaBlend(
                          c.violet.withValues(alpha: 0.45),
                          c.border,
                        )
                      : c.border,
                ),
                boxShadow: [
                  BoxShadow(
                    color: c.violet.withValues(alpha: c.isDark ? 0.22 : 0.10),
                    blurRadius: 40,
                    spreadRadius: -10,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: Stack(
                  children: [
                    // Lusion architectural surface: deep void in Dark Grading, high-key
                    // white-to-lavender in Daylight.
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: c.isDark
                                ? const [
                                    Color(0xFF0B0C10),
                                    Color(0xFF12141C),
                                    Color(0xFF171A28),
                                  ]
                                : const [
                                    Color(0xFFFFFFFF),
                                    Color(0xFFF0F1FA),
                                    Color(0xFFE4E6EF),
                                  ],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _AuroraPainter(
                            aurora: _drift,
                            isDark: c.isDark,
                            blue: c.violet,
                            cyan: const Color(0xFF22D3EE),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(PhotonSpace.md),
                      child: content,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Perspective tilt of the cached card texture (above): one matrix per
          // pointer move, no subtree work.
          builder: (context, tilt, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0011)
              ..rotateX(tilt.dx)
              ..rotateY(tilt.dy),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// `VERIFIED LEAD ARCHITECT` with a pulsing online pip, the workspace tag, and
/// the close button.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.account,
    required this.animate,
    required this.onClose,
  });

  final StudioAccount account;
  final bool animate;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Row(
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: context.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(PhotonRadius.pill),
              border: Border.all(color: context.accent.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FlashingPip(
                  color: const Color(0xFF34D399),
                  size: 6,
                  flash: animate,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'VERIFIED LEAD ARCHITECT',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.labelCaps.copyWith(
                      fontSize: 8,
                      color: context.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Text(
          account.workspaceId,
          style: t.text.mono(
            size: 9.5,
            weight: FontWeight.w600,
            height: 1.2,
            color: context.ink.withValues(alpha: 0.8),
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: PhotonSpace.sm),
          Tooltip(
            message: 'Close (Esc)',
            child: Semantics(
              button: true,
              label: 'Close account console',
              child: HoverBuilder(
                cursor: SystemMouseCursors.click,
                builder: (context, hovered) => GestureDetector(
                  key: const ValueKey('pip-close-account'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.ink.withValues(
                        alpha: hovered ? 0.22 : 0.1,
                      ),
                      border: Border.all(
                        color: context.ink.withValues(
                          alpha: hovered ? 0.7 : 0.3,
                        ),
                      ),
                    ),
                    child: Icon(Icons.close, size: 13, color: context.ink),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The latest action, read out at the foot of the card (the workspace toast
/// sits behind the modal).
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm + 2),
      decoration: BoxDecoration(
        color: context.sunk(0.24),
        borderRadius: BorderRadius.circular(PhotonRadius.pill),
        border: Border.all(color: context.ink.withValues(alpha: 0.1)),
      ),
      child: ValueListenableBuilder<String?>(
        valueListenable: studio.toast,
        builder: (context, message, _) => Row(
          children: [
            Pip(
              color: message == null
                  ? context.ink.withValues(alpha: 0.35)
                  : context.accent,
              size: 5,
            ),
            const SizedBox(width: PhotonSpace.sm),
            Expanded(
              child: Text(
                message ?? 'READY',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.labelCaps.copyWith(
                  fontSize: 8.5,
                  color: message == null
                      ? context.ink.withValues(alpha: 0.5)
                      : context.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Double-ring avatar and the name block.
class _Hero extends StatelessWidget {
  const _Hero({required this.account, required this.ring});

  final StudioAccount account;
  final Animation<double> ring;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final white = c.carbon;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer ring: a conic cyan/blue sweep, turning.
              // Its own layer: the ring's turn repaints this 72px box, never the
              // name block beside it.
              RepaintBoundary(
                child: RotationTransition(
                  turns: ring,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          c.violetInk,
                          c.violet,
                          c.violet.withValues(alpha: 0.06),
                          c.violetInk,
                        ],
                        stops: const [0.0, 0.35, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // Inner ring and the monogram.
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.substrate,
                  border: Border.all(color: c.border, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  account.initials,
                  style: t.text.ui(
                    size: 22,
                    weight: FontWeight.w600,
                    tracking: -0.02,
                    color: white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: PhotonSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                account.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.ui(
                  size: 20,
                  weight: FontWeight.w600,
                  height: 1.2,
                  tracking: -0.02,
                  color: white,
                ),
              ),
              Text(
                account.handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.mono(
                  size: 11,
                  weight: FontWeight.w500,
                  height: 1.4,
                  color: context.accent,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'B.Tech CSE · Lead Rendering & VFX Architect',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.text.ui(
                  size: 11,
                  height: 1.35,
                  color: white.withValues(alpha: 0.88),
                ),
              ),
              Text(
                account.organization,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.mono(
                  size: 9.5,
                  height: 1.5,
                  color: white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.selected, required this.onSelect});

  /// Null when the drawer is folded away.
  final ProfileTab? selected;
  final ValueChanged<ProfileTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.sunk(0.24),
        borderRadius: BorderRadius.circular(PhotonRadius.pill),
        border: Border.all(color: context.ink.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          for (final tab in ProfileTab.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: selected == tab,
                label: tab.label,
                child: HoverBuilder(
                  cursor: SystemMouseCursors.click,
                  builder: (context, hovered) => GestureDetector(
                    key: Key(tab.keyName),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(tab),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 24,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: selected == tab
                            ? context.ink.withValues(alpha: 0.2)
                            : (hovered
                                  ? context.ink.withValues(alpha: 0.1)
                                  : Colors.transparent),
                        borderRadius: BorderRadius.circular(PhotonRadius.pill),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          tab.label,
                          maxLines: 1,
                          style: t.text.labelCaps.copyWith(
                            fontSize: 8.5,
                            color: context.ink.withValues(
                              alpha: selected == tab || hovered ? 1 : 0.7,
                            ),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
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

/// The glass curtain under the tabs.
class _Drawer extends StatelessWidget {
  const _Drawer({
    required this.tab,
    required this.studio,
    required this.editing,
    required this.onToggleEdit,
    required this.nameController,
    required this.orgController,
  });

  final ProfileTab tab;
  final StudioController studio;
  final bool editing;
  final VoidCallback onToggleEdit;
  final TextEditingController nameController;
  final TextEditingController orgController;

  @override
  Widget build(BuildContext context) {
    // Its own layer: the curtain opening, a tab cross-fading or a field being
    // edited repaints the drawer alone, never the card around it.
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(PhotonSpace.md - 2),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // Dark: a frosted wash of ink; Daylight: white cards on lavender.
            colors: context.photon.colors.isDark
                ? [
                    context.ink.withValues(alpha: 0.08),
                    context.ink.withValues(alpha: 0.03),
                  ]
                : [
                    context.photon.colors.substrate,
                    context.photon.colors.surface,
                  ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.photon.colors.border),
        ),
        child: switch (tab) {
          ProfileTab.identity => _IdentityPane(
            studio: studio,
            editing: editing,
            onToggleEdit: onToggleEdit,
            nameController: nameController,
            orgController: orgController,
          ),
          ProfileTab.plan => _PlanPane(studio: studio),
          ProfileTab.auth => _AuthPane(studio: studio),
        },
      ),
    );
  }
}

/// Puts [outer] above [child] when given: a widget answers to two keys (the
/// card's own and the console's long-standing ones) by nesting them.
Widget _alsoKeyed(Key? outer, Widget child) =>
    outer == null ? child : KeyedSubtree(key: outer, child: child);

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: t.text.labelCaps.copyWith(
                fontSize: 7.5,
                color: context.ink.withValues(alpha: 0.55),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.text.mono(
                size: 10,
                height: 1.4,
                color: context.ink.withValues(alpha: 0.92),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A caption over a group of rows.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: t.text.labelCaps.copyWith(
              fontSize: 7.5,
              color: context.ink.withValues(alpha: 0.55),
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Small glass button used inside the drawer. With no [label] it is an icon
/// button.
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = false,
    this.tooltip,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool filled;
  final String? tooltip;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final accent = danger ? t.colors.rose : t.colors.carbon;
    final button = Semantics(
      button: true,
      label: tooltip ?? label,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 24,
            padding: EdgeInsets.symmetric(
              horizontal: label.isEmpty ? 6 : PhotonSpace.sm + 2,
            ),
            decoration: BoxDecoration(
              color: context.ink.withValues(
                alpha: filled ? 0.26 : (hovered ? 0.18 : 0.08),
              ),
              borderRadius: BorderRadius.circular(PhotonRadius.control),
              border: Border.all(
                color: accent.withValues(alpha: hovered || filled ? 0.8 : 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) Icon(icon, size: 12, color: accent),
                if (icon != null && label.isNotEmpty) const SizedBox(width: 4),
                if (label.isNotEmpty)
                  Text(
                    label,
                    style: t.text.labelCaps.copyWith(
                      fontSize: 8,
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _IdentityPane extends StatelessWidget {
  const _IdentityPane({
    required this.studio,
    required this.editing,
    required this.onToggleEdit,
    required this.nameController,
    required this.orgController,
  });

  final StudioController studio;
  final bool editing;
  final VoidCallback onToggleEdit;
  final TextEditingController nameController;
  final TextEditingController orgController;

  @override
  Widget build(BuildContext context) {
    final a = studio.account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _KeyValue('GITHUB', 'github.com/mfarazcodes'),
        _KeyValue('EMAIL', a.email),
        _KeyValue('ROLE', '${a.role} · ${a.organization}'),
        const _KeyValue(
          'NODE',
          'Motorola Motobook 60 · Windows 11 · Vulkan RT',
        ),
        if (editing) ...[
          const SizedBox(height: PhotonSpace.sm),
          _ProfileField(
            fieldKey: const Key('account-name-field'),
            label: 'DISPLAY NAME',
            controller: nameController,
            onChanged: (v) => studio.updateAccountProfile(displayName: v),
          ),
          const SizedBox(height: PhotonSpace.sm),
          _ProfileField(
            fieldKey: const Key('account-org-field'),
            label: 'ORGANIZATION',
            controller: orgController,
            onChanged: (v) => studio.updateAccountProfile(organization: v),
          ),
        ],
        const SizedBox(height: PhotonSpace.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: _GlassButton(
            key: const Key('account-edit-profile-btn'),
            label: editing ? 'DONE' : 'EDIT PROFILE',
            icon: editing ? Icons.check : Icons.edit_outlined,
            filled: editing,
            onTap: onToggleEdit,
          ),
        ),
      ],
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(PhotonRadius.control),
      borderSide: BorderSide(color: color),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: t.text.labelCaps.copyWith(
            fontSize: 7.5,
            color: context.ink.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 30,
          child: TextField(
            key: fieldKey,
            controller: controller,
            onChanged: onChanged,
            maxLines: 1,
            cursorColor: context.accent,
            style: t.text.telemetryMd.copyWith(color: context.ink),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: context.sunk(0.28),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: border(context.ink.withValues(alpha: 0.25)),
              enabledBorder: border(context.ink.withValues(alpha: 0.25)),
              focusedBorder: border(context.accent),
            ),
          ),
        ),
      ],
    );
  }
}

String _group(num n) {
  final s = n.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

String _trim(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

class _PlanPane extends StatelessWidget {
  const _PlanPane({required this.studio});

  final StudioController studio;

  static String _short(PlanTier tier) => switch (tier) {
    PlanTier.indie => 'INDIE LAB',
    PlanTier.pro => 'STUDIO PRO',
    PlanTier.enterprise => 'ENTERPRISE',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final a = studio.account;
    final gpu = a.gpuHoursUsed / a.tier.gpuHours;
    final vault = a.storageUsedGb / a.storageLimitGb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                '${_short(a.tier)} · ${a.tier.price.replaceAll(' ', '')}',
                key: const Key('profile-plan-summary'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.ui(
                  size: 13,
                  weight: FontWeight.w600,
                  color: context.ink,
                ),
              ),
            ),
            const SizedBox(width: PhotonSpace.sm),
            Text(
              a.tier.price,
              style: t.text.mono(
                size: 10,
                height: 1.3,
                color: context.ink.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
        Text(
          a.tier.quota,
          style: t.text.mono(
            size: 9.5,
            height: 1.4,
            color: context.ink.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: PhotonSpace.sm),
        Wrap(
          spacing: PhotonSpace.xs + 2,
          runSpacing: PhotonSpace.xs + 2,
          children: [
            for (final tier in PlanTier.values)
              _alsoKeyed(
                Key('tier-${tier.name}'),
                _TierChip(
                  key: Key('profile-tier-${tier.name}'),
                  label: _short(tier),
                  selected: a.tier == tier,
                  onTap: () => studio.setPlanTier(tier),
                ),
              ),
          ],
        ),
        const SizedBox(height: PhotonSpace.md),
        _QuotaBar(
          title: 'GPU RENDER COMPUTE QUOTA',
          primary:
              '${_trim(a.gpuHoursUsed)} / ${_group(a.tier.gpuHours)} GPU-hrs',
          detail:
              '${_trim(a.gpuHoursUsed)} / ${_group(a.tier.gpuHours)} hrs · ${(gpu * 100).round()}%'
              '${gpu > 1 ? ' · OVER QUOTA' : ''}',
          fraction: gpu,
        ),
        const SizedBox(height: PhotonSpace.sm + 2),
        _QuotaBar(
          title: 'OPENUSD CLOUD VAULT STORAGE',
          primary:
              '${_trim(a.storageUsedGb)} / ${_group(a.storageLimitGb)} GB USD Vault',
          detail:
              '${_trim(a.storageUsedGb)} / ${_trim(a.storageLimitGb)} GB · ${(vault * 100).round()}%',
          fraction: vault,
        ),
      ],
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
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
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(
              horizontal: PhotonSpace.md - 2,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? context.ink.withValues(alpha: 0.9)
                  : context.ink.withValues(alpha: hovered ? 0.16 : 0.06),
              borderRadius: BorderRadius.circular(PhotonRadius.pill),
              border: Border.all(
                color: context.ink.withValues(alpha: selected ? 1 : 0.3),
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: t.text.labelCaps.copyWith(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: selected ? t.colors.onCarbon : context.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A quota: a title, the headline figure, a detail line, and an animated bar
/// that is Lusion blue, and rose when over.
class _QuotaBar extends StatelessWidget {
  const _QuotaBar({
    required this.title,
    required this.primary,
    required this.detail,
    required this.fraction,
  });

  final String title;
  final String primary;
  final String detail;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final over = fraction > 1;
    final hot = fraction > 0.9;
    return Semantics(
      label: title,
      value: detail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.text.labelCaps.copyWith(
              fontSize: 7.5,
              color: context.ink.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                primary,
                maxLines: 1,
                style: t.text.mono(
                  size: 11,
                  weight: FontWeight.w600,
                  height: 1.3,
                  color: context.ink,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                detail,
                maxLines: 1,
                style: t.text.mono(
                  size: 9,
                  height: 1.4,
                  color: over
                      ? t.colors.rose
                      : context.ink.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: fraction.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 520),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: context.ink.withValues(alpha: 0.14),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: v,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: hot
                                ? [const Color(0xFFF59E0B), t.colors.rose]
                                : [t.colors.violet, t.colors.violetInk],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Authentication, API and MCP keys, and the active sessions.
class _AuthPane extends StatefulWidget {
  const _AuthPane({required this.studio});

  final StudioController studio;

  @override
  State<_AuthPane> createState() => _AuthPaneState();
}

class _AuthPaneState extends State<_AuthPane> {
  final Set<String> _revealed = {};

  Future<void> _copy(String secret) async {
    try {
      await Clipboard.setData(ClipboardData(text: secret));
      widget.studio.showToast('KEY COPIED TO CLIPBOARD');
    } catch (_) {
      widget.studio.showToast('CLIPBOARD UNAVAILABLE');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final studio = widget.studio;
    final a = studio.account;
    final system = a.authMethod == AuthMethod.passkey
        ? 'WebAuthn Hardware Passkey + Ed25519 JWT'
        : '${a.authMethod.label} + Ed25519 JWT';
    final muted = context.ink.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('ACTIVE AUTHENTICATION'),
        const SizedBox(height: 2),
        Text(
          system,
          key: const Key('profile-auth-system'),
          style: t.text.mono(
            size: 10.5,
            weight: FontWeight.w600,
            height: 1.4,
            color: context.ink,
          ),
        ),
        Text(
          a.authMethod.label,
          style: t.text.mono(size: 9.5, height: 1.4, color: muted),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            const Pip(color: Color(0xFF22C55E), size: 5),
            const SizedBox(width: PhotonSpace.sm - 2),
            Flexible(
              child: Text(
                'JWT SESSION · TLS 1.3 · Ed25519 Signed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.mono(size: 9, height: 1.4, color: muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: PhotonSpace.sm),
        Wrap(
          spacing: PhotonSpace.xs + 2,
          runSpacing: PhotonSpace.xs + 2,
          children: [
            for (final m in AuthMethod.values)
              _TierChip(
                key: Key('auth-${m.name}'),
                label: m.shortLabel,
                selected: a.authMethod == m,
                onTap: () => studio.setAuthMethod(m),
              ),
          ],
        ),
        const SizedBox(height: PhotonSpace.sm),
        _alsoKeyed(
          const Key('account-2fa-toggle'),
          _SwitchRow(
            key: const Key('profile-2fa-toggle'),
            label: '2FA / TOTP AUTHENTICATOR',
            caption: a.twoFactorEnabled
                ? 'Enabled · 6-digit rolling code'
                : 'Disabled',
            state: a.twoFactorEnabled ? 'ARMED' : 'OFF',
            value: a.twoFactorEnabled,
            onTap: studio.toggleTwoFactor,
          ),
        ),
        _SwitchRow(
          key: const Key('account-hwkey-toggle'),
          label: 'FIPS HARDWARE PASSKEY ENCLAVE',
          caption: a.hardwareKeyBound ? 'Bound · FIDO2 / CTAP2' : 'Not bound',
          state: a.hardwareKeyBound ? 'BOUND' : 'UNBOUND',
          value: a.hardwareKeyBound,
          onTap: studio.toggleHardwareKey,
        ),
        const SizedBox(height: PhotonSpace.sm),
        _SectionLabel(
          'API & MCP KEYS',
          trailing: _GlassButton(
            key: const Key('create-api-key-btn'),
            label: '+ NEW KEY',
            onTap: () =>
                studio.createApiKey('Studio Key ${a.apiKeys.length + 1}'),
          ),
        ),
        const SizedBox(height: PhotonSpace.sm - 2),
        if (a.apiKeys.isEmpty)
          Text(
            'NO ACTIVE KEYS',
            style: t.text.labelCaps.copyWith(color: muted),
          ),
        for (var i = 0; i < a.apiKeys.length; i++) ...[
          _KeyRow(
            record: a.apiKeys[i],
            primary: i == 0,
            revealed: _revealed.contains(a.apiKeys[i].id),
            onReveal: () => setState(() {
              if (!_revealed.remove(a.apiKeys[i].id)) {
                _revealed.add(a.apiKeys[i].id);
              }
            }),
            onCopy: () => _copy(a.apiKeys[i].secret),
            onRotate: () => studio.rotateApiKey(a.apiKeys[i].id),
          ),
          const SizedBox(height: PhotonSpace.sm - 2),
        ],
        const SizedBox(height: PhotonSpace.xs),
        _SectionLabel(
          'ACTIVE CLUSTER & AGENT SESSIONS',
          trailing: Text(
            '${a.sessions.length}',
            style: t.text.mono(size: 9, height: 1.2, color: muted),
          ),
        ),
        const SizedBox(height: PhotonSpace.sm - 2),
        for (var i = 0; i < a.sessions.length; i++) ...[
          if (i > 0)
            Divider(
              height: PhotonSpace.md,
              thickness: 1,
              color: context.ink.withValues(alpha: 0.12),
            ),
          _SessionRow(studio: studio, session: a.sessions[i]),
        ],
      ],
    );
  }
}

/// A labelled glass switch with a state word.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.label,
    required this.caption,
    required this.state,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String caption;
  final String state;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Semantics(
      toggled: value,
      label: label,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.labelCaps.copyWith(
                          fontSize: 8.5,
                          color: context.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.mono(
                          size: 9,
                          height: 1.4,
                          color: context.ink.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  state,
                  style: t.text.labelCaps.copyWith(
                    fontSize: 8,
                    color: value
                        ? context.accent
                        : context.ink.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: PhotonSpace.sm),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 32,
                  height: 17,
                  padding: const EdgeInsets.all(2),
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: value
                        ? t.colors.violet
                        : context.ink.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(PhotonRadius.pill),
                    border: Border.all(
                      color: context.ink.withValues(
                        alpha: hovered ? 0.8 : 0.35,
                      ),
                    ),
                  ),
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
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

/// One API or MCP key: its label, the masked (or revealed) secret, and reveal,
/// copy and rotate. The first ("primary") key also answers to the card's own
/// `profile-*` keys.
class _KeyRow extends StatelessWidget {
  const _KeyRow({
    required this.record,
    required this.primary,
    required this.revealed,
    required this.onReveal,
    required this.onCopy,
    required this.onRotate,
  });

  final ApiKeyRecord record;
  final bool primary;
  final bool revealed;
  final VoidCallback onReveal;
  final VoidCallback onCopy;
  final VoidCallback onRotate;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Container(
      padding: const EdgeInsets.all(PhotonSpace.sm),
      decoration: BoxDecoration(
        color: context.sunk(0.2),
        borderRadius: BorderRadius.circular(PhotonRadius.control + 2),
        border: Border.all(color: context.ink.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.ui(
                    size: 12,
                    weight: FontWeight.w500,
                    height: 1.3,
                    color: context.ink,
                  ),
                ),
              ),
              _GlassButton(
                key: Key('reveal-key-${record.id}'),
                label: '',
                icon: revealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                tooltip: revealed ? 'Mask key' : 'Reveal key',
                onTap: onReveal,
              ),
              const SizedBox(width: 4),
              _alsoKeyed(
                primary ? const Key('profile-copy-key-btn') : null,
                _GlassButton(
                  key: Key('copy-key-${record.id}'),
                  label: '',
                  icon: Icons.copy,
                  tooltip: 'Copy key',
                  onTap: onCopy,
                ),
              ),
              const SizedBox(width: 4),
              _alsoKeyed(
                primary ? const Key('profile-rotate-key-btn') : null,
                _GlassButton(
                  key: Key('rotate-key-${record.id}'),
                  label: '',
                  icon: Icons.autorenew,
                  tooltip: 'Rotate key',
                  danger: true,
                  onTap: onRotate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                revealed ? record.secret : record.masked,
                key: primary ? const Key('profile-key-masked') : null,
                maxLines: 1,
                style: t.text.mono(
                  size: 10.5,
                  height: 1.4,
                  color: revealed ? context.accent : context.ink,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'created ${record.created} · used ${record.lastUsed} · ${record.scopes.join(', ')}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.text.mono(
              size: 9,
              height: 1.4,
              color: context.ink.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.studio, required this.session});

  final StudioController studio;
  final ActiveSession session;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, right: PhotonSpace.sm),
          child: Pip(
            color: session.isCurrent ? const Color(0xFF22C55E) : context.accent,
            size: 6,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.device,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.text.ui(
                  size: 12,
                  weight: FontWeight.w500,
                  height: 1.3,
                  color: context.ink,
                ),
              ),
              Text(
                '${session.location} · ${session.ip}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.mono(
                  size: 9.5,
                  height: 1.4,
                  color: context.ink.withValues(alpha: 0.7),
                ),
              ),
              Text(
                '${session.protocol} · ${session.lastActive}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.mono(
                  size: 9,
                  height: 1.4,
                  color: context.ink.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: PhotonSpace.sm),
        if (session.isCurrent)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(PhotonRadius.control - 1),
            ),
            // Light green on the void; a deep green on Daylight's lavender.
            child: Text(
              'THIS DEVICE',
              style: t.text.labelCaps.copyWith(
                fontSize: 7.5,
                color: t.colors.isDark
                    ? const Color(0xFF86EFAC)
                    : const Color(0xFF15803D),
              ),
            ),
          )
        else
          _GlassButton(
            key: Key('revoke-session-${session.id}'),
            label: 'REVOKE',
            danger: true,
            onTap: () => studio.revokeSession(session.id),
          ),
      ],
    );
  }
}

/// The aurora: three drifting Lusion-blue blooms. Nothing follows the cursor:
/// no ring and no spotlight (the card's own tilt is the pointer response).
class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.aurora,
    required this.isDark,
    required this.blue,
    required this.cyan,
  }) : super(repaint: aurora);

  final ValueListenable<double> aurora;
  final bool isDark;

  /// Lusion Electric Blue, and the lifted blue for the second bloom.
  final Color blue;
  final Color cyan;

  @override
  void paint(Canvas canvas, Size size) {
    final a = aurora.value * 2 * math.pi;
    // One Paint for all three blooms; only its shader changes.
    final paint = Paint();
    void bloom(Offset fraction, double radius, Color color) {
      final center = Offset(
        fraction.dx * size.width,
        fraction.dy * size.height,
      );
      final r = radius * size.width;
      canvas.drawCircle(
        center,
        r,
        paint
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    // Lusion Electric Blue at 0.18 (Dark) / 0.08 (Daylight).
    final k = isDark ? 0.18 : 0.08;
    bloom(
      Offset(0.22 + 0.12 * math.sin(a), 0.2 + 0.1 * math.cos(a * 1.3)),
      0.55,
      blue.withValues(alpha: k),
    );
    bloom(
      Offset(0.8 + 0.1 * math.cos(a * 0.8), 0.45 + 0.12 * math.sin(a * 1.1)),
      0.5,
      blue.withValues(alpha: k * 0.8),
    );
    bloom(
      Offset(0.5 + 0.18 * math.sin(a * 0.6 + 2), 0.9 + 0.06 * math.cos(a)),
      0.6,
      cyan.withValues(alpha: k * 0.5),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.aurora != aurora ||
      old.isDark != isDark ||
      old.blue != blue ||
      old.cyan != cyan;
}
