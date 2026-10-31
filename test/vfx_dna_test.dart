import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:photon/models/vfx_dna.dart';

VfxDna compile(String prompt, {String negative = '', String solver = '', int seed = 1}) =>
    VfxDna.compile(prompt: prompt, negative: negative, solver: solver, seed: seed);

String hex(Color c) => c.toARGB32().toRadixString(16).padLeft(8, '0');

/// Whether [c] is within [tol] per RGB channel of [target] (0xRRGGBB).
bool near(Color c, int target, {int tol = 60}) {
  final r = (target >> 16) & 0xFF, g = (target >> 8) & 0xFF, b = target & 0xFF;
  return (c.r * 255 - r).abs() <= tol && (c.g * 255 - g).abs() <= tol && (c.b * 255 - b).abs() <= tol;
}

void main() {
  group('VfxDna.compile', () {
    test('"Neon cyberpunk fluid simulation" is a neon fluid with a grid and CRT fx', () {
      final dna = compile('Neon cyberpunk fluid simulation');
      expect(dna.paletteName, 'neon');
      expect(near(dna.colors[0], 0x00F5FF), isTrue, reason: 'electric cyan');
      expect(near(dna.colors[1], 0xFF007F), isTrue, reason: 'hot magenta');
      expect(near(dna.colors[2], 0x7B2CBF), isTrue, reason: 'violet');
      expect(near(dna.background, 0x05030D, tol: 12), isTrue, reason: 'dark void');
      expect(dna.primary, VfxSolver.metaballFluid);
      expect(dna.secondary, contains(VfxSolver.cyberGridWave));
      expect(dna.fx, containsAll([VfxFx.scanlines, VfxFx.chromaticSplit, VfxFx.additiveBloom]));
    });

    test('"Golden solar shockwave vortex" is a shockwave + vortex in gold and fire', () {
      final dna = compile('Golden solar shockwave vortex');
      expect(dna.paletteName, 'gold+fire');
      expect(dna.primary, VfxSolver.shockwaveRings);
      expect(dna.secondary, contains(VfxSolver.vortexAttractor));
      expect(dna.fx, isNot(contains(VfxFx.scanlines)));
    });

    test('different prompts get different palettes and different solver stacks', () {
      final a = compile('Neon cyberpunk fluid simulation');
      final b = compile('Golden solar shockwave vortex');
      expect(a.colors.map(hex), isNot(b.colors.map(hex)));
      expect(a.background, isNot(b.background));
      expect(a.primary, isNot(b.primary));
      expect([a.primary, ...a.secondary], isNot([b.primary, ...b.secondary]));
      expect(a.label, isNot(b.label));
    });

    test('theme keywords map to their palettes', () {
      expect(compile('lava flowing over rocks').paletteName, 'fire');
      expect(compile('toxic bio sludge').paletteName, 'matrix');
      expect(compile('arctic cryo crystals').paletteName, 'ice');
      expect(compile('cosmic astral dust').paletteName, 'gold');
      expect(compile('crimson blood mist').paletteName, 'blood');
      expect(compile('noir monochrome smoke').paletteName, 'noir');
      expect(compile('pink liquid slime splash').paletteName, 'candy');
      expect(near(compile('fire').colors[1], 0xFF5400, tol: 60), isTrue);
    });

    test('the same prompt always compiles to the same DNA', () {
      expect(
        compile('a quiet harbour at dawn').toJson(),
        compile('a quiet harbour at dawn').toJson(),
      );
    });

    test('prompts that name no theme get unique procedural palettes', () {
      final seen = <String>{};
      for (var i = 0; i < 150; i++) {
        final dna = compile('abstract scene number $i');
        expect(dna.paletteName, 'procedural');
        seen.add(dna.colors.map(hex).join());
      }
      expect(seen, hasLength(150), reason: 'no two prompts share a palette');
      // Procedural backdrops stay dark so additive light reads.
      expect(compile('a quiet harbour').background.computeLuminance(), lessThan(0.05));
    });

    test('same theme still varies per prompt', () {
      final seen = {
        for (var i = 0; i < 30; i++) compile('neon sign number $i').colors.map(hex).join(),
      };
      expect(seen.length, greaterThan(20));
    });

    test('a solver is always chosen, with 1-2 supporting layers', () {
      for (var i = 0; i < 200; i++) {
        final dna = compile('prompt $i with no keywords at all', seed: i);
        expect(dna.secondary.length, inInclusiveRange(1, 2));
        expect(dna.secondary, isNot(contains(dna.primary)));
        expect(dna.secondary.toSet(), hasLength(dna.secondary.length));
        expect(dna.layers.last, dna.primary, reason: 'primary paints on top');
      }
    });

    test('the negative prompt switches keywords off', () {
      expect(compile('neon grid').has(VfxFx.scanlines), isFalse); // not a CRT word
      expect(compile('retro crt neon').has(VfxFx.scanlines), isTrue);
      expect(compile('retro crt neon', negative: 'scanlines, crt').has(VfxFx.scanlines), isFalse);
      expect(compile('fire swirl').has(VfxFx.additiveBloom), isTrue);
      expect(compile('fire swirl', negative: 'bloom').has(VfxFx.additiveBloom), isFalse);
      expect(compile('neon fluid', negative: 'neon').paletteName, 'procedural');
      // A generic negative prompt must not disable anything.
      expect(compile('fire swirl', negative: 'blurry, low quality').has(VfxFx.additiveBloom), isTrue);
    });

    test('form fields feed speed, detail, buoyancy and glow', () {
      VfxDna c({String prompt = 'cloud', String fps = '', String res = '', bool vol = false}) =>
          VfxDna.compile(prompt: prompt, frameRate: fps, resolution: res, volumetric: vol);
      expect(c(fps: '120fps').speed, lessThan(c().speed));
      expect(c(prompt: 'slow motion cloud').speed, lessThan(1));
      expect(c(prompt: 'fast warp cloud').speed, greaterThan(1));
      expect(c(res: '3840x2160').detail, greaterThan(c(res: '1280x720').detail));
      expect(c(prompt: 'rising smoke').buoyancy, greaterThan(0));
      expect(c(prompt: 'falling rain').buoyancy, lessThan(0));
      expect(c(vol: true).glow, greaterThan(c().glow));
      expect(c(vol: true).volumetric, isTrue);
    });

    test('emitter geometry comes from the prompt, and each mode reshapes it', () {
      expect(compile('a glowing ring portal').emitter, VfxEmitter.ring);
      expect(compile('laser beam').emitter, VfxEmitter.line);
      final dna = compile('a glowing ring portal');
      expect({for (var m = 0; m < 3; m++) dna.emitterFor(m)}, hasLength(3));
      expect(dna.emitterFor(0), dna.emitter);
    });
  });

  group('VfxDna.withOverrides (engine "dna" object)', () {
    final base = compile('Neon cyberpunk fluid simulation');

    test('replaces palette, solvers and fx', () {
      final dna = base.withOverrides({
        'palette': {
          'background': '#010203',
          'colors': ['#FF0000', '00FF00', '#0000FF'],
        },
        'primary': 'vortexAttractor',
        'secondary': ['Neural Plexus', 'metaballFluid', 'bogus'],
        'fx': ['scanlines', 'wireframeOverlay'],
        'emitter': 'ring',
        'glow': 1.4,
        'volumetric': true,
      });
      expect(hex(dna.background), 'ff010203');
      expect(dna.colors.map(hex), ['ffff0000', 'ff00ff00', 'ff0000ff']);
      expect(dna.paletteName, 'custom');
      expect(dna.primary, VfxSolver.vortexAttractor);
      expect(dna.secondary, [VfxSolver.neuralPlexus, VfxSolver.metaballFluid]);
      expect(dna.fx, {VfxFx.scanlines, VfxFx.wireframeOverlay});
      expect(dna.emitter, VfxEmitter.ring);
      expect(dna.glow, 1.4);
      expect(dna.volumetric, isTrue);
    });

    test('a theme name selects a built-in palette', () {
      final dna = base.withOverrides({'palette': 'fire'});
      expect(dna.paletteName, 'fire');
      expect(near(dna.colors[1], 0xFF5400, tol: 2), isTrue);
    });

    test('fx accepts a {name: bool} map and leaves the rest alone', () {
      final dna = base.withOverrides({
        'fx': {'scanlines': false, 'motionTrails': true},
      });
      expect(dna.has(VfxFx.scanlines), isFalse);
      expect(dna.has(VfxFx.motionTrails), isTrue);
      expect(dna.has(VfxFx.chromaticSplit), isTrue);
    });

    test('malformed values are ignored and numbers are clamped', () {
      final dna = base.withOverrides({
        'palette': {'colors': ['nope', 1, null], 'background': 7.5},
        'primary': 42,
        'glow': 99,
        'speed': 'fast',
        'fx': 'scanlines',
        'emitter': 'cube',
      });
      expect(dna.colors.map(hex), base.colors.map(hex));
      expect(dna.primary, base.primary);
      expect(dna.glow, 1.6);
      expect(dna.speed, base.speed);
      expect(dna.fx, base.fx);
      expect(dna.emitter, base.emitter);
    });

    test('the primary never doubles as a supporting layer', () {
      final dna = base.withOverrides({'primary': 'cyberGridWave'});
      expect(dna.primary, VfxSolver.cyberGridWave);
      expect(dna.secondary, isNot(contains(VfxSolver.cyberGridWave)));
    });

    test('toJson round-trips through withOverrides', () {
      final other = compile('Golden solar shockwave vortex');
      final back = other.withOverrides(base.toJson());
      expect(back.primary, base.primary);
      expect(back.secondary, base.secondary);
      expect(back.fx, base.fx);
      expect(back.colors.map(hex), base.colors.map(hex));
      expect(hex(back.background), hex(base.background));
      expect(back.emitter, base.emitter);
    });

    test('compile applies overrides on top of the local result', () {
      final dna = VfxDna.compile(
        prompt: 'Neon cyberpunk fluid simulation',
        overrides: {'primary': 'neuralPlexus'},
      );
      expect(dna.primary, VfxSolver.neuralPlexus);
      expect(dna.paletteName, 'neon');
    });
  });
}
