import 'package:flutter/material.dart';

import '../models/desktop_node.dart';
import '../state/workspace_controller.dart';
import '../theme/photon_theme.dart';
import '../widgets/overlay_shell.dart';
import '../widgets/sim_view.dart';

const _projects = [
  ('VOLUMETRIC SHOCKWAVE', 'Volumetric Fluid Solver', '10.30.2026', SimKind.fog),
  ('LIQUID CHROME BLOOM', 'GLSL PBR Fragment', '10.29.2026', SimKind.chrome),
  ('NANOBOT DISSOLVE', 'Boids / Curl Noise', '10.28.2026', SimKind.swarm),
  ('CAUSTIC POOL LOOP', 'Photon Mapping Lite', '10.27.2026', SimKind.caustics),
  ('MARBLE STORM', 'FBM Domain Warp', '10.25.2026', SimKind.marble),
  ('VACUUM SEAL HERO', 'Shrink-Wrap Membrane', '10.24.2026', SimKind.cloth),
  ('PINK GOO TITLE', 'SPH Metaball Solver', '10.22.2026', SimKind.liquid),
  ('TOPOLOGY SWEEP', 'Mesh Topology Viewer', '10.18.2026', SimKind.wireframe),
];

/// High-contrast monochrome grade used on alternate frames.
const _mono = ColorFilter.matrix([
  0.55, 0.9, 0.15, 0, -60,
  0.55, 0.9, 0.15, 0, -60,
  0.55, 0.9, 0.15, 0, -60,
  0, 0, 0, 1, 0,
]);

/// Full-screen pitch-black archive of recent renders with giant kinetic rows.
class KineticArchive extends StatelessWidget {
  const KineticArchive({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    return OverlayShell(
      open: ws.overlay == StudioOverlay.archive,
      onDismiss: ws.closeOverlay,
      blur: 0,
      scrim: const Color(0x00000000),
      builder: (context, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 1.04, end: 1.0).animate(a),
          child: const _ArchiveBody(),
        ),
      ),
    );
  }
}

class _ArchiveBody extends StatefulWidget {
  const _ArchiveBody();

  @override
  State<_ArchiveBody> createState() => _ArchiveBodyState();
}

class _ArchiveBodyState extends State<_ArchiveBody> {
  int? _hover;
  int? _pinned;

  int? get _active => _hover ?? _pinned;

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.read(context);
    final w = MediaQuery.sizeOf(context).width;
    final titleSize = (w * 0.068).clamp(44.0, 128.0);
    return Material(
      color: PC.archive,
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(36, 110, 36, 80),
              itemCount: _projects.length,
              itemBuilder: (context, i) => _row(i, titleSize),
            ),
          ),
          Positioned(
            left: 36,
            top: 34,
            child: Text('RECENT RENDERS  ·  ${_projects.length}',
                style: PT.mono(size: 13, color: PC.archiveMuted, weight: FontWeight.w700)),
          ),
          Positioned(
            right: 28,
            top: 22,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: ws.closeOverlay,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(color: PC.white, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: PC.ink, size: 26),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(int i, double titleSize) {
    final (title, solver, date, kind) = _projects[i];
    final active = _active == i;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 500 + i * 70),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 40 * (1 - t)), child: child),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = i),
        onExit: (_) => setState(() => _hover = _hover == i ? null : _hover),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _pinned = _pinned == i ? null : i),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1C1C1C))),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(bottom: titleSize * 0.62, right: 18),
                      child: Text((i + 1).toString().padLeft(2, '0'),
                          style: PT.mono(size: 13, color: PC.archiveMuted)),
                    ),
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 260),
                        style: PT.display(
                          size: titleSize,
                          color: active ? PC.white : PC.archiveMuted,
                          weight: FontWeight.w800,
                        ),
                        child: Text(title, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: active ? 1 : 0,
                      duration: const Duration(milliseconds: 260),
                      child: AnimatedSlide(
                        offset: active ? Offset.zero : const Offset(0.2, 0),
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: titleSize * 0.16),
                          child: Text('$solver — $date',
                              style: PT.mono(size: 14, color: const Color(0xFFBDBDBD))),
                        ),
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: active ? _strip(kind) : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _strip(SimKind kind) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12, left: 34),
      child: SizedBox(
        height: 230,
        child: Row(
          children: [
            for (var f = 0; f < 4; f++) ...[
              if (f > 0) const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: f.isOdd
                            ? ColorFiltered(
                                colorFilter: _mono,
                                child: SimView(kind: kind, speed: 0.6 + f * 0.45),
                              )
                            : SimView(kind: kind, speed: 0.6 + f * 0.45),
                      ),
                      Positioned(
                        left: 10,
                        top: 8,
                        child: Text((f + 1).toString().padLeft(2, '0'),
                            style: PT.mono(
                                size: 13,
                                color: f.isOdd ? PC.white : PC.ink,
                                weight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
