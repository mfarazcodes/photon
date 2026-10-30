import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/photon_theme.dart';

/// Floating window chrome: translucent rim, #F8F8F8 body, traffic lights and
/// a centred uppercase title. The header drags the window.
class MacWindow extends StatefulWidget {
  const MacWindow({
    super.key,
    required this.title,
    required this.child,
    this.footer,
    this.onClose,
    this.onMinimize,
    this.onMaximize,
    this.onDrag,
    this.onDragEnd,
    this.onFocus,
    this.dark = false,
    this.rim = true,
  });

  final String title;
  final Widget child;
  final Widget? footer;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final ValueChanged<Offset>? onDrag;
  final VoidCallback? onDragEnd;
  final VoidCallback? onFocus;
  final bool dark;
  final bool rim;

  @override
  State<MacWindow> createState() => _MacWindowState();
}

class _MacWindowState extends State<MacWindow> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    reverseDuration: const Duration(milliseconds: 200),
  )..forward();
  late final Animation<double> _curve =
      CurvedAnimation(parent: _intro, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);

  Future<void> _close() async {
    await _intro.reverse();
    widget.onClose?.call();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: widget.dark ? PC.ink : PC.window,
        child: Column(
          children: [
            _Header(
              title: widget.title,
              dark: widget.dark,
              onClose: widget.onClose == null ? null : _close,
              onMinimize: widget.onMinimize,
              onMaximize: widget.onMaximize,
              onDrag: widget.onDrag,
              onDragEnd: widget.onDragEnd,
            ),
            Container(height: 1, color: widget.dark ? const Color(0xFF222222) : PC.hairline),
            Expanded(child: widget.child),
            if (widget.footer != null) ...[
              Container(height: 1, color: PC.hairline),
              SizedBox(
                height: 66,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: widget.footer,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final framed = widget.rim
        ? ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0x8CD9D9D9),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xB3FFFFFF)),
                ),
                child: body,
              ),
            ),
          )
        : body;

    return FadeTransition(
      opacity: _intro,
      child: ScaleTransition(
        scale: Tween(begin: 0.92, end: 1.0).animate(_curve),
        child: Listener(
          onPointerDown: (_) => widget.onFocus?.call(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.rim ? 30 : 20),
              boxShadow: PC.windowShadow,
            ),
            child: framed,
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.dark,
    this.onClose,
    this.onMinimize,
    this.onMaximize,
    this.onDrag,
    this.onDragEnd,
  });

  final String title;
  final bool dark;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final ValueChanged<Offset>? onDrag;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: onDrag == null ? null : (d) => onDrag!(d.delta),
      onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
      onDoubleTap: onMaximize,
      child: SizedBox(
        height: 58,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 22,
              child: TrafficLights(
                onClose: onClose,
                onMinimize: onMinimize,
                onMaximize: onMaximize,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 110),
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PT.label(size: 15, color: dark ? PC.white : PC.ink, spacing: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Red / yellow / green controls; glyphs appear when the group is hovered.
class TrafficLights extends StatefulWidget {
  const TrafficLights({super.key, this.onClose, this.onMinimize, this.onMaximize});

  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;

  @override
  State<TrafficLights> createState() => _TrafficLightsState();
}

class _TrafficLightsState extends State<TrafficLights> {
  bool _hover = false;

  Widget _light(Color color, IconData icon, VoidCallback? onTap) {
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 15,
          height: 15,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: onTap == null ? const Color(0xFFD5D5D5) : color,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x1A000000), width: 0.5),
          ),
          child: AnimatedOpacity(
            opacity: _hover && onTap != null ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: Icon(icon, size: 10, color: const Color(0x99000000)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _light(PC.red, Icons.close_rounded, widget.onClose),
          _light(PC.amber, Icons.remove_rounded, widget.onMinimize),
          _light(PC.green, Icons.open_in_full_rounded, widget.onMaximize),
        ],
      ),
    );
  }
}

/// Footer row used by most windows: caption on the left, blue link on the right.
class WindowFooter extends StatelessWidget {
  const WindowFooter({super.key, required this.caption, required this.action, this.onAction});

  final String caption;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PT.label(size: 16, weight: FontWeight.w400)),
        ),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onAction,
            child: Row(
              children: [
                Text(action, style: PT.label(size: 16, color: PC.blue, weight: FontWeight.w400)),
                const SizedBox(width: 6),
                const Icon(Icons.open_in_new_rounded, size: 17, color: PC.blue),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
