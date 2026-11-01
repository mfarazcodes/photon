import 'package:flutter/material.dart';

import '../theme/photon_theme.dart';

/// Rebuilds with the pointer-hover state of its region.
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.basic,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.cursor,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(context, _hovered),
  );
}

/// Status pip that fades in and out (the 4px "computing" indicator).
class FlashingPip extends StatefulWidget {
  const FlashingPip({super.key, required this.color, this.size = 4, this.flash = true});

  final Color color;
  final double size;
  final bool flash;

  @override
  State<FlashingPip> createState() => _FlashingPipState();
}

class _FlashingPipState extends State<FlashingPip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.flash) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(FlashingPip old) {
    super.didUpdateWidget(old);
    if (widget.flash && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.flash && _c.isAnimating) {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_c),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Static round pip.
class Pip extends StatelessWidget {
  const Pip({super.key, required this.color, this.size = 6, this.glow = false});

  final Color color;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: glow ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)] : null,
    ),
  );
}

/// HUD capsule: full pill radius, hairline border, Level-2 shadow.
class PillCapsule extends StatelessWidget {
  const PillCapsule({
    super.key,
    required this.child,
    this.height = 28,
    this.padding = const EdgeInsets.symmetric(horizontal: PhotonSpace.md),
    this.background,
    this.borderColor,
    this.shadow = true,
  });

  final Widget child;
  final double height;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Color? borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Container(
      height: height,
      padding: padding,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? t.colors.substrate,
        borderRadius: BorderRadius.circular(PhotonRadius.pill),
        border: Border.all(color: borderColor ?? t.colors.border),
        boxShadow: shadow ? t.level2 : null,
      ),
      child: child,
    );
  }
}

/// Primary studio action: Matte Carbon fill, hover lift, 0.98 press scale.
class PhotonButton extends StatefulWidget {
  const PhotonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.trailing,
    this.height = 28,
    this.radius = PhotonRadius.pill,
    this.mono = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? trailing;
  final double height;
  final double radius;

  /// Label-caps styling (HUD buttons) rather than Geist 12px medium.
  final bool mono;

  @override
  State<PhotonButton> createState() => _PhotonButtonState();
}

class _PhotonButtonState extends State<PhotonButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final fill = _hover
        ? Color.alphaBlend(c.onCarbon.withValues(alpha: 0.14), c.carbon)
        : c.carbon;
    final style = widget.mono
        ? t.text.labelCaps.copyWith(color: c.onCarbon, fontWeight: FontWeight.w600)
        : t.text.buttonLabel.copyWith(color: c.onCarbon);
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _down ? 0.98 : 1,
            duration: const Duration(milliseconds: 90),
            child: Container(
              height: widget.height,
              padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(widget.radius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.label.toUpperCase(), style: style),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: PhotonSpace.xs),
                    widget.trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The three macOS window-control pips.
class MacWindowPips extends StatelessWidget {
  const MacWindowPips({super.key, this.size = 10});

  final double size;

  static const _close = Color(0xFFFF5F56);
  static const _minimize = Color(0xFFFFBD2E);
  static const _zoom = Color(0xFF27C93F);

  @override
  Widget build(BuildContext context) {
    Widget pip(Color c) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black.withValues(alpha: 0.12), width: 0.5),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pip(_close),
        const SizedBox(width: 6),
        pip(_minimize),
        const SizedBox(width: 6),
        pip(_zoom),
      ],
    );
  }
}

/// 32px floating-window titlebar with a 1px hairline divider underneath.
class MacTitlebar extends StatelessWidget {
  const MacTitlebar({super.key, required this.title, this.leading, this.trailing, this.titleSuffix});

  final String title;
  final Widget? leading;
  final Widget? trailing;
  final Widget? titleSuffix;

  static const double height = 32;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.colors.border)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: leading ?? const MacWindowPips(),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: t.text.telemetrySm.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              if (titleSuffix != null) ...[
                const SizedBox(width: PhotonSpace.sm),
                titleSuffix!,
              ],
            ],
          ),
          if (trailing != null) Align(alignment: Alignment.centerRight, child: trailing),
        ],
      ),
    );
  }
}
