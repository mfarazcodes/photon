import 'package:flutter/material.dart';

import '../painters/glyph_painters.dart';
import '../state/workspace_controller.dart';
import '../theme/photon_theme.dart';
import '../widgets/overlay_shell.dart';
import '../widgets/sim_view.dart';
import 'mac_window.dart';

/// Right slide-over "GENERATE VFX." drawer over a blurred desktop. Its form
/// lives in [WorkspaceController.draft]; submitting starts a render job.
class PromptDrawer extends StatelessWidget {
  const PromptDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    return OverlayShell(
      open: ws.overlay == StudioOverlay.promptDrawer,
      onDismiss: ws.closeOverlay,
      builder: (context, a) => LayoutBuilder(builder: (context, c) {
        final width = (c.maxWidth * 0.36).clamp(460.0, 680.0);
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween(begin: const Offset(1.08, 0), end: Offset.zero).animate(a),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
              child: SizedBox(
                width: width,
                height: c.maxHeight - 16,
                child: const _DrawerWindow(),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _DrawerWindow extends StatefulWidget {
  const _DrawerWindow();

  @override
  State<_DrawerWindow> createState() => _DrawerWindowState();
}

class _DrawerWindowState extends State<_DrawerWindow> {
  static const _checkLabels = [
    'Enable volumetric lighting and bloom passes.',
    'Temporal denoise with OptiX (adds ~12% render time).',
    'Export multi-pass EXR to the Render Library.*',
  ];

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.read(context);
    final draft = ws.draft;
    return MacWindow(
      title: 'PROMPT STUDIO',
      rim: false,
      onClose: ws.closeOverlay,
      footer: WindowFooter(
        caption: 'Ready to render on Cloud GPU.',
        action: 'Launch Render Job',
        onAction: ws.submitPrompt,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 270,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: TimeBuilder(
                      builder: (_, t) => CustomPaint(painter: HalftoneBannerPainter(t)),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    top: 14,
                    child: Text('PHOTON://PROMPT_STUDIO',
                        style: PT.mono(size: 11, color: const Color(0xFF8A8A8A))),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 14,
                    child: Text('STIPPLE PREVIEW · LIVE',
                        style: PT.mono(size: 11, color: const Color(0xFF8A8A8A))),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 34),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text('GENERATE VFX.', style: PT.display(size: 66)),
          ),
          const SizedBox(height: 18),
          Text(
            'Describe a shot in plain language. Photon compiles it into a node graph, '
            'solves the physics on GPU and streams every pass back to your desktop.',
            style: PT.body(size: 17),
          ),
          const SizedBox(height: 22),
          ValueListenableBuilder<bool>(
            valueListenable: draft.error,
            builder: (context, error, _) => _Field(
              controller: draft.prompt,
              hint: 'Scene Prompt',
              maxLines: 3,
              errorText: error ? 'A scene prompt is required to render.' : null,
              onChanged: (_) {
                if (draft.error.value) draft.error.value = false;
              },
            ),
          ),
          _Field(controller: draft.negative, hint: 'Negative Prompt'),
          Row(
            children: [
              Expanded(child: _Field(controller: draft.resolution, hint: 'Resolution')),
              const SizedBox(width: 24),
              Expanded(child: _Field(controller: draft.frameRate, hint: 'Frame Rate')),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _Field(
                  controller: draft.solver,
                  hint: 'Physics Solver (e.g. SPH, boids, caustics)',
                ),
              ),
              const SizedBox(width: 24),
              Expanded(child: _Field(controller: draft.seed, hint: 'Seed')),
            ],
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < draft.checks.length; i++)
            _Check(
              label: _checkLabels[i],
              value: draft.checks[i],
              onChanged: () => setState(() => draft.checks[i] = !draft.checks[i]),
            ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        minLines: 1,
        maxLines: maxLines,
        style: PT.label(size: 19, weight: FontWeight.w400),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: PT.label(size: 19, color: PC.muted, weight: FontWeight.w400),
          errorText: errorText,
          errorStyle: PT.label(size: 13, color: PC.red, weight: FontWeight.w500),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFC9C9C9)),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: PC.blue, width: 1.6),
          ),
          errorBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: PC.red, width: 1.6),
          ),
          focusedErrorBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: PC.red, width: 1.6),
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: value ? PC.blue : PC.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: value ? PC.blue : const Color(0xFF6B6B6B), width: 1.4),
                ),
                child: value
                    ? const Icon(Icons.check_rounded, size: 14, color: PC.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: PT.body(size: 15.5, color: PC.inkSoft))),
            ],
          ),
        ),
      ),
    );
  }
}
