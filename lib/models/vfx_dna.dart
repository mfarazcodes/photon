import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor;

/// The physics / emitter primitives a generated effect is composed from.
enum VfxSolver {
  metaballFluid('Metaball Fluid', [
    'fluid', 'liquid', 'goo\$', 'gooey', 'slime', 'blob', 'metaball', 'sph\$', 'splash',
    'water\$', 'ooze', 'melt', 'paint', 'mercury', 'drip', 'lava', 'jelly',
  ]),
  curlParticleFlow('Curl Particle Flow', [
    'particle', 'curl', 'flow', 'smoke', 'swarm', 'nano', 'dust', 'ember', 'spark',
    'stream', 'wind\$', 'vapor', 'fog', 'boid', 'nebula', 'aurora', 'turbulen',
  ]),
  shockwaveRings('Shockwave Rings', [
    'shock', 'explosion', 'explode', 'blast', 'ripple', 'pulse', 'impact', 'detonat',
    'nova', 'burst', 'ring', 'boom',
  ]),
  neuralPlexus('Neural Plexus', [
    'neural', 'network', 'brain', 'synapse', 'plexus', 'node', 'constellation',
    'circuit', 'web\$', 'data', 'nerve',
  ]),
  vortexAttractor('Vortex Attractor', [
    'vortex', 'tornado', 'whirl', 'spiral', 'black hole', 'singularity', 'attractor',
    'galaxy', 'swirl', 'accretion', 'funnel', 'cyclone', 'orbit', 'gravity',
  ]),
  cyberGridWave('Cyber Grid Wave', [
    'grid', 'terrain', 'wireframe', 'mesh', 'cloth', 'synthwave', 'retro', 'landscape',
    'topolog', 'lattice',
  ]);

  const VfxSolver(this.label, this.words);
  final String label;
  final List<String> words;
}

/// Post-processing passes.
enum VfxFx {
  /// Blurred additive glow on top of the crisp pass.
  additiveBloom([]),

  /// Rolling CRT scanlines.
  scanlines([
    'cyberpunk', 'crt', 'glitch', 'retro', 'vhs', 'synthwave', 'scanline', 'terminal',
    'hologram', 'matrix', 'tron',
  ]),

  /// RGB channel split.
  chromaticSplit([
    'glitch', 'chromatic', 'aberration', 'prism', 'rgb', 'iridescent', 'holographic',
    'hologram', 'cyberpunk', 'lens', 'dispersion', 'rainbow',
  ]),

  /// Long velocity streaks.
  motionTrails([
    'trail', 'streak', 'comet', 'warp', 'motion', 'speed', 'flow', 'fast',
    'long exposure', 'light painting',
  ]),

  /// HUD grid, corner brackets and a cursor reticle.
  wireframeOverlay([
    'wireframe', 'wire\$', 'hud', 'blueprint', 'schematic', 'mesh', 'tactical',
    'topolog',
  ]);

  const VfxFx(this.words);
  final List<String> words;
}

/// Where matter is born. Layers that spawn or arrange matter read this.
enum VfxEmitter {
  point(['impact', 'burst', 'explosion', 'nova', 'fountain', 'spray']),
  ring(['ring', 'halo', 'portal', 'circle', 'orbit', 'crown']),
  sphere(['sphere', 'orb\$', 'planet', 'ball', 'globe', 'bubble']),
  line(['beam', 'laser', 'rain\$', 'raining', 'strand', 'ribbon', 'jet\$']),
  plane(['sheet', 'wall', 'plane\$', 'floor', 'curtain', 'terrain', 'ocean', 'carpet']);

  const VfxEmitter(this.words);
  final List<String> words;
}

class _PaletteDef {
  const _PaletteDef(this.name, this.words, this.background, this.colors, {this.glow = 1.0});

  final String name;
  final List<String> words;
  final Color background;

  /// Hot core, body, cool accent.
  final List<Color> colors;
  final double glow;
}

const List<_PaletteDef> _palettes = [
  _PaletteDef(
    'neon',
    ['neon', 'cyberpunk', 'cyber', 'synthwave', 'vaporwave', 'tron', 'laser', 'hologram', 'outrun'],
    Color(0xFF05030D),
    [Color(0xFF00F5FF), Color(0xFFFF007F), Color(0xFF7B2CBF)],
    glow: 1.2,
  ),
  _PaletteDef(
    'fire',
    ['fire', 'lava', 'solar', 'magma', 'inferno', 'ember', 'flame', 'sun', 'volcan', 'molten', 'blaze', 'burn'],
    Color(0xFF0A0200),
    [Color(0xFFFFF3B0), Color(0xFFFF5400), Color(0xFF9E0059)],
    glow: 1.25,
  ),
  _PaletteDef(
    'matrix',
    ['matrix', 'toxic', 'bio', 'acid', 'radioactive', 'virus', 'hacker'],
    Color(0xFF020A04),
    [Color(0xFF00FF66), Color(0xFF00B4D8), Color(0xFFB8FF3C)],
    glow: 1.1,
  ),
  _PaletteDef(
    'ice',
    ['ice', 'cryo', 'arctic', 'frost', 'frozen', 'snow', 'glacier', 'crystal'],
    Color(0xFF030A14),
    [Color(0xFFCAF0F8), Color(0xFF0077B6), Color(0xFF5E60CE)],
  ),
  _PaletteDef(
    'gold',
    ['gold', 'astral', 'cosmic', 'celestial', 'stars', 'galaxy'],
    Color(0xFF06030E),
    [Color(0xFFFFD166), Color(0xFFF77F00), Color(0xFF5A189A)],
    glow: 1.1,
  ),
  _PaletteDef(
    'blood',
    ['blood', 'crimson', 'scarlet', 'gore', 'vampire', 'ruby'],
    Color(0xFF0C0103),
    [Color(0xFFFF4D4D), Color(0xFFC1121F), Color(0xFFFFB3A7)],
  ),
  _PaletteDef(
    'noir',
    ['monochrome', 'noir', 'grayscale', 'greyscale', 'black and white', 'silver'],
    Color(0xFF050506),
    [Color(0xFFFFFFFF), Color(0xFF9AA0A6), Color(0xFF4B5058)],
    glow: 0.75,
  ),
  _PaletteDef(
    'ocean',
    ['ocean', 'sea\$', 'aqua', 'underwater', 'abyss', 'tide', 'deep', 'water\$'],
    Color(0xFF02101A),
    [Color(0xFF7CF4FF), Color(0xFF1E88E5), Color(0xFF00E5A8)],
  ),
  _PaletteDef(
    'candy',
    ['pink', 'candy', 'bubblegum', 'rose', 'pastel'],
    Color(0xFF12020E),
    [Color(0xFFFF9EDB), Color(0xFFFF4FA3), Color(0xFF8E7CFF)],
  ),
];

/// Weak hints: a palette suggests a solver when the prompt names none.
const Map<String, VfxSolver> _impliedSolver = {
  'neon': VfxSolver.cyberGridWave,
  'fire': VfxSolver.curlParticleFlow,
  'matrix': VfxSolver.cyberGridWave,
  'ice': VfxSolver.neuralPlexus,
  'gold': VfxSolver.vortexAttractor,
  'ocean': VfxSolver.metaballFluid,
  'candy': VfxSolver.metaballFluid,
  'blood': VfxSolver.metaballFluid,
};

const List<String> _riseWords = [
  'fire', 'flame', 'ember', 'smoke', 'steam', 'rise\$', 'rising', 'float', 'bubble',
  'spark', 'heat', 'balloon',
];
const List<String> _fallWords = [
  'rain\$', 'raining', 'snow', 'fall', 'drip', 'ash\$', 'ashes', 'melt', 'sink',
];
const List<String> _slowWords = ['slow', 'slowmo', 'bullet time', 'freeze', 'languid', 'calm'];
const List<String> _fastWords = ['fast', 'rapid', 'frantic', 'warp', 'speed', 'violent', 'chaotic'];
const List<String> _brightWords = ['intense', 'blinding', 'radiant', 'luminous', 'bright', 'brilliant'];
const List<String> _dimWords = ['dim', 'subtle', 'moody', 'faint', 'muted'];
const List<String> _flatWords = ['matte', 'flat', 'unlit'];
const List<String> _bloomWords = ['bloom', 'glow'];

/// Keyword matcher over the positive prompt. Keywords come in groups (one
/// palette, one solver, one effect...); if the negative prompt names any
/// keyword of a group the whole group is off, so a negative "crt" really
/// turns scanlines off even if the prompt says "retro". A trailing `$` makes
/// a keyword match a whole word only.
class _Text {
  _Text(this.pos, this.neg);

  final String pos;
  final String neg;

  static final Map<String, RegExp> _patterns = {};

  static RegExp _pattern(String word) => _patterns.putIfAbsent(word, () {
        final whole = word.endsWith('\$');
        final body = RegExp.escape(whole ? word.substring(0, word.length - 1) : word);
        return RegExp(whole ? '\\b$body\\b' : '\\b$body');
      });

  /// Distinct hit positions, so "shock" and "shockwave" count one token once.
  ({int count, int first}) scan(Iterable<String> words) {
    if (negated(words)) return (count: 0, first: -1);
    final starts = <int>{};
    for (final w in words) {
      for (final m in _pattern(w).allMatches(pos)) {
        starts.add(m.start);
      }
    }
    return (count: starts.length, first: starts.isEmpty ? -1 : starts.reduce(math.min));
  }

  bool has(Iterable<String> words) => scan(words).count > 0;

  /// True when the negative prompt names any of [words].
  bool negated(Iterable<String> words) =>
      neg.isNotEmpty && words.any((w) => _pattern(w).hasMatch(neg));
}

/// A compiled, immutable description of one generated visual effect: its
/// palette, the physics layers it is built from and its post-processing.
///
/// The same prompt always compiles to the same DNA; different prompts get
/// different palettes (named themes are nudged by the prompt hash, and prompts
/// that name no theme get a procedural palette).
class VfxDna {
  VfxDna({
    required this.paletteName,
    required this.background,
    required this.colors,
    required this.primary,
    this.secondary = const [],
    this.fx = const {VfxFx.additiveBloom},
    this.emitter = VfxEmitter.point,
    this.glow = 1.0,
    this.speed = 1.0,
    this.buoyancy = 0.0,
    this.detail = 1.0,
    this.volumetric = false,
    this.denoise = false,
    this.hash = 0,
    this.seed = 0,
  }) : assert(colors.length == 3);

  final String paletteName;
  final Color background;

  /// Hot core, body, cool accent.
  final List<Color> colors;
  final VfxSolver primary;

  /// Up to two supporting layers, painted behind the primary.
  final List<VfxSolver> secondary;
  final Set<VfxFx> fx;
  final VfxEmitter emitter;

  /// Overall light intensity, 0.5..1.6.
  final double glow;

  /// Time scale from frame rate and wording (slow motion, warp...).
  final double speed;

  /// Vertical drift: positive rises, negative falls.
  final double buoyancy;

  /// Resolution-derived detail multiplier for particle and mesh counts.
  final double detail;
  final bool volumetric;
  final bool denoise;

  /// Stable hash of the prompt text.
  final int hash;

  /// The render seed this DNA was compiled for.
  final int seed;

  /// Layers in paint order: supporting layers first, the primary on top.
  List<VfxSolver> get layers => [...secondary.reversed, primary];

  bool has(VfxFx f) => fx.contains(f);

  /// The emitter geometry in effect for viewport [mode] (0..2). Each mode
  /// lands on a different one, so the mode buttons reshape the effect.
  VfxEmitter emitterFor(int mode) =>
      VfxEmitter.values[(emitter.index + mode * 2) % VfxEmitter.values.length];

  /// e.g. "Metaball Fluid + Cyber Grid Wave".
  String get label => [primary, ...secondary].map((s) => s.label).join(' + ');

  // ---------------------------------------------------------------------------
  // Compiler
  // ---------------------------------------------------------------------------

  /// Compiles the Prompt Studio form fields. [overrides] is the optional `dna`
  /// object from the render server; see [withOverrides] for its keys.
  factory VfxDna.compile({
    required String prompt,
    String negative = '',
    String solver = '',
    int seed = 0,
    String resolution = '',
    String frameRate = '',
    bool volumetric = false,
    bool denoise = false,
    Map<String, dynamic>? overrides,
  }) {
    final text = _Text(
      '${prompt.toLowerCase()} ${solver.toLowerCase()}',
      negative.toLowerCase(),
    );
    final h = _fnv('${prompt.trim().toLowerCase()}|${solver.trim().toLowerCase()}');
    final hs = _mix(h, seed);

    // --- Palette -------------------------------------------------------------
    final hits = <(_PaletteDef, ({int count, int first}))>[];
    for (final p in _palettes) {
      final s = text.scan(p.words);
      if (s.count > 0) hits.add((p, s));
    }
    hits.sort((a, b) {
      final byCount = b.$2.count.compareTo(a.$2.count);
      return byCount != 0 ? byCount : a.$2.first.compareTo(b.$2.first);
    });

    final String paletteName;
    final Color background;
    final List<Color> colors;
    var glow = 1.0;
    if (hits.isEmpty) {
      final proc = _procedural(h);
      paletteName = 'procedural';
      background = proc.$1;
      colors = proc.$2;
    } else {
      final a = hits.first.$1;
      // A second named theme lends its body colour: "golden solar" is gold
      // with a molten-orange accent.
      final b = hits.length > 1 ? hits[1].$1 : null;
      paletteName = b == null ? a.name : '${a.name}+${b.name}';
      // Same theme, different prompt: nudge hue by up to 7 degrees and
      // lightness by up to 4%, in fine steps, so two prompts rarely match.
      final hue = ((h >> 8) % 141 - 70) / 10;
      final light = ((h >> 16) % 81 - 40) / 1000;
      colors = [
        _shift(a.colors[0], hue, light),
        _shift((b ?? a).colors[1], hue, light),
        _shift(a.colors[2], hue, light),
      ];
      background = _shift(a.background, hue, 0);
      glow = a.glow;
    }

    // --- Solvers -------------------------------------------------------------
    final scored = <(VfxSolver, double, int)>[];
    for (final s in VfxSolver.values) {
      final r = text.scan(s.words);
      if (r.count > 0) scored.add((s, math.min(r.count, 3).toDouble(), r.first));
    }
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      return byScore != 0 ? byScore : a.$3.compareTo(b.$3);
    });

    final chosen = <VfxSolver>[for (final s in scored) s.$1];
    if (chosen.length < 2) {
      // Nothing explicit for the supporting slot: let the theme suggest one.
      final implied = hits.isEmpty ? null : _impliedSolver[hits.first.$1.name];
      if (implied != null && !chosen.contains(implied)) chosen.add(implied);
    }
    if (chosen.isEmpty) chosen.add(VfxSolver.values[hs % VfxSolver.values.length]);
    final primary = chosen.first;
    final secondary = chosen.skip(1).take(2).toList();

    VfxSolver pick(int salt) {
      final pool = [
        for (final s in VfxSolver.values)
          if (s != primary && !secondary.contains(s)) s
      ];
      return pool[_mix(hs, salt) % pool.length];
    }

    if (secondary.isEmpty) secondary.add(pick(1));
    if (secondary.length == 1 && (hs >> 5) % 100 < 35) secondary.add(pick(2));

    // --- Post FX -------------------------------------------------------------
    final fx = <VfxFx>{
      for (final f in VfxFx.values)
        if (f.words.isNotEmpty && text.has(f.words)) f,
    };
    final noBloom = text.negated(_bloomWords) || text.has(_flatWords);
    if (!noBloom) fx.add(VfxFx.additiveBloom);

    // --- Forces, light, timing ----------------------------------------------
    var buoyancy = 0.0;
    if (text.has(_riseWords)) buoyancy += 0.6;
    if (text.has(_fallWords)) buoyancy -= 0.6;

    var speed = 1.0;
    final fps = double.tryParse(RegExp(r'\d+(\.\d+)?').firstMatch(frameRate)?.group(0) ?? '');
    if (fps != null && fps >= 90) speed *= 0.7;
    if (text.has(_slowWords)) speed *= 0.65;
    if (text.has(_fastWords)) speed *= 1.45;

    if (volumetric) glow += 0.25;
    if (text.has(_brightWords)) glow += 0.25;
    if (text.has(_dimWords)) glow -= 0.25;

    final emitterHit = <(VfxEmitter, int)>[
      for (final e in VfxEmitter.values)
        if (text.scan(e.words) case (:final count, :final first) when count > 0) (e, first),
    ]..sort((a, b) => a.$2.compareTo(b.$2));

    final dna = VfxDna(
      paletteName: paletteName,
      background: background,
      colors: colors,
      primary: primary,
      secondary: secondary,
      fx: fx,
      emitter: emitterHit.isEmpty ? _defaultEmitter(primary) : emitterHit.first.$1,
      glow: glow.clamp(0.5, 1.6),
      speed: speed.clamp(0.4, 2.0),
      buoyancy: buoyancy,
      detail: _detailOf(resolution),
      volumetric: volumetric,
      denoise: denoise,
      hash: h,
      seed: seed,
    );
    return overrides == null ? dna : dna.withOverrides(overrides);
  }

  // ---------------------------------------------------------------------------
  // Overrides from the render server
  // ---------------------------------------------------------------------------

  /// Applies a server-supplied `dna` object. Every key is optional and
  /// anything malformed is ignored:
  ///
  /// - `palette`: a theme name (`"fire"`), or `{"background": "#05030D",
  ///   "colors": ["#00F5FF", "#FF007F", "#7B2CBF"]}`; `colors` and
  ///   `background` are also accepted at the top level
  /// - `primary` / `solver`: a solver name (`"vortexAttractor"`)
  /// - `secondary`: a list of solver names (at most two are used)
  /// - `fx`: a list of effect names, or a `{name: bool}` map
  /// - `emitter`: `point`, `ring`, `sphere`, `line` or `plane`
  /// - `glow`, `speed`, `buoyancy`, `detail`: numbers
  /// - `volumetric`, `denoise`: booleans
  VfxDna withOverrides(Map<String, dynamic> o) {
    var background = this.background;
    var colors = this.colors;
    var paletteName = this.paletteName;

    final pal = o['palette'];
    if (pal is String) {
      for (final p in _palettes) {
        if (_norm(p.name) == _norm(pal)) {
          paletteName = p.name;
          background = p.background;
          colors = p.colors;
        }
      }
    }
    final src = pal is Map ? pal : o;
    final bg = _parseColor(src['background']);
    if (bg != null) {
      background = bg;
      paletteName = 'custom';
    }
    final list = src['colors'];
    if (list is List) {
      final parsed = [for (final c in list) _parseColor(c)];
      if (parsed.length >= 3 && !parsed.take(3).contains(null)) {
        colors = [for (final c in parsed.take(3)) c!];
        paletteName = 'custom';
      }
    }

    final newPrimary = _solverFrom(o['primary'] ?? o['solver']) ?? primary;
    var newSecondary = secondary;
    final sec = o['secondary'];
    if (sec is List) {
      newSecondary = <VfxSolver>[];
      for (final s in sec) {
        final v = _solverFrom(s);
        if (v != null && v != newPrimary && !newSecondary.contains(v) && newSecondary.length < 2) {
          newSecondary.add(v);
        }
      }
    } else {
      newSecondary = [for (final s in secondary) if (s != newPrimary) s];
    }

    var newFx = fx;
    final f = o['fx'];
    if (f is List) {
      newFx = {for (final n in f) ?_fxFrom(n)};
    } else if (f is Map) {
      newFx = {...fx};
      f.forEach((k, v) {
        final fxv = _fxFrom(k);
        if (fxv == null || v is! bool) return;
        v ? newFx.add(fxv) : newFx.remove(fxv);
      });
    }

    double? num01(Object? v, double lo, double hi) =>
        v is num && v.isFinite ? v.toDouble().clamp(lo, hi) : null;

    return VfxDna(
      paletteName: paletteName,
      background: background,
      colors: colors,
      primary: newPrimary,
      secondary: newSecondary,
      fx: newFx,
      emitter: _emitterFrom(o['emitter']) ?? emitter,
      glow: num01(o['glow'], 0.5, 1.6) ?? glow,
      speed: num01(o['speed'], 0.4, 2.0) ?? speed,
      buoyancy: num01(o['buoyancy'], -1, 1) ?? buoyancy,
      detail: num01(o['detail'], 0.5, 2.0) ?? detail,
      volumetric: o['volumetric'] is bool ? o['volumetric'] as bool : volumetric,
      denoise: o['denoise'] is bool ? o['denoise'] as bool : denoise,
      hash: hash,
      seed: seed,
    );
  }

  /// The inverse of [withOverrides]; `withOverrides(toJson())` reproduces this.
  Map<String, Object?> toJson() => {
        'palette': {
          'name': paletteName,
          'background': _hex(background),
          'colors': [for (final c in colors) _hex(c)],
        },
        'primary': primary.name,
        'secondary': [for (final s in secondary) s.name],
        'fx': [for (final f in fx) f.name],
        'emitter': emitter.name,
        'glow': glow,
        'speed': speed,
        'buoyancy': buoyancy,
        'detail': detail,
        'volumetric': volumetric,
        'denoise': denoise,
      };

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static VfxSolver? _solverFrom(Object? v) {
    if (v is! String) return null;
    final n = _norm(v);
    for (final s in VfxSolver.values) {
      if (_norm(s.name) == n || _norm(s.label) == n) return s;
    }
    return null;
  }

  static VfxFx? _fxFrom(Object? v) {
    if (v is! String) return null;
    final n = _norm(v);
    for (final f in VfxFx.values) {
      if (_norm(f.name) == n) return f;
    }
    return null;
  }

  static VfxEmitter? _emitterFrom(Object? v) {
    if (v is! String) return null;
    final n = _norm(v);
    for (final e in VfxEmitter.values) {
      if (e.name == n) return e;
    }
    return null;
  }

  /// `#RRGGBB`, `#AARRGGBB`, `RRGGBB` or an ARGB int.
  static Color? _parseColor(Object? v) {
    if (v is int) return Color(v > 0xFFFFFF ? v : 0xFF000000 | v);
    if (v is! String) return null;
    var s = v.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
    final n = int.tryParse(s, radix: 16);
    if (n == null) return null;
    if (s.length == 6) return Color(0xFF000000 | n);
    if (s.length == 8) return Color(n);
    return null;
  }

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static VfxEmitter _defaultEmitter(VfxSolver s) => switch (s) {
        VfxSolver.metaballFluid => VfxEmitter.sphere,
        VfxSolver.curlParticleFlow => VfxEmitter.point,
        VfxSolver.shockwaveRings => VfxEmitter.point,
        VfxSolver.neuralPlexus => VfxEmitter.sphere,
        VfxSolver.vortexAttractor => VfxEmitter.ring,
        VfxSolver.cyberGridWave => VfxEmitter.plane,
      };

  /// 32-bit FNV-1a.
  static int _fnv(String s) {
    var h = 0x811C9DC5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static int _mix(int h, int salt) {
    var x = (h ^ (salt * 0x9E3779B1)) & 0xFFFFFFFF;
    x = ((x ^ (x >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF;
    x = ((x ^ (x >> 12)) * 0x297A2D39) & 0xFFFFFFFF;
    return (x ^ (x >> 15)) & 0x7FFFFFFF;
  }

  static Color _shift(Color c, double hueDeg, double dLight) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withHue((((hsl.hue + hueDeg) % 360) + 360) % 360)
        .withLightness((hsl.lightness + dLight).clamp(0.0, 1.0))
        .toColor();
  }

  /// A palette for prompts that name no theme. Hue, saturation, lightness and
  /// the spread of the harmony (analogous, complementary or triadic) all come
  /// from different bits of the hash, on a near-black tint of the accent.
  static (Color, List<Color>) _procedural(int h) {
    final base = (h % 36000) / 100;
    final j1 = ((h >> 15) % 41 - 20).toDouble();
    final j2 = ((h >> 21) % 41 - 20).toDouble();
    final (o1, o2) = switch ((h >> 9) % 3) {
      0 => (32.0 + j1, -34.0 + j2), // analogous
      1 => (180.0 + j1 / 2, 28.0 + j2), // complementary
      _ => (120.0 + j1, 240.0 + j2), // triadic
    };
    final sat = 0.85 + ((h >> 7) % 16) / 100;
    final lit = 0.55 + ((h >> 11) % 14) / 100;
    Color hsl(double hue, double s, double l) =>
        HSLColor.fromAHSL(1, ((hue % 360) + 360) % 360, s, l).toColor();
    return (
      hsl(base + o2, 0.55, 0.035),
      [hsl(base, sat, lit), hsl(base + o1, sat - 0.05, lit - 0.05), hsl(base + o2, sat - 0.1, lit - 0.1)],
    );
  }

  static double _detailOf(String res) {
    final s = res.toLowerCase();
    double? height;
    final wh = RegExp(r'(\d{3,5})\s*[x×]\s*(\d{3,5})').firstMatch(s);
    if (wh != null) {
      height = double.parse(wh.group(2)!);
    } else if (s.contains('8k')) {
      height = 4320;
    } else if (s.contains('4k') || s.contains('uhd')) {
      height = 2160;
    } else if (s.contains('2k')) {
      height = 1440;
    } else {
      final p = RegExp(r'(\d{3,4})\s*p').firstMatch(s);
      if (p != null) height = double.parse(p.group(1)!);
    }
    return height == null ? 1.0 : (height / 1080).clamp(0.75, 1.5);
  }
}
