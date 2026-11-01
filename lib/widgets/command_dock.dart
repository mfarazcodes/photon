import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/render_socket.dart';
import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'intent_file_trigger.dart';
import 'photon_primitives.dart';

/// Bottom command dock: "P." monogram, scene prompt field, quick-action pills
/// and the trigger that dispatches the prompt JSON over the WebSocket.
///
/// Items swell toward the pointer (Gaussian proximity magnification), the pills
/// share one continuous hit strip, and a light beam circles the dock while the
/// prompt has focus.
///
/// On wide windows everything sits on one bar; below [_inlineWidth] the pills
/// move to their own strip above the bar (companion layout).
class CommandDock extends StatefulWidget {
  const CommandDock({super.key});

  @override
  State<CommandDock> createState() => _CommandDockState();
}

class _CommandDockState extends State<CommandDock> {
  // Wide enough for the 1.2x pills to sit beside a usable prompt field.
  static const double _inlineWidth = 1240;

  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'scene-prompt');

  /// Pointer x in global coordinates, or null when it is off the dock. Items
  /// listen to this directly, so hovering never rebuilds the dock itself.
  final ValueNotifier<double?> _hoverX = ValueNotifier(null);

  static const _presets = <String, String>{
    'bsdf': 'Brushed gold BSDF, roughness 0.35, soft studio key light',
    'archive': 'Load archived scene: ',
    'camera': '85mm lens, f/1.4, focus 1.8m, shallow depth of field',
  };

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _focus.removeListener(_onFocusChanged);
    _hoverX.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  /// Ctrl+K (⌘K on macOS) jumps to the prompt from anywhere in the app, and
  /// Escape lets go of it so single-key shortcuts are not trapped in the field.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (!_focus.hasFocus) return false;
      _focus.unfocus();
      return true;
    }
    if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
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

    Widget swell(Widget child, String id) =>
        _ProximityScale(key: ValueKey('proximity-$id'), hoverX: _hoverX, child: child);

    final pills = [
      swell(_QuickPill(emoji: '⚡', label: 'RENDER PROMPT', onTap: _send), 'render'),
      swell(_QuickPill(emoji: '🎛️', label: 'BSDF SHADERS', onTap: () => _applyPreset('bsdf')), 'bsdf'),
      swell(_QuickPill(emoji: '📁', label: 'SCENE ARCHIVE', onTap: () => _applyPreset('archive')), 'archive'),
      swell(_QuickPill(emoji: '🎥', label: 'CAMERA OPTICS', onTap: () => _applyPreset('camera')), 'camera'),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final inline = box.maxWidth >= _inlineWidth;
        final bar = _DockSurface(
          hoverX: _hoverX,
          beam: _focus.hasFocus,
          child: Row(
            children: [
              swell(const _Monogram(), 'monogram'),
              const SizedBox(width: PhotonSpace.sm),
              swell(
                IntentFileTrigger(
                  key: const Key('intent-file-trigger-dock'),
                  onTap: () => studio.setIngestSheetOpen(true),
                  scale: 1.1,
                ),
                'filetrigger',
              ),
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
                const SizedBox(width: PhotonSpace.sm),
                // No spacers: each pill carries its own padding as hit area.
                ...pills,
                const SizedBox(width: PhotonSpace.sm),
                swell(_LinkButton(link: studio.link), 'link'),
                // The two 40px buttons swell toward each other; 16px keeps them
                // apart at the worst case.
                const SizedBox(width: PhotonSpace.lg),
              ] else
                const SizedBox(width: PhotonSpace.sm),
              swell(_SendButton(onPressed: _send, accent: c.violet), 'send'),
            ],
          ),
        );
        if (inline) return bar;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DockSurface(
              hoverX: _hoverX,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: pills),
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

/// Swells and lifts [child] by its horizontal distance to the pointer:
/// weight `exp(-(d / 72)^2)`, scale 1 to 1.16, lift up to 3.5px.
class _ProximityScale extends StatelessWidget {
  const _ProximityScale({super.key, required this.hoverX, required this.child});

  final ValueListenable<double?> hoverX;
  final Widget child;

  static const double sigma = 86;
  static const double extraScale = 0.16;
  static const double lift = 3.5;

  double _weight(BuildContext context, double pointerX) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return 0;
    final centerX = box.localToGlobal(box.size.center(Offset.zero)).dx;
    final d = (pointerX - centerX) / sigma;
    return math.exp(-d * d);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: hoverX,
      child: child,
      builder: (context, x, child) {
        final target = x == null ? 0.0 : _weight(context, x);
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: target),
          duration: const Duration(milliseconds: 70),
          curve: Curves.easeOut,
          child: child,
          builder: (context, w, child) => Transform.translate(
            offset: Offset(0, -lift * w),
            child: Transform.scale(scale: 1 + extraScale * w, child: child),
          ),
        );
      },
    );
  }
}

/// Matte Carbon dock surface with a hairline highlight and deep ambient
/// shadow. While [beam] is set, a violet-to-rose light travels its perimeter.
class _DockSurface extends StatefulWidget {
  const _DockSurface({required this.child, required this.hoverX, this.beam = false});

  final Widget child;
  final ValueNotifier<double?> hoverX;
  final bool beam;

  @override
  State<_DockSurface> createState() => _DockSurfaceState();
}

class _DockSurfaceState extends State<_DockSurface> with SingleTickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.beam) _orbit.repeat();
  }

  @override
  void didUpdateWidget(_DockSurface old) {
    super.didUpdateWidget(old);
    if (widget.beam && !_orbit.isAnimating) {
      _orbit.repeat();
    } else if (!widget.beam && _orbit.isAnimating) {
      _orbit.stop();
    }
  }

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    const radius = 15.0;
    return MouseRegion(
      onHover: (e) => widget.hoverX.value = e.position.dx,
      onExit: (_) => widget.hoverX.value = null,
      child: Stack(
        // Hand the parent's tight width straight to the surface.
        fit: StackFit.passthrough,
        children: [
          Container(
            key: const ValueKey('dock-surface'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: c.dock,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: c.isDark ? Colors.white.withValues(alpha: 0.1) : c.border),
              boxShadow: c.isDark
                  // Dark Studio: a deep ambient drop.
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 42,
                        spreadRadius: -12,
                        offset: const Offset(0, 20),
                      ),
                    ]
                  // Daylight Lab: the Level-2 window shadow plus a soft lift.
                  : [
                      ...context.photon.level2,
                      BoxShadow(
                        color: c.shadow.withValues(alpha: 0.08),
                        blurRadius: 28,
                        spreadRadius: -8,
                        offset: const Offset(0, 12),
                      ),
                    ],
            ),
            child: widget.child,
          ),
          if (widget.beam)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('dock-beam'),
                  painter: _BeamBorderPainter(
                    progress: _orbit,
                    radius: radius,
                    violet: c.violetInk,
                    rose: c.rose,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 1px perimeter stroke lit by a rotating sweep gradient.
class _BeamBorderPainter extends CustomPainter {
  _BeamBorderPainter({
    required this.progress,
    required this.radius,
    required this.violet,
    required this.rose,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final double radius;
  final Color violet;
  final Color rose;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final clear = violet.withValues(alpha: 0);
    final shader = SweepGradient(
      colors: [clear, violet, rose, clear, clear],
      stops: const [0.0, 0.1, 0.2, 0.32, 1.0],
      transform: GradientRotation(progress.value * 2 * math.pi),
    ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius)),
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_BeamBorderPainter old) =>
      old.violet != violet || old.rose != rose || old.radius != radius;
}

class _Monogram extends StatelessWidget {
  const _Monogram();

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.isDark ? Colors.white.withValues(alpha: 0.1) : c.hoverFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.isDark ? Colors.transparent : c.border),
        boxShadow: [BoxShadow(color: c.violet.withValues(alpha: 0.3), blurRadius: 12)],
      ),
      child: const PhotonLogoMark(size: 22, semanticLabel: 'Photon'),
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
    // Daylight fields sit on white, so they need a hairline to read as fields.
    final restingBorder = c.isDark ? border : border.copyWith(borderSide: BorderSide(color: c.border));
    return SizedBox(
      height: 44,
      child: TextField(
        key: const Key('scene-prompt'),
        controller: controller,
        focusNode: focusNode,
        onSubmitted: (_) => onSubmit(),
        textInputAction: TextInputAction.send,
        maxLines: 1,
        cursorColor: c.violetInk,
        cursorHeight: 18,
        style: t.text.telemetryMd.copyWith(fontSize: 13.5, color: c.onDock),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: c.isDark ? Colors.white.withValues(alpha: 0.08) : c.canvas,
          hoverColor: c.isDark ? Colors.white.withValues(alpha: 0.13) : c.hoverFill,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
          hintText: 'Describe optical scene, lighting, or drop .USD...',
          hintStyle: t.text.telemetrySm.copyWith(fontSize: 12, color: c.onDock.withValues(alpha: 0.55)),
          prefixIcon: Icon(Icons.auto_fix_high, size: 18, color: c.violetInk),
          prefixIconConstraints: const BoxConstraints(minWidth: 42),
          suffixIcon: showShortcut
              ? Padding(
                  padding: const EdgeInsets.only(right: PhotonSpace.sm + 2),
                  child: Center(
                    widthFactor: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.isDark ? Colors.white.withValues(alpha: 0.16) : c.surface,
                        borderRadius: BorderRadius.circular(PhotonRadius.control),
                        border: Border.all(color: c.border),
                      ),
                      child: Text(
                        _shortcutLabel,
                        style: t.text.mono(size: 10.5, weight: FontWeight.w700, height: 1.1, color: c.onDock),
                      ),
                    ),
                  ),
                )
              : null,
          border: restingBorder,
          enabledBorder: restingBorder,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: c.onDock.withValues(alpha: 0.5)),
          ),
        ),
      ),
    );
  }
}

/// Quick-action pill. The visible capsule is inset inside a taller, wider hit
/// area, so neighbouring pills touch and there is no dead space between them.
class _QuickPill extends StatelessWidget {
  const _QuickPill({required this.emoji, required this.label, required this.onTap});

  final String emoji;
  final String label;
  final VoidCallback onTap;

  /// Half the visual gap between pills; each pill owns this much on both sides.
  ///
  /// Sized for the proximity swell: when the pointer sits between two pills
  /// both grow toward each other (about 8px of closing at worst), so the 16px
  /// gap this makes leaves them clear instead of fusing at the corners.
  static const double hitPadding = PhotonSpace.sm;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Semantics(
      button: true,
      label: label,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          key: ValueKey('pill-hit-$label'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: hitPadding),
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.isDark
                    ? Colors.white.withValues(alpha: hovered ? 0.2 : 0.12)
                    : (hovered ? c.violet.withValues(alpha: 0.12) : c.hoverFill),
                borderRadius: BorderRadius.circular(PhotonRadius.pill),
                border: c.isDark
                    ? null
                    : Border.all(color: hovered ? c.violet.withValues(alpha: 0.4) : c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 13.5, height: 1.2)),
                  const SizedBox(width: PhotonSpace.sm - 1),
                  Text(
                    label,
                    style: t.text.labelCaps.copyWith(
                      fontSize: 10.5,
                      color: hovered && !c.isDark ? c.violetInk : c.onDock,
                      fontWeight: FontWeight.w600,
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

/// Engine link indicator (the "memory" chip): cyan ping when live.
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.link});

  final RenderLink link;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final live = link == RenderLink.live;
    return Tooltip(
      message: switch (link) {
        RenderLink.live => 'Render engine connected · ws://127.0.0.1:8765',
        RenderLink.connecting => 'Connecting to render engine…',
        RenderLink.offline => 'Render engine offline · retrying',
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c.isDark ? Colors.white.withValues(alpha: 0.12) : c.hoverFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.isDark ? Colors.transparent : c.border),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.memory, size: 19, color: c.onDock),
            Positioned(
              top: 8,
              right: 8,
              child: FlashingPip(
                color: live ? const Color(0xFF22D3EE) : c.ghost,
                size: 6,
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hovered ? Color.alphaBlend(Colors.white.withValues(alpha: 0.12), accent) : accent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 14, spreadRadius: -2)],
              ),
              child: const Icon(Icons.arrow_upward, size: 20, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
