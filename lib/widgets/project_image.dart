import 'dart:io';

import 'package:flutter/material.dart';

import '../models/studio_project.dart';
import '../theme/photon_theme.dart';

/// A project's picture, for the sidebar thumbnail and the deck print.
///
/// It shows what the project actually has: uploaded bytes, its bundled render,
/// an image file on disk, or an embedded URL, in that order. A project with
/// none (one started blank) gets a neutral placeholder, never somebody else's
/// image.
class ProjectImage extends StatelessWidget {
  const ProjectImage({
    super.key,
    required this.project,
    required this.cacheWidth,
    this.iconSize = 14,
    this.filterQuality = FilterQuality.medium,
  });

  final StudioProject project;

  /// Decode width in pixels.
  final int cacheWidth;
  final double iconSize;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    Widget placeholder() => ColoredBox(
      color: c.hoverFill,
      child: Center(child: Icon(Icons.add_photo_alternate_outlined, size: iconSize, color: c.ghost)),
    );

    final bytes = project.customBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        filterQuality: filterQuality,
        errorBuilder: (_, _, _) => placeholder(),
      );
    }
    if (project.previewAsset.isNotEmpty) {
      return Image.asset(
        project.previewAsset,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        filterQuality: filterQuality,
        errorBuilder: (_, _, _) => ColoredBox(color: c.hoverFill),
      );
    }
    final path = project.localFilePath;
    if (path != null && project.hasImage && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        filterQuality: filterQuality,
        errorBuilder: (_, _, _) => placeholder(),
      );
    }
    final url = project.externalUrl;
    if (url != null) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        filterQuality: filterQuality,
        errorBuilder: (_, _, _) => placeholder(),
      );
    }
    return placeholder();
  }
}
