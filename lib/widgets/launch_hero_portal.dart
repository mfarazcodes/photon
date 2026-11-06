import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// The opening landing page: Photon's launch film as an ambient, full-bleed
/// backdrop with editorial type over it, and one way in.
///
/// There is no player here: no controls, no timeline, no timecode. The film's
/// keyframes (pulled from `assets/videos/photon_hero.mp4`) cross-fade in a slow
/// loop behind a vignette, decoded ahead of time so the loop never stalls on a
/// decode. A single ticker drives it, and it stops the moment the page is left,
/// so nothing of the landing page runs once the studio is open.
class LaunchHeroPortal extends StatefulWidget {
  const LaunchHeroPortal({super.key});

  static const String edition = "EDITION WINTER '26 // SPATIAL RAY-TRACING ENGINE";
  static const String headline = 'Physically Based Light Transport.';
  static const String cta = 'Take me to Photon';

  /// Seconds each keyframe is on screen, including its cross-fade.
  static const double segmentSeconds = 4;

  /// Share of a segment spent cross-fading into the next frame.
  static const double fadeShare = 0.45;

  /// How far a frame pushes in over its whole life, as a scale gain.
  static const double pushGain = 0.04;

  /// Where a frame's push-in stands when it is handed from incoming to primary.
  /// It climbs 0 to this while fading in, then this to 1 as the primary, so the
  /// scale is the same on both sides of the hand-over.
  static const double handoff = 0.35;

  /// The two film layers at loop time [t] (seconds): which frames, the
  /// incoming one's opacity, and each layer's scale.
  ///
  /// The scale is continuous across every segment boundary and across the
  /// loop's wrap: a frame's push-in progress runs `0 -> handoff` while it fades
  /// in and `handoff -> 1` while it is primary, and at the instant it changes
  /// role the two expressions agree.
  static ({int primary, int incoming, double mix, double primaryScale, double incomingScale}) layersAt(double t) {
    final count = kHeroKeyframes.length;
    final phase = t / segmentSeconds;
    final primary = phase.floor() % count;
    final within = phase - phase.floor();
    final fadeStart = 1 - fadeShare;
    final fade = within <= fadeStart ? 0.0 : (within - fadeStart) / fadeShare;
    // Smootherstep: zero velocity at both ends of the fade.
    final mix = fade * fade * fade * (fade * (fade * 6 - 15) + 10);
    return (
      primary: primary,
      incoming: (primary + 1) % count,
      mix: mix,
      primaryScale: 1 + pushGain * (handoff + (1 - handoff) * within),
      incomingScale: 1 + pushGain * handoff * fade,
    );
  }

  /// Decode width for the film frames (the window is rarely wider).
  static const int frameWidth = 1600;

  /// The frames as images, shared by [precacheImage] and the widget tree so
  /// both hit the same cache entry.
  static final List<ImageProvider> frameProviders = [
    for (final k in kHeroKeyframes) ResizeImage(AssetImage(k.asset), width: frameWidth),
  ];

  @override
  State<LaunchHeroPortal> createState() => _LaunchHeroPortalState();
}

class _LaunchHeroPortalState extends State<LaunchHeroPortal> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  /// Seconds into the loop.
  final ValueNotifier<double> _time = ValueNotifier(0);
  bool _precached = false;
  bool _left = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final studio = StudioScope.of(context);
    if (!_precached) {
      _precached = true;
      for (final provider in LaunchHeroPortal.frameProviders) {
        precacheImage(provider, context, onError: (_, _) {});
      }
    }
    // Tests (animateShader off) hold the first frame still.
    final shouldRun = studio.animateShader && studio.showLaunchPortal && !_left;
    if (shouldRun && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) => _time.value = elapsed.inMicroseconds / 1e6;

  /// Stops the animation first, then hands over to the studio.
  void _enter() {
    _left = true;
    if (_ticker.isActive) _ticker.stop();
    StudioScope.read(context).enterPhotonStudio();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(
        color: const Color(0xFF0E0E10),
        child: LayoutBuilder(
          builder: (context, box) {
            final headlineSize = (box.maxWidth * 0.052).clamp(30.0, 68.0);
            return Stack(
              fit: StackFit.expand,
              children: [
                _FilmBackdrop(time: _time),
                // Vignette: the near-black of the studio at the edges, so the
                // type stays razor sharp over the busiest frames.
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: Key('hero-vignette'),
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          radius: 0.95,
                          colors: [Color(0x000E0E10), Color(0x990E0E10), Color(0xFF0E0E10)],
                          stops: [0.35, 0.78, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                // A floor under the headline.
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 320,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x000E0E10), Color(0xCC0E0E10)],
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned(left: 0, right: 0, top: 0, child: _Masthead()),
                Positioned(
                  left: PhotonSpace.xl,
                  right: PhotonSpace.xl,
                  bottom: math.max(48.0, box.maxHeight * 0.12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          LaunchHeroPortal.headline,
                          key: const Key('hero-headline'),
                          textAlign: TextAlign.center,
                          style: context.photon.text
                              .ui(size: headlineSize, weight: FontWeight.w500, height: 1.08, tracking: -0.035, color: Colors.white)
                              .copyWith(fontStyle: FontStyle.italic),
                        ),
                      ),
                      const SizedBox(height: PhotonSpace.xl),
                      KeyedSubtree(
                        key: const Key('enter-studio-btn'),
                        child: _TakeMeButton(onTap: _enter, time: _time),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The film: two keyframes cross-faded by the loop clock. Each sits in its own
/// repaint boundary, so a fade only recomposites two cached layers.
class _FilmBackdrop extends StatelessWidget {
  const _FilmBackdrop({required this.time});

  final ValueListenable<double> time;

  /// One film layer: its own repaint boundary (the decoded frame stays a warm
  /// texture), its own scale, its own opacity. Both layers are always in the
  /// tree, so nothing is inserted or removed mid-loop.
  static Widget _layer({required int frame, required double scale, required double opacity}) {
    return KeyedSubtree(
      key: ValueKey('film-frame-$frame'),
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: RepaintBoundary(
            child: Image(
              image: LaunchHeroPortal.frameProviders[frame],
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF0E0E10)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      key: const Key('hero-stage'),
      valueListenable: time,
      builder: (context, t, _) {
        final l = LaunchHeroPortal.layersAt(t);
        return Stack(
          fit: StackFit.expand,
          children: [
            _layer(frame: l.primary, scale: l.primaryScale, opacity: 1),
            _layer(frame: l.incoming, scale: l.incomingScale, opacity: l.mix),
          ],
        );
      },
    );
  }
}

/// `PHOTON®` on the left, the edition line in the centre.
class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.xl, vertical: PhotonSpace.lg),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PhotonLogoMark(size: 22, isDark: true, semanticLabel: 'Photon'),
                const SizedBox(width: PhotonSpace.sm + 2),
                Text(
                  'PHOTON®',
                  key: const Key('hero-wordmark'),
                  style: t.text.mono(size: 12, weight: FontWeight.w700, height: 1.2, tracking: 0.12, color: Colors.white),
                ),
              ],
            ),
          ),
          // Kept clear of the wordmark on narrow windows.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 120),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                LaunchHeroPortal.edition,
                key: const Key('hero-edition-label'),
                maxLines: 1,
                style: t.text.labelCaps.copyWith(fontSize: 10, color: Colors.white.withValues(alpha: 0.82), letterSpacing: 1.1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one control: a glass pill ringed by a slow specular beam, that lifts on
/// hover and nudges its arrow.
class _TakeMeButton extends StatelessWidget {
  const _TakeMeButton({required this.onTap, required this.time});

  final VoidCallback onTap;
  final ValueListenable<double> time;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Semantics(
      button: true,
      label: LaunchHeroPortal.cta,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          key: const Key('take-me-to-photon-btn'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            offset: Offset(0, hovered ? -0.08 : 0),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 160),
              scale: hovered ? 1.04 : 1,
              child: CustomPaint(
                foregroundPainter: _BeamBorderPainter(time: time, hovered: hovered),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: hovered ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(PhotonRadius.pill),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF8A2BE2).withValues(alpha: hovered ? 0.55 : 0.3), blurRadius: hovered ? 36 : 24, spreadRadius: -6),
                    ],
                  ),
                  // Scales down rather than overflow on a very narrow window.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          LaunchHeroPortal.cta,
                          style: t.text.ui(size: 16, weight: FontWeight.w600, height: 1.2, tracking: -0.01, color: Colors.white),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: hovered ? 14 : 10,
                        ),
                        const Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                      ],
                    ),
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

/// A 1.4px pill outline, lit by a sweep gradient that turns with the loop.
class _BeamBorderPainter extends CustomPainter {
  _BeamBorderPainter({required this.time, required this.hovered}) : super(repaint: time);

  final ValueListenable<double> time;
  final bool hovered;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const clear = Color(0x00FFFFFF);
    final shader = SweepGradient(
      colors: const [clear, Color(0xFFB57BFF), Colors.white, Color(0xFFFF2D78), clear, clear],
      stops: const [0.0, 0.12, 0.2, 0.28, 0.42, 1.0],
      transform: GradientRotation(time.value * 2 * math.pi / 3.2),
    ).createShader(rect);
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.7), Radius.circular(size.height / 2));
    // The resting hairline, then the beam over it.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: hovered ? 0.5 : 0.28),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_BeamBorderPainter old) => old.hovered != hovered;
}
