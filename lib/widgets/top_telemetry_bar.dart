import 'package:flutter/material.dart';

import '../services/render_socket.dart';
import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';
import 'shader_theme_switch.dart';

/// The studio header: one 40px architectural bar with the Photon mark and name
/// on the left, workspace quick-switches in the middle, and GPU telemetry,
/// convergence status, theme switch and the EXR export on the right. Scrolls
/// horizontally when the window is too narrow to fit it all (companion layout).
class TopTelemetryBar extends StatelessWidget {
  const TopTelemetryBar({super.key});

  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    return AnimatedContainer(
      key: const ValueKey('top-bar'),
      duration: const Duration(milliseconds: 180),
      height: height,
      decoration: BoxDecoration(
        // Dark Studio: carbon panel. Daylight Lab: crisp alabaster (#F9F9FB)
        // with Matte Carbon text and the #E2E2E6 structural border.
        color: c.isDark ? c.substrate : c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: PhotonSpace.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _StudioBadge(),
                    SizedBox(width: PhotonSpace.lg),
                    _WorkspaceSwitch(),
                    SizedBox(width: PhotonSpace.lg),
                    _TelemetryCluster(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StudioBadge extends StatelessWidget {
  const _StudioBadge();

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const PhotonLogoMark(size: 24, semanticLabel: 'Photon'),
        const SizedBox(width: PhotonSpace.sm),
        Text(
          'PHOTON VFX STUDIO®',
          style: t.text.labelCaps.copyWith(color: t.colors.carbon, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// SPLIT / VIEWPORT / OPTICS / ACCOUNT: which panels the workspace shows.
class _WorkspaceSwitch extends StatelessWidget {
  const _WorkspaceSwitch();

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    final t = context.photon;
    final focus = studio.maximizedPanel;
    return PillCapsule(
      padding: const EdgeInsets.all(3),
      shadow: false,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            label: 'SPLIT',
            selected: focus == null,
            onTap: () => studio.setMaximizedPanel(null),
            tokens: t,
          ),
          _Segment(
            label: 'VIEWPORT',
            selected: focus == 'viewport',
            onTap: () => studio.setMaximizedPanel('viewport'),
            tokens: t,
          ),
          _Segment(
            label: 'OPTICS',
            selected: focus == 'optics',
            onTap: () => studio.setMaximizedPanel('optics'),
            tokens: t,
          ),
          _Segment(
            label: 'ACCOUNT',
            selected: focus == 'account',
            onTap: () => studio.setMaximizedPanel('account'),
            tokens: t,
          ),
        ],
      ),
    );
  }
}

class _TelemetryCluster extends StatelessWidget {
  const _TelemetryCluster();

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GpuPill(studio: studio),
        const SizedBox(width: PhotonSpace.sm),
        _StatusCapsule(studio: studio),
        const SizedBox(width: PhotonSpace.sm),
        _ShowcasePill(studio: studio),
        const SizedBox(width: PhotonSpace.sm),
        ShaderThemeSwitch(
          key: const Key('shader-theme-switch'),
          dark: studio.darkGrading,
          onChanged: studio.setDarkGrading,
          animate: studio.animateShader,
        ),
        const SizedBox(width: PhotonSpace.sm),
        PhotonButton(
          label: 'Export EXR',
          onPressed: studio.exportExr,
          trailing: Icon(Icons.north_east, size: 11, color: studio.palette.onCarbon),
        ),
        const SizedBox(width: PhotonSpace.sm),
        _AccountPill(studio: studio),
        const SizedBox(width: PhotonSpace.xs),
        _PaletteButton(studio: studio),
      ],
    );
  }
}

/// "Vulkan RT • 256 SPP" with a sync pip: green when the engine link is live.
class _GpuPill extends StatelessWidget {
  const _GpuPill({required this.studio});

  final StudioController studio;

  static const _live = Color(0xFF22C55E);
  static const _pending = Color(0xFFF5A524);

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final link = studio.link;
    final (color, hint) = switch (link) {
      RenderLink.live => (_live, 'Engine connected'),
      RenderLink.connecting => (_pending, 'Connecting to engine…'),
      RenderLink.offline => (_pending, 'Engine offline · showing preview render'),
    };
    return Tooltip(
      message: hint,
      child: PillCapsule(
        shadow: false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlashingPip(color: color, size: 6, flash: link == RenderLink.live),
            const SizedBox(width: PhotonSpace.sm - 2),
            Text(
              'Vulkan RT • ${studio.targetSamples} SPP',
              style: t.text.telemetrySm.copyWith(color: t.colors.textMuted, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// CONVERGING (violet, flashing pip) or CONVERGED (carbon at 6%).
class _StatusCapsule extends StatelessWidget {
  const _StatusCapsule({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return ValueListenableBuilder<int>(
      valueListenable: studio.samples,
      builder: (context, _, _) {
        final done = studio.converged;
        final fg = done ? c.carbon : c.violetInk;
        final bg = (done ? c.carbon : c.violet).withValues(alpha: done ? 0.06 : 0.08);
        return PillCapsule(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm),
          background: bg,
          borderColor: Colors.transparent,
          shadow: false,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FlashingPip(color: fg, size: 4, flash: !done),
              const SizedBox(width: PhotonSpace.xs + 2),
              Text(done ? 'CONVERGED' : 'CONVERGING', style: t.text.labelCaps.copyWith(color: fg)),
            ],
          ),
        );
      },
    );
  }
}

/// `SHOWCASE`: reopens the launch film.
class _ShowcasePill extends StatelessWidget {
  const _ShowcasePill({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Tooltip(
      message: 'Showcase / launch portal',
      child: Semantics(
        button: true,
        label: 'Showcase launch portal',
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            key: const Key('open-launch-portal-btn'),
            behavior: HitTestBehavior.opaque,
            onTap: studio.openLaunchPortal,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm + 2),
              decoration: BoxDecoration(
                color: hovered ? c.violet.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(PhotonRadius.pill),
                border: Border.all(color: hovered ? c.violet.withValues(alpha: 0.6) : c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_circle_outline, size: 13, color: hovered ? c.violetInk : c.textMuted),
                  const SizedBox(width: PhotonSpace.xs + 1),
                  Text('SHOWCASE', style: t.text.labelCaps.copyWith(color: hovered ? c.violetInk : c.textMuted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.tokens,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final PhotonTokens tokens;

  @override
  Widget build(BuildContext context) {
    final c = tokens.colors;
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
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm + 2),
            decoration: BoxDecoration(
              color: selected ? c.carbon : (hovered ? c.hoverFill : Colors.transparent),
              borderRadius: BorderRadius.circular(PhotonRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: tokens.text.labelCaps.copyWith(color: selected ? c.onCarbon : c.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `(MF) MOHD FARAZ [PRO]`: opens the account console.
class _AccountPill extends StatelessWidget {
  const _AccountPill({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final a = studio.account;
    final open = studio.accountModalOpen;
    return Tooltip(
      message: 'Account & authentication',
      child: Semantics(
        button: true,
        label: 'Account: ${a.displayName}, ${a.tier.label}',
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            key: const Key('account-pill-btn'),
            behavior: HitTestBehavior.opaque,
            onTap: studio.toggleAccountModal,
            child: AnimatedContainer(
              key: const Key('profile-card-trigger'),
              duration: const Duration(milliseconds: 140),
              height: 28,
              padding: const EdgeInsets.fromLTRB(4, 0, PhotonSpace.sm, 0),
              decoration: BoxDecoration(
                color: open ? c.violet.withValues(alpha: 0.12) : (hovered ? c.hoverFill : c.substrate),
                borderRadius: BorderRadius.circular(PhotonRadius.pill),
                border: Border.all(color: open || hovered ? c.violet.withValues(alpha: 0.6) : c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFF8A2BE2), Color(0xFFFF2D78)]),
                    ),
                    child: Text(
                      a.initials,
                      style: t.text.mono(size: 8, weight: FontWeight.w700, height: 1, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: PhotonSpace.sm - 1),
                  Text(
                    a.displayName.toUpperCase(),
                    style: t.text.labelCaps.copyWith(color: c.carbon, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: PhotonSpace.sm - 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: a.tier.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(PhotonRadius.pill),
                    ),
                    child: Text(a.tier.tag, style: t.text.labelCaps.copyWith(fontSize: 7.5, color: a.tier.color)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The command-palette trigger (also `Ctrl+P`).
class _PaletteButton extends StatelessWidget {
  const _PaletteButton({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    return Tooltip(
      message: 'Command palette (Ctrl+P)',
      child: Semantics(
        button: true,
        label: 'Command palette',
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            key: const Key('command-palette-btn'),
            behavior: HitTestBehavior.opaque,
            onTap: studio.toggleCommandPalette,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: studio.commandPaletteOpen ? c.violet.withValues(alpha: 0.12) : (hovered ? c.hoverFill : Colors.transparent),
                borderRadius: BorderRadius.circular(PhotonRadius.pill),
                border: Border.all(color: studio.commandPaletteOpen || hovered ? c.violet.withValues(alpha: 0.6) : c.border),
              ),
              child: Icon(Icons.search, size: 14, color: studio.commandPaletteOpen ? c.violetInk : c.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
