import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:photon/models/sim_params.dart';
import 'package:photon/models/vfx_dna.dart';
import 'package:photon/painters/generative_vfx_painter.dart';

const Size kSize = Size(320, 200);

/// A single-layer effect, so differences between renders come from that layer.
VfxDna solo(VfxSolver s, {String palette = 'neon', Set<VfxFx>? fx}) => VfxDna.compile(
      prompt: 'test',
      seed: 7,
      overrides: {
        'primary': s.name,
        'secondary': <String>[],
        'palette': palette,
        'fx': [for (final f in fx ?? {VfxFx.additiveBloom}) f.name],
      },
    );

/// Steps a painter for [frames] frames at 30 fps, then rasterises one frame.
Future<Uint8List> render(
  VfxDna dna, {
  int mode = 0,
  SimParams? params,
  int frames = 40,
  Offset? mouse,
  bool pressed = false,
  bool thumb = false,
}) async {
  final pb = Playback(seed: 7)..mode = mode;
  final p = GenerativeVfxPainter(dna: dna, params: params ?? SimParams(), playback: pb, thumb: thumb)
    ..mouse = mouse
    ..pressed = pressed;
  for (var i = 0; i < frames; i++) {
    p.step(1 / 30, kSize);
  }
  final rec = PictureRecorder();
  p.paint(Canvas(rec), kSize);
  final img = await rec.endRecording().toImage(kSize.width.round(), kSize.height.round());
  final bytes = (await img.toByteData())!.buffer.asUint8List();
  img.dispose();
  return bytes;
}

/// Pixels whose brightest channel is above [level]. The backdrop glow alone
/// stays well under the default; only the layers' own light gets past it.
int bright(Uint8List rgba, {int level = 200}) {
  var n = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i] > level || rgba[i + 1] > level || rgba[i + 2] > level) n++;
  }
  return n;
}

void main() {
  testWidgets('every solver paints visible light in every mode', (tester) async {
    await tester.runAsync(() async {
      for (final s in VfxSolver.values) {
        for (var mode = 0; mode < 3; mode++) {
          final px = await render(solo(s), mode: mode, frames: 20);
          expect(bright(px), greaterThan(20), reason: '${s.name} mode $mode is blank');
        }
      }
    });
  });

  testWidgets('each solver looks different from the others', (tester) async {
    await tester.runAsync(() async {
      final shots = {for (final s in VfxSolver.values) s: await render(solo(s))};
      final all = shots.entries.toList();
      for (var i = 0; i < all.length; i++) {
        for (var j = i + 1; j < all.length; j++) {
          expect(
            listEquals(all[i].value, all[j].value),
            isFalse,
            reason: '${all[i].key.name} and ${all[j].key.name} rendered identically',
          );
        }
      }
    });
  });

  testWidgets('the three viewport modes reshape every solver', (tester) async {
    await tester.runAsync(() async {
      for (final s in VfxSolver.values) {
        final m0 = await render(solo(s), mode: 0);
        final m1 = await render(solo(s), mode: 1);
        final m2 = await render(solo(s), mode: 2);
        expect(listEquals(m0, m1), isFalse, reason: '${s.name}: mode 1 == mode 0');
        expect(listEquals(m1, m2), isFalse, reason: '${s.name}: mode 2 == mode 1');
        expect(listEquals(m0, m2), isFalse, reason: '${s.name}: mode 2 == mode 0');
      }
    });
  });

  testWidgets('the live sliders morph each solver', (tester) async {
    // Which of the sliders each solver is wired to.
    const wired = <VfxSolver, List<String>>{
      VfxSolver.metaballFluid: ['turbulence', 'coherence', 'density', 'dispersion'],
      VfxSolver.curlParticleFlow: ['turbulence', 'coherence', 'density', 'dispersion'],
      VfxSolver.shockwaveRings: ['turbulence', 'density', 'dispersion'],
      VfxSolver.neuralPlexus: ['turbulence', 'coherence', 'density', 'dispersion'],
      VfxSolver.vortexAttractor: ['turbulence', 'coherence', 'density', 'dispersion'],
      VfxSolver.cyberGridWave: ['turbulence', 'coherence', 'density', 'dispersion'],
    };
    SimParams with_(String name, double v) {
      final p = SimParams();
      switch (name) {
        case 'turbulence':
          p.update(turbulence: v);
        case 'coherence':
          p.update(coherence: v);
        case 'density':
          p.update(density: v);
        case 'dispersion':
          p.update(dispersion: v);
      }
      return p;
    }

    await tester.runAsync(() async {
      for (final entry in wired.entries) {
        for (final name in entry.value) {
          final lo = await render(solo(entry.key), params: with_(name, name == 'dispersion' ? 0 : 0.1));
          final hi = await render(solo(entry.key), params: with_(name, 0.95));
          expect(listEquals(lo, hi), isFalse, reason: '${entry.key.name} ignores $name');
        }
      }
    });
  });

  testWidgets('the pointer interacts with every solver', (tester) async {
    await tester.runAsync(() async {
      for (final s in VfxSolver.values) {
        final away = await render(solo(s));
        // Off-centre: several layers key off the offset from the middle.
        final hover = await render(solo(s), mouse: const Offset(0.3, 0.6));
        final press = await render(solo(s), mouse: const Offset(0.3, 0.6), pressed: true);
        expect(listEquals(away, hover), isFalse, reason: '${s.name} ignores hover');
        expect(listEquals(hover, press), isFalse, reason: '${s.name} ignores press');
      }
    });
  });

  testWidgets('the same seed renders identically; a new seed lays it out again', (tester) async {
    await tester.runAsync(() async {
      for (final s in VfxSolver.values) {
        final a = await render(solo(s));
        final b = await render(solo(s));
        expect(listEquals(a, b), isTrue, reason: '${s.name} is not deterministic');
      }
    });
    final pb = Playback(seed: 1);
    final p = GenerativeVfxPainter(dna: solo(VfxSolver.curlParticleFlow), params: SimParams(), playback: pb);
    p.step(0.016, kSize);
    pb.seed = 2; // reroll
    p.step(0.016, kSize);
    p.paint(Canvas(PictureRecorder()), kSize);
  });

  testWidgets('different palettes render different light', (tester) async {
    await tester.runAsync(() async {
      for (final s in VfxSolver.values) {
        final neon = await render(solo(s));
        final fire = await render(solo(s, palette: 'fire'));
        expect(listEquals(neon, fire), isFalse, reason: s.name);
      }
    });
  });

  testWidgets('post fx change the picture', (tester) async {
    await tester.runAsync(() async {
      final dna = solo(VfxSolver.neuralPlexus);
      final plain = await render(dna);
      for (final f in [VfxFx.scanlines, VfxFx.chromaticSplit, VfxFx.wireframeOverlay]) {
        final withFx = await render(solo(VfxSolver.neuralPlexus, fx: {VfxFx.additiveBloom, f}));
        expect(listEquals(plain, withFx), isFalse, reason: f.name);
      }
      final noBloom = await render(solo(VfxSolver.neuralPlexus, fx: {}));
      expect(listEquals(plain, noBloom), isFalse, reason: 'bloom');
    });
  });

  testWidgets('a layered DNA, a paused first frame and thumbnails all paint', (tester) async {
    await tester.runAsync(() async {
      final stack = VfxDna.compile(
        prompt: 'Neon cyberpunk fluid simulation volumetric',
        volumetric: true,
        overrides: {'secondary': ['cyberGridWave', 'shockwaveRings'], 'fx': ['scanlines', 'wireframeOverlay', 'chromaticSplit', 'motionTrails', 'additiveBloom']},
      );
      expect(bright(await render(stack, mouse: const Offset(0.4, 0.6), frames: 20)), greaterThan(100));
      expect(bright(await render(stack, thumb: true)), greaterThan(0));

      // Opening paused: no step ever advances time, but it must still draw.
      for (final s in VfxSolver.values) {
        final p = GenerativeVfxPainter(dna: solo(s), params: SimParams(), playback: Playback(seed: 7));
        p.step(0, kSize);
        p.paint(Canvas(PictureRecorder()), kSize);
      }
    });
  });

  testWidgets('CPU cost per frame stays small', (tester) async {
    // Not asserted tightly: `flutter test` runs unoptimised. This guards
    // against an order-of-magnitude regression, and prints the numbers.
    final timings = <String>[];
    for (final s in VfxSolver.values) {
      final p = GenerativeVfxPainter(dna: solo(s), params: SimParams(), playback: Playback(seed: 7));
      for (var i = 0; i < 10; i++) {
        p.step(1 / 60, kSize);
        p.paint(Canvas(PictureRecorder()), const Size(1240, 760));
      }
      final sw = Stopwatch()..start();
      const frames = 30;
      for (var i = 0; i < frames; i++) {
        p.step(1 / 60, const Size(1240, 760));
        p.paint(Canvas(PictureRecorder()), const Size(1240, 760));
      }
      final ms = sw.elapsedMicroseconds / 1000 / frames;
      timings.add('${s.name}: ${ms.toStringAsFixed(2)} ms');
      expect(ms, lessThan(60), reason: '${s.name} is far too slow on the CPU');
    }
    // ignore: avoid_print
    print('step+record at 1240x760 (debug JIT): ${timings.join(', ')}');
  });
}
