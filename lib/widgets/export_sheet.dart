import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// The export sheet: the render frame and the scene manifest, written out.
///
/// It opens from `EXPORT EXR`, shows the manifest that was staged, and offers
/// two actions that work with the engine offline: the viewport frame as a
/// 4K PNG, and the scene as `.pht.json` (also copied to the clipboard).
class ExportProjectModal extends StatefulWidget {
  const ExportProjectModal({super.key});

  @override
  State<ExportProjectModal> createState() => _ExportProjectModalState();
}

class _ExportProjectModalState extends State<ExportProjectModal> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    final t = context.photon;
    final c = t.colors;
    void close() => studio.setExportModalOpen(false);
    final project = studio.activeProject;
    final lines = (studio.stagedManifest ?? '').split('\n');
    final preview = lines.take(16).join('\n') + (lines.length > 16 ? '\n  …' : '');
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
            key: const Key('export-backdrop'),
            behavior: HitTestBehavior.opaque,
            onTap: close,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
          ),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.sizeOf(context).height),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Container(
                  key: const Key('export-project-modal'),
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
                            Icon(Icons.ios_share, size: 13, color: c.violetInk),
                            const SizedBox(width: PhotonSpace.sm - 2),
                            Expanded(child: Text('EXPORT RENDER & SCENE', style: t.text.labelCaps.copyWith(color: c.carbon))),
                            Semantics(
                              button: true,
                              label: 'Close',
                              child: GestureDetector(
                                key: const Key('export-close'),
                                behavior: HitTestBehavior.opaque,
                                onTap: close,
                                child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close, size: 13, color: c.textMuted)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: PhotonSpace.sm),
                        Text(
                          project?.name ?? 'SCENE',
                          key: const Key('export-project-name'),
                          style: t.text.headlineSm,
                        ),
                        Text(
                          '${studio.modelTier.name} · ${studio.integrator.label} · ${studio.targetSamples} SPP',
                          key: const Key('export-summary'),
                          style: t.text.telemetrySm.copyWith(color: c.textMuted),
                        ),
                        const SizedBox(height: PhotonSpace.md - 2),
                        Text('SCENE MANIFEST · .PHT.JSON', style: t.text.labelCaps.copyWith(fontSize: 8, color: c.ghost)),
                        const SizedBox(height: PhotonSpace.xs + 2),
                        Container(
                          height: 150,
                          width: double.infinity,
                          padding: const EdgeInsets.all(PhotonSpace.sm),
                          decoration: BoxDecoration(
                            color: c.canvas,
                            borderRadius: BorderRadius.circular(PhotonRadius.control + 2),
                            border: Border.all(color: c.border),
                          ),
                          child: SingleChildScrollView(
                            child: Text(preview, key: const Key('export-manifest-preview'), style: t.text.mono(size: 9, height: 1.4, color: c.textMuted)),
                          ),
                        ),
                        const SizedBox(height: PhotonSpace.md - 2),
                        Row(
                          children: [
                            Expanded(
                              child: _ExportButton(
                                key: const Key('export-frame-btn'),
                                label: 'EXPORT .EXR / .PNG FRAME',
                                icon: Icons.image_outlined,
                                primary: true,
                                busy: _busy,
                                onTap: () => _run(studio.exportFrame),
                              ),
                            ),
                            const SizedBox(width: PhotonSpace.sm),
                            Expanded(
                              child: _ExportButton(
                                key: const Key('export-pht-btn'),
                                label: 'EXPORT .PHT SCENE JSON',
                                icon: Icons.data_object,
                                primary: false,
                                busy: _busy,
                                onTap: () => _run(studio.exportSceneManifest),
                              ),
                            ),
                          ],
                        ),
                        if (studio.lastExportSummary != null) ...[
                          const SizedBox(height: PhotonSpace.sm),
                          Row(
                            children: [
                              const Pip(color: Color(0xFF22C55E), size: 5),
                              const SizedBox(width: PhotonSpace.sm - 2),
                              Expanded(
                                child: Text(
                                  'SAVED · ${studio.lastExportSummary}',
                                  key: const Key('export-saved-path'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.text.mono(size: 9, height: 1.4, color: c.textMuted),
                                ),
                              ),
                            ],
                          ),
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

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    super.key,
    required this.label,
    required this.icon,
    required this.primary,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Semantics(
      button: true,
      enabled: !busy,
      label: label,
      child: HoverBuilder(
        cursor: busy ? SystemMouseCursors.wait : SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: busy ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm),
            decoration: BoxDecoration(
              color: primary
                  ? (hovered ? Color.alphaBlend(c.onCarbon.withValues(alpha: 0.14), c.carbon) : c.carbon)
                  : (hovered ? c.violet.withValues(alpha: 0.14) : Colors.transparent),
              borderRadius: BorderRadius.circular(PhotonRadius.control + 2),
              border: Border.all(color: primary ? Colors.transparent : (hovered ? c.violet : c.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 13, color: primary ? c.onCarbon : c.textMuted),
                const SizedBox(width: PhotonSpace.sm - 2),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      busy ? 'WORKING...' : label,
                      maxLines: 1,
                      style: t.text.labelCaps.copyWith(fontSize: 8.5, color: primary ? c.onCarbon : c.carbon, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
