import 'package:flutter/widgets.dart';

enum SceneAssetKind { material, shader, mesh, light, passes }

/// A spatial desktop node that can be dragged onto the viewport.
@immutable
class SceneAsset {
  const SceneAsset({
    required this.name,
    required this.extension,
    required this.kind,
    required this.subtitle,
    required this.icon,
    this.badge,
    this.previewAsset,
  });

  /// Display name without extension, e.g. `LIQUID_GLASS`.
  final String name;

  /// File extension without the dot (`ior`, `bsdf`, `usd`) or empty for
  /// nodes like `HDRI_STUDIO` and `EXR_PASSES` that are not single files.
  final String extension;
  final SceneAssetKind kind;
  final String subtitle;
  final IconData icon;

  /// Small corner tag such as `1.54`, `USD`, `32K` or `32b`.
  final String? badge;

  /// Bundled preview render, used instead of [icon] when present.
  final String? previewAsset;

  /// Identifier carried by `Draggable<String>` and sent to the engine.
  String get fileName => extension.isEmpty ? name : '$name.$extension';
}
