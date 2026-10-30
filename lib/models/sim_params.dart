import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Live shader parameters. The engine inspector edits the workspace-wide
/// instance; generated nodes carry their own seeded copy. Every [VfxSim] and
/// [SimView] reads these each frame, so a slider change shows up immediately.
class SimParams extends ChangeNotifier {
  SimParams({
    this.turbulence = 0.68,
    this.coherence = 0.5,
    this.density = 0.8,
    this.dispersion = 0.0,
    this.timeScale = 1.0,
  });

  double turbulence;
  double coherence;
  double density;

  /// Chromatic dispersion: RGB channel split, in 0..1.
  double dispersion;

  /// Playback speed multiplier, 0.25..2.
  double timeScale;

  SimParams copy() => SimParams(
        turbulence: turbulence,
        coherence: coherence,
        density: density,
        dispersion: dispersion,
        timeScale: timeScale,
      );

  void update({
    double? turbulence,
    double? coherence,
    double? density,
    double? dispersion,
    double? timeScale,
  }) {
    this.turbulence = turbulence ?? this.turbulence;
    this.coherence = coherence ?? this.coherence;
    this.density = density ?? this.density;
    this.dispersion = dispersion ?? this.dispersion;
    this.timeScale = timeScale ?? this.timeScale;
    notifyListeners();
  }
}

/// Playback state of one viewport: transport, 240-frame timeline, seed, FPS.
class Playback extends ChangeNotifier {
  Playback({this.seed = 884213});

  static const int frames = 240;
  static const double fps = 24;
  static const double loopSeconds = frames / fps;

  bool playing = true;

  /// Seconds of simulated time. It only grows; [frame] wraps it.
  double clock = 0;
  int seed;

  /// Sub-mode of the sim (the LIQUID_MORPH shape: sphere, splash, type).
  int mode = 0;

  /// Measured render rate, updated by the owning [SimView].
  int measuredFps = 60;

  int get frame => ((clock * fps) % frames).floor();

  void advance(double dt) {
    if (!playing) return;
    clock += dt;
    notifyListeners();
  }

  void togglePlay() {
    playing = !playing;
    notifyListeners();
  }

  void scrubTo(int frame) {
    final base = (clock / loopSeconds).floor() * loopSeconds;
    clock = base + frame.clamp(0, frames - 1) / fps;
    notifyListeners();
  }

  void setMode(int value) {
    if (value == mode) return;
    mode = value;
    notifyListeners();
  }

  void reroll() {
    seed = 100000 + math.Random().nextInt(899999);
    notifyListeners();
  }

  void reportFps(int value) {
    if (value == measuredFps) return;
    measuredFps = value;
    notifyListeners();
  }
}
