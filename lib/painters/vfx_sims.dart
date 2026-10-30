import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart';

import '../models/desktop_node.dart';
import '../models/sim_params.dart';
import 'vfx_surface_sims.dart';

final SimParams _kDefaultParams = SimParams();

/// A self-contained procedural effect. The same sim renders desktop
/// thumbnails ([thumb] = true, low resolution) and full viewport windows.
///
/// Interactive sims are mirror-symmetric about the vertical centre line: the
/// pointer acts as two pointers (itself and its mirror image), so whatever
/// you do on one side happens on the other.
abstract class VfxSim {
  VfxSim({this.thumb = false});

  final bool thumb;
  double t = 0;

  /// Live shader parameters, set by the owning view every frame.
  SimParams params = _kDefaultParams;

  /// Playback seed and sub-mode (e.g. the LIQUID_MORPH shape), set by the view.
  int seed = 0;
  int mode = 0;

  /// Pointer in local coordinates, null when outside.
  Offset? pointer;
  bool pressed = false;

  /// Edge-triggered flags, valid during the current [step].
  bool justPressed = false;
  bool justReleased = false;
  bool _wasPressed = false;
  Offset? _prevPointer;

  /// Pointer velocity in px/s.
  Offset pointerVel = Offset.zero;

  Shader? _bgShader;
  Size? _bgSize;

  Color get background;

  /// A background shader built once per size instead of once per frame.
  Shader bgShader(Size size, Shader Function(Rect rect) build) {
    if (_bgShader == null || _bgSize != size) {
      _bgShader = build(Offset.zero & size);
      _bgSize = size;
    }
    return _bgShader!;
  }

  void step(double dt, Size size) {
    t += dt;
    justPressed = pressed && !_wasPressed;
    justReleased = !pressed && _wasPressed;
    _wasPressed = pressed;
    final p = pointer, q = _prevPointer;
    pointerVel = (p != null && q != null && dt > 0) ? (p - q) / dt : Offset.zero;
    _prevPointer = p;
  }

  void drag(Offset delta) {}

  void paint(Canvas canvas, Size size);
}

VfxSim createSim(SimKind kind, {bool thumb = false}) => switch (kind) {
      SimKind.liquid => LiquidSim(thumb: thumb),
      SimKind.swarm => SwarmSim(thumb: thumb),
      SimKind.chrome => ChromeSim(thumb: thumb),
      SimKind.fog => FogSim(thumb: thumb),
      SimKind.core => CoreSim(thumb: thumb),
      SimKind.cloth => ClothSim(thumb: thumb),
      SimKind.caustics => CausticsSim(thumb: thumb),
      SimKind.marble => MarbleSim(thumb: thumb),
      SimKind.wireframe => WireframeSim(thumb: thumb),
    };

Float32List fibonacciSphere(int n) {
  final out = Float32List(n * 3);
  final phi = math.pi * (3 - math.sqrt(5));
  for (var i = 0; i < n; i++) {
    final y = 1 - (i / (n - 1)) * 2;
    final r = math.sqrt(1 - y * y);
    out[i * 3] = math.cos(phi * i) * r;
    out[i * 3 + 1] = y;
    out[i * 3 + 2] = math.sin(phi * i) * r;
  }
  return out;
}

/// Names of the LIQUID_MORPH shapes, in [VfxSim.mode] order.
const List<String> kLiquidModes = ['Sphere', 'Splash', 'Type'];

// -----------------------------------------------------------------------------
// LIQUID_MORPH: slime. Metaballs on springs, tied together with elastic links.
// Three shapes the blobs morph between: a glossy sphere, a fluid splash and an
// inflated "H". Grab a blob and drag: links stretch into thinning strands and
// the body wobbles back on release. Small specular droplets drift around and
// are repelled by the cursor. Left/right mirror symmetric.
// -----------------------------------------------------------------------------
class LiquidSim extends VfxSim {
  LiquidSim({super.thumb}) {
    for (var m = 0; m < 3; m++) {
      _tu.add(Float64List(n));
      _tv.add(Float64List(n));
      _tr.add(Float64List(n));
      _build(m);
    }
    for (var i = 0; i < n; i++) {
      final left = i < 2 * _pairs && i.isEven;
      final right = i < 2 * _pairs && i.isOdd;
      _side[i] = left ? 1 : (right ? -1 : 0);
      _phase[i] = (i < 2 * _pairs ? (i ~/ 2) : i) * 1.7;
    }
    _fromU.setAll(0, _tu[0]);
    _fromV.setAll(0, _tv[0]);
    _fromR.setAll(0, _tr[0]);
    _hu.setAll(0, _tu[0]);
    _hv.setAll(0, _tv[0]);
    _rn.setAll(0, _tr[0]);
    u.setAll(0, _tu[0]);
    v.setAll(0, _tv[0]);
    _rebuildLinks();
  }

  static const int _pairs = 14;
  static const int _axes = 4;
  static const int _bodyPairs = 11; // pairs beyond this are droplets
  static const int n = _pairs * 2 + _axes;

  final List<Float64List> _tu = [], _tv = [], _tr = [];
  final Float64List _fromU = Float64List(n), _fromV = Float64List(n), _fromR = Float64List(n);
  final Float64List _hu = Float64List(n), _hv = Float64List(n), _rn = Float64List(n);
  final Float64List u = Float64List(n), v = Float64List(n);
  final Float64List du = Float64List(n), dv = Float64List(n);
  final Float64List _fu = Float64List(n), _fv = Float64List(n);
  final Float64List _side = Float64List(n), _phase = Float64List(n);
  final List<(int, int, double)> _links = [];

  int _modeApplied = 0;
  int _seedApplied = 0;
  double _morph = 1;
  int _grab = -1;

  static const int _bands = 8;
  static const int _cap = 160;
  static const List<Color> _colors = [
    Color(0xFF8E0A47),
    Color(0xFFC2185B),
    Color(0xFFE8457F),
    Color(0xFFFF6FA5),
    Color(0xFFFF94BE),
    Color(0xFFFFB8D4),
    Color(0xFFFFDDEB),
    Color(0xFFFFFFFF),
  ];

  final _bx = Float64List(_cap), _by = Float64List(_cap), _br = Float64List(_cap);
  List<Float32List> _core = const [], _edge = const [];
  final _coreN = Int32List(_bands), _edgeN = Int32List(_bands);
  int _cells = 0;
  final Paint _dot = Paint()..strokeCap = StrokeCap.round;

  /// Elastic links as (blobA, blobB, restLength); exposed for tests.
  List<(int, int, double)> get links => _links;

  /// Index of the blob that mirrors [i] across the vertical axis.
  int mirrorOf(int i) => i < 2 * _pairs ? (i.isEven ? i + 1 : i - 1) : i;

  bool _isDrop(int i) => i >= 2 * _bodyPairs && i < 2 * _pairs;

  @override
  Color get background => const Color(0xFFFFFFFF);

  // --- shape targets --------------------------------------------------------

  void _pair(int m, int k, double uu, double vv, double r) {
    _tu[m][2 * k] = uu;
    _tv[m][2 * k] = vv;
    _tr[m][2 * k] = r;
    _tu[m][2 * k + 1] = 1 - uu;
    _tv[m][2 * k + 1] = vv;
    _tr[m][2 * k + 1] = r;
  }

  void _axis(int m, int a, double vv, double r) {
    final i = 2 * _pairs + a;
    _tu[m][i] = 0.5;
    _tv[m][i] = vv;
    _tr[m][i] = r;
  }

  void _build(int m) {
    // Everything starts parked and invisible; each shape claims what it needs.
    for (var k = 0; k < _pairs; k++) {
      _pair(m, k, 0.4, 0.5, 0);
    }
    for (var a = 0; a < _axes; a++) {
      _axis(m, a, 0.5, 0);
    }
    switch (m) {
      case 0: // glossy sphere
        for (var a = 0; a < _axes; a++) {
          final d = (a - 1.5).abs();
          _axis(m, a, 0.5 + (a - 1.5) * 0.11, 0.10 - d * 0.012);
        }
        for (var k = 0; k < _bodyPairs; k++) {
          final th = 2.399963 * k + 0.4;
          final rho = 0.21 * math.sqrt((k + 0.5) / _bodyPairs);
          _pair(m, k, 0.5 - (rho * math.cos(th)).abs() - 0.03, 0.5 + rho * math.sin(th),
              0.085 - 0.004 * (k % 3));
        }
        for (var j = 0; j < 3; j++) {
          final phi = 0.9 + j * 1.25;
          _pair(m, _bodyPairs + j, 0.5 - 0.3 * math.cos(phi).abs() - 0.02,
              0.5 + 0.3 * math.sin(phi), 0.03 - j * 0.003);
        }
      case 1: // splash
        _axis(m, 0, 0.70, 0.115);
        _axis(m, 1, 0.55, 0.07);
        _axis(m, 2, 0.40, 0.055);
        _axis(m, 3, 0.26, 0.04);
        for (var k = 0; k < 3; k++) {
          _pair(m, k, 0.5 - (0.1 + 0.1 * k), 0.70 + 0.01 * k, 0.085 - 0.01 * k);
        }
        for (var j = 0; j < 8; j++) {
          final phi = (12 + j * 9.5) * math.pi / 180;
          final d = 0.18 + 0.02 * j;
          _pair(m, 3 + j, 0.5 - math.sin(phi) * d, 0.66 - math.cos(phi) * d, 0.048 - 0.003 * j);
        }
        for (var j = 0; j < 3; j++) {
          _pair(m, _bodyPairs + j, 0.5 - (0.38 + 0.03 * j), 0.2 + 0.12 * j, 0.026);
        }
      default: // inflated "H"
        for (var k = 0; k < 7; k++) {
          _pair(m, k, 0.33, 0.25 + k * 0.083, 0.064);
        }
        _pair(m, 7, 0.40, 0.5, 0.058);
        _pair(m, 8, 0.45, 0.5, 0.056);
        _axis(m, 0, 0.5, 0.06);
        const drops = [(0.16, 0.30), (0.12, 0.62), (0.22, 0.84)];
        for (var j = 0; j < 3; j++) {
          _pair(m, _bodyPairs + j, drops[j].$1, drops[j].$2, 0.03);
        }
    }
  }

  void _rebuildLinks() {
    _links.clear();
    final uu = _tu[_modeApplied], vv = _tv[_modeApplied], rr = _tr[_modeApplied];
    for (var i = 0; i < n; i++) {
      if (_isDrop(i) || rr[i] < 0.01) continue;
      for (var j = i + 1; j < n; j++) {
        if (_isDrop(j) || rr[j] < 0.01) continue;
        final d = math.sqrt(math.pow(uu[i] - uu[j], 2) + math.pow(vv[i] - vv[j], 2));
        if (d < (rr[i] + rr[j]) * 1.0 + 0.02) _links.add((i, j, d));
      }
    }
  }

  void _switchMode(int m) {
    // Morph from wherever the blobs' targets currently are.
    _fromU.setAll(0, _hu);
    _fromV.setAll(0, _hv);
    _fromR.setAll(0, _rn);
    _modeApplied = m;
    _morph = 0;
    _rebuildLinks();
    _grab = -1;
  }

  void _reseed() {
    final rng = math.Random(seed);
    for (var k = 0; k < _pairs; k++) {
      final ph = rng.nextDouble() * 6.28;
      _phase[2 * k] = ph;
      _phase[2 * k + 1] = ph;
    }
    for (var a = 0; a < _axes; a++) {
      _phase[2 * _pairs + a] = rng.nextDouble() * 6.28;
    }
  }

  // --- simulation -----------------------------------------------------------

  @override
  void step(double dt, Size size) {
    super.step(dt, size);
    if (size.isEmpty) return;
    dt = dt.clamp(0.0, 1 / 30);

    final want = mode.clamp(0, 2);
    if (want != _modeApplied) _switchMode(want);
    if (seed != _seedApplied) {
      _seedApplied = seed;
      _reseed();
    }

    // Ease the shape targets toward the active mode.
    _morph = math.min(1.0, _morph + dt * 1.4);
    final e = Curves01.smooth(_morph);
    final tu = _tu[_modeApplied], tv = _tv[_modeApplied], tr = _tr[_modeApplied];
    for (var i = 0; i < n; i++) {
      _hu[i] = _fromU[i] + (tu[i] - _fromU[i]) * e;
      _hv[i] = _fromV[i] + (tv[i] - _fromV[i]) * e;
      _rn[i] = _fromR[i] + (tr[i] - _fromR[i]) * e;
    }

    final turb = params.turbulence, coh = params.coherence;
    final drift = 0.03 * (0.4 + 1.6 * turb);
    final kHome = 34 * (0.6 + 0.8 * coh);
    final kLink = 16 * (0.4 + 1.2 * coh) * e;

    final p = pointer;
    final pu = p == null ? 0.0 : p.dx / size.width;
    final pv = p == null ? 0.0 : p.dy / size.height;

    // Pressing near a blob grabs it; its mirror partner follows the mirrored
    // pointer, so the slime stretches symmetrically.
    if (justPressed && p != null) {
      var best = -1;
      var bd = 0.3;
      for (var i = 0; i < n; i++) {
        if (_isDrop(i) || _rn[i] < 0.02) continue;
        final d1 = math.sqrt(math.pow(u[i] - pu, 2) + math.pow(v[i] - pv, 2));
        final d2 = math.sqrt(math.pow(u[i] - (1 - pu), 2) + math.pow(v[i] - pv, 2));
        if (d1 < bd) {
          bd = d1;
          best = i;
        }
        if (d2 < bd) {
          bd = d2;
          best = mirrorOf(i);
        }
      }
      _grab = best;
    }
    if (!pressed) _grab = -1;

    const sub = 3;
    final h = dt / sub;
    for (var s = 0; s < sub; s++) {
      for (var i = 0; i < n; i++) {
        final hx = _hu[i] + _side[i] * drift * math.sin(t * 0.7 + _phase[i]);
        final hy = _hv[i] + drift * math.cos(t * 0.55 + _phase[i] * 1.3);
        final drop = _isDrop(i);
        final k = drop ? 7.0 : kHome;
        final c = drop ? 1.6 : 3.4;
        _fu[i] = -k * (u[i] - hx) - c * du[i];
        _fv[i] = -k * (v[i] - hy) - c * dv[i];
      }
      // Elastic links between neighbouring blobs.
      for (final (a, b, rest) in _links) {
        final dx = u[b] - u[a], dy = v[b] - v[a];
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 1e-6) continue;
        final f = kLink * (len - rest) / len;
        _fu[a] += f * dx;
        _fv[a] += f * dy;
        _fu[b] -= f * dx;
        _fv[b] -= f * dy;
      }
      // Soft-body overlap: blobs push each other apart.
      for (var i = 0; i < n; i++) {
        if (_rn[i] < 0.01) continue;
        for (var j = i + 1; j < n; j++) {
          if (_rn[j] < 0.01) continue;
          final dx = u[j] - u[i], dy = v[j] - v[i];
          final d = math.sqrt(dx * dx + dy * dy);
          final minD = (_rn[i] + _rn[j]) * 0.8;
          if (d < minD && d > 1e-5) {
            final f = 60 * (minD - d) / d;
            _fu[i] -= f * dx;
            _fv[i] -= f * dy;
            _fu[j] += f * dx;
            _fv[j] += f * dy;
          }
        }
      }
      if (p != null) {
        for (var img = 0; img < 2; img++) {
          final px = img == 0 ? pu : 1 - pu;
          for (var i = 0; i < n; i++) {
            final dx = px - u[i], dy = pv - v[i];
            final d = math.sqrt(dx * dx + dy * dy);
            if (_isDrop(i)) {
              // Specular droplets flee the cursor.
              if (d < 0.24) {
                final f = 1 - d / 0.24;
                _fu[i] -= 70 * f * dx / (d + 0.03);
                _fv[i] -= 70 * f * dy / (d + 0.03);
              }
            } else if (d < 0.22) {
              final f = 1 - d / 0.22;
              final k = pressed ? 40.0 : 22.0;
              _fu[i] += k * f * dx;
              _fv[i] += k * f * dy;
            }
          }
          if (_grab >= 0) {
            final g = img == 0 ? _grab : mirrorOf(_grab);
            _fu[g] += 200 * (px - u[g]) - 8 * du[g];
            _fv[g] += 200 * (pv - v[g]) - 8 * dv[g];
          }
        }
      }
      for (var i = 0; i < n; i++) {
        du[i] += _fu[i] * h;
        dv[i] += _fv[i] * h;
        u[i] = (u[i] + du[i] * h).clamp(0.03, 0.97);
        v[i] = (v[i] + dv[i] * h).clamp(0.03, 0.97);
      }
    }
  }

  void _ensure(int cells) {
    if (cells <= _cells) return;
    _cells = cells;
    _core = List.generate(_bands, (_) => Float32List(cells * 2));
    _edge = List.generate(_bands, (_) => Float32List(cells * 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, m = math.min(w, h);
    if (m <= 0) return;
    final cell = math.max(2.4, m / (thumb ? 30 : 76));
    final cols = (w / cell).ceil(), rows = (h / cell).ceil();
    _ensure(cols * rows);

    var nb = 0;
    for (var i = 0; i < n; i++) {
      if (_rn[i] < 0.003) continue;
      final pulse = 1 + 0.07 * math.sin(t * 1.2 + _phase[i] * 2);
      _bx[nb] = u[i] * w;
      _by[nb] = v[i] * h;
      _br[nb] = _rn[i] * m * 0.95 * pulse;
      nb++;
    }
    // Stretched links grow thin strands of slime between their blobs.
    for (final (a, b, rest) in _links) {
      final len = math.sqrt(math.pow(u[b] - u[a], 2) + math.pow(v[b] - v[a], 2));
      final s = len / rest;
      if (s <= 1.2 || nb + 2 > _cap) continue;
      final base = math.min(_rn[a], _rn[b]) * m * 0.6;
      final r = base * (1.3 / s).clamp(0.25, 1.0);
      for (var k = 1; k <= 2; k++) {
        final f = k / 3;
        _bx[nb] = (u[a] + (u[b] - u[a]) * f) * w;
        _by[nb] = (v[a] + (v[b] - v[a]) * f) * h;
        _br[nb] = r;
        nb++;
      }
    }

    _coreN.fillRange(0, _bands, 0);
    _edgeN.fillRange(0, _bands, 0);
    final r0 = m * 0.1;
    for (var row = 0; row < rows; row++) {
      final y = (row + 0.5) * cell;
      for (var col = 0; col < cols; col++) {
        final x = (col + 0.5) * cell;
        var f = 0.0, gx = 0.0, gy = 0.0;
        for (var k = 0; k < nb; k++) {
          final dx = x - _bx[k], dy = y - _by[k];
          final d2 = dx * dx + dy * dy + 1;
          // Steep (r/d)^4 falloff keeps blobs distinct with thin necks.
          final q0 = _br[k] * _br[k] / d2;
          final q = q0 * q0;
          f += q;
          final g = 2 * q / d2;
          gx += g * dx;
          gy += g * dy;
        }
        if (f < 0.5) continue;
        var nx = 1.8 * gx * r0, ny = 1.8 * gy * r0;
        final inv = 1 / math.sqrt(nx * nx + ny * ny + 1);
        nx *= inv;
        ny *= inv;
        final nz = inv;
        final diff = math.max(0.0, -0.45 * nx - 0.55 * ny + 0.7 * nz);
        final sh = math.max(0.0, -0.244 * nx - 0.298 * ny + 0.922 * nz);
        final spec = math.pow(sh, 28).toDouble();
        final tone = 0.14 + 0.62 * diff + 0.9 * spec;
        final band = (tone * _bands).floor().clamp(0, _bands - 1);
        if (f < 1.0) {
          final c = _edgeN[band];
          _edge[band][c * 2] = x;
          _edge[band][c * 2 + 1] = y;
          _edgeN[band] = c + 1;
        } else {
          final c = _coreN[band];
          _core[band][c * 2] = x;
          _core[band][c * 2 + 1] = y;
          _coreN[band] = c + 1;
        }
      }
    }

    for (var b = 0; b < _bands; b++) {
      _dot.color = _colors[b];
      if (_edgeN[b] > 0) {
        _dot.strokeWidth = cell * 0.55;
        canvas.drawRawPoints(PointMode.points,
            Float32List.sublistView(_edge[b], 0, _edgeN[b] * 2), _dot);
      }
      if (_coreN[b] > 0) {
        _dot.strokeWidth = cell * 1.12;
        canvas.drawRawPoints(PointMode.points,
            Float32List.sublistView(_core[b], 0, _coreN[b] * 2), _dot);
      }
    }
  }
}

/// Small easing helpers shared by the sims.
class Curves01 {
  Curves01._();

  /// Smoothstep on 0..1.
  static double smooth(double x) => x * x * (3 - 2 * x);
}

// -----------------------------------------------------------------------------
// NANOBOT_SWARM: agents orbit attractors. Only the left half is simulated and
// every agent is drawn twice (mirrored), so the swarm is always symmetric.
// Hover to lure it, press to cinch it tight, release to burst it apart.
// Params: density = how many agents are active, coherence = how tightly they
// hold their orbits, turbulence = how wildly they jitter.
// -----------------------------------------------------------------------------
class SwarmSim extends VfxSim {
  SwarmSim({super.thumb}) {
    n = thumb ? 260 : 1800;
    x = Float32List(n);
    y = Float32List(n);
    vx = Float32List(n);
    vy = Float32List(n);
    _scatter(0);
    for (var b = 0; b < 3; b++) {
      _buf.add(Float32List(n * 4));
    }
  }

  late final int n;
  late final Float32List x, y, vx, vy;
  final List<Float32List> _buf = [];
  final _cnt = Int32List(3);
  int _seedApplied = 0;
  final Paint _pt = Paint()..strokeCap = StrokeCap.round;
  final Paint _bg = Paint();

  static const List<Color> _colors = [
    Color(0xFFB76E8A),
    Color(0xFFF3B2C8),
    Color(0xFFFFF1D6),
  ];

  @override
  Color get background => const Color(0xFF140B12);

  void _scatter(int s) {
    final rng = math.Random(s == 0 ? 7 : s);
    for (var i = 0; i < n; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final r = math.sqrt(rng.nextDouble()) * 0.22;
      x[i] = 0.3 + math.cos(a) * r * 0.9;
      y[i] = 0.5 + math.sin(a) * r;
      vx[i] = 0;
      vy[i] = 0;
    }
  }

  int get _active => (n * (0.3 + 0.7 * params.density)).round().clamp(1, n);

  @override
  void step(double dt, Size size) {
    super.step(dt, size);
    if (size.isEmpty) return;
    dt = dt.clamp(0.0, 1 / 30);
    if (seed != _seedApplied) {
      _seedApplied = seed;
      _scatter(seed);
    }
    final ax = 0.3 + 0.08 * math.cos(t * 0.6), ay = 0.5 + 0.18 * math.sin(t * 0.9);
    final cy = 0.5 + 0.22 * math.sin(t * 0.7 + 1);
    final p = pointer;
    final pu = p == null ? 0.0 : p.dx / size.width;
    final pv = p == null ? 0.0 : p.dy / size.height;
    final qu = 1 - pu;
    final damp = math.pow(0.94, dt * 60).toDouble();
    final burst = justReleased && p != null;
    final grip = 0.7 + 0.6 * params.coherence;
    final jitter = 0.1 + 0.8 * params.turbulence;
    final count = _active;
    for (var i = 0; i < count; i++) {
      double tx, ty;
      if (i % 3 == 0) {
        tx = 0.5;
        ty = cy;
      } else {
        tx = ax;
        ty = ay;
      }
      // Half of the agents chase whichever pointer image is nearer.
      var chase = false;
      var imgU = pu;
      if (p != null) {
        final d1 = (x[i] - pu) * (x[i] - pu) + (y[i] - pv) * (y[i] - pv);
        final d2 = (x[i] - qu) * (x[i] - qu) + (y[i] - pv) * (y[i] - pv);
        imgU = d1 <= d2 ? pu : qu;
        if (i.isEven) {
          chase = true;
          tx = imgU;
          ty = pv;
        }
      }
      final dx = tx - x[i], dy = ty - y[i];
      final d = math.sqrt(dx * dx + dy * dy) + 1e-4;
      // Each agent springs toward its own orbital shell around the target.
      final shell = (0.06 + 0.16 * ((i * 0.618034) % 1)) * (chase ? 0.6 : 1);
      final pull = (d - shell) * (pressed ? 30.0 : 16.0) * grip;
      final s = (i % 4 < 2 ? 1.4 : -1.4);
      final wob = math.sin(i * 12.9 + t * 3) * jitter;
      vx[i] = (vx[i] + (dx / d * pull - dy / d * s + wob) * dt) * damp;
      vy[i] = (vy[i] + (dy / d * pull + dx / d * s - wob) * dt) * damp;
      if (burst) {
        final ex = x[i] - imgU, ey = y[i] - pv;
        final ed = math.sqrt(ex * ex + ey * ey) + 1e-4;
        if (ed < 0.3) {
          final k = (1 - ed / 0.3) * 1.3;
          vx[i] += ex / ed * k;
          vy[i] += ey / ed * k;
        }
      }
      x[i] += vx[i] * dt;
      y[i] += vy[i] * dt;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    _bg.shader = bgShader(
      size,
      (r) => const RadialGradient(
        colors: [Color(0xFF3A1A2C), Color(0xFF140B12)],
        radius: 0.9,
      ).createShader(r),
    );
    canvas.drawRect(rect, _bg);
    _cnt.fillRange(0, 3, 0);
    final count = _active;
    for (var i = 0; i < count; i++) {
      final sp = math.sqrt(vx[i] * vx[i] + vy[i] * vy[i]);
      final b = sp < 0.22 ? 0 : (sp < 0.45 ? 1 : 2);
      final c = _cnt[b];
      final px = x[i] * size.width, py = y[i] * size.height;
      _buf[b][c * 4] = px;
      _buf[b][c * 4 + 1] = py;
      _buf[b][c * 4 + 2] = size.width - px;
      _buf[b][c * 4 + 3] = py;
      _cnt[b] = c + 1;
    }
    _pt.strokeWidth = thumb ? 1.7 : 2.0;
    for (var b = 0; b < 3; b++) {
      if (_cnt[b] == 0) continue;
      _pt.color = _colors[b];
      canvas.drawRawPoints(PointMode.points,
          Float32List.sublistView(_buf[b], 0, _cnt[b] * 4), _pt);
    }
  }
}

// -----------------------------------------------------------------------------
// CHROME_SHADER: a jelly chrome knot. Every sample of the tube is a spring
// coupled to its neighbours, so pulling it drags a smooth, wobbly bulge along
// the tube. Mirrored pointer keeps the pull symmetric. Coherence = jelly
// stiffness, turbulence = ripple along the tube.
// -----------------------------------------------------------------------------
class ChromeSim extends VfxSim {
  ChromeSim({super.thumb});

  static const int _samples = 260;
  final _px = Float64List(_samples + 1);
  final _py = Float64List(_samples + 1);
  final _pz = Float64List(_samples + 1);
  final _bx = Float64List(_samples + 1);
  final _by = Float64List(_samples + 1);
  final _ox = Float64List(_samples);
  final _oy = Float64List(_samples);
  final _vx = Float64List(_samples);
  final _vy = Float64List(_samples);
  final Paint _bg = Paint();
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  Shader? _tint;
  Size? _tintSize;

  @override
  Color get background => const Color(0xFFFFFFFF);

  @override
  void step(double dt, Size size) {
    super.step(dt, size);
    if (size.isEmpty) return;
    dt = dt.clamp(0.0, 1 / 30);
    final m = math.min(size.width, size.height);
    final reach = m * 0.26;
    final kn = 180 * (0.4 + 1.2 * params.coherence);
    final p = pointer;
    final q = p == null ? null : Offset(size.width - p.dx, p.dy);
    const sub = 2;
    final h = dt / sub;
    for (var s = 0; s < sub; s++) {
      for (var k = 0; k < _samples; k++) {
        final cx = _bx[k] + _ox[k], cy = _by[k] + _oy[k];
        final a = (k - 1 + _samples) % _samples, b = (k + 1) % _samples;
        var fx = -40 * _ox[k] - 4.5 * _vx[k] + kn * (_ox[a] + _ox[b] - 2 * _ox[k]);
        var fy = -40 * _oy[k] - 4.5 * _vy[k] + kn * (_oy[a] + _oy[b] - 2 * _oy[k]);
        if (p != null && q != null) {
          final d1 = (cx - p.dx) * (cx - p.dx) + (cy - p.dy) * (cy - p.dy);
          final d2 = (cx - q.dx) * (cx - q.dx) + (cy - q.dy) * (cy - q.dy);
          final tgt = d1 <= d2 ? p : q;
          final d = math.sqrt(math.min(d1, d2));
          if (d < reach) {
            final f = 1 - d / reach;
            final kp = pressed ? 70.0 : 14.0;
            fx += kp * f * (tgt.dx - cx);
            fy += kp * f * (tgt.dy - cy);
          }
        }
        _vx[k] += fx * h;
        _vy[k] += fy * h;
      }
      for (var k = 0; k < _samples; k++) {
        _ox[k] += _vx[k] * h;
        _oy[k] += _vy[k] * h;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, m = math.min(w, h);
    if (m <= 0) return;
    final rect = Offset.zero & size;
    _bg.shader = bgShader(
      size,
      (r) => const RadialGradient(
        center: Alignment(0, 0.2),
        radius: 0.9,
        colors: [Color(0xFFFFFFFF), Color(0xFFF1F1F4)],
      ).createShader(r),
    );
    canvas.drawRect(rect, _bg);
    if (_tint == null || _tintSize != size) {
      _tint = const LinearGradient(
        colors: [Color(0x55FF8FC8), Color(0x55B9A6FF), Color(0x5582E9FF)],
      ).createShader(rect);
      _tintSize = size;
    }

    final scale = m * 0.135;
    final cx = w / 2, cy = h / 2;
    final rot = t * 0.45;
    final tilt = 0.5 + 0.15 * math.sin(t * 0.3);
    final cr = math.cos(rot), sr = math.sin(rot);
    final ct = math.cos(tilt), st = math.sin(tilt);
    final ripple = params.turbulence * scale * 0.06;

    for (var k = 0; k <= _samples; k++) {
      final s = k / _samples * math.pi * 2;
      final x = math.sin(s) + 2 * math.sin(2 * s);
      final y = math.cos(s) - 2 * math.cos(2 * s);
      final z = -math.sin(3 * s);
      final x1 = x * cr - z * sr;
      final z1 = x * sr + z * cr;
      final y1 = y * ct - z1 * st;
      final z2 = y * st + z1 * ct;
      final persp = 6 / (6 - z2);
      final wave = ripple * math.sin(s * 7 + t * 2.4);
      final bx = cx + x1 * scale * persp + wave;
      final by = cy + y1 * scale * persp + wave * 0.6;
      _bx[k] = bx;
      _by[k] = by;
      final o = k % _samples;
      _px[k] = bx + _ox[o];
      _py[k] = by + _oy[o];
      _pz[k] = z2;
    }

    final back = Path(), front = Path();
    bool? lastFront;
    for (var k = 0; k < _samples; k++) {
      final isFront = (_pz[k] + _pz[k + 1]) >= 0;
      final path = isFront ? front : back;
      if (lastFront != isFront) path.moveTo(_px[k], _py[k]);
      path.lineTo(_px[k + 1], _py[k + 1]);
      lastFront = isFront;
    }

    final tube = scale * 0.95;
    _tube(canvas, back, tube, dim: true);
    _tube(canvas, front, tube, dim: false);
  }

  void _tube(Canvas canvas, Path path, double w, {required bool dim}) {
    _line.shader = null;
    const layers = [
      (1.0, Color(0xFF2E3440)),
      (0.86, Color(0xFF6B7280)),
      (0.68, Color(0xFFB8BEC9)),
    ];
    for (final (f, c) in layers) {
      _line
        ..strokeWidth = w * f
        ..color = dim ? Color.lerp(c, const Color(0xFF1F2430), 0.25)! : c;
      canvas.drawPath(path, _line);
    }
    _line
      ..strokeWidth = w * 0.62
      ..color = const Color(0xFFFFFFFF)
      ..shader = _tint;
    canvas.drawPath(path, _line);
    _line
      ..shader = null
      ..strokeWidth = w * 0.42
      ..color = const Color(0xFFEDEFF4);
    canvas.drawPath(path, _line);
    _line
      ..strokeWidth = w * 0.14
      ..color = const Color(0xEEFFFFFF);
    canvas.drawPath(path.shift(Offset(-w * 0.12, -w * 0.12)), _line);
  }
}

// -----------------------------------------------------------------------------
// VOLUMETRIC_FOG: blurred participating media lit by a movable key light.
// Density = how many puffs, turbulence = how fast they drift.
// -----------------------------------------------------------------------------
class FogSim extends VfxSim {
  FogSim({super.thumb});

  static const List<Color> _puff = [
    Color(0x998B6CF2),
    Color(0x7738C6E8),
    Color(0x77E879B8),
    Color(0x88818CF8),
  ];

  final Paint _bg = Paint();
  final Paint _blob = Paint();
  final Paint _ray = Paint();
  final Paint _glow = Paint();
  final Paint _dust = Paint()
    ..strokeCap = StrokeCap.round
    ..color = const Color(0xB3FFFFFF);
  Float32List _motes = Float32List(0);

  @override
  Color get background => const Color(0xFFF6F4FB);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, m = math.min(w, h);
    if (m <= 0) return;
    final rect = Offset.zero & size;
    _bg.shader = bgShader(
      size,
      (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF7F4FF), Color(0xFFD9CCF5)],
      ).createShader(r),
    );
    canvas.drawRect(rect, _bg);

    final light = pointer ?? Offset(w * 0.72, h * 0.2);
    final drift = 0.5 + params.turbulence;

    // God rays fanning down-left from the key light.
    for (var k = 0; k < 7; k++) {
      final a = 2.15 + k * 0.13 + 0.05 * math.sin(t * 0.6 + k);
      final len = m * 1.5;
      final spread = 0.035 + 0.01 * math.sin(t + k);
      final p1 = light + Offset(math.cos(a - spread), math.sin(a - spread)) * len;
      final p2 = light + Offset(math.cos(a + spread), math.sin(a + spread)) * len;
      final ray = Path()
        ..moveTo(light.dx, light.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();
      _ray.shader = LinearGradient(
        colors: const [Color(0x88FFFFFF), Color(0x00FFFFFF)],
        begin: Alignment.center,
        end: Alignment(math.cos(a), math.sin(a)),
      ).createShader(Rect.fromCircle(center: light, radius: len));
      canvas.drawPath(ray, _ray);
    }

    final count = ((thumb ? 9 : 26) * (0.4 + 0.9 * params.density)).round();
    for (var i = 0; i < count; i++) {
      final px = w * (0.5 + 0.42 * math.sin(t * 0.08 * drift * (1 + i % 3) + i * 2.1));
      final py = h * (0.58 + 0.28 * math.cos(t * 0.07 * drift * (1 + i % 4) + i * 1.3));
      final r = m * (0.15 + 0.07 * math.sin(i * 1.9));
      final lit = (1 - ((Offset(px, py) - light).distance / (m * 0.9))).clamp(0.0, 1.0);
      final base = _puff[i % _puff.length];
      _blob
        ..color = Color.lerp(base, const Color(0xAAFFFFFF), lit * 0.6)!
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.55);
      canvas.drawCircle(Offset(px, py), r, _blob);
    }

    _glow.shader = const RadialGradient(
      colors: [Color(0xEEFFFFFF), Color(0x00FFFFFF)],
    ).createShader(Rect.fromCircle(center: light, radius: m * 0.22));
    canvas.drawCircle(light, m * 0.22, _glow);

    // Dust motes drifting upward through the beam.
    final motes = thumb ? 24 : 90;
    if (_motes.length != motes * 2) _motes = Float32List(motes * 2);
    for (var i = 0; i < motes; i++) {
      final hx = (math.sin(i * 91.7) * 43758.5453) % 1;
      final hy = (math.sin(i * 27.3) * 12543.123) % 1;
      _motes[i * 2] = w * hx.abs() + 6 * math.sin(t + i);
      _motes[i * 2 + 1] = h - ((t * 14 * drift * (0.3 + hx.abs()) + hy.abs() * h) % h);
    }
    _dust.strokeWidth = thumb ? 1.2 : 1.8;
    canvas.drawRawPoints(PointMode.points, _motes, _dust);
  }
}

// -----------------------------------------------------------------------------
// CORE: a miniature Photon Core used for avatars and the engine card.
// -----------------------------------------------------------------------------
class CoreSim extends VfxSim {
  CoreSim({super.thumb});

  static final Float32List _pts = fibonacciSphere(1800);
  static const List<Color> _colors = [
    Color(0x806D28D9),
    Color(0xCC8B5CF6),
    Color(0xFF22D3EE),
    Color(0xFFE0FDFF),
  ];
  final List<Float32List> _buf = List.generate(4, (_) => Float32List(1800 * 2));
  final _cnt = Int32List(4);
  final Paint _bg = Paint();
  final Paint _halo = Paint();
  final Paint _dot = Paint()..strokeCap = StrokeCap.round;
  double _haloBlur = -1;

  @override
  Color get background => const Color(0xFF0E3A40);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, m = math.min(w, h);
    if (m <= 0) return;
    final rect = Offset.zero & size;
    _bg.shader = bgShader(
      size,
      (r) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3B8C8A), Color(0xFF15474D), Color(0xFF0B1F2A)],
      ).createShader(r),
    );
    canvas.drawRect(rect, _bg);
    if (_haloBlur != m) {
      _haloBlur = m;
      _halo
        ..color = const Color(0x557C3AED)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, m * 0.12);
    }
    canvas.drawCircle(Offset(w * 0.5, h * 0.5), m * 0.46, _halo);

    _cnt.fillRange(0, 4, 0);
    final yaw = t * 0.5;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    const pitch = -0.35;
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final scale = m * 0.3;
    for (var i = 0; i < 1800; i++) {
      final x = _pts[i * 3], y = _pts[i * 3 + 1], z = _pts[i * 3 + 2];
      final wob = 1 + 0.08 * math.sin(3 * x + t * 1.4) * math.sin(3 * y - t);
      final x1 = x * cy - z * sy;
      final z1 = x * sy + z * cy;
      final y1 = y * cp - z1 * sp;
      final z2 = y * sp + z1 * cp;
      final diff = math.max(0.0, -0.5 * x1 - 0.6 * y1 + 0.6 * z2);
      final rim = 1 - z2.abs();
      final s = (0.2 + 0.6 * diff + 0.4 * rim * rim).clamp(0.0, 0.999);
      final b = z2 < 0 ? 0 : (s * 3).floor() + 1;
      final band = b.clamp(0, 3);
      final c = _cnt[band];
      _buf[band][c * 2] = w / 2 + x1 * scale * wob;
      _buf[band][c * 2 + 1] = h / 2 + y1 * scale * wob;
      _cnt[band] = c + 1;
    }
    _dot.strokeWidth = (m / 150).clamp(1.1, 2.6);
    for (var b = 0; b < 4; b++) {
      if (_cnt[b] == 0) continue;
      _dot.color = _colors[b];
      canvas.drawRawPoints(PointMode.points,
          Float32List.sublistView(_buf[b], 0, _cnt[b] * 2), _dot);
    }
  }
}
