import 'package:flutter/material.dart';

import '../models/desktop_node.dart';
import '../painters/glyph_painters.dart';
import '../state/workspace_controller.dart';
import '../theme/photon_theme.dart';
import '../widgets/overlay_shell.dart';
import '../widgets/sim_view.dart';
import 'mac_window.dart';

/// Right slide-over "GENERATE VFX." drawer over a blurred desktop.
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
  final _prompt = TextEditingController();
  final _negative = TextEditingController();
  final _resolution = TextEditingController();
  final _fps = TextEditingController();
  final _solver = TextEditingController();
  final _seed = TextEditingController();
  final _checks = [true, false, true];

  static const _checkLabels = [
    'Enable volumetric lighting and bloom passes.',
    'Temporal denoise with OptiX (adds ~12% render time).',
    'Export multi-pass EXR to the Render Library.*',
  ];

  @override
  void dispose() {
    for (final c in [_prompt, _negative, _resolution, _fps, _solver, _seed]) {
      c.dispose();
    }
    super.dispose();
  }

  SimKind _guessSim(String text) {
    final t = text.toLowerCase();
    if (t.contains('chrome') || t.contains('metal')) return SimKind.chrome;
    if (t.contains('liquid') || t.contains('goo') || t.contains('fluid')) return SimKind.liquid;
    if (t.contains('marble') || t.contains('smoke')) return SimKind.marble;
    if (t.contains('water') || t.contains('caustic') || t.contains('pool')) return SimKind.caustics;
    if (t.contains('swarm') || t.contains('nano') || t.contains('particle')) return SimKind.swarm;
    if (t.contains('cloth') || t.contains('vacuum') || t.contains('plastic')) return SimKind.cloth;
    if (t.contains('wire') || t.contains('mesh')) return SimKind.wireframe;
    return SimKind.fog;
  }

  void _launch() {
    final ws = WorkspaceScope.read(context);
    ws.launchRender(_prompt.text, _guessSim(_prompt.text));
  }

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.read(context);
    return MacWindow(
      title: 'PROMPT STUDIO',
      rim: false,
      onClose: ws.closeOverlay,
      footer: WindowFooter(
        caption: 'Ready to render on Cloud GPU.',
        action: 'Launch Render Job',
        onAction: _launch,
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
          _Field(controller: _prompt, hint: 'Scene Prompt', maxLines: 3),
          _Field(controller: _negative, hint: 'Negative Prompt'),
          Row(
            children: [
              Expanded(child: _Field(controller: _resolution, hint: 'Resolution')),
              const SizedBox(width: 24),
              Expanded(child: _Field(controller: _fps, hint: 'Frame Rate')),
            ],
          ),
          Row(
            children: [
              Expanded(child: _Field(controller: _solver, hint: 'Physics Solver')),
              const SizedBox(width: 24),
              Expanded(child: _Field(controller: _seed, hint: 'Seed')),
            ],
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < _checks.length; i++)
            _Check(
              label: _checkLabels[i],
              value: _checks[i],
              onChanged: () => setState(() => _checks[i] = !_checks[i]),
            ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, this.maxLines = 1});

  final TextEditingController controller;
  final String hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: TextField(
        controller: controller,
        minLines: 1,
        maxLines: maxLines,
        style: PT.label(size: 19, weight: FontWeight.w400),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: PT.label(size: 19, color: PC.muted, weight: FontWeight.w400),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFC9C9C9)),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: PC.blue, width: 1.6),
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
