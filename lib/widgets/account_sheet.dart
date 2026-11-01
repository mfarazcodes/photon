import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'animated_profile_card.dart';
import 'photon_primitives.dart';

/// The account console as a centered modal over the workspace: a dimmed,
/// blurred backdrop and the [AccountSheet]. A backdrop click, Escape, or the
/// red window pip dismisses it.
class AccountInspectorModal extends StatelessWidget {
  const AccountInspectorModal({super.key});

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    void close() => studio.setAccountModalOpen(false);
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            key: const Key('account-backdrop'),
            behavior: HitTestBehavior.opaque,
            onTap: close,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(PhotonSpace.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 720),
                // Swallow clicks on the sheet so they do not reach the backdrop.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const AccountSheet(embedded: false),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The account console window. [embedded] fills the workspace column (used
/// when the workspace is switched to ACCOUNT); otherwise it sizes to its
/// content inside the modal.
class AccountSheet extends StatelessWidget {
  const AccountSheet({super.key, required this.embedded});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    final t = context.photon;
    final c = t.colors;
    final account = studio.account;

    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(PhotonSpace.md),
      child: LayoutBuilder(
        builder: (context, box) {
          const gap = PhotonSpace.md;
          final cards = [
            const AnimatedBlueProfileCard(key: Key('animated-profile-card')),
            _PlanTierCard(studio: studio),
            _AuthenticationCard(studio: studio),
            _ActiveSessionsCard(studio: studio),
          ];
          if (box.maxWidth >= 780) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(children: [cards[0], const SizedBox(height: gap), cards[1]]),
                ),
                const SizedBox(width: gap),
                Expanded(
                  child: Column(children: [cards[2], const SizedBox(height: gap), cards[3]]),
                ),
              ],
            );
          }
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: gap), cards[i]],
            ],
          );
        },
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: c.substrate,
        borderRadius: BorderRadius.circular(PhotonRadius.window),
        border: Border.all(color: c.border),
        boxShadow: t.level2,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: embedded ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MacTitlebar(
            title: 'ACCOUNT_CONSOLE',
            leading: MacWindowPips(
              id: 'account',
              onClose: embedded ? () => studio.setMaximizedPanel(null) : () => studio.setAccountModalOpen(false),
              onZoom: embedded
                  ? () => studio.setMaximizedPanel(null)
                  : () {
                      studio.setAccountModalOpen(false);
                      studio.setMaximizedPanel('account');
                    },
            ),
            trailing: _TierChip(tier: account.tier),
          ),
          if (embedded) Expanded(child: body) else Flexible(child: body),
          _StatusStrip(studio: studio),
        ],
      ),
    );
  }
}

/// The last action, since the workspace toast sits behind the modal.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
      child: ValueListenableBuilder<String?>(
        valueListenable: studio.toast,
        builder: (context, message, _) => Row(
          children: [
            Pip(color: message == null ? c.ghost : c.violet, size: 5),
            const SizedBox(width: PhotonSpace.sm),
            Expanded(
              child: Text(
                message ?? 'READY',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.labelCaps.copyWith(color: message == null ? c.ghost : c.violetInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({required this.tier});

  final PlanTier tier;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tier.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(PhotonRadius.control - 2),
      ),
      child: Text(tier.tag, style: t.text.labelCaps.copyWith(fontSize: 8, color: tier.color)),
    );
  }
}

/// A titled telemetry card.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.icon, required this.child, this.trailing});

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PhotonSpace.md),
      decoration: BoxDecoration(
        color: c.isDark ? c.surface : c.canvas,
        borderRadius: BorderRadius.circular(PhotonRadius.window),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: c.violetInk),
              const SizedBox(width: PhotonSpace.sm - 2),
              Expanded(
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.text.labelCaps),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: PhotonSpace.md - 2),
          child,
        ],
      ),
    );
  }
}

/// Small hairline button used across the cards.
class _MicroButton extends StatelessWidget {
  const _MicroButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.tooltip,
    this.accent,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? tooltip;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final color = accent ?? c.violet;
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
            padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 6 : PhotonSpace.sm + 2),
            decoration: BoxDecoration(
              color: hovered ? color.withValues(alpha: 0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(PhotonRadius.control),
              border: Border.all(color: hovered ? color.withValues(alpha: 0.7) : c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) Icon(icon, size: 12, color: hovered ? color : c.textMuted),
                if (icon != null && label.isNotEmpty) const SizedBox(width: 4),
                if (label.isNotEmpty)
                  Text(
                    label,
                    style: t.text.labelCaps.copyWith(fontSize: 8, color: hovered ? color : c.textMuted),
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

/// A selectable pill (plan tiers, auth protocols).
class _ChoicePill extends StatelessWidget {
  const _ChoicePill({super.key, required this.label, required this.selected, required this.color, required this.onTap});

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

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
            padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md - 2, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.16) : (hovered ? c.hoverFill : Colors.transparent),
              borderRadius: BorderRadius.circular(PhotonRadius.pill),
              border: Border.all(color: selected ? color : (hovered ? color.withValues(alpha: 0.5) : c.border)),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: t.text.labelCaps.copyWith(fontSize: 8.5, color: selected ? color : c.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({super.key, required this.label, required this.caption, required this.value, required this.onChanged});

  final String label;
  final String caption;
  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Semantics(
      toggled: value,
      label: label,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.text.labelCaps.copyWith(color: c.carbon)),
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.telemetrySm.copyWith(fontSize: 9, color: c.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: PhotonSpace.sm),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 30,
                  height: 16,
                  padding: const EdgeInsets.all(2),
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: value ? c.violet : c.hoverFill,
                    borderRadius: BorderRadius.circular(PhotonRadius.pill),
                    border: Border.all(color: value ? c.violet : (hovered ? c.violet.withValues(alpha: 0.5) : c.border)),
                  ),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: value ? Colors.white : c.ghost, shape: BoxShape.circle),
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

// ----------------------------------------------------------------- profile

// -------------------------------------------------------------------- plan

String _group(num n) {
  final s = n.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

String _trim(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

class _PlanTierCard extends StatelessWidget {
  const _PlanTierCard({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final a = studio.account;
    final gpuFraction = a.gpuHoursUsed / a.tier.gpuHours;
    final storageFraction = a.storageUsedGb / a.storageLimitGb;
    return _Card(
      title: 'PLAN TIER & GPU CLUSTER QUOTA',
      icon: Icons.memory,
      trailing: _TierChip(tier: a.tier),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  a.tier.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.headlineSm.copyWith(color: a.tier.color),
                ),
              ),
              const SizedBox(width: PhotonSpace.sm),
              Text(a.tier.price, style: t.text.telemetryMd.copyWith(color: c.textMuted)),
            ],
          ),
          Text(a.tier.quota, style: t.text.telemetrySm.copyWith(color: c.textMuted)),
          const SizedBox(height: PhotonSpace.md - 2),
          Wrap(
            spacing: PhotonSpace.sm - 2,
            runSpacing: PhotonSpace.sm - 2,
            children: [
              for (final tier in PlanTier.values)
                _ChoicePill(
                  key: Key('tier-${tier.name}'),
                  label: tier.label,
                  selected: a.tier == tier,
                  color: tier.color,
                  onTap: () => studio.setPlanTier(tier),
                ),
            ],
          ),
          const SizedBox(height: PhotonSpace.md),
          _QuotaBar(
            label: 'GPU RENDER COMPUTE QUOTA',
            value:
                '${_trim(a.gpuHoursUsed)} / ${_group(a.tier.gpuHours)} hrs · ${(gpuFraction * 100).round()}%'
                '${gpuFraction > 1 ? ' · OVER QUOTA' : ''}',
            fraction: gpuFraction,
            color: gpuFraction > 1 ? c.rose : a.tier.color,
          ),
          const SizedBox(height: PhotonSpace.md - 2),
          _QuotaBar(
            label: 'OPENUSD CLOUD VAULT STORAGE',
            value: '${_trim(a.storageUsedGb)} / ${_trim(a.storageLimitGb)} GB · ${(storageFraction * 100).round()}%',
            fraction: storageFraction,
            color: c.violet,
          ),
        ],
      ),
    );
  }
}

class _QuotaBar extends StatelessWidget {
  const _QuotaBar({required this.label, required this.value, required this.fraction, required this.color});

  final String label;
  final String value;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Semantics(
      label: label,
      value: value,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.text.labelCaps.copyWith(fontSize: 8)),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, maxLines: 1, style: t.text.telemetryMd.copyWith(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(PhotonRadius.pill),
            child: Stack(
              children: [
                Container(height: 4, color: c.border),
                FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: Container(height: 4, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- authentication

class _AuthenticationCard extends StatefulWidget {
  const _AuthenticationCard({required this.studio});

  final StudioController studio;

  @override
  State<_AuthenticationCard> createState() => _AuthenticationCardState();
}

class _AuthenticationCardState extends State<_AuthenticationCard> {
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
    final c = t.colors;
    final studio = widget.studio;
    final a = studio.account;
    return _Card(
      title: 'AUTHENTICATION & SECURITY',
      icon: Icons.verified_user_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ACTIVE PROTOCOL', style: t.text.labelCaps.copyWith(fontSize: 8)),
          const SizedBox(height: 2),
          Text(a.authMethod.label, style: t.text.telemetryMd.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            children: [
              const Pip(color: Color(0xFF22C55E), size: 5),
              const SizedBox(width: PhotonSpace.sm - 2),
              Flexible(
                child: Text(
                  'JWT SESSION · TLS 1.3 · Ed25519 Signed',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.telemetrySm.copyWith(color: c.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: PhotonSpace.md - 2),
          Wrap(
            spacing: PhotonSpace.sm - 2,
            runSpacing: PhotonSpace.sm - 2,
            children: [
              for (final m in AuthMethod.values)
                _ChoicePill(
                  key: Key('auth-${m.name}'),
                  label: m.shortLabel,
                  selected: a.authMethod == m,
                  color: c.violet,
                  onTap: () => studio.setAuthMethod(m),
                ),
            ],
          ),
          const SizedBox(height: PhotonSpace.sm),
          _SwitchRow(
            key: const Key('account-2fa-toggle'),
            label: '2FA / TOTP AUTHENTICATOR',
            caption: a.twoFactorEnabled ? 'Enabled · 6-digit rolling code' : 'Disabled',
            value: a.twoFactorEnabled,
            onChanged: studio.toggleTwoFactor,
          ),
          _SwitchRow(
            key: const Key('account-hwkey-toggle'),
            label: 'FIPS HARDWARE PASSKEY ENCLAVE',
            caption: a.hardwareKeyBound ? 'Bound · FIDO2 / CTAP2' : 'Not bound',
            value: a.hardwareKeyBound,
            onChanged: studio.toggleHardwareKey,
          ),
          const SizedBox(height: PhotonSpace.sm),
          Row(
            children: [
              Expanded(child: Text('API & MCP KEYS', style: t.text.labelCaps)),
              _MicroButton(
                key: const Key('create-api-key-btn'),
                label: '+ NEW KEY',
                onTap: () => studio.createApiKey('Studio Key ${a.apiKeys.length + 1}'),
              ),
            ],
          ),
          const SizedBox(height: PhotonSpace.sm),
          for (final key in a.apiKeys) ...[
            _KeyRow(
              record: key,
              revealed: _revealed.contains(key.id),
              onReveal: () => setState(() {
                if (!_revealed.remove(key.id)) _revealed.add(key.id);
              }),
              onCopy: () => _copy(key.secret),
              onRotate: () => studio.rotateApiKey(key.id),
            ),
            const SizedBox(height: PhotonSpace.sm - 2),
          ],
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({
    required this.record,
    required this.revealed,
    required this.onReveal,
    required this.onCopy,
    required this.onRotate,
  });

  final ApiKeyRecord record;
  final bool revealed;
  final VoidCallback onReveal;
  final VoidCallback onCopy;
  final VoidCallback onRotate;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Container(
      padding: const EdgeInsets.all(PhotonSpace.sm),
      decoration: BoxDecoration(
        color: c.substrate,
        borderRadius: BorderRadius.circular(PhotonRadius.control),
        border: Border.all(color: c.border),
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
                  style: t.text.ui(size: 12, weight: FontWeight.w500, height: 1.3),
                ),
              ),
              _MicroButton(
                key: Key('reveal-key-${record.id}'),
                label: '',
                icon: revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                tooltip: revealed ? 'Mask key' : 'Reveal key',
                onTap: onReveal,
              ),
              const SizedBox(width: 4),
              _MicroButton(
                key: Key('copy-key-${record.id}'),
                label: '',
                icon: Icons.copy,
                tooltip: 'Copy key',
                onTap: onCopy,
              ),
              const SizedBox(width: 4),
              _MicroButton(
                key: Key('rotate-key-${record.id}'),
                label: '',
                icon: Icons.autorenew,
                tooltip: 'Rotate key',
                accent: c.rose,
                onTap: onRotate,
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
                maxLines: 1,
                style: t.text.telemetrySm.copyWith(color: revealed ? c.violetInk : c.carbon),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'created ${record.created} · used ${record.lastUsed} · ${record.scopes.join(', ')}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.text.telemetrySm.copyWith(fontSize: 9, color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- sessions

class _ActiveSessionsCard extends StatelessWidget {
  const _ActiveSessionsCard({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final sessions = studio.account.sessions;
    return _Card(
      title: 'ACTIVE CLUSTER & AGENT SESSIONS',
      icon: Icons.hub_outlined,
      trailing: Text('${sessions.length}', style: t.text.telemetrySm.copyWith(color: c.textMuted)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sessions.length; i++) ...[
            if (i > 0) Divider(height: PhotonSpace.md, thickness: 1, color: c.border),
            _SessionRow(studio: studio, session: sessions[i]),
          ],
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
    final c = t.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, right: PhotonSpace.sm),
          child: Pip(color: session.isCurrent ? const Color(0xFF22C55E) : c.violet, size: 6),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.device,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.text.ui(size: 12, weight: FontWeight.w500, height: 1.3),
              ),
              Text(
                '${session.location} · ${session.ip}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.telemetrySm.copyWith(color: c.textMuted),
              ),
              Text(
                '${session.protocol} · ${session.lastActive}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.telemetrySm.copyWith(fontSize: 9, color: c.ghost),
              ),
            ],
          ),
        ),
        const SizedBox(width: PhotonSpace.sm),
        if (session.isCurrent)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(PhotonRadius.control - 1),
            ),
            child: Text('THIS DEVICE', style: t.text.labelCaps.copyWith(fontSize: 7.5, color: const Color(0xFF22C55E))),
          )
        else
          _MicroButton(
            key: Key('revoke-session-${session.id}'),
            label: 'REVOKE',
            accent: c.rose,
            onTap: () => studio.revokeSession(session.id),
          ),
      ],
    );
  }
}
