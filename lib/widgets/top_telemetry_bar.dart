import 'package:flutter/material.dart';

import '../services/render_socket.dart';
import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// Top HUD: studio identity badge on the left, telemetry capsules, theme
/// toggle and the EXR export action on the right. Scrolls horizontally when
/// the window is too narrow to fit everything (companion layout).
class TopTelemetryBar extends StatelessWidget {
  const TopTelemetryBar({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _StudioBadge(),
                SizedBox(width: PhotonSpace.md),
                _TelemetryCluster(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StudioBadge extends StatelessWidget {
  const _StudioBadge();

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return PillCapsule(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Pip(color: t.colors.carbon, size: 8),
          const SizedBox(width: PhotonSpace.sm),
          Text(
            'PHOTON VFX STUDIO®',
            style: t.text.labelCaps.copyWith(color: t.colors.carbon, fontWeight: FontWeight.w700),
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
