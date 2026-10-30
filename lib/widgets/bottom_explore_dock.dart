import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/desktop_node.dart';
import '../state/workspace_controller.dart';
import '../theme/photon_theme.dart';
import 'sim_view.dart';

class _DockItem {
  const _DockItem(this.title, this.badge, this.onTap, {this.external = false});

  final String title;
  final Widget badge;
  final VoidCallback onTap;
  final bool external;
}

/// Black floating `[ P. | EXPLORE | ☰ ]` bar that morphs upward into a menu.
class BottomExploreDock extends StatelessWidget {
  const BottomExploreDock({super.key});

  static const double _dockH = 76;
  static const double _itemH = 74;

  List<_DockItem> _items(WorkspaceController ws) => [
        _DockItem('ABOUT PHOTON', const SimView(kind: SimKind.core, thumb: true),
            () => ws.openOverlay(StudioOverlay.about)),
        _DockItem('RECENT RENDERS', const SimView(kind: SimKind.caustics, thumb: true),
            () => ws.openOverlay(StudioOverlay.archive)),
        _DockItem('PRESET ARCHIVE', const SimView(kind: SimKind.marble, thumb: true),
            () => ws.openFinder(FinderView.presetVault)),
        _DockItem('NEW VFX PROMPT', const SimView(kind: SimKind.wireframe, thumb: true),
            () => ws.openOverlay(StudioOverlay.promptDrawer)),
        _DockItem('NODE GRAPH STUDIO®', const _LetterBadge('N.', Color(0xFFFF6FCF)),
            ws.openInspector,
            external: true),
        _DockItem(
            'CLOUD GPU CLUSTER®',
            const _LetterBadge('G/C', Color(0xFFFFB3E6), light: true),
            () => ws.openFinder(FinderView.cloudCluster),
            external: true),
      ];

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    final open = ws.exploreOpen;
    final items = _items(ws);
    final listH = items.length * _itemH;
    final width = math.min(690.0, MediaQuery.sizeOf(context).width - 32);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 460),
      curve: open ? Curves.easeOutQuart : Curves.easeInOutCubic,
      width: width,
      height: open ? _dockH + listH : _dockH,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: PC.dock,
        borderRadius: BorderRadius.circular(open ? 20 : 18),
        border: Border.all(color: const Color(0xFF2C2C2C), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 40, offset: Offset(0, 18)),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: OverflowBox(
              alignment: Alignment.bottomCenter,
              minHeight: 0,
              maxHeight: listH,
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++)
                    _MenuRow(item: items[i], index: i, open: open, height: _itemH),
                ],
              ),
            ),
          ),
          SizedBox(height: _dockH - 3, child: _DockBar(open: open)),
        ],
      ),
    );
  }
}

class _DockBar extends StatelessWidget {
  const _DockBar({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.read(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: ws.toggleExplore,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Row(
            children: [
              Text('P.',
                  style: PT.display(size: 40, color: PC.white, weight: FontWeight.w900)),
              Expanded(
                child: Center(
                  child: Text('EXPLORE',
                      style: PT.label(
                          size: 22, color: PC.white, weight: FontWeight.w700, spacing: 0.6)),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, a) => RotationTransition(
                  turns: Tween(begin: 0.75, end: 1.0).animate(a),
                  child: FadeTransition(opacity: a, child: child),
                ),
                child: Icon(
                  open ? Icons.close_rounded : Icons.menu_rounded,
                  key: ValueKey(open),
                  color: PC.white,
                  size: 34,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.item,
    required this.index,
    required this.open,
    required this.height,
  });

  final _DockItem item;
  final int index;
  final bool open;
  final double height;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    // Rows nearest the dock reveal first as the card grows upward.
    final order = 5 - widget.index;
    return AnimatedOpacity(
      opacity: widget.open ? 1 : 0,
      duration: Duration(milliseconds: 220 + order * 45),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: widget.open ? Offset.zero : const Offset(0, 0.4),
        duration: Duration(milliseconds: 320 + order * 45),
        curve: Curves.easeOutCubic,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: item.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: widget.height,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: _hover ? PC.dockRaised : PC.dock,
                border: const Border(bottom: BorderSide(color: Color(0xFF262626))),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(width: 52, height: 52, child: item.badge),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 180),
                      padding: EdgeInsets.only(left: _hover ? 6 : 0),
                      child: Text(item.title,
                          style: PT.label(
                              size: 19, color: PC.white, weight: FontWeight.w800, spacing: 0.4)),
                    ),
                  ),
                  Icon(
                    item.external ? Icons.open_in_new_rounded : Icons.arrow_forward_rounded,
                    color: _hover ? PC.white : const Color(0xFFBDBDBD),
                    size: 24,
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

class _LetterBadge extends StatelessWidget {
  const _LetterBadge(this.text, this.color, {this.light = false});

  final String text;
  final Color color;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light ? [color, const Color(0xFFFFFFFF)] : [color, color],
        ),
      ),
      child: Text(text,
          style: PT.display(
              size: light ? 17 : 26,
              color: light ? const Color(0xFFFFFFFF) : PC.ink,
              weight: FontWeight.w900)),
    );
  }
}
