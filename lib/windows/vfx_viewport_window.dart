import 'package:flutter/material.dart';

import '../models/desktop_node.dart';
import '../theme/photon_theme.dart';
import '../widgets/sim_view.dart';

/// Interactive procedural preview for `.vfx`, `.frag` and `.obj` nodes.
class VfxViewportContent extends StatelessWidget {
  const VfxViewportContent({super.key, required this.node});

  final DesktopNode node;

  @override
  Widget build(BuildContext context) {
    final fg = node.darkTile ? PC.white : PC.ink;
    final chipBg = node.darkTile ? const Color(0x33FFFFFF) : const Color(0x14000000);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: SimView(kind: node.sim ?? SimKind.core, interactive: true),
            ),
            Positioned(
              left: 14,
              top: 14,
              child: IgnorePointer(
                child: Row(
                  children: [
                    _Chip(text: node.solver.toUpperCase(), fg: fg, bg: chipBg),
                    const SizedBox(width: 6),
                    _Chip(text: 'LIVE', fg: PC.white, bg: PC.blue),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 14,
              bottom: 14,
              child: IgnorePointer(
                child: _Chip(text: 'HOVER · DRAG · PRESS', fg: fg, bg: chipBg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.fg, required this.bg});

  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Text(text, style: PT.mono(size: 11, color: fg, weight: FontWeight.w700)),
    );
  }
}
