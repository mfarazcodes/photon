import 'package:flutter/material.dart';

import '../models/scene_asset.dart';
import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// Draggable spatial desktop nodes framing the viewport.
///
/// [Axis.vertical] is the desktop perimeter column; [Axis.horizontal] is the
/// companion carousel. Each node is a `Draggable<String>` carrying the asset
/// file name, which the viewport's `DragTarget<String>` turns into a load
/// event.
class PerimeterAssetStrip extends StatelessWidget {
  const PerimeterAssetStrip({super.key, this.axis = Axis.vertical});

  final Axis axis;

  static const double nodeWidth = 96;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final studio = StudioScope.of(context);
    final vertical = axis == Axis.vertical;

    final nodes = [
      for (final asset in kSceneAssets)
        _AssetNode(
          asset: asset,
          selected: studio.selectedAsset == asset.fileName,
          onSelect: () => studio.selectAsset(
            studio.selectedAsset == asset.fileName ? null : asset.fileName,
          ),
          // Drag across the strip's scroll axis so scrolling still works.
          dragAffinity: vertical ? Axis.horizontal : Axis.vertical,
        ),
    ];

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.grid_view, size: 12, color: t.colors.violetInk),
              const SizedBox(width: PhotonSpace.xs + 2),
              Text(vertical ? 'ASSETS' : 'ACTIVE SCENE ASSETS', style: t.text.labelCaps),
            ],
          ),
          Text(
            vertical ? '${kSceneAssets.length}' : '${kSceneAssets.length} NODES CACHED',
            style: t.text.telemetrySm.copyWith(color: t.colors.ghost),
          ),
        ],
      ),
    );

    if (vertical) {
      return SizedBox(
        width: nodeWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: PhotonSpace.sm),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: nodes.length,
                separatorBuilder: (_, _) => const SizedBox(height: PhotonSpace.sm),
                itemBuilder: (_, i) => nodes[i],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        const SizedBox(height: PhotonSpace.sm),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: nodes.length,
            separatorBuilder: (_, _) => const SizedBox(width: PhotonSpace.sm),
            itemBuilder: (_, i) => SizedBox(width: nodeWidth, child: nodes[i]),
          ),
        ),
      ],
    );
  }
}

class _AssetNode extends StatelessWidget {
  const _AssetNode({
    required this.asset,
    required this.selected,
    required this.onSelect,
    required this.dragAffinity,
  });

  final SceneAsset asset;
  final bool selected;
  final VoidCallback onSelect;
  final Axis dragAffinity;

  @override
  Widget build(BuildContext context) {
    return Draggable<String>(
      data: asset.fileName,
      affinity: dragAffinity,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: PerimeterAssetStrip.nodeWidth,
          child: _NodeCard(asset: asset, selected: true, hovered: false, lifted: true),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _NodeCard(asset: asset, selected: false, hovered: false),
      ),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${asset.fileName}, ${asset.subtitle}. Drag onto the viewport to load.',
        child: HoverBuilder(
          cursor: SystemMouseCursors.grab,
          builder: (context, hovered) => GestureDetector(
            onTap: onSelect,
            child: _NodeCard(asset: asset, selected: selected, hovered: hovered),
          ),
        ),
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.asset,
    required this.selected,
    required this.hovered,
    this.lifted = false,
  });

  final SceneAsset asset;
  final bool selected;
  final bool hovered;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final borderColor = selected
        ? c.violet
        : hovered
        ? c.violet.withValues(alpha: 0.4)
        : c.border;
    return Container(
      padding: const EdgeInsets.all(PhotonSpace.sm),
      decoration: BoxDecoration(
        color: c.substrate,
        borderRadius: BorderRadius.circular(PhotonRadius.window),
        border: Border.all(color: borderColor),
        boxShadow: lifted ? t.causticGlow : (selected ? t.level2 : null),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Thumbnail(asset: asset),
          const SizedBox(height: PhotonSpace.sm - 2),
          Text(
            asset.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: t.text.telemetrySm.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            asset.subtitle.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: t.text.labelCaps.copyWith(fontSize: 8, letterSpacing: 0.4, color: c.ghost),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.asset});

  final SceneAsset asset;

  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;

    final Color bg;
    final Color fg;
    switch (asset.kind) {
      case SceneAssetKind.light:
      case SceneAssetKind.passes:
        bg = c.carbon;
        fg = c.onCarbon;
      case SceneAssetKind.shader:
        bg = c.hoverFill;
        fg = c.violetInk;
      case SceneAssetKind.mesh:
      case SceneAssetKind.material:
        bg = c.hoverFill;
        fg = c.textMuted;
    }

    final badge = asset.badge;
    final Color badgeBg;
    final Color badgeFg;
    switch (asset.kind) {
      case SceneAssetKind.shader:
        badgeBg = c.carbon;
        badgeFg = c.onCarbon;
      case SceneAssetKind.mesh:
        badgeBg = c.violet.withValues(alpha: 0.14);
        badgeFg = c.violetInk;
      case SceneAssetKind.passes:
        badgeBg = c.violet;
        badgeFg = Colors.white;
      case SceneAssetKind.light:
      case SceneAssetKind.material:
        badgeBg = Colors.transparent;
        badgeFg = c.onCarbon.withValues(alpha: 0.7);
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PhotonRadius.control + 2),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: bg),
            if (asset.kind == SceneAssetKind.shader)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [
                      c.violet.withValues(alpha: 0.30),
                      c.violet.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            if (asset.previewAsset != null)
              Image.asset(
                asset.previewAsset!,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => Icon(asset.icon, size: 20, color: fg),
              )
            else
              Center(child: Icon(asset.icon, size: 20, color: fg)),
            if (asset.kind == SceneAssetKind.material)
              const Positioned(
                top: 4,
                left: 4,
                child: Pip(color: Color(0xFFFBBF24), size: 6),
              ),
            if (badge != null)
              Positioned(
                right: 3,
                bottom: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(PhotonRadius.control - 2),
                  ),
                  child: Text(
                    badge,
                    style: t.text.mono(size: 8, weight: FontWeight.w600, height: 1, color: badgeFg),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
