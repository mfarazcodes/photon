import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/desktop_node.dart';
import '../painters/glyph_painters.dart';
import '../painters/pass_painter.dart';
import '../state/workspace_controller.dart';
import '../theme/photon_theme.dart';
import 'sim_view.dart';

/// A file or folder on the spatial desktop. Exactly [kIconBox] in size.
class DesktopIcon extends StatefulWidget {
  const DesktopIcon({super.key, required this.node, required this.selected});

  final DesktopNode node;
  final bool selected;

  @override
  State<DesktopIcon> createState() => _DesktopIconState();
}

class _DesktopIconState extends State<DesktopIcon> with SingleTickerProviderStateMixin {
  bool _hover = false;
  late final AnimationController _hoverController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Nodes created by a finished render pop onto the desktop.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: widget.node.generated ? 0 : 1, end: 1),
      duration: const Duration(milliseconds: 560),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: t, child: child),
      ),
      child: _icon(context),
    );
  }

  Widget _icon(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hover = true);
        _hoverController.forward();
      },
      onExit: (_) {
        setState(() => _hover = false);
        _hoverController.reverse();
      },
      child: AnimatedBuilder(
        animation: _hoverController,
        builder: (context, _) => SizedBox.fromSize(
          size: kIconBox,
          child: Column(
            children: [
              AnimatedScale(
                scale: 1.0 + (_hoverController.value * 0.05),
                duration: Duration.zero,
                child: Container(
                  width: kThumbSize + 8,
                  height: kThumbSize + 8,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0x0F000000) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? const Color(0xFFD4D4D4) : Colors.transparent,
                    ),
                  ),
                  child: IconThumb(node: widget.node, hoverProgress: _hoverController.value),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 24,
                width: kIconBox.width,
                child: OverflowBox(
                  maxWidth: 320,
                  child: FileLabel(text: widget.node.label, selected: selected),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FileLabel extends StatelessWidget {
  const FileLabel({super.key, required this.text, required this.selected, this.size = 14.5});

  final String text;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? PC.blue : const Color(0x002563EB),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: PT.label(size: size, color: selected ? PC.white : PC.ink),
      ),
    );
  }
}

/// Procedural thumbnail for a node: folder glyph, pass strips or a live sim.
class IconThumb extends StatelessWidget {
  const IconThumb({super.key, required this.node, this.radius = 10, this.hoverProgress = 0.0});

  final DesktopNode node;
  final double radius;
  final double hoverProgress;

  @override
  Widget build(BuildContext context) {
    if (node.isFolder) {
      return Transform.translate(
        offset: Offset(0, -4.0 * hoverProgress),
        child: CustomPaint(
          painter: FolderPainter(
            tag: node.folderTag ?? '',
            tagColor: node.tagColor ?? PC.blue,
            hoverProgress: hoverProgress,
          ),
        ),
      );
    }
    final dna = node.dna;
    final Widget content = node.kind == NodeKind.comp
        ? const PassStripsThumb()
        : dna != null
        // Generated files preview the effect compiled from their prompt.
        ? SimView(kind: node.sim ?? SimKind.core, dna: dna, thumb: true, hoverReactive: true)
        : TimeBuilder(
            builder: (context, time) => CustomPaint(
              painter: VfxGlyphPainter(
                kind: node.sim ?? SimKind.core,
                hoverProgress: hoverProgress,
                time: time.value,
              ),
            ),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );
  }
}

/// Five vertical slices of the pass scene, like a contact sheet.
class PassStripsThumb extends StatelessWidget {
  const PassStripsThumb({super.key});

  @override
  Widget build(BuildContext context) {
    return TimeBuilder(
      builder: (context, time) => CustomPaint(
        painter: _StripsPainter(time),
        size: Size.infinite,
      ),
    );
  }
}

class _StripsPainter extends CustomPainter {
  _StripsPainter(this.time) : super(repaint: time);

  final ValueListenable<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF111111));
    final stripW = size.width / kPassNames.length;
    for (var i = 0; i < kPassNames.length; i++) {
      canvas.save();
      final r = Rect.fromLTWH(i * stripW, size.height * 0.2, stripW - 1, size.height * 0.6);
      canvas.clipRect(r);
      canvas.translate(0, size.height * 0.2);
      paintPass(canvas, Size(size.width, size.height * 0.6), i, time.value);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _StripsPainter old) => old.time != time;
}

/// The centre `PHOTON_ENGINE_V3.4` card pinned over the core.
class CoreCard extends StatefulWidget {
  const CoreCard({super.key});

  @override
  State<CoreCard> createState() => _CoreCardState();
}

class _CoreCardState extends State<CoreCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cardSize = kCoreCardBox.width;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: SizedBox.fromSize(
        size: kCoreCardBox,
        child: Column(
          children: [
            AnimatedScale(
              scale: _hover ? 1.025 : 1,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: cardSize,
                    height: cardSize,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0x59FFFFFF),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0x99FFFFFF)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: const SimView(kind: SimKind.core),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PC.blue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'PHOTON_ENGINE_V3.4',
                style: PT.label(size: 16, color: PC.white, spacing: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
