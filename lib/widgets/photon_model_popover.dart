import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/render_socket.dart';
import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// The PHOTON LUMEN-1 selector, floating above the dock: the engine address
/// and link with a RECONNECT action, and the three tiers as cards. Choosing a
/// tier applies its preset and closes the popover; a click outside or Escape
/// dismisses it.
class PhotonModelPopover extends StatelessWidget {
  const PhotonModelPopover({super.key});

  static const double width = 360;

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    final t = context.photon;
    final c = t.colors;
    void close() => studio.setModelPopoverOpen(false);
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
          // Outside the card: a transparent barrier that closes it.
          GestureDetector(
            key: const Key('model-popover-barrier'),
            behavior: HitTestBehavior.opaque,
            onTap: close,
            child: const SizedBox.expand(),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              // Above the dock, over the chip it opened from.
              padding: EdgeInsets.only(
                right: MediaQuery.sizeOf(context).width >= 900 ? 72 : PhotonSpace.md,
                bottom: MediaQuery.sizeOf(context).width >= 900 ? 104 : 200,
                left: PhotonSpace.md,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Container(
                  key: const Key('photon-model-popover'),
                  width: width,
                  padding: const EdgeInsets.all(PhotonSpace.md),
                  decoration: BoxDecoration(
                    color: c.dock,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.isDark ? Colors.white.withValues(alpha: 0.14) : c.border),
                    boxShadow: [
                      BoxShadow(color: studio.modelTier.accent.withValues(alpha: 0.2), blurRadius: 28, spreadRadius: -8),
                      ...t.level2,
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.memory, size: 13, color: c.violetInk),
                          const SizedBox(width: PhotonSpace.sm - 2),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'PHOTON LUMEN-1 · NEURAL RAY KERNEL',
                                maxLines: 1,
                                style: t.text.labelCaps.copyWith(color: c.onDock, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: PhotonSpace.sm),
                      _EngineRow(studio: studio),
                      const SizedBox(height: PhotonSpace.sm + 2),
                      for (final tier in PhotonModelTier.values) ...[
                        _TierCard(
                          tier: tier,
                          selected: studio.modelTier == tier,
                          onTap: () => studio.setModelTier(tier),
                        ),
                        const SizedBox(height: PhotonSpace.sm - 2),
                      ],
                    ],
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

/// `ws://127.0.0.1:8765`, the link state, and RECONNECT.
class _EngineRow extends StatelessWidget {
  const _EngineRow({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return ValueListenableBuilder<RenderLink>(
      valueListenable: studio.socket.link,
      builder: (context, link, _) {
        final (label, color) = switch (link) {
          RenderLink.live => ('LIVE', const Color(0xFF22D3EE)),
          RenderLink.connecting => ('CONNECTING', const Color(0xFFF5A524)),
          RenderLink.offline => ('OFFLINE', c.ghost),
        };
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm + 2, vertical: 6),
          decoration: BoxDecoration(
            color: c.onDock.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(PhotonRadius.control + 2),
            border: Border.all(color: c.onDock.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Pip(color: color, size: 6),
              const SizedBox(width: PhotonSpace.sm - 1),
              Expanded(
                child: Text(
                  '${studio.socket.uri}',
                  key: const Key('model-engine-uri'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.mono(size: 9.5, height: 1.3, color: c.onDock),
                ),
              ),
              const SizedBox(width: PhotonSpace.sm),
              Text(label, style: t.text.labelCaps.copyWith(fontSize: 8, color: color, fontWeight: FontWeight.w700)),
              const SizedBox(width: PhotonSpace.sm),
              Semantics(
                button: true,
                label: 'Reconnect engine',
                child: HoverBuilder(
                  cursor: SystemMouseCursors.click,
                  builder: (context, hovered) => GestureDetector(
                    key: const Key('model-reconnect-btn'),
                    behavior: HitTestBehavior.opaque,
                    onTap: studio.reconnectEngine,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: hovered ? c.violet.withValues(alpha: 0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(PhotonRadius.control),
                        border: Border.all(color: hovered ? c.violet : c.onDock.withValues(alpha: 0.25)),
                      ),
                      child: Text('RECONNECT', style: t.text.labelCaps.copyWith(fontSize: 7.5, color: c.onDock, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.selected, required this.onTap});

  final PhotonModelTier tier;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: tier.title,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          key: Key('model-tier-${tier.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              color: selected ? tier.accent.withValues(alpha: 0.14) : (hovered ? c.onDock.withValues(alpha: 0.08) : c.onDock.withValues(alpha: 0.04)),
              borderRadius: BorderRadius.circular(PhotonRadius.window + 2),
              border: Border.all(color: selected ? tier.accent : (hovered ? tier.accent.withValues(alpha: 0.5) : c.onDock.withValues(alpha: 0.12))),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: tier.accent,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(PhotonRadius.window + 1)),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md - 2, vertical: PhotonSpace.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tier.title,
                                  maxLines: 1,
                                  style: t.text.ui(size: 13, weight: FontWeight.w600, height: 1.2, color: c.onDock),
                                ),
                              ),
                              if (selected) Icon(Icons.check_circle, size: 14, color: tier.accent),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tier.detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.text.mono(size: 9.5, height: 1.35, color: c.onDock.withValues(alpha: 0.78)),
                          ),
                          Text(
                            tier.spec,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.text.mono(size: 8.5, height: 1.35, color: c.onDock.withValues(alpha: 0.5)),
                          ),
                        ],
                      ),
                    ),
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
