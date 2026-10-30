import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart';

import '../models/desktop_node.dart';
import 'vfx_surface_sims.dart';

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

  Color get background;

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

// -----------------------------------------------------------------------------
// LIQUID_MORPH: slime. Metaballs on springs, tied together with elastic links.
// Grab a blob and drag: the links stretch into thinning strands, and on release
// the whole body wobbles back. Left/right mirror symmetric.
// -----------------------------------------------------------------------------
class LiquidSim extends VfxSim {
  LiquidSim({super.thumb}) {
    final hu = <double>[], hv = <double>[], hr = <double>[];
    final side = <double>[], phase = <double>[];
    final mir = <int>[];
    void add(double u, double v, double r, double s, double ph) {
      hu.add(u);
      hv.add(v);
      hr.add(r);
      side.add(s);
      phase.add(ph);
      mir.add(hu.length - 1);
    }

    const pairs = [
      (0.30, 0.36, 0.105),
      (0.37, 0.60, 0.095),
      (0.21, 0.50, 0.080),
      (0.41, 0.47, 0.120),
    ];
    for (var k = 0; k < pairs.length; k++) {
      final (u, v, r) = pairs[k];
      final i = hu.length;
      add(u, v, r, 1, k * 1.7);
      add(1 - u, v, r, -1, k * 1.7);
      mir[i] = i + 1;
      mir[i + 1] = i;
    }
    add(0.5, 0.22, 0.085, 0, 5.1);
    add(0.5, 0.76, 0.090, 0, 6.3);

    n = hu.length;
    homeU = Float64List.fromList(hu);
    homeV = Float64List.fromList(hv);
    rad = Float64List.fromList(hr);
    _side = Float64List.fromList(side);
    _phase = Float64List.fromList(phase);
    _mirror = mir;
    u = Float64List.fromList(hu);
    v = Float64List.fromList(hv);
    du = Float64List(n);
    dv = Float64List(n);
    _fu = Float64List(n);
    _fv = Float64List(n);
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final d = math.sqrt(math.pow(hu[i] - hu[j], 2) + math.pow(hv[i] - hv[j], 2));
        if (d < 0.36) _links.add((i, j, d));
      }
    }
  }

  late final int n;
  late final Float64List homeU, homeV, rad, u, v, du, dv;
  late final Float64List _side, _phase, _fu, _fv;
  late final List<int> _mirror;
  final List<(int, int, double)> _links = [];
  int _grab = -1;

  /// Elastic links as (blobA, blobB, restLength); exposed for tests.
  List<(int, int, double)> get links => _links;

  /// Index of the blob that mirrors [i] across the vertical axis.
  int mirrorOf(int i) => _mirror[i];

  static const int _bands = 8;
  static const int _cap = 96;
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

  @override
  Color get background => const Color(0xFFFFFFFF);

  @override
  void step(double dt, Size size) {
    super.step(dt, size);
    if (size.isEmpty) return;
    dt = dt.clamp(0.0, 1 / 30);
    final p = pointer;
    final pu = p == null ? 0.0 : p.dx / size.width;
    final pv = p == null ? 0.0 : p.dy / size.height;

    // Pressing near a blob grabs it; its mirror partner follows the mirrored
    // pointer, so the slime stretches symmetrically.
    if (justPressed && p != null) {
      var best = -1;
      var bd = 0.3;
      for (var i = 0; i < n; i++) {
        final d1 = math.sqrt(math.pow(u[i] - pu, 2) + math.pow(v[i] - pv, 2));
        final d2 = math.sqrt(math.pow(u[i] - (1 - pu), 2) + math.pow(v[i] - pv, 2));
        if (d1 < bd) {
          bd = d1;
          best = i;
        }
        if (d2 < bd) {
          bd = d2;
          best = _mirror[i];
        }
      }
      _grab = best;
    }
    if (!pressed) _grab = -1;

    const sub = 3;
    final h = dt / sub;
    for (var s = 0; s < sub; s++) {
      for (var i = 0; i < n; i++) {
        final hx = homeU[i] + _side[i] * 0.035 * math.sin(t * 0.7 + _phase[i]);
        final hy = homeV[i] + 0.035 * math.cos(t * 0.55 + _phase[i] * 1.3);
        _fu[i] = -34 * (u[i] - hx) - 3.4 * du[i];
        _fv[i] = -34 * (v[i] - hy) - 3.4 * dv[i];
      }
      // Elastic links between neighbouring blobs.
      for (final (a, b, rest) in _links) {
        final dx = u[b] - u[a], dy = v[b] - v[a];
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 1e-6) continue;
        final f = 16 * (len - rest) / len;
        _fu[a] += f * dx;
        _fv[a] += f * dy;
        _fu[b] -= f * dx;
        _fv[b] -= f * dy;
      }
      // Soft-body overlap: blobs push each other apart.
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          final dx = u[j] - u[i], dy = v[j] - v[i];
          final d = math.sqrt(dx * dx + dy * dy);
          final minD = (rad[i] + rad[j]) * 0.8;
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
            if (d < 0.22) {
              final f = 1 - d / 0.22;
              final k = pressed ? 40.0 : 22.0;
              _fu[i] += k * f * dx;
              _fv[i] += k * f * dy;
            }
          }
          if (_grab >= 0) {
            final g = img == 0 ? _grab : _mirror[_grab];
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
      final pulse = 1 + 0.07 * math.sin(t * 1.2 + _phase[i] * 2);
      _bx[nb] = u[i] * w;
      _by[nb] = v[i] * h;
      _br[nb] = rad[i] * m * 0.95 * pulse;
      nb++;
    }
    // Stretched links grow thin strands of slime between their blobs.
    for (final (a, b, rest) in _links) {
      final len = math.sqrt(math.pow(u[b] - u[a], 2) + math.pow(v[b] - v[a], 2));
      final s = len / rest;
      if (s <= 1.2 || nb + 2 > _cap) continue;
      final base = math.min(rad[a], rad[b]) * m * 0.6;
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

    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var b = 0; b < _bands; b++) {
      paint.color = _colors[b];
      if (_edgeN[b] > 0) {
        paint.strokeWidth = cell * 0.55;
        canvas.drawRawPoints(PointMode.points,
            Float32List.sublistView(_edge[b], 0, _edgeN[b] * 2), paint);
      }
      if (_coreN[b] > 0) {
        paint.strokeWidth = cell * 1.12;
        canvas.drawRawPoints(PointMode.points,
            Float32List.sublistView(_core[b], 0, _coreN[b] * 2), paint);
      }
    }
  }
}

// -----------------------------------------------------------------------------
// NANOBOT_SWARM: agents orbit attractors. Only the left half is simulated and
// every agent is drawn twice (mirrored), so the swarm is always symmetric.
// Hover to lure it, press to cinch it tight, release to burst it apart.
// -----------------------------------------------------------------------------
class SwarmSim extends VfxSim {
  SwarmSim({super.thumb}) {
    n = thumb ? 260 : 1800;
    x = Float32List(n);
    y = Float32List(n);
    vx = Float32List(n);
    vy = Float32List(n);
    final rng = math.Random(7);
    for (var i = 0; i < n; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final r = math.sqrt(rng.nextDouble()) * 0.22;
      x[i] = 0.3 + math.cos(a) * r * 0.9;
      y[i] = 0.5 + math.sin(a) * r;
    }
    for (var b = 0; b < 3; b++) {
      _buf.add(Float32List(n * 4));
    }
  }

  late final int n;
  late final Float32List x, y, vx, vy;
  final List<Float32List> _buf = [];
  final _cnt = Int32List(3);

  static const List<Color> _colors = [
    Color(0xFFB76E8A),
    Color(0xFFF3B2C8),
    Color(0xFFFFF1D6),
  ];

  @override
  Color get background => const Color(0xFF140B12);

  @override
  void step(double dt, Size size) {
    super.step(dt, size);
    if (size.isEmpty) return;
    dt = dt.clamp(0.0, 1 / 30);
    final ax = 0.3 + 0.08 * math.cos(t * 0.6), ay = 0.5 + 0.18 * math.sin(t * 0.9);
    final cy = 0.5 + 0.22 * math.sin(t * 0.7 + 1);
    final p = pointer;
    final pu = p == null ? 0.0 : p.dx / size.width;
    final pv = p == null ? 0.0 : p.dy / size.height;
    final qu = 1 - pu;
    final damp = math.pow(0.94, dt * 60).toDouble();
    final burst = justReleased && p != null;
    for (var i = 0; i < n; i++) {
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
      final pull = (d - shell) * (pressed ? 30.0 : 16.0);
      final s = (i % 4 < 2 ? 1.4 : -1.4);
      final wob = math.sin(i * 12.9 + t * 3) * 0.4;
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
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF3A1A2C), Color(0xFF140B12)],
          radius: 0.9,
        ).createShader(rect),
    );
    _cnt.fillRange(0, 3, 0);
    for (var i = 0; i < n; i++) {
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
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = thumb ? 1.7 : 2.0;
    for (var b = 0; b < 3; b++) {
      if (_cnt[b] == 0) continue;
      paint.color = _colors[b];
      canvas.drawRawPoints(PointMode.points,
          Float32List.sublistView(_buf[b], 0, _cnt[b] * 4), paint);
    }
  }
}

// -----------------------------------------------------------------------------
// CHROME_SHADER: a jelly chrome knot. Every sample of the tube is a spring
// coupled to its neighbours, so pulling it drags a smooth, wobbly bulge along
// the tube. Mirrored pointer keeps the pull symmetric.
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

  @override
  Color get background => const Color(0xFFFFFFFF);

  @override
  void step(double dt, Size size) {
    super.step(dt, size);
    if (size.isEmpty) return;
    dt = dt.clamp(0.0, 1 / 30);
    final m = math.min(size.width, size.height);
    final reach = m * 0.26;
    final p = pointer;
    final q = p == null ? null : Offset(size.width - p.dx, p.dy);
    const sub = 2;
    final h = dt / sub;
    for (var s = 0; s < sub; s++) {
      for (var k = 0; k < _samples; k++) {
        final cx = _bx[k] + _ox[k], cy = _by[k] + _oy[k];
        final a = (k - 1 + _samples) % _samples, b = (k + 1) % _samples;
        var fx = -40 * _ox[k] - 4.5 * _vx[k] + 180 * (_ox[a] + _ox[b] - 2 * _ox[k]);
        var fy = -40 * _oy[k] - 4.5 * _vy[k] + 180 * (_oy[a] + _oy[b] - 2 * _oy[k]);
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
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, 0.2),
          radius: 0.9,
          colors: [Color(0xFFFFFFFF), Color(0xFFF1F1F4)],
        ).createShader(rect),
    );

    final scale = m * 0.135;
    final cx = w / 2, cy = h / 2;
    final rot = t * 0.45;
    final tilt = 0.5 + 0.15 * math.sin(t * 0.3);
    final cr = math.cos(rot), sr = math.sin(rot);
    final ct = math.cos(tilt), st = math.sin(tilt);

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
      final bx = cx + x1 * scale * persp;
      final by = cy + y1 * scale * persp;
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
    _tube(canvas, back, tube, rect, dim: true);
    _tube(canvas, front, tube, rect, dim: false);
  }

  void _tube(Canvas canvas, Path path, double w, Rect rect, {required bool dim}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const layers = [
      (1.0, Color(0xFF2E3440)),
      (0.86, Color(0xFF6B7280)),
      (0.68, Color(0xFFB8BEC9)),
    ];
    for (final (f, c) in layers) {
      paint
        ..strokeWidth = w * f
        ..color = dim ? Color.lerp(c, const Color(0xFF1F2430), 0.25)! : c;
      canvas.drawPath(path, paint);
    }
    paint
      ..strokeWidth = w * 0.62
      ..color = const Color(0xFFFFFFFF)
      ..shader = const LinearGradient(
        colors: [Color(0x55FF8FC8), Color(0x55B9A6FF), Color(0x5582E9FF)],
      ).createShader(rect);
    canvas.drawPath(path, paint);
    paint
      ..shader = null
      ..strokeWidth = w * 0.42
      ..color = const Color(0xFFEDEFF4);
    canvas.drawPath(path, paint);
    paint
      ..strokeWidth = w * 0.14
      ..color = const Color(0xEEFFFFFF);
    canvas.drawPath(path.shift(Offset(-w * 0.12, -w * 0.12)), paint);
  }
}

// -----------------------------------------------------------------------------
// VOLUMETRIC_FOG: blurred participating media lit by a movable key light.
// -----------------------------------------------------------------------------
class FogSim extends VfxSim {
  FogSim({super.thumb});

  static const List<Color> _puff = [
    Color(0x998B6CF2),
    Color(0x7738C6E8),
    Color(0x77E879B8),
    Color(0x88818CF8),
  ];

  @override
  Color get background => const Color(0xFFF6F4FB);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, m = math.min(w, h);
    if (m <= 0) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7F4FF), Color(0xFFD9CCF5)],
        ).createShader(rect),
    );

    final light = pointer ?? Offset(w * 0.72, h * 0.2);

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
      canvas.drawPath(
        ray,
        Paint()
          ..shader = LinearGradient(
            colors: const [Color(0x88FFFFFF), Color(0x00FFFFFF)],
            begin: Alignment.center,
            end: Alignment(math.cos(a), math.sin(a)),
          ).createShader(Rect.fromCircle(center: light, radius: len)),
      );
    }

    final count = thumb ? 9 : 26;
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final px = w * (0.5 + 0.42 * math.sin(t * 0.08 * (1 + i % 3) + i * 2.1));
      final py = h * (0.58 + 0.28 * math.cos(t * 0.07 * (1 + i % 4) + i * 1.3));
      final r = m * (0.15 + 0.07 * math.sin(i * 1.9));
      final lit = (1 - ((Offset(px, py) - light).distance / (m * 0.9))).clamp(0.0, 1.0);
      final base = _puff[i % _puff.length];
      paint
        ..color = Color.lerp(base, const Color(0xAAFFFFFF), lit * 0.6)!
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.55);
      canvas.drawCircle(Offset(px, py), r, paint);
    }

    final glow = Rect.fromCircle(center: light, radius: m * 0.22);
    canvas.drawCircle(
      light,
      m * 0.22,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xEEFFFFFF), Color(0x00FFFFFF)],
        ).createShader(glow),
    );

    // Dust motes drifting upward through the beam.
    final motes = thumb ? 24 : 90;
    final pts = Float32List(motes * 2);
    for (var i = 0; i < motes; i++) {
      final hx = (math.sin(i * 91.7) * 43758.5453) % 1;
      final hy = (math.sin(i * 27.3) * 12543.123) % 1;
      pts[i * 2] = w * hx.abs() + 6 * math.sin(t + i);
      pts[i * 2 + 1] = h - ((t * 14 * (0.3 + hx.abs()) + hy.abs() * h) % h);
    }
    canvas.drawRawPoints(
      PointMode.points,
      pts,
      Paint()
        ..color = const Color(0xB3FFFFFF)
        ..strokeWidth = thumb ? 1.2 : 1.8
        ..strokeCap = StrokeCap.round,
    );
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

  @override
  Color get background => const Color(0xFF0E3A40);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, m = math.min(w, h);
    if (m <= 0) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B8C8A), Color(0xFF15474D), Color(0xFF0B1F2A)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.5),
      m * 0.46,
      Paint()
        ..color = const Color(0x557C3AED)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, m * 0.12),
    );

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
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (m / 150).clamp(1.1, 2.6);
    for (var b = 0; b < 4; b++) {
      if (_cnt[b] == 0) continue;
      paint.color = _colors[b];
      canvas.drawRawPoints(PointMode.points,
          Float32List.sublistView(_buf[b], 0, _cnt[b] * 2), paint);
    }
  }
}
