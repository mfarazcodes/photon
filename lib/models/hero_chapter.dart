import 'package:flutter/foundation.dart';

/// Length of `assets/videos/photon_hero.mp4`: 7s plus 4 frames at 60 fps.
const double kHeroDurationSeconds = 7 + 4 / 60;

/// Frame rate shown in the timecode readout.
const int kHeroFps = 60;

/// One chapter of the launch film. The film's own title card lists the same
/// five, and the portal's chapter index follows the playhead through them.
@immutable
class HeroChapter {
  const HeroChapter({
    required this.index,
    required this.title,
    required this.detail,
    required this.startSeconds,
    required this.presetLabel,
  });

  /// Zero-based.
  final int index;
  final String title;

  /// The right-hand caption on the film's card (`n(λ) = A + B/λ²`).
  final String detail;

  /// Where the chapter's line lights up in the film.
  final double startSeconds;

  /// What loading the chapter's studio preset does, for the button tooltip.
  final String presetLabel;

  /// `01`, `02`, ...
  String get number => (index + 1).toString().padLeft(2, '0');
}

const List<HeroChapter> kHeroChapters = [
  HeroChapter(
    index: 0,
    title: 'Cauchy Dispersion',
    detail: 'n(λ) = A + B/λ²',
    startSeconds: 3.1,
    presetLabel: 'VOLUMETRIC_PRISM · 470 nm',
  ),
  HeroChapter(
    index: 1,
    title: 'BiDir Path Tracing',
    detail: 'MIS · 12 BOUNCES',
    startSeconds: 3.9,
    presetLabel: 'BIDIRECTIONAL PT · 12 bounces',
  ),
  HeroChapter(
    index: 2,
    title: 'Microfacet GGX',
    detail: 'α = 0.08 · SMITH G2',
    startSeconds: 4.7,
    presetLabel: 'GOLD_ATELIER_BSDF',
  ),
  HeroChapter(
    index: 3,
    title: 'OIDN Denoiser',
    detail: 'ALBEDO + NORMAL AOV',
    startSeconds: 5.5,
    presetLabel: 'A/B WIPE · RAW vs DENOISED',
  ),
  HeroChapter(
    index: 4,
    title: 'Vulkan RT Core',
    detail: 'VK_KHR_RAY_QUERY',
    startSeconds: 6.3,
    presetLabel: 'BVH / RAY OVERLAY',
  ),
];

/// The chapter lit at [seconds], or null during the opening prism scene.
HeroChapter? heroChapterAt(double seconds) {
  HeroChapter? current;
  for (final c in kHeroChapters) {
    if (seconds >= c.startSeconds) current = c;
  }
  return current;
}

/// Keyframes pulled from the film: instant scrubbing, and the stand-in where
/// the OS has no video codec (headless tests).
@immutable
class HeroKeyframe {
  const HeroKeyframe(this.seconds, this.asset);

  final double seconds;
  final String asset;
}

const List<HeroKeyframe> kHeroKeyframes = [
  HeroKeyframe(0.5, 'assets/images/hero_frame_01.jpg'),
  HeroKeyframe(2.0, 'assets/images/hero_frame_02.jpg'),
  HeroKeyframe(4.2, 'assets/images/hero_frame_03.jpg'),
  HeroKeyframe(6.5, 'assets/images/hero_frame_04.jpg'),
];

/// The keyframe nearest to [seconds].
HeroKeyframe nearestHeroKeyframe(double seconds) {
  var best = kHeroKeyframes.first;
  for (final k in kHeroKeyframes) {
    if ((k.seconds - seconds).abs() < (best.seconds - seconds).abs()) best = k;
  }
  return best;
}

/// `00:00:03:20`: hours, minutes, seconds, frames at [kHeroFps].
String heroTimecode(double seconds) {
  // The epsilon keeps whole-frame times (7s + 4 frames) from rounding down.
  final total = (seconds.clamp(0.0, kHeroDurationSeconds) * kHeroFps + 1e-6).floor();
  final frames = total % kHeroFps;
  final secs = (total ~/ kHeroFps) % 60;
  final mins = (total ~/ (kHeroFps * 60)) % 60;
  final hours = total ~/ (kHeroFps * 3600);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(hours)}:${two(mins)}:${two(secs)}:${two(frames)}';
}
