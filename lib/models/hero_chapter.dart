import 'package:flutter/foundation.dart';

/// Length of `assets/videos/photon_hero.mp4`: 7s plus 4 frames at 60 fps. The
/// landing page loops its motion over this span.
const double kHeroDurationSeconds = 7 + 4 / 60;

/// A keyframe pulled from the film. The landing page cross-fades these as its
/// full-bleed backdrop: instant to show, and independent of any OS video codec
/// (so it also renders on headless test hosts).
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
