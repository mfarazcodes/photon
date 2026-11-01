import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// The launch portal: the Photon "Edition Winter '26" film as a full-screen
/// landing experience, opened on launch and on demand from the header.
///
/// The film (`assets/videos/photon_hero.mp4`) is shown through four keyframes
/// pulled from it (0.5s, 2.0s, 4.2s, 6.5s) that cross-fade along the playhead
/// with a slow push-in. That keeps scrubbing instant and works on machines and
/// test hosts with no video codec. A chapter index on the left lights up with
/// the playhead; a click on a chapter jumps to it, and its preset button loads
/// the matching studio setup.
class LaunchHeroPortal extends StatefulWidget {
  const LaunchHeroPortal({super.key});

  /// The title card, as the film cuts it.
  static const String title = "PHOTON EDITION // WINTER '26";

  /// Below this width the timecode drops out of the header.
  static const double compactWidth = 900;

  @override
  State<LaunchHeroPortal> createState() => _LaunchHeroPortalState();
}

class _LaunchHeroPortalState extends State<LaunchHeroPortal> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  StudioController? _studio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _studio = StudioScope.of(context);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Runs while the film plays. Tests (and `animateShader: false`) hold the
  /// playhead still, so they scrub it explicitly.
  void _syncTicker() {
    final studio = _studio!;
    final shouldRun = studio.heroPlaying && studio.animateShader;
    if (shouldRun && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final studio = _studio!;
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final next = studio.heroTime.value + dt;
    if (next >= kHeroDurationSeconds) {
      studio.seekHero(kHeroDurationSeconds);
      studio.setHeroPlaying(false);
    } else {
      studio.seekHero(next);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final studio = StudioScope.read(context);
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      studio.dismissLaunchPortal();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      studio.toggleHeroPlaying();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      studio.seekHero(studio.heroTime.value - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      studio.seekHero(studio.heroTime.value + 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOut,
        builder: (context, v, child) => Opacity(opacity: v, child: child),
        child: LayoutBuilder(
          builder: (context, box) {
            final compact = box.maxWidth < LaunchHeroPortal.compactWidth;
            return ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _HeroStage(time: studio.heroTime),
                  // Legibility scrim behind the chapter index.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: compact ? 0 : 340,
                    child: const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0xE6000000), Color(0x00000000)]),
                        ),
                      ),
                    ),
                  ),
                  if (!compact)
                    Positioned(
                      left: PhotonSpace.xl,
                      top: _HeaderBar.height + PhotonSpace.lg,
                      bottom: _TransportBar.height + PhotonSpace.lg,
                      width: 268,
                      child: _ChapterRail(studio: studio),
                    ),
                  Positioned(left: 0, right: 0, top: 0, height: _HeaderBar.height, child: _HeaderBar(studio: studio, compact: compact)),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: _TransportBar.height,
                    child: _TransportBar(studio: studio, compact: compact),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The film: two keyframes cross-faded by the playhead, with a slow push-in.
class _HeroStage extends StatelessWidget {
  const _HeroStage({required this.time});

  final ValueListenable<double> time;

  static Widget _frame(HeroKeyframe k) => Image.asset(
    k.asset,
    fit: BoxFit.cover,
    gaplessPlayback: true,
    cacheWidth: 1600,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: time,
      builder: (context, t, _) {
        // Which two keyframes the playhead sits between, and how far across.
        var from = kHeroKeyframes.first;
        var to = kHeroKeyframes.first;
        var mix = 0.0;
        if (t >= kHeroKeyframes.last.seconds) {
          from = to = kHeroKeyframes.last;
        } else if (t > kHeroKeyframes.first.seconds) {
          for (var i = 0; i < kHeroKeyframes.length - 1; i++) {
            final a = kHeroKeyframes[i];
            final b = kHeroKeyframes[i + 1];
            if (t >= a.seconds && t < b.seconds) {
              from = a;
              to = b;
              mix = Curves.easeInOut.transform((t - a.seconds) / (b.seconds - a.seconds));
              break;
            }
          }
        }
        final push = 1.0 + 0.035 * (t / kHeroDurationSeconds).clamp(0.0, 1.0);
        return Transform.scale(
          key: const Key('hero-stage'),
          scale: push,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _frame(from),
              if (to != from && mix > 0.001) Opacity(opacity: mix, child: _frame(to)),
            ],
          ),
        );
      },
    );
  }
}

/// A frosted bar over the film.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, required this.top});

  final Widget child;

  /// True for the header (hairline underneath), false for the transport.
  final bool top;

  @override
  Widget build(BuildContext context) {
    final edge = BorderSide(color: Colors.white.withValues(alpha: 0.12));
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            border: top ? Border(bottom: edge) : Border(top: edge),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.studio, required this.compact});

  final StudioController studio;
  final bool compact;

  static const double height = 46;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final white = Colors.white;
    return _Glass(
      top: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.lg),
        child: Row(
          children: [
            const PhotonLogoMark(size: 20, isDark: true, semanticLabel: 'Photon'),
            const SizedBox(width: PhotonSpace.sm + 2),
            Flexible(
              child: Text(
                "PHOTON VFX STUDIO® — EDITION WINTER '26",
                key: const Key('hero-edition-label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.labelCaps.copyWith(fontSize: 9.5, color: white, fontWeight: FontWeight.w700),
              ),
            ),
            const Spacer(),
            if (!compact) ...[
              ValueListenableBuilder<double>(
                valueListenable: studio.heroTime,
                builder: (context, time, _) => Text(
                  'TC ${heroTimecode(time)} · $kHeroFps FPS',
                  key: const Key('hero-timecode'),
                  maxLines: 1,
                  style: t.text.mono(size: 10, weight: FontWeight.w500, height: 1.2, color: white.withValues(alpha: 0.78)),
                ),
              ),
              const SizedBox(width: PhotonSpace.lg),
            ],
            _EnterButton(onTap: studio.dismissLaunchPortal),
          ],
        ),
      ),
    );
  }
}

class _EnterButton extends StatelessWidget {
  const _EnterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Semantics(
      button: true,
      label: 'Enter Spatial Studio',
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          key: const Key('enter-studio-btn'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovered ? const Color(0xFFFFFFFF) : const Color(0xFFF3F3F5),
              borderRadius: BorderRadius.circular(PhotonRadius.pill),
              boxShadow: [BoxShadow(color: const Color(0xFF8A2BE2).withValues(alpha: hovered ? 0.7 : 0.4), blurRadius: hovered ? 22 : 14)],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'ENTER SPATIAL STUDIO →',
                maxLines: 1,
                style: t.text.labelCaps.copyWith(fontSize: 9.5, color: const Color(0xFF0E0E10), fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Left rail: the edition title and the five chapters.
class _ChapterRail extends StatelessWidget {
  const _ChapterRail({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('CHAPTER INDEX', style: t.text.labelCaps.copyWith(fontSize: 8, color: Colors.white.withValues(alpha: 0.55))),
        const SizedBox(height: PhotonSpace.sm),
        Text.rich(
          TextSpan(
            style: t.text.ui(size: 22, weight: FontWeight.w500, height: 1.15, tracking: -0.02, color: Colors.white),
            children: const [
              TextSpan(text: 'PHOTON EDITION '),
              TextSpan(text: '//', style: TextStyle(color: Color(0xFFFF2D78))),
              TextSpan(text: " WINTER '26"),
            ],
          ),
          key: const Key('hero-title'),
        ),
        const SizedBox(height: PhotonSpace.lg),
        ValueListenableBuilder<double>(
          valueListenable: studio.heroTime,
          builder: (context, time, _) {
            final active = heroChapterAt(time)?.index;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final chapter in kHeroChapters)
                  _ChapterRow(
                    chapter: chapter,
                    active: active == chapter.index,
                    progress: active == chapter.index ? _chapterProgress(chapter, time) : (active != null && active > chapter.index ? 1 : 0),
                    onSelect: () {
                      studio.seekHero(chapter.startSeconds + 0.05);
                      studio.setHeroPlaying(true);
                    },
                    onPreset: () => studio.applyHeroChapterPreset(chapter.index),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  static double _chapterProgress(HeroChapter chapter, double time) {
    final end = chapter.index + 1 < kHeroChapters.length ? kHeroChapters[chapter.index + 1].startSeconds : kHeroDurationSeconds;
    return ((time - chapter.startSeconds) / (end - chapter.startSeconds)).clamp(0.0, 1.0);
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.chapter,
    required this.active,
    required this.progress,
    required this.onSelect,
    required this.onPreset,
  });

  final HeroChapter chapter;
  final bool active;
  final double progress;
  final VoidCallback onSelect;
  final VoidCallback onPreset;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Semantics(
      button: true,
      selected: active,
      label: 'Chapter ${chapter.number}: ${chapter.title}',
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) {
          final fg = Colors.white.withValues(alpha: active ? 1 : (hovered ? 0.85 : 0.55));
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                key: Key('hero-chapter-${chapter.index}'),
                behavior: HitTestBehavior.opaque,
                onTap: onSelect,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 12,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 160),
                            opacity: active ? 1 : 0,
                            child: const Pip(color: Color(0xFFFF2D78), size: 6, glow: true),
                          ),
                        ),
                      ),
                      Text('${chapter.number} /', style: t.text.mono(size: 10, weight: FontWeight.w600, height: 1.6, color: fg)),
                      const SizedBox(width: PhotonSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              chapter.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.text.ui(size: 15, height: 1.3, tracking: -0.01, color: fg).copyWith(fontStyle: FontStyle.italic),
                            ),
                            Text(
                              chapter.detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.text.labelCaps.copyWith(fontSize: 8, color: fg.withValues(alpha: fg.a * 0.75)),
                            ),
                          ],
                        ),
                      ),
                      Tooltip(
                        message: 'Load preset · ${chapter.presetLabel}',
                        child: GestureDetector(
                          key: Key('hero-chapter-preset-${chapter.index}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: onPreset,
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: Icon(Icons.tune, size: 13, color: Colors.white.withValues(alpha: active || hovered ? 0.95 : 0.4)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Chapter progress hairline.
              Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.14),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress,
                  child: const ColoredBox(color: Color(0xFFFF2D78), child: SizedBox(height: 1)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({required this.studio, required this.compact});

  final StudioController studio;
  final bool compact;

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return _Glass(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.lg),
        child: Row(
          children: [
            _PlayToggle(studio: studio),
            const SizedBox(width: PhotonSpace.md),
            ValueListenableBuilder<double>(
              valueListenable: studio.heroTime,
              builder: (context, time, _) => Text(
                '${_clock(time)} / ${_clock(kHeroDurationSeconds)}',
                key: const Key('hero-clock'),
                maxLines: 1,
                style: t.text.mono(size: 10, weight: FontWeight.w500, height: 1.2, color: Colors.white.withValues(alpha: 0.8)),
              ),
            ),
            const SizedBox(width: PhotonSpace.md),
            Expanded(child: _Scrubber(studio: studio)),
            const SizedBox(width: PhotonSpace.md),
            _ReferenceButton(onTap: studio.loadHeroAsViewportReference, compact: compact),
          ],
        ),
      ),
    );
  }

  static String _clock(double seconds) {
    final s = seconds.clamp(0.0, kHeroDurationSeconds);
    final whole = s.floor();
    final tenth = ((s - whole) * 10).floor();
    return '${(whole ~/ 60).toString().padLeft(2, '0')}:${(whole % 60).toString().padLeft(2, '0')}.$tenth';
  }
}

class _PlayToggle extends StatelessWidget {
  const _PlayToggle({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final playing = studio.heroPlaying;
    return Semantics(
      button: true,
      label: playing ? 'Pause' : 'Play',
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          key: const Key('hero-video-play-toggle'),
          behavior: HitTestBehavior.opaque,
          onTap: studio.toggleHeroPlaying,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md - 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: hovered ? 0.24 : 0.14),
              borderRadius: BorderRadius.circular(PhotonRadius.pill),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(playing ? Icons.pause : Icons.play_arrow, size: 14, color: Colors.white),
                const SizedBox(width: 5),
                Text(
                  playing ? 'PAUSE' : 'PLAY',
                  style: t.text.labelCaps.copyWith(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReferenceButton extends StatelessWidget {
  const _ReferenceButton({required this.onTap, required this.compact});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    return Semantics(
      button: true,
      label: 'Load as viewport reference',
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          key: const Key('hero-load-reference-btn'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md - 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF8A2BE2).withValues(alpha: hovered ? 0.55 : 0.36),
              borderRadius: BorderRadius.circular(PhotonRadius.pill),
              border: Border.all(color: const Color(0xFFB57BFF).withValues(alpha: hovered ? 1 : 0.7)),
            ),
            child: Text(
              compact ? 'LOAD REFERENCE' : 'LOAD AS VIEWPORT REFERENCE',
              maxLines: 1,
              style: t.text.labelCaps.copyWith(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

/// The timeline: chapter ticks, a filled track and a thumb. A click or drag
/// anywhere on it moves the playhead.
class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.studio});

  final StudioController studio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        void seekTo(double dx) => studio.seekHero(dx / box.maxWidth * kHeroDurationSeconds);
        return Semantics(
          slider: true,
          label: 'Film timeline',
          value: heroTimecode(studio.heroTime.value),
          child: GestureDetector(
            key: const Key('hero-scrubber'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seekTo(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: SizedBox(
                height: 30,
                child: ValueListenableBuilder<double>(
                  valueListenable: studio.heroTime,
                  builder: (context, time, _) => CustomPaint(painter: _ScrubberPainter(time)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScrubberPainter extends CustomPainter {
  _ScrubberPainter(this.time);

  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final x = (time / kHeroDurationSeconds).clamp(0.0, 1.0) * size.width;
    final track = RRect.fromLTRBR(0, y - 2, size.width, y + 2, const Radius.circular(2));
    canvas.drawRRect(track, Paint()..color = Colors.white.withValues(alpha: 0.18));
    final fill = RRect.fromLTRBR(0, y - 2, x, y + 2, const Radius.circular(2));
    canvas.drawRRect(
      fill,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFF8A2BE2), Color(0xFFFF2D78)]).createShader(Rect.fromLTWH(0, 0, size.width, 1)),
    );
    // Chapter ticks.
    final tick = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.5);
    for (final c in kHeroChapters) {
      final cx = c.startSeconds / kHeroDurationSeconds * size.width;
      canvas.drawLine(Offset(cx, y - 7), Offset(cx, y + 7), tick);
    }
    canvas.drawCircle(Offset(x, y), 7, Paint()..color = const Color(0xFFFF2D78).withValues(alpha: 0.35));
    canvas.drawCircle(Offset(x, y), 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_ScrubberPainter old) => old.time != time;
}
