import 'package:flutter/material.dart';

import '../services/render_socket.dart';
import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

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
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: c.substrate,
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

/// SPLIT / VIEWPORT / OPTICS: which panels the workspace shows.
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
            icon: Icons.view_agenda_outlined,
            label: 'SPLIT',
            selected: focus == null,
            onTap: () => studio.setMaximizedPanel(null),
            tokens: t,
          ),
          _Segment(
            icon: Icons.crop_landscape,
            label: 'VIEWPORT',
            selected: focus == 'viewport',
            onTap: () => studio.setMaximizedPanel('viewport'),
            tokens: t,
          ),
          _Segment(
            icon: Icons.tune,
            label: 'OPTICS',
            selected: focus == 'optics',
            onTap: () => studio.setMaximizedPanel('optics'),
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
        _ThemeToggle(studio: studio),
        const SizedBox(width: PhotonSpace.sm),
        PhotonButton(
          label: 'Export EXR',
          onPressed: studio.exportExr,
          trailing: Icon(Icons.north_east, size: 11, color: studio.palette.onCarbon),
        ),
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

/// Daylight Cyclorama / Dark Grading Mode switch.
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return PillCapsule(
      padding: const EdgeInsets.all(3),
      shadow: false,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            icon: Icons.wb_sunny_outlined,
            label: 'DAYLIGHT',
            selected: !studio.darkGrading,
            onTap: () => studio.setDarkGrading(false),
            tokens: t,
          ),
          _Segment(
            icon: Icons.dark_mode_outlined,
            label: 'DARK GRADING',
            selected: studio.darkGrading,
            onTap: () => studio.setDarkGrading(true),
            tokens: t,
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.tokens,
  });

  final IconData icon;
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
                Icon(icon, size: 11, color: selected ? c.onCarbon : c.textMuted),
                const SizedBox(width: PhotonSpace.xs + 1),
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
