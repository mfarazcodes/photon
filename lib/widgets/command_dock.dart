import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/render_socket.dart';
import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// Bottom command dock: "P." monogram, scene prompt field, quick-action pills
/// and the trigger that dispatches the prompt JSON over the WebSocket.
///
/// On wide windows everything sits on one bar; below [_inlineWidth] the pills
/// move to their own strip above the bar (companion layout).
class CommandDock extends StatefulWidget {
  const CommandDock({super.key});

  @override
  State<CommandDock> createState() => _CommandDockState();
}

class _CommandDockState extends State<CommandDock> {
  static const double _inlineWidth = 1120;

  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'scene-prompt');

  static const _presets = <String, String>{
    'bsdf': 'Brushed gold BSDF, roughness 0.35, soft studio key light',
    'archive': 'Load archived scene: ',
    'camera': '85mm lens, f/1.4, focus 1.8m, shallow depth of field',
  };

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Ctrl+K (⌘K on macOS) jumps to the prompt from anywhere in the app.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyK) return false;
    final kb = HardwareKeyboard.instance;
    if (!(kb.isControlPressed || kb.isMetaPressed)) return false;
    _focus.requestFocus();
    return true;
  }

  void _send() => StudioScope.read(context).sendPrompt(_text.text);

  void _applyPreset(String key) {
    final preset = _presets[key]!;
    final existing = _text.text.trim();
    final next = existing.isEmpty ? preset : '$existing, $preset';
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    final c = context.photon.colors;

    final pills = [
      _QuickPill(emoji: '⚡', label: 'RENDER PROMPT', onTap: _send),
      _QuickPill(emoji: '🎛️', label: 'BSDF SHADERS', onTap: () => _applyPreset('bsdf')),
      _QuickPill(emoji: '📁', label: 'SCENE ARCHIVE', onTap: () => _applyPreset('archive')),
      _QuickPill(emoji: '🎥', label: 'CAMERA OPTICS', onTap: () => _applyPreset('camera')),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final inline = box.maxWidth >= _inlineWidth;
        final bar = _DockSurface(
          child: Row(
            children: [
              const _Monogram(),
              const SizedBox(width: PhotonSpace.md),
              Expanded(
                child: _PromptField(
                  controller: _text,
                  focusNode: _focus,
                  onSubmit: _send,
                  showShortcut: box.maxWidth >= 480,
                ),
              ),
              if (inline) ...[
                const SizedBox(width: PhotonSpace.md),
                for (final p in pills) ...[p, const SizedBox(width: PhotonSpace.sm)],
                _LinkButton(link: studio.link),
                const SizedBox(width: PhotonSpace.sm),
              ] else
                const SizedBox(width: PhotonSpace.sm),
              _SendButton(onPressed: _send, accent: c.violet),
            ],
          ),
        );
        if (inline) return bar;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DockSurface(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final p in pills) ...[p, if (p != pills.last) const SizedBox(width: PhotonSpace.sm)],
                  ],
                ),
              ),
            ),
            const SizedBox(height: PhotonSpace.sm),
            bar,
          ],
        );
      },
    );
  }
}

/// Matte Carbon dock surface with a hairline highlight and deep ambient shadow.
class _DockSurface extends StatelessWidget {
  const _DockSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md, vertical: PhotonSpace.sm),
      decoration: BoxDecoration(
        color: c.dock,
        borderRadius: BorderRadius.circular(PhotonRadius.window + 4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 42,
            spreadRadius: -12,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram();

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(PhotonRadius.window),
        boxShadow: [BoxShadow(color: c.violet.withValues(alpha: 0.3), blurRadius: 10)],
      ),
      child: Text.rich(
        TextSpan(
          text: 'P',
          style: t.text.headlineMd.copyWith(color: c.onDock, fontWeight: FontWeight.w700, letterSpacing: -1),
          children: [
            TextSpan(
              text: '.',
              style: TextStyle(color: c.violetInk, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        semanticsLabel: 'Photon',
      ),
    );
  }
}

class _PromptField extends StatelessWidget {
  const _PromptField({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.showShortcut,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final bool showShortcut;

  static String get _shortcutLabel => defaultTargetPlatform == TargetPlatform.macOS ? '⌘K' : 'CTRL K';

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(PhotonRadius.window),
      borderSide: BorderSide.none,
    );
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onSubmitted: (_) => onSubmit(),
        textInputAction: TextInputAction.send,
        maxLines: 1,
        cursorColor: c.violetInk,
        cursorHeight: 14,
        style: t.text.telemetryMd.copyWith(color: c.onDock),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.1),
          hoverColor: Colors.white.withValues(alpha: 0.15),
          contentPadding: const EdgeInsets.symmetric(vertical: PhotonSpace.sm + 1),
          hintText: 'Describe optical scene, lighting, or drop .USD...',
          hintStyle: t.text.telemetrySm.copyWith(color: c.onDock.withValues(alpha: 0.55)),
          prefixIcon: Icon(Icons.auto_fix_high, size: 14, color: c.violetInk),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          suffixIcon: showShortcut
              ? Padding(
                  padding: const EdgeInsets.only(right: PhotonSpace.sm),
                  child: Center(
                    widthFactor: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(PhotonRadius.control),
                      ),
                      child: Text(
                        _shortcutLabel,
                        style: t.text.mono(size: 9, weight: FontWeight.w700, height: 1.1, color: c.onDock),
                      ),
                    ),
                  ),
                )
              : null,
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: c.onDock.withValues(alpha: 0.5)),
          ),
        ),
      ),
    );
  }
}

class _QuickPill extends StatelessWidget {
  const _QuickPill({required this.emoji, required this.label, required this.onTap});

  final String emoji;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Semantics(
      button: true,
      label: label,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: hovered ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(PhotonRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 11, height: 1.2)),
                const SizedBox(width: PhotonSpace.sm - 2),
                Text(
                  label,
                  style: t.text.labelCaps.copyWith(color: t.colors.onDock, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Engine link indicator (the "memory" chip): cyan ping when live.
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.link});

  final RenderLink link;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final live = link == RenderLink.live;
    return Tooltip(
      message: switch (link) {
        RenderLink.live => 'Render engine connected · ws://127.0.0.1:8765',
        RenderLink.connecting => 'Connecting to render engine…',
        RenderLink.offline => 'Render engine offline · retrying',
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(PhotonRadius.window),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.memory, size: 15, color: t.colors.onDock),
            Positioned(
              top: 7,
              right: 7,
              child: FlashingPip(
                color: live ? const Color(0xFF22D3EE) : t.colors.ghost,
                size: 5,
                flash: live,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Primary trigger: dispatches the prompt JSON.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.onPressed, required this.accent});

  final VoidCallback onPressed;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Dispatch prompt (Enter)',
      child: Semantics(
        button: true,
        label: 'Dispatch prompt',
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: hovered ? Color.alphaBlend(Colors.white.withValues(alpha: 0.12), accent) : accent,
                borderRadius: BorderRadius.circular(PhotonRadius.window),
                boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 12, spreadRadius: -2)],
              ),
              child: const Icon(Icons.arrow_upward, size: 16, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
