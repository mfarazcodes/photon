import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// The drawer tabs under the card.
enum ProfileTab {
  identity('IDENTITY', 'profile-tab-identity'),
  plan('PLAN & QUOTA', 'profile-tab-plan'),
  auth('AUTH & KEYS', 'profile-tab-auth');

  const ProfileTab(this.label, this.keyName);

  final String label;
  final String keyName;
}

/// The account's identity card: an electric-blue architectural card with an
/// aurora light field that follows the cursor (and tilts the card toward it in
/// 3D), a rotating conic ring around the avatar, and a glass curtain drawer
/// that opens under the tabs: identity, plan and quota, auth and keys.
///
/// Hovering the card opens the drawer if it was folded away; clicking the
/// selected tab folds it, clicking another switches to it.
class AnimatedBlueProfileCard extends StatefulWidget {
  const AnimatedBlueProfileCard({super.key});

  static const Color navy = Color(0xFF0A192F);
  static const Color cobalt = Color(0xFF1E3A8A);
  static const Color electric = Color(0xFF2563EB);
  static const Color cyan = Color(0xFF06B6D4);

  @override
  State<AnimatedBlueProfileCard> createState() => _AnimatedBlueProfileCardState();
}

class _AnimatedBlueProfileCardState extends State<AnimatedBlueProfileCard> with SingleTickerProviderStateMixin {
  /// Pointer over the card, 0..1 in both axes; null when it is elsewhere.
  final ValueNotifier<Offset?> _pointer = ValueNotifier(null);
  late final AnimationController _aurora = AnimationController(vsync: this, duration: const Duration(seconds: 14), value: 0.25);

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
    _pointer.dispose();
    _aurora.dispose();
    _name.dispose();
    _org.dispose();
    super.dispose();
  }

  void _syncAnimation(bool animate) {
    if (animate == _animating) return;
    _animating = animate;
    if (animate) {
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
    final a = studio.account;
    final open = !_folded || _hovering;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusRow(account: a, animate: studio.animateShader),
        const SizedBox(height: PhotonSpace.md),
        _Hero(account: a, ring: _aurora),
        const SizedBox(height: PhotonSpace.md),
        _TabBar(selected: open ? _tab : null, onSelect: _onTab),
        // Only opening and folding animate the height. Content changes inside
        // an open drawer (editing, a new tab) resize at once, so the cards
        // below never overlap it mid-animation.
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: open ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => Offstage(
            offstage: v == 0,
            child: ClipRect(
              child: Align(alignment: Alignment.topCenter, heightFactor: v, child: child),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: PhotonSpace.sm),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
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

    return Semantics(
      container: true,
      label: 'Profile card: ${a.displayName}',
      child: MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) {
        _pointer.value = null;
        setState(() => _hovering = false);
      },
      onHover: (e) {
        final box = context.findRenderObject();
        if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return;
        final local = box.globalToLocal(e.position);
        _pointer.value = Offset(
          (local.dx / box.size.width).clamp(0.0, 1.0),
          (local.dy / box.size.height).clamp(0.0, 1.0),
        );
      },
      child: ValueListenableBuilder<Offset?>(
        valueListenable: _pointer,
        // The card body is built once per state change, not per pointer move.
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AnimatedBlueProfileCard.cyan.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(color: AnimatedBlueProfileCard.cyan.withValues(alpha: 0.22), blurRadius: 26, spreadRadius: -4),
              BoxShadow(color: AnimatedBlueProfileCard.electric.withValues(alpha: 0.3), blurRadius: 40, spreadRadius: -10, offset: const Offset(0, 14)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Stack(
              children: [
                // Deep cobalt-to-cyan backdrop.
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AnimatedBlueProfileCard.navy,
                          AnimatedBlueProfileCard.cobalt,
                          AnimatedBlueProfileCard.electric,
                          AnimatedBlueProfileCard.cyan,
                        ],
                        stops: [0.0, 0.42, 0.78, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _AuroraPainter(pointer: _pointer, aurora: _aurora)),
                  ),
                ),
                Padding(padding: const EdgeInsets.all(PhotonSpace.md), child: content),
              ],
            ),
          ),
        ),
        builder: (context, p, child) {
          // 3D tilt toward the pointer: up to ~7 degrees.
          final tiltY = p == null ? 0.0 : (p.dx - 0.5) * 0.12;
          final tiltX = p == null ? 0.0 : -(p.dy - 0.5) * 0.12;
          return TweenAnimationBuilder<Offset>(
            tween: Tween<Offset>(end: Offset(tiltX, tiltY)),
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: child,
            builder: (context, tilt, child) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0011)
                ..rotateX(tilt.dx)
                ..rotateY(tilt.dy),
              child: child,
            ),
          );
        },
      ),
      ),
    );
  }
}

/// `VERIFIED LEAD ARCHITECT` with a pulsing online pip, and the workspace tag.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.account, required this.animate});

  final StudioAccount account;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Row(
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AnimatedBlueProfileCard.cyan.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(PhotonRadius.pill),
              border: Border.all(color: AnimatedBlueProfileCard.cyan.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FlashingPip(color: const Color(0xFF34D399), size: 6, flash: animate),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'VERIFIED LEAD ARCHITECT',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.labelCaps.copyWith(fontSize: 8, color: const Color(0xFFCFFAFE), fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: PhotonSpace.sm),
        Text(
          account.workspaceId,
          style: t.text.mono(size: 9.5, weight: FontWeight.w600, height: 1.2, color: Colors.white.withValues(alpha: 0.8)),
        ),
      ],
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
    final white = Colors.white;
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
              RotationTransition(
                turns: ring,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        AnimatedBlueProfileCard.cyan,
                        AnimatedBlueProfileCard.electric,
                        Color(0x1006B6D4),
                        AnimatedBlueProfileCard.cyan,
                      ],
                      stops: [0.0, 0.35, 0.7, 1.0],
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
                  color: AnimatedBlueProfileCard.navy,
                  border: Border.all(color: white.withValues(alpha: 0.18), width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  account.initials,
                  style: t.text.ui(size: 22, weight: FontWeight.w600, tracking: -0.02, color: white),
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
                style: t.text.ui(size: 20, weight: FontWeight.w600, height: 1.2, tracking: -0.02, color: white),
              ),
              Text(
                account.handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.mono(size: 11, weight: FontWeight.w500, height: 1.4, color: const Color(0xFF67E8F9)),
              ),
              const SizedBox(height: 3),
              Text(
                'B.Tech CSE · Lead Rendering & VFX Architect',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.text.ui(size: 11, height: 1.35, color: white.withValues(alpha: 0.88)),
              ),
              Text(
                account.organization,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.mono(size: 9.5, height: 1.5, color: white.withValues(alpha: 0.6)),
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
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(PhotonRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
                            ? Colors.white.withValues(alpha: 0.2)
                            : (hovered ? Colors.white.withValues(alpha: 0.1) : Colors.transparent),
                        borderRadius: BorderRadius.circular(PhotonRadius.pill),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          tab.label,
                          maxLines: 1,
                          style: t.text.labelCaps.copyWith(
                            fontSize: 8.5,
                            color: Colors.white.withValues(alpha: selected == tab || hovered ? 1 : 0.7),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PhotonSpace.md - 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0.06)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
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
    );
  }
}

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
            child: Text(label, style: t.text.labelCaps.copyWith(fontSize: 7.5, color: Colors.white.withValues(alpha: 0.55))),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.text.mono(size: 10, height: 1.4, color: Colors.white.withValues(alpha: 0.92)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small glass button used inside the drawer.
class _GlassButton extends StatelessWidget {
  const _GlassButton({super.key, required this.label, required this.onTap, this.icon, this.filled = false});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Semantics(
      button: true,
      label: label,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm + 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: filled ? 0.26 : (hovered ? 0.18 : 0.08)),
              borderRadius: BorderRadius.circular(PhotonRadius.control),
              border: Border.all(color: Colors.white.withValues(alpha: hovered || filled ? 0.7 : 0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 11, color: Colors.white), const SizedBox(width: 4)],
                Text(label, style: t.text.labelCaps.copyWith(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
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
        const _KeyValue('NODE', 'Motorola Motobook 60 · Windows 11 · Vulkan RT'),
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
  const _ProfileField({required this.fieldKey, required this.label, required this.controller, required this.onChanged});

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
        Text(label, style: t.text.labelCaps.copyWith(fontSize: 7.5, color: Colors.white.withValues(alpha: 0.6))),
        const SizedBox(height: 3),
        SizedBox(
          height: 30,
          child: TextField(
            key: fieldKey,
            controller: controller,
            onChanged: onChanged,
            maxLines: 1,
            cursorColor: AnimatedBlueProfileCard.cyan,
            style: t.text.telemetryMd.copyWith(color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.28),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: border(Colors.white.withValues(alpha: 0.25)),
              enabledBorder: border(Colors.white.withValues(alpha: 0.25)),
              focusedBorder: border(AnimatedBlueProfileCard.cyan),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_short(a.tier)} · ${a.tier.price.replaceAll(' ', '')}',
          key: const Key('profile-plan-summary'),
          style: t.text.ui(size: 13, weight: FontWeight.w600, color: Colors.white),
        ),
        const SizedBox(height: PhotonSpace.sm),
        Wrap(
          spacing: PhotonSpace.xs + 2,
          runSpacing: PhotonSpace.xs + 2,
          children: [
            for (final tier in PlanTier.values)
              _TierChip(
                key: Key('profile-tier-${tier.name}'),
                label: _short(tier),
                selected: a.tier == tier,
                onTap: () => studio.setPlanTier(tier),
              ),
          ],
        ),
        const SizedBox(height: PhotonSpace.md),
        _ProgressRow(
          label: '${_trim(a.gpuHoursUsed)} / ${_group(a.tier.gpuHours)} GPU-hrs',
          fraction: a.gpuHoursUsed / a.tier.gpuHours,
        ),
        const SizedBox(height: PhotonSpace.sm),
        _ProgressRow(
          label: '${_trim(a.storageUsedGb)} / ${_group(a.storageLimitGb)} GB USD Vault',
          fraction: a.storageUsedGb / a.storageLimitGb,
        ),
      ],
    );
  }

  static String _trim(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

class _TierChip extends StatelessWidget {
  const _TierChip({super.key, required this.label, required this.selected, required this.onTap});

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
            padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md - 2, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? Colors.white.withValues(alpha: 0.9) : Colors.white.withValues(alpha: hovered ? 0.16 : 0.06),
              borderRadius: BorderRadius.circular(PhotonRadius.pill),
              border: Border.all(color: Colors.white.withValues(alpha: selected ? 1 : 0.3)),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: t.text.labelCaps.copyWith(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: selected ? AnimatedBlueProfileCard.navy : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.label, required this.fraction});

  final String label;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final f = fraction.clamp(0.0, 1.0);
    final hot = fraction > 0.9;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.text.mono(size: 9.5, height: 1.3, color: Colors.white.withValues(alpha: 0.9))),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: f),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: Colors.white.withValues(alpha: 0.14))),
                  FractionallySizedBox(
                    widthFactor: v,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: hot
                              ? const [Color(0xFFF59E0B), Color(0xFFFF2D78)]
                              : const [AnimatedBlueProfileCard.cyan, Color(0xFF67E8F9)],
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
    );
  }
}

class _AuthPane extends StatelessWidget {
  const _AuthPane({required this.studio});

  final StudioController studio;

  Future<void> _copy(ApiKeyRecord key) async {
    try {
      await Clipboard.setData(ClipboardData(text: key.secret));
      studio.showToast('KEY COPIED TO CLIPBOARD');
    } catch (_) {
      studio.showToast('CLIPBOARD UNAVAILABLE');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final a = studio.account;
    final key = a.apiKeys.isEmpty ? null : a.apiKeys.first;
    final system = a.authMethod == AuthMethod.passkey
        ? 'WebAuthn Hardware Passkey + Ed25519 JWT'
        : '${a.authMethod.label} + Ed25519 JWT';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ACTIVE AUTHENTICATION', style: t.text.labelCaps.copyWith(fontSize: 7.5, color: Colors.white.withValues(alpha: 0.55))),
        const SizedBox(height: 2),
        Text(system, key: const Key('profile-auth-system'), style: t.text.mono(size: 10.5, weight: FontWeight.w600, height: 1.4, color: Colors.white)),
        const SizedBox(height: PhotonSpace.sm),
        _MiniSwitchRow(
          key: const Key('profile-2fa-toggle'),
          label: 'TWO-FACTOR',
          state: a.twoFactorEnabled ? 'ARMED' : 'OFF',
          value: a.twoFactorEnabled,
          onTap: studio.toggleTwoFactor,
        ),
        const SizedBox(height: PhotonSpace.sm),
        if (key == null)
          Text('NO ACTIVE KEYS', style: t.text.labelCaps.copyWith(color: Colors.white.withValues(alpha: 0.6)))
        else ...[
          Text(
            key.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.text.labelCaps.copyWith(fontSize: 7.5, color: Colors.white.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  key.masked,
                  key: const Key('profile-key-masked'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.mono(size: 10.5, height: 1.4, color: Colors.white),
                ),
              ),
              const SizedBox(width: PhotonSpace.sm),
              _GlassButton(
                key: const Key('profile-copy-key-btn'),
                label: 'COPY',
                icon: Icons.copy,
                onTap: () => _copy(key),
              ),
              const SizedBox(width: PhotonSpace.xs + 2),
              _GlassButton(
                key: const Key('profile-rotate-key-btn'),
                label: 'ROTATE',
                icon: Icons.autorenew,
                onTap: () => studio.rotateApiKey(key.id),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MiniSwitchRow extends StatelessWidget {
  const _MiniSwitchRow({super.key, required this.label, required this.state, required this.value, required this.onTap});

  final String label;
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
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: t.text.labelCaps.copyWith(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              Text(state, style: t.text.labelCaps.copyWith(fontSize: 8, color: value ? const Color(0xFF67E8F9) : Colors.white.withValues(alpha: 0.6))),
              const SizedBox(width: PhotonSpace.sm),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 32,
                height: 17,
                padding: const EdgeInsets.all(2),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: value ? AnimatedBlueProfileCard.cyan : Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(PhotonRadius.pill),
                  border: Border.all(color: Colors.white.withValues(alpha: hovered ? 0.8 : 0.35)),
                ),
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The aurora: three drifting colour blooms plus a spotlight under the cursor.
class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.pointer, required this.aurora}) : super(repaint: Listenable.merge([pointer, aurora]));

  final ValueListenable<Offset?> pointer;
  final Animation<double> aurora;

  @override
  void paint(Canvas canvas, Size size) {
    final a = aurora.value * 2 * math.pi;
    void bloom(Offset fraction, double radius, Color color) {
      final center = Offset(fraction.dx * size.width, fraction.dy * size.height);
      final r = radius * size.width;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    bloom(Offset(0.22 + 0.12 * math.sin(a), 0.2 + 0.1 * math.cos(a * 1.3)), 0.55, AnimatedBlueProfileCard.cyan.withValues(alpha: 0.34));
    bloom(Offset(0.8 + 0.1 * math.cos(a * 0.8), 0.45 + 0.12 * math.sin(a * 1.1)), 0.5, const Color(0xFF60A5FA).withValues(alpha: 0.3));
    bloom(Offset(0.5 + 0.18 * math.sin(a * 0.6 + 2), 0.9 + 0.06 * math.cos(a)), 0.6, const Color(0xFF22D3EE).withValues(alpha: 0.22));

    final p = pointer.value;
    if (p != null) {
      final center = Offset(p.dx * size.width, p.dy * size.height);
      bloom(Offset(p.dx, p.dy), 0.34, Colors.white.withValues(alpha: 0.2));
      canvas.drawCircle(
        center,
        28,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AnimatedBlueProfileCard.cyan.withValues(alpha: 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => false;
}
