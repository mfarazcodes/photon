import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// A tactile folder button for adding `.USD`, `.EXR`, `.BSDF`, `.IOR` and `.OBJ`
/// scene files.
///
/// At rest it is a closed folder: a back plate with its tab, two miniature file
/// sheets (`USD` and `EXR`) tucked inside, and a frosted front flap. On hover
/// the flap tilts forward 14 degrees in perspective, the sheets fan up and out
/// on an overshoot spring (`Curves.easeOutBack`), and the border lights with a
/// violet halo.
class IntentFileTrigger extends StatefulWidget {
  const IntentFileTrigger({super.key, required this.onTap, this.scale = 1});

  final VoidCallback onTap;

  /// Uniform size multiplier; the folder is 36x28 at 1.
  final double scale;

  static const Size baseSize = Size(36, 28);

  @override
  State<IntentFileTrigger> createState() => _IntentFileTriggerState();
}

class _IntentFileTriggerState extends State<IntentFileTrigger> with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  void _setHover(bool hovered) => hovered ? _open.forward() : _open.reverse();

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    final size = IntentFileTrigger.baseSize;
    return Tooltip(
      message: 'Ingest .USD · .EXR · .BSDF · .IOR · .OBJ',
      child: Semantics(
        button: true,
        label: 'Add scene file',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _setHover(true),
          onExit: (_) => _setHover(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: SizedBox(
              width: size.width * widget.scale,
              height: size.height * widget.scale,
              child: FittedBox(
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: AnimatedBuilder(
                    animation: _open,
                    builder: (context, _) {
                      // easeOutBack overshoots 1 before settling: the spring.
                      final raw = _open.value;
                      final spring = Curves.easeOutBack.transform(raw);
                      return _FolderArt(spring: spring, glow: raw, colors: c);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderArt extends StatelessWidget {
  const _FolderArt({required this.spring, required this.glow, required this.colors});

  /// Overshooting open amount (0 closed, 1 fully open, briefly beyond).
  final double spring;

  /// Plain 0..1 open amount, for the halo.
  final double glow;
  final PhotonPalette colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final t = context.photon;
    final plate = c.isDark ? const Color(0xFF2B2C34) : const Color(0xFFDADAE3);
    final edge = Color.lerp(c.isDark ? const Color(0xFF45464F) : const Color(0xFFBDBDC9), c.violet, glow)!;

    Widget sheet({required String label, required double left, required double restTilt, required double openTilt, required Offset openShift, required Color accent}) {
      final tilt = (restTilt + (openTilt - restTilt) * spring) * math.pi / 180;
      return Positioned(
        left: left + openShift.dx * spring,
        top: 8 + openShift.dy * spring,
        child: Transform.rotate(
          angle: tilt,
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 17,
            height: 21,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(
              color: c.isDark ? const Color(0xFFF3F3F5) : Colors.white,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: accent.withValues(alpha: 0.7), width: 1),
            ),
            child: Text(
              label,
              style: t.text.mono(size: 5.5, weight: FontWeight.w700, height: 1, color: accent),
            ),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Back plate with its tab.
        Positioned.fill(child: CustomPaint(painter: _FolderPlatePainter(plate: plate, edge: edge, glow: glow, violet: c.violet))),
        sheet(
          label: 'USD',
          left: 4,
          restTilt: -3,
          openTilt: -17,
          openShift: const Offset(-2.5, -10),
          accent: const Color(0xFF8A2BE2),
        ),
        sheet(
          label: 'EXR',
          left: 14,
          restTilt: 3,
          openTilt: 15,
          openShift: const Offset(2.5, -11),
          accent: const Color(0xFFFF2D78),
        ),
        // Front flap: frosted glass, hinged along its bottom edge.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 17,
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.012)
              ..rotateX(-14 * math.pi / 180 * spring),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: c.isDark
                      ? [const Color(0xFF51525C).withValues(alpha: 0.92), const Color(0xFF32333B).withValues(alpha: 0.96)]
                      : [Colors.white.withValues(alpha: 0.96), const Color(0xFFE6E6EE).withValues(alpha: 0.96)],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3), bottom: Radius.circular(4)),
                border: Border.all(color: edge),
                boxShadow: [BoxShadow(color: c.violet.withValues(alpha: 0.55 * glow), blurRadius: 10, spreadRadius: 0.5)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FolderPlatePainter extends CustomPainter {
  const _FolderPlatePainter({required this.plate, required this.edge, required this.glow, required this.violet});

  final Color plate;
  final Color edge;
  final double glow;
  final Color violet;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromLTRBR(0, 4, size.width, size.height, const Radius.circular(4));
    final tab = RRect.fromLTRBAndCorners(
      0,
      0,
      15,
      7,
      topLeft: const Radius.circular(3),
      topRight: const Radius.circular(3),
    );
    final path = Path()
      ..addRRect(body)
      ..addRRect(tab);
    if (glow > 0.01) {
      canvas.drawPath(
        path,
        Paint()
          ..color = violet.withValues(alpha: 0.5 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawPath(path, Paint()..color = plate);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edge,
    );
  }

  @override
  bool shouldRepaint(_FolderPlatePainter old) =>
      old.plate != plate || old.edge != edge || old.glow != glow || old.violet != violet;
}

/// One curated asset in the ingest sheet.
@immutable
class IngestPreset {
  const IngestPreset(this.fileName, this.sizeMb, this.description, this.icon);

  final String fileName;
  final double sizeMb;
  final String description;
  final IconData icon;

  String get extension => fileName.substring(fileName.lastIndexOf('.') + 1).toUpperCase();
}

const List<IngestPreset> kIngestPresets = [
  IngestPreset('CHRONOS_WATCH.usd', 112.4, 'Hero mesh · 12 prims · PBR', Icons.watch_outlined),
  IngestPreset('CAUSTIC_POOL.exr', 64.8, 'Multi-layer · 32-bit · AOVs', Icons.layers_outlined),
  IngestPreset('DIAMOND_BRDF.ior', 8.2, 'Spectral dispersion shader', Icons.diamond_outlined),
  IngestPreset('STUDIO_SOFTBOX.hdr', 36.0, 'Dome light · 16K latlong', Icons.wb_sunny_outlined),
];

/// The ingest sheet: bring a file from disk, embed a direct URL, or pick one of
/// the curated samples. Escape or a click outside closes it; any of them starts
/// the Progressive Flux Loader.
class FileIngestSheet extends StatefulWidget {
  const FileIngestSheet({super.key});

  /// The largest image read into memory for the viewport (bigger ones are shown
  /// from disk instead).
  static const int maxInlineImageBytes = 32 * 1024 * 1024;

  @override
  State<FileIngestSheet> createState() => _FileIngestSheetState();
}

class _FileIngestSheetState extends State<FileIngestSheet> {
  final TextEditingController _path = TextEditingController();
  final TextEditingController _url = TextEditingController();
  final FocusNode _pathFocus = FocusNode(debugLabel: 'ingest-path');

  /// A line under the browse card: what happened, or what to do next.
  String? _note;
  bool _browsing = false;

  @override
  void dispose() {
    _path.dispose();
    _url.dispose();
    _pathFocus.dispose();
    super.dispose();
  }

  /// Opens the native file dialog; if there is none, or it is cancelled, falls
  /// back to the path field.
  Future<void> _browse() async {
    if (_browsing) return;
    final studio = StudioScope.read(context);
    setState(() => _browsing = true);
    final picked = await studio.pickLocalFile();
    if (!mounted) return;
    setState(() => _browsing = false);
    if (picked == null) {
      setState(() => _note = 'NO FILE CHOSEN · TYPE OR PASTE A PATH BELOW');
      _pathFocus.requestFocus();
      return;
    }
    _ingestPath(picked);
  }

  /// Reads [raw] from disk (size, and the bytes of an image) and ingests it.
  void _ingestPath(String raw) {
    final studio = StudioScope.read(context);
    var path = raw.trim();
    if (path.length > 1 && path.startsWith('"') && path.endsWith('"')) path = path.substring(1, path.length - 1);
    if (path.isEmpty) {
      setState(() => _note = 'TYPE OR PASTE A FILE PATH');
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      studio.showToast('FILE NOT FOUND · $path');
      setState(() => _note = 'FILE NOT FOUND · CHECK THE PATH');
      return;
    }
    final size = file.lengthSync();
    final dot = path.lastIndexOf('.');
    final ext = dot > 0 ? path.substring(dot + 1).toLowerCase() : '';
    final Uint8List? bytes = StudioController.imageExtensions.contains(ext) && size <= FileIngestSheet.maxInlineImageBytes
        ? file.readAsBytesSync()
        : null;
    studio.startLocalFileIngest(filePath: path, bytes: bytes, sizeMb: size / (1024 * 1024));
  }

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    final t = context.photon;
    final c = t.colors;
    void close() => studio.setIngestSheetOpen(false);
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
          GestureDetector(
            key: const Key('ingest-backdrop'),
            behavior: HitTestBehavior.opaque,
            onTap: close,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.42)),
          ),
          Center(
            child: ConstrainedBox(
              // Wide enough for the path and URL fields; it scrolls inside the
              // window rather than overflow it.
              constraints: BoxConstraints(maxWidth: 480, maxHeight: MediaQuery.sizeOf(context).height),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Container(
                  key: const Key('file-ingest-sheet'),
                  margin: const EdgeInsets.all(PhotonSpace.lg),
                  padding: const EdgeInsets.all(PhotonSpace.md),
                  decoration: BoxDecoration(
                    color: c.substrate,
                    borderRadius: BorderRadius.circular(PhotonRadius.window),
                    border: Border.all(color: c.border),
                    boxShadow: t.level2,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.create_new_folder_outlined, size: 13, color: c.violetInk),
                          const SizedBox(width: PhotonSpace.sm - 2),
                          Expanded(
                            child: Text('INGEST SCENE FILES', style: t.text.labelCaps.copyWith(color: c.carbon)),
                          ),
                          Semantics(
                            button: true,
                            label: 'Close',
                            child: GestureDetector(
                              key: const Key('ingest-close'),
                              behavior: HitTestBehavior.opaque,
                              onTap: close,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.close, size: 13, color: c.textMuted),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: PhotonSpace.sm),
                      Wrap(
                        spacing: PhotonSpace.xs + 2,
                        runSpacing: PhotonSpace.xs,
                        children: [
                          for (final ext in const ['USD', 'EXR', 'BSDF', 'IOR', 'OBJ', 'HDR'])
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: c.violet.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(PhotonRadius.pill),
                              ),
                              child: Text('.$ext', style: t.text.labelCaps.copyWith(fontSize: 8, color: c.violetInk)),
                            ),
                        ],
                      ),
                      const SizedBox(height: PhotonSpace.md),
                      Text('LOCAL FILE UPLOAD', style: t.text.labelCaps.copyWith(fontSize: 8, color: c.ghost)),
                      const SizedBox(height: PhotonSpace.xs + 2),
                      _BrowseCard(
                        key: const Key('ingest-local-file-btn'),
                        busy: _browsing,
                        onTap: _browse,
                      ),
                      if (_note != null) ...[
                        const SizedBox(height: PhotonSpace.xs + 2),
                        Text(_note!, key: const Key('ingest-note'), style: t.text.labelCaps.copyWith(fontSize: 7.5, color: c.rose)),
                      ],
                      const SizedBox(height: PhotonSpace.sm),
                      _InputRow(
                        fieldKey: const Key('ingest-local-path-input'),
                        buttonKey: const Key('ingest-local-path-submit'),
                        controller: _path,
                        focusNode: _pathFocus,
                        hint: r'C:\path\to\scene.png, .exr, .usd',
                        button: 'INGEST',
                        onSubmit: () => _ingestPath(_path.text),
                      ),
                      const SizedBox(height: PhotonSpace.md),
                      Text('DIRECT URL EMBED', style: t.text.labelCaps.copyWith(fontSize: 8, color: c.ghost)),
                      const SizedBox(height: PhotonSpace.xs + 2),
                      _InputRow(
                        fieldKey: const Key('ingest-url-input'),
                        buttonKey: const Key('ingest-url-submit-btn'),
                        controller: _url,
                        hint: 'https://.../scene.png, .exr, .usd or ws://...',
                        button: 'EMBED URL',
                        onSubmit: () => studio.startUrlIngest(_url.text),
                      ),
                      const SizedBox(height: PhotonSpace.md),
                      Text('CURATED ASSETS', style: t.text.labelCaps.copyWith(fontSize: 8, color: c.ghost)),
                      const SizedBox(height: PhotonSpace.xs + 2),
                      for (final preset in kIngestPresets) ...[
                        _PresetRow(
                          preset: preset,
                          onTap: () => studio.startFileUpload(preset.fileName, sizeMb: preset.sizeMb),
                        ),
                        const SizedBox(height: PhotonSpace.xs + 2),
                      ],
                    ],
                  ),
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

/// A dashed, tactile card that opens the file dialog.
class _BrowseCard extends StatelessWidget {
  const _BrowseCard({super.key, required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Semantics(
      button: true,
      label: 'Upload local file',
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: hovered ? c.violet : c.border,
              fill: hovered ? c.violet.withValues(alpha: 0.07) : c.hoverFill,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md, vertical: PhotonSpace.md - 2),
              child: Row(
                children: [
                  Icon(Icons.upload_file, size: 20, color: hovered ? c.violetInk : c.textMuted),
                  const SizedBox(width: PhotonSpace.md - 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'UPLOAD LOCAL FILE (.PNG, .JPG, .USD, .EXR, .OBJ)',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.text.labelCaps.copyWith(fontSize: 8.5, color: c.carbon),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Pick a file on this computer. Images open in the viewport as they are.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.text.telemetrySm.copyWith(fontSize: 9, color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: PhotonSpace.sm),
                  Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm + 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.carbon,
                      borderRadius: BorderRadius.circular(PhotonRadius.control),
                    ),
                    child: Text(
                      busy ? 'OPENING...' : 'BROWSE DISK...',
                      style: t.text.labelCaps.copyWith(fontSize: 8, color: c.onCarbon, fontWeight: FontWeight.w700),
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

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.fill});

  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(PhotonRadius.window));
    canvas.drawRRect(rrect, Paint()..color = fill);
    final border = Path()..addRRect(rrect.deflate(0.5));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in border.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color || old.fill != fill;
}

/// A single-line field with an action button beside it; Enter submits too.
class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.fieldKey,
    required this.buttonKey,
    required this.controller,
    required this.hint,
    required this.button,
    required this.onSubmit,
    this.focusNode,
  });

  final Key fieldKey;
  final Key buttonKey;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final String button;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(PhotonRadius.control),
      borderSide: BorderSide(color: color),
    );
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 30,
            child: TextField(
              key: fieldKey,
              controller: controller,
              focusNode: focusNode,
              onSubmitted: (_) => onSubmit(),
              maxLines: 1,
              cursorColor: c.violetInk,
              style: t.text.telemetryMd.copyWith(color: c.carbon),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.canvas,
                hintText: hint,
                hintStyle: t.text.telemetrySm.copyWith(color: c.ghost),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: border(c.border),
                enabledBorder: border(c.border),
                focusedBorder: border(c.violet),
              ),
            ),
          ),
        ),
        const SizedBox(width: PhotonSpace.sm),
        Semantics(
          button: true,
          label: button,
          child: HoverBuilder(
            cursor: SystemMouseCursors.click,
            builder: (context, hovered) => GestureDetector(
              key: buttonKey,
              behavior: HitTestBehavior.opaque,
              onTap: onSubmit,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hovered ? c.violet.withValues(alpha: 0.16) : c.violet.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(PhotonRadius.control),
                  border: Border.all(color: hovered ? c.violet : c.violet.withValues(alpha: 0.5)),
                ),
                child: Text(button, style: t.text.labelCaps.copyWith(fontSize: 8, color: c.violetInk, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.preset, required this.onTap});

  final IngestPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Semantics(
      button: true,
      label: 'Ingest ${preset.fileName}',
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          key: Key('ingest-file-${preset.fileName}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm + 2, vertical: PhotonSpace.sm),
            decoration: BoxDecoration(
              color: hovered ? c.violet.withValues(alpha: 0.1) : c.hoverFill,
              borderRadius: BorderRadius.circular(PhotonRadius.control),
              border: Border.all(color: hovered ? c.violet.withValues(alpha: 0.6) : c.border),
            ),
            child: Row(
              children: [
                Icon(preset.icon, size: 15, color: hovered ? c.violetInk : c.textMuted),
                const SizedBox(width: PhotonSpace.sm + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.mono(size: 11, weight: FontWeight.w600, height: 1.3, color: c.carbon),
                      ),
                      Text(
                        preset.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.telemetrySm.copyWith(fontSize: 9, color: c.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: PhotonSpace.sm),
                Text('${preset.sizeMb.toStringAsFixed(1)} MB', style: t.text.labelCaps.copyWith(fontSize: 8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
