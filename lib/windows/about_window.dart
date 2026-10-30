import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/desktop_node.dart';
import '../state/workspace_controller.dart';
import '../theme/photon_theme.dart';
import '../widgets/overlay_shell.dart';
import '../widgets/sim_view.dart';
import 'mac_window.dart';

/// Left-aligned editorial window about Photon.
class AboutWindow extends StatelessWidget {
  const AboutWindow({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    return OverlayShell(
      open: ws.overlay == StudioOverlay.about,
      onDismiss: ws.closeOverlay,
      builder: (context, a) => LayoutBuilder(builder: (context, c) {
        final width = (c.maxWidth * 0.36).clamp(460.0, 680.0);
        return Align(
          alignment: Alignment.centerLeft,
          child: SlideTransition(
            position: Tween(begin: const Offset(-1.08, 0), end: Offset.zero).animate(a),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 0, 12),
              child: SizedBox(
                width: width,
                height: c.maxHeight - 24,
                child: MacWindow(
                  title: 'ABOUT PHOTON',
                  rim: false,
                  onClose: ws.closeOverlay,
                  footer: Row(
                    children: [
                      _link('Privacy Policy'),
                      const Spacer(),
                      _link('Release Notes'),
                    ],
                  ),
                  child: const _AboutBody(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _link(String text) => Row(
        children: [
          Text(text, style: PT.label(size: 16, color: PC.muted, weight: FontWeight.w400)),
          const SizedBox(width: 6),
          const Icon(Icons.open_in_new_rounded, size: 16, color: PC.muted),
        ],
      );
}

class _AboutBody extends StatelessWidget {
  const _AboutBody();

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.read(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
      children: [
        const _HeroCard(),
        const SizedBox(height: 26),
        Text('[ PHOTON ]', style: PT.label(size: 20, weight: FontWeight.w700)),
        const SizedBox(height: 6),
        FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text('TEXT-TO-VFX ENGINE', style: PT.display(size: 54)),
        ),
        const SizedBox(height: 22),
        Text(
          'A real-time studio for turning language into light, matter and motion.',
          style: PT.label(size: 30, weight: FontWeight.w400, spacing: -0.4, height: 1.12),
        ),
        const SizedBox(height: 22),
        const _Marquee(),
        const SizedBox(height: 22),
        Text(
          'Photon is a native Windows rendering engine. Write a scene prompt and it is '
          'compiled into a node graph of solvers: SPH fluids, boids, volumetric fog, '
          'cloth membranes and neural radiance fields.',
          style: PT.body(size: 17),
        ),
        const SizedBox(height: 16),
        Text(
          'Every effect is procedural. The 15,000-point Photon Core, the shader previews '
          'and the pass compositor are all generated on the GPU, frame by frame, with no '
          'baked assets.',
          style: PT.body(size: 17),
        ),
        const SizedBox(height: 40),
        Text('[ ABOUT THE CORE ]', style: PT.label(size: 20, weight: FontWeight.w700)),
        const SizedBox(height: 22),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: const SizedBox(height: 360, child: SimView(kind: SimKind.core, interactive: true)),
        ),
        const SizedBox(height: 34),
        Text('A NON-LINEAR\nRENDER STUDIO', style: PT.display(size: 48)),
        const SizedBox(height: 22),
        Text(
          'Photon treats a render as a conversation. Prompts, seeds and solver fields stay '
          'live, so you can steer a shot while the cluster is still rendering it.',
          style: PT.body(size: 17),
        ),
        const SizedBox(height: 16),
        Text(
          'Local GPU nodes handle previews at 60 FPS; the Cloud GPU Cluster renders '
          'final multi-pass EXRs straight into your Render Library.',
          style: PT.body(size: 17),
        ),
        const SizedBox(height: 22),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: ws.openInspector,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Open the Engine Inspector',
                    style: PT.label(size: 17, color: PC.blue, weight: FontWeight.w400)),
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

/// Dark hero card; click or scroll over it to switch editorial slides.
class _HeroCard extends StatefulWidget {
  const _HeroCard();

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  int _slide = 0;

  void _toggle() => setState(() => _slide = 1 - _slide);

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: PC.white, borderRadius: BorderRadius.circular(100)),
        child: Text(text, style: PT.mono(size: 12, color: PC.ink, weight: FontWeight.w700)),
      );

  Widget _content(BuildContext context) {
    if (_slide == 0) {
      return Column(
        key: const ValueKey(0),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _pill('[ Research ]'),
          Text('[ PHOTON ]', style: PT.mono(size: 14, color: const Color(0xFF9A9A9A))),
          Text('REAL-TIME NEURAL\nVFX STUDIO',
              style: PT.display(size: 38, color: PC.white, weight: FontWeight.w800)),
        ],
      );
    }
    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _pill('[ Architecture ]'),
        Text('A NON-CONFORMIST\nRENDER ENGINE',
            style: PT.display(size: 38, color: PC.white, weight: FontWeight.w800)),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: WorkspaceScope.read(context).openInspector,
            child: Text('Explore Node Core ↗',
                style: PT.label(size: 16, color: const Color(0xFF7FA6FF), weight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) _toggle();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Container(
            height: 230,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: PC.ink,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(a),
                        child: child,
                      ),
                    ),
                    child: _content(context),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Row(
                    children: [
                      for (var i = 0; i < 2; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.only(left: 6),
                          width: i == _slide ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _slide ? PC.white : const Color(0xFF555555),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
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

/// Endlessly scrolling row of capability pills.
class _Marquee extends StatefulWidget {
  const _Marquee();

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee> with SingleTickerProviderStateMixin {
  static const _items = [
    ('CUDA 12', PC.blue, true),
    ('VULKAN COMPUTE', PC.ink, true),
    ('OPTIX DENOISE', PC.pink, false),
    ('NeRF', PC.purple, true),
    ('SPH FLUIDS', PC.ink, false),
    ('15K STIPPLE CORE', PC.blue, false),
    ('EXR MULTI-PASS', PC.ink, true),
    ('WINDOWS NATIVE', PC.magenta, false),
  ];

  final GlobalKey _rowKey = GlobalKey();
  final ValueNotifier<double> _offset = ValueNotifier(0);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final box = _rowKey.currentContext?.findRenderObject() as RenderBox?;
      final w = box?.size.width ?? 0;
      if (w > 0) _offset.value = (elapsed.inMicroseconds / 1e6 * 38) % w;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _offset.dispose();
    super.dispose();
  }

  Widget _row({Key? key}) => Row(
        key: key,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (text, color, filled) in _items)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: filled ? color : Colors.transparent,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: color, width: 1.4),
              ),
              child: Text(text,
                  style: PT.mono(
                      size: 12, color: filled ? PC.white : color, weight: FontWeight.w700)),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          maxWidth: double.infinity,
          child: ValueListenableBuilder<double>(
            valueListenable: _offset,
            builder: (context, x, child) =>
                Transform.translate(offset: Offset(-x, 0), child: child),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [_row(key: _rowKey), _row(), _row()],
            ),
          ),
        ),
      ),
    );
  }
}
