import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../theme/photon_theme.dart';
import 'command_dock.dart';
import 'mac_window_viewport.dart';
import 'optics_inspector_deck.dart';
import 'perimeter_asset_strip.dart';
import 'top_telemetry_bar.dart';

/// The full studio workspace.
///
/// At [wideBreakpoint] and above it renders the desktop spatial studio:
/// asset perimeter on the left, viewport over the optics deck, command dock
/// along the bottom. Below it, it reflows to the vertical companion
/// controller: ribbon, asset carousel, viewport, optics, floating dock.
class SpatialCanvas extends StatelessWidget {
  const SpatialCanvas({super.key});

  static const double wideBreakpoint = 900;

  /// Shortest height the desktop layout is laid out for; shorter windows scroll.
  static const double _minDesktopHeight = 720;

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    return ColoredBox(
      color: c.canvas,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: _DotMatrixSubstrate(color: c.ghost.withValues(alpha: 0.4)),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) =>
                  box.maxWidth >= wideBreakpoint ? _desktop(box) : _companion(context, box),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktop(BoxConstraints box) {
    final layout = Padding(
      padding: const EdgeInsets.all(PhotonSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TopTelemetryBar(),
          const SizedBox(height: PhotonSpace.md),
          const Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PerimeterAssetStrip(axis: Axis.vertical),
                SizedBox(width: PhotonSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: MacWindowViewport()),
                      SizedBox(height: PhotonSpace.md),
                      OpticsInspectorDeck(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: PhotonSpace.md),
          const CommandDock(),
        ],
      ),
    );

    if (box.maxHeight >= _minDesktopHeight) return layout;
    return SingleChildScrollView(
      child: SizedBox(height: _minDesktopHeight, child: layout),
    );
  }

  Widget _companion(BuildContext context, BoxConstraints box) {
    // Clearance for the floating dock: pill strip + prompt bar + margins.
    final dockClearance = math.min(box.maxHeight * 0.4, 156.0);
    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            PhotonSpace.md,
            PhotonSpace.sm,
            PhotonSpace.md,
            dockClearance,
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TopTelemetryBar(),
              SizedBox(height: PhotonSpace.lg),
              PerimeterAssetStrip(axis: Axis.horizontal),
              SizedBox(height: PhotonSpace.lg),
              MacWindowViewport(stageAspectRatio: 16 / 10),
              SizedBox(height: PhotonSpace.lg),
              OpticsInspectorDeck(),
            ],
          ),
        ),
        const Positioned(
          left: PhotonSpace.md,
          right: PhotonSpace.md,
          bottom: PhotonSpace.md,
          child: CommandDock(),
        ),
      ],
    );
  }
}

/// Interleaved `x, y` coordinates of the dot grid, rebuilt only when the size
/// changes. Repaints (theme change, route transitions) reuse the same list
/// instead of allocating thousands of [Offset]s each time.
class DotGridCache {
  static const double pitch = 16;

  Size? _size;
  Float32List? _coords;

  Float32List coordsFor(Size size) {
    final cached = _coords;
    if (cached != null && _size == size) return cached;
    final coords = Float32List(_cells(size.width) * _cells(size.height) * 2);
    var i = 0;
    for (var y = pitch / 2; y < size.height; y += pitch) {
      for (var x = pitch / 2; x < size.width; x += pitch) {
        coords[i++] = x;
        coords[i++] = y;
      }
    }
    _size = size;
    return _coords = coords;
  }

  /// Dots along one axis; counted with the same loop that fills the list.
  static int _cells(double extent) {
    var n = 0;
    for (var p = pitch / 2; p < extent; p += pitch) {
      n++;
    }
    return n;
  }
}

/// Dot-matrix substrate behind the floating windows (16px pitch).
class _DotMatrixSubstrate extends StatefulWidget {
  const _DotMatrixSubstrate({required this.color});

  final Color color;

  @override
  State<_DotMatrixSubstrate> createState() => _DotMatrixSubstrateState();
}

class _DotMatrixSubstrateState extends State<_DotMatrixSubstrate> {
  final DotGridCache _cache = DotGridCache();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DotMatrixPainter(color: widget.color, cache: _cache));
}

class _DotMatrixPainter extends CustomPainter {
  const _DotMatrixPainter({required this.color, required this.cache});

  final Color color;
  final DotGridCache cache;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawRawPoints(PointMode.points, cache.coordsFor(size), paint);
  }

  @override
  bool shouldRepaint(_DotMatrixPainter old) => old.color != color;
}
