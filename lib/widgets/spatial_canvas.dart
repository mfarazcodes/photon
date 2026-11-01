import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'account_sheet.dart';
import 'command_dock.dart';
import 'command_palette.dart';
import 'intent_file_trigger.dart';
import 'launch_hero_portal.dart';
import 'mac_window_viewport.dart';
import 'optics_inspector_deck.dart';
import 'progressive_flux_loader.dart';
import 'projects_sidebar.dart';
import 'roller_prompt_result.dart';
import 'top_telemetry_bar.dart';

/// The full studio workspace.
///
/// At [wideBreakpoint] and above it renders the desktop spatial studio: header
/// across the top, projects sidebar on the left, viewport over the optics deck,
/// command dock along the bottom. Below it, it reflows to the vertical
/// companion controller: header, project carousel, viewport, optics, floating
/// dock. The dot-matrix substrate behind it lights up around the pointer.
class SpatialCanvas extends StatefulWidget {
  const SpatialCanvas({super.key});

  static const double wideBreakpoint = 900;

  @override
  State<SpatialCanvas> createState() => _SpatialCanvasState();
}

class _SpatialCanvasState extends State<SpatialCanvas> {
  /// Shortest height the desktop layout is laid out for; shorter windows scroll.
  static const double _minDesktopHeight = 720;

  /// Pointer in this widget's coordinates. Only the dot painter listens, so
  /// moving the mouse repaints one layer and rebuilds nothing.
  final ValueNotifier<Offset?> _pointerPos = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _pointerPos.dispose();
    super.dispose();
  }

  /// Ctrl+P opens the command palette; Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z step the
  /// optics history. Undo and redo are left alone while a text field has focus,
  /// so typing keeps its own undo.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    final kb = HardwareKeyboard.instance;
    if (!(kb.isControlPressed || kb.isMetaPressed)) return false;
    final studio = StudioScope.read(context);
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyP) {
      studio.toggleCommandPalette();
      return true;
    }
    final typing = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (typing) return false;
    if (key == LogicalKeyboardKey.keyZ) {
      kb.isShiftPressed ? studio.redo() : studio.undo();
      return true;
    }
    if (key == LogicalKeyboardKey.keyY) {
      studio.redo();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    final c = context.photon.colors;
    return MouseRegion(
      opaque: false,
      onExit: (_) => _pointerPos.value = null,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: (e) => _pointerPos.value = e.localPosition,
        // Hover events stop while a button is down; keep following drags.
        onPointerMove: (e) => _pointerPos.value = e.localPosition,
        child: ColoredBox(
          color: c.canvas,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: DotMatrixSubstrate(
                  color: c.isDark ? const Color(0xFF2E3036) : const Color(0xFFD0D0D8),
                  highlight: c.isDark ? Colors.white : const Color(0xFF0E0E10),
                  tint: c.isDark ? const Color(0xFFB57BFF) : c.violet,
                  pointerPos: _pointerPos,
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, box) => box.maxWidth >= SpatialCanvas.wideBreakpoint
                      ? _desktop(studio, box)
                      : _companion(studio, box),
                ),
              ),
              // Overlays sit above everything, header and dock included.
              if (studio.uploadLoaderVisible) _fluxLoader(studio),
              if (studio.promptResult != null) _rollerResult(studio),
              // Keyed so one overlay appearing never resets another's state.
              if (studio.ingestSheetOpen)
                const Positioned.fill(key: ValueKey('overlay-ingest'), child: FileIngestSheet()),
              if (studio.accountModalOpen)
                const Positioned.fill(key: ValueKey('overlay-account'), child: AccountInspectorModal(key: Key('account-modal'))),
              if (studio.commandPaletteOpen) const Positioned.fill(key: ValueKey('overlay-palette'), child: CommandPalette()),
              if (studio.showLaunchPortal)
                const Positioned.fill(key: ValueKey('overlay-portal'), child: LaunchHeroPortal(key: Key('launch-hero-portal'))),
            ],
          ),
        ),
      ),
    );
  }

  /// The ingest progress card, top-center over the viewport stage. It never
  /// takes pointer events.
  Widget _fluxLoader(StudioController studio) {
    return Positioned.fill(
      key: const ValueKey('overlay-flux'),
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.only(top: TopTelemetryBar.height + 64),
          child: Align(
            alignment: Alignment.topCenter,
            child: ProgressiveFluxLoader(
              key: const Key('progressive-flux-loader'),
              fileName: studio.uploadingFileName ?? '',
              progress: studio.uploadProgress,
              phaseLabel: studio.uploadPhaseLabel,
              phaseIndex: studio.uploadPhaseIndex,
              phaseCount: StudioController.uploadPhases.length,
              sizeMb: studio.uploadSizeMb,
              animate: studio.animateShader,
            ),
          ),
        ),
      ),
    );
  }

  /// The prompt / ingest result banner, centered just above the dock.
  Widget _rollerResult(StudioController studio) {
    final wide = MediaQuery.sizeOf(context).width >= SpatialCanvas.wideBreakpoint;
    return Positioned.fill(
      key: const ValueKey('overlay-roller'),
      child: Padding(
        padding: EdgeInsets.only(bottom: wide ? 104 : 200, left: PhotonSpace.md, right: PhotonSpace.md),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: RollerPromptResult(
            key: const Key('roller-prompt-result'),
            result: studio.promptResult!,
            onDismiss: studio.dismissPromptResult,
          ),
        ),
      ),
    );
  }

  /// Viewport and optics windows, honoring collapse and maximize state.
  List<Widget> _panels(StudioController studio) {
    final maximized = studio.maximizedPanel;
    // The account console takes the whole column when it is the workspace.
    if (maximized == 'account') return const [Expanded(child: AccountSheet(embedded: true))];
    final showViewport = maximized != 'optics';
    final showOptics = maximized != 'viewport';
    const viewport = MacWindowViewport();
    const optics = OpticsInspectorDeck();
    return [
      if (showViewport) studio.viewportCollapsed ? viewport : const Expanded(child: viewport),
      if (showViewport && showOptics) const SizedBox(height: PhotonSpace.md),
      if (showOptics)
        // A collapsed or maximized neighbour hands its space to this panel.
        (!studio.opticsCollapsed && (maximized == 'optics' || studio.viewportCollapsed))
            ? const Expanded(child: optics)
            : optics,
    ];
  }

  Widget _desktop(StudioController studio, BoxConstraints box) {
    final layout = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TopTelemetryBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(PhotonSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ProjectsSidebar(),
                      const SizedBox(width: PhotonSpace.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _panels(studio),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PhotonSpace.md),
                const CommandDock(),
              ],
            ),
          ),
        ),
      ],
    );

    if (box.maxHeight >= _minDesktopHeight) return layout;
    return SingleChildScrollView(
      child: SizedBox(height: _minDesktopHeight, child: layout),
    );
  }

  Widget _companion(StudioController studio, BoxConstraints box) {
    // Clearance for the floating dock: pill strip + prompt bar + margins.
    final dockClearance = math.min(box.maxHeight * 0.4, 196.0);
    final maximized = studio.maximizedPanel;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TopTelemetryBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  PhotonSpace.md,
                  PhotonSpace.md,
                  PhotonSpace.md,
                  dockClearance,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ProjectsSidebar(axis: Axis.horizontal),
                    const SizedBox(height: PhotonSpace.lg),
                    if (maximized == 'account')
                      const AccountSheet(embedded: false)
                    else ...[
                      if (maximized != 'optics') const MacWindowViewport(stageAspectRatio: 16 / 10),
                      if (maximized == null) const SizedBox(height: PhotonSpace.lg),
                      if (maximized != 'viewport') const OpticsInspectorDeck(),
                    ],
                  ],
                ),
              ),
            ),
          ],
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

/// Dot-grid coordinates (interleaved `x, y`, row-major), rebuilt only when the
/// size changes. Repaints reuse the same list instead of allocating thousands
/// of [Offset]s each time.
class DotGridCache {
  static const double pitch = 16;

  Size? _size;
  Float32List? _coords;

  /// Grid dimensions of the cached [coordsFor] result.
  int columns = 0;
  int rows = 0;

  Float32List coordsFor(Size size) {
    final cached = _coords;
    if (cached != null && _size == size) return cached;
    columns = _cells(size.width);
    rows = _cells(size.height);
    final coords = Float32List(columns * rows * 2);
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

/// Dot-matrix substrate (16px pitch) behind the floating windows. Dots within
/// [DotMatrixPainter.spotlightRadius] of [pointerPos] swell and light up.
class DotMatrixSubstrate extends StatefulWidget {
  const DotMatrixSubstrate({
    super.key,
    required this.color,
    required this.highlight,
    required this.tint,
    required this.pointerPos,
  });

  /// Resting dot color.
  final Color color;

  /// Color of the dot under the pointer.
  final Color highlight;

  /// Mid-ring tint between [color] and [highlight].
  final Color tint;
  final ValueNotifier<Offset?> pointerPos;

  @override
  State<DotMatrixSubstrate> createState() => _DotMatrixSubstrateState();
}

class _DotMatrixSubstrateState extends State<DotMatrixSubstrate> {
  final DotGridCache _cache = DotGridCache();

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: DotMatrixPainter(
      color: widget.color,
      highlight: widget.highlight,
      tint: widget.tint,
      cache: _cache,
      pointerPos: widget.pointerPos,
    ),
  );
}

class DotMatrixPainter extends CustomPainter {
  DotMatrixPainter({
    required this.color,
    required this.highlight,
    required this.tint,
    required this.cache,
    required this.pointerPos,
  }) : super(repaint: pointerPos);

  final Color color;
  final Color highlight;
  final Color tint;
  final DotGridCache cache;
  final ValueNotifier<Offset?> pointerPos;

  static const double spotlightRadius = 170;
  static const double baseStroke = 1.3;
  static const double peakStroke = 2.4;

  /// Falloff weight for a dot [distance] px from the pointer: 1 under the
  /// cursor, easing to 0 at [spotlightRadius].
  static double proximity(double distance) =>
      distance >= spotlightRadius ? 0 : math.pow(1 - distance / spotlightRadius, 2).toDouble();

  /// Resting color through the violet tint to the highlight as [t] goes 0 to 1.
  Color colorAt(double t) =>
      t < 0.5 ? Color.lerp(color, tint, t * 2)! : Color.lerp(tint, highlight, (t - 0.5) * 2)!;

  @override
  void paint(Canvas canvas, Size size) {
    final coords = cache.coordsFor(size);
    canvas.drawRawPoints(
      PointMode.points,
      coords,
      Paint()
        ..color = color
        ..strokeWidth = baseStroke
        ..strokeCap = StrokeCap.round,
    );

    final p = pointerPos.value;
    if (p == null) return;

    // Only the grid cells inside the spotlight's bounding box are visited.
    const pitch = DotGridCache.pitch;
    const half = pitch / 2;
    final colMin = math.max(0, ((p.dx - spotlightRadius - half) / pitch).ceil());
    final colMax = math.min(cache.columns - 1, ((p.dx + spotlightRadius - half) / pitch).floor());
    final rowMin = math.max(0, ((p.dy - spotlightRadius - half) / pitch).ceil());
    final rowMax = math.min(cache.rows - 1, ((p.dy + spotlightRadius - half) / pitch).floor());
    const r2 = spotlightRadius * spotlightRadius;

    final paint = Paint();
    for (var row = rowMin; row <= rowMax; row++) {
      for (var col = colMin; col <= colMax; col++) {
        final i = (row * cache.columns + col) * 2;
        final x = coords[i];
        final y = coords[i + 1];
        final dx = x - p.dx;
        final dy = y - p.dy;
        final d2 = dx * dx + dy * dy;
        if (d2 >= r2) continue;
        final t = proximity(math.sqrt(d2));
        paint.color = colorAt(t);
        canvas.drawCircle(Offset(x, y), (baseStroke + (peakStroke - baseStroke) * t) / 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(DotMatrixPainter old) =>
      old.color != color || old.highlight != highlight || old.tint != tint;
}
