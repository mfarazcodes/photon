import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/rendering.dart';

import '../models/sim_params.dart';
import '../models/vfx_dna.dart';

const double _tau = math.pi * 2;

/// Deterministic hash noise in [0, 1) for an integer key.
double _h01(int n) {
  var x = (n * 0x27D4EB2D) & 0xFFFFFFFF;
  x = ((x ^ (x >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF;
  x = ((x ^ (x >> 12)) * 0x297A2D39) & 0xFFFFFFFF;
  x ^= x >> 15;
  return (x & 0xFFFFFF) / 0x1000000;
}

double _fract(double v) => v - v.floorToDouble();

// One colour-matrix paint per channel; `plus` adds the three passes back
// together, so an offset between them shows as chromatic dispersion.
final List<Paint> _channelPaints = [
  for (var c = 0; c < 3; c++)
    Paint()
      ..blendMode = BlendMode.plus
      ..colorFilter = ColorFilter.matrix([
        if (c == 0) ...[1, 0, 0, 0, 0] else ...[0, 0, 0, 0, 0],
        if (c == 1) ...[0, 1, 0, 0, 0] else ...[0, 0, 0, 0, 0],
        if (c == 2) ...[0, 0, 1, 0, 0] else ...[0, 0, 0, 0, 0],
        0, 0, 0, 1, 0,
      ]),
];

/// Paints [scene] three times, once per colour channel, with the red and blue
/// passes pushed [shift] pixels apart.
void paintChannelSplit(Canvas canvas, Rect rect, double shift, void Function() scene) {
  canvas.saveLayer(rect, Paint());
  for (var c = 0; c < 3; c++) {
    canvas.saveLayer(rect, _channelPaints[c]);
    canvas.translate((c - 1) * shift, 0);
    scene();
    canvas.restore();
  }
  canvas.restore();
}

/// Per-frame state shared by every layer of one effect.
class _Frame {
  Size size = Size.zero;
  late SimParams params;
  double t = 0;
  double dt = 0;
  int mode = 0;

  /// Pointer in pixels, null when outside.
  Offset? mouse;
  Offset mouseVel = Offset.zero;
  bool pressed = false;
  bool justPressed = false;
  bool bloom = true;
  bool thumb = false;

  /// Camera shake for this frame, accumulated by layers in [_Layer.prepare].
  Offset shake = Offset.zero;

  double get scale => size.shortestSide;
  Offset get center => Offset(size.width / 2, size.height / 2);
}

/// Perspective camera. World space is y-up; a positive pitch looks down.
class _Proj {
  double _cosY = 1, _sinY = 0, _cosP = 1, _sinP = 0;
  double _dist = 3, _ox = 0, _oy = 0, _scale = 1;

  /// Outputs of [project]: screen position and perspective scale.
  double x = 0, y = 0, k = 1;

  void set({
    required double yaw,
    required double pitch,
    required double dist,
    required Offset center,
    required double scale,
  }) {
    _cosY = math.cos(yaw);
    _sinY = math.sin(yaw);
    _cosP = math.cos(pitch);
    _sinP = math.sin(pitch);
    _dist = dist;
    _ox = center.dx;
    _oy = center.dy;
    _scale = scale;
  }

  void project(double wx, double wy, double wz) {
    final x1 = wx * _cosY + wz * _sinY;
    final z1 = -wx * _sinY + wz * _cosY;
    final y1 = wy * _cosP + z1 * _sinP;
    final z2 = -wy * _sinP + z1 * _cosP;
    final d = _dist + z2;
    k = _dist / (d < 0.2 ? 0.2 : d);
    x = _ox + x1 * k * _scale;
    y = _oy - y1 * k * _scale;
  }
}

/// Points or segments sorted into 3 colours x 3 brightness tiers, so a whole
/// particle field is a handful of `drawRawPoints` calls instead of thousands.
class _Buckets {
  _Buckets(this.capacity, {required this.lines})
      : stride = lines ? 4 : 2,
        _data = [for (var i = 0; i < 9; i++) Float32List(capacity * (lines ? 4 : 2))],
        counts = Int32List(9);

  final int capacity;
  final bool lines;
  final int stride;
  final List<Float32List> _data;
  final Int32List counts;

  void clear() => counts.fillRange(0, 9, 0);

  void line(int ci, int tier, double x0, double y0, double x1, double y1) {
    final b = ci * 3 + tier;
    final n = counts[b];
    if (n >= capacity) return;
    final d = _data[b], o = n * 4;
    d[o] = x0;
    d[o + 1] = y0;
    d[o + 2] = x1;
    d[o + 3] = y1;
    counts[b] = n + 1;
  }

  void point(int ci, int tier, double x, double y) {
    final b = ci * 3 + tier;
    final n = counts[b];
    if (n >= capacity) return;
    final d = _data[b], o = n * 2;
    d[o] = x;
    d[o + 1] = y;
    counts[b] = n + 1;
  }

  void draw(
    Canvas canvas,
    Paint paint,
    List<Color> colors,
    List<double> alphas,
    double weight, {
    int minTier = 0,
    List<double>? widths,
  }) {
    final mode = lines ? PointMode.lines : PointMode.points;
    for (var b = 0; b < 9; b++) {
      final n = counts[b], tier = b % 3;
      if (n == 0 || tier < minTier) continue;
      paint.color = colors[b ~/ 3].withValues(alpha: (alphas[tier] * weight).clamp(0.0, 1.0));
      if (widths != null) paint.strokeWidth = widths[tier];
      canvas.drawRawPoints(mode, Float32List.sublistView(_data[b], 0, n * stride), paint);
    }
  }
}

/// One physics / emitter primitive of an effect.
abstract class _Layer {
  _Layer(this.dna, this.f, int seed) : rng = math.Random(seed);

  final VfxDna dna;
  final _Frame f;
  final math.Random rng;

  /// 1 for the primary layer, lower for supporting layers.
  double weight = 1;

  List<Color> get col => dna.colors;
  double get glow => dna.glow * weight;

  /// Called at the start of every paint, before the camera shake is applied.
  void prepare() {}

  /// Advances stateful simulation by [_Frame.dt].
  void step() {}

  void paint(Canvas canvas);
}

// -----------------------------------------------------------------------------
// 1. Metaball fluid: glossy blobs on springs with surface tension. Blurred
// circles are thresholded through a colour matrix so neighbours fuse into one
// body and pull out into tendrils; each lobe then gets a lit gradient, a
// specular glint that follows the cursor and a two-tone rim light.
// -----------------------------------------------------------------------------
class _MetaballLayer extends _Layer {
  _MetaballLayer(super.dna, super.f, super.seed) {
    for (var i = 0; i < n; i++) {
      r[i] = (0.085 + 0.075 * rng.nextDouble()) * (f.thumb ? 1.35 : 1.0);
      ph[i] = rng.nextDouble();
      ph2[i] = rng.nextDouble();
      mix[i] = rng.nextDouble();
      grow[i] = 1;
      final h = _home(i, 0, dna.emitterFor(0));
      x[i] = h.dx;
      y[i] = h.dy;
    }
  }

  late final int n = f.thumb ? 14 : 30;
  late final Float64List x = Float64List(n), y = Float64List(n);
  late final Float64List vx = Float64List(n), vy = Float64List(n);
  late final Float64List fx = Float64List(n), fy = Float64List(n);
  late final Float64List r = Float64List(n), grow = Float64List(n);
  late final Float64List ph = Float64List(n), ph2 = Float64List(n), mix = Float64List(n);
  late final Float64List px = Float64List(n), py = Float64List(n), rr = Float64List(n);

  final Paint _goo = Paint()
    ..colorFilter = const ColorFilter.matrix(<double>[
      1, 0, 0, 0, 0, //
      0, 1, 0, 0, 0,
      0, 0, 1, 0, 0,
      0, 0, 0, 16, -6,
    ]);
  final Paint _blob = Paint();
  final Paint _strand = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _glowPaint = Paint()..blendMode = BlendMode.plus;
  final Paint _shade = Paint();
  final Paint _rim = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;
  final Paint _spec = Paint();

  /// Target position of blob [i] in unit space (y down) for emitter shape [e].
  Offset _home(int i, double t, VfxEmitter e) {
    switch (e) {
      case VfxEmitter.sphere:
        final a = i * 2.39996 + t * 0.25;
        final rad = math.sqrt((i + 0.5) / n) * 0.62;
        return Offset(math.cos(a) * rad, math.sin(a) * rad * 0.92);
      case VfxEmitter.ring:
        final a = i / n * _tau + t * 0.35;
        final rad = 0.6 + 0.04 * math.sin(t * 2 + i);
        return Offset(math.cos(a) * rad, math.sin(a) * rad);
      case VfxEmitter.point:
        // Ballistic fountain: every blob loops through its own arc.
        final p = _fract(t * 0.38 + i / n);
        return Offset(
          (ph[i] - 0.5) * 1.7 * p,
          0.5 - 3.0 * p * (1 - p) * (0.4 + 0.6 * ph2[i]),
        );
      case VfxEmitter.line:
        return Offset(
          -0.85 + 1.7 * i / (n - 1),
          0.2 * math.sin(i * 0.9 + t * 1.6),
        );
      case VfxEmitter.plane:
        return Offset(
          ((i % 6) - 2.5) * 0.3,
          ((i ~/ 6) - 2) * 0.27 + 0.05 * math.sin(t * 1.5 + i),
        );
    }
  }

  @override
  void step() {
    final dt = f.dt.clamp(0.0, 0.05);
    if (dt <= 0) return;
    final p = f.params;
    final t = f.t;
    final e = dna.emitterFor(f.mode);
    final active = math.max(4, (n * (0.5 + 0.5 * p.density)).round());
    final stiff = 9.0 + 9.0 * p.coherence;
    final cohesion = 2.0 + 7.0 * p.coherence;
    final turb = p.turbulence * (dna.denoise ? 0.6 : 1.0);
    final unit = f.scale * 0.42;
    final c = f.center;
    final ms = f.mouse;
    final m = ms == null ? null : Offset((ms.dx - c.dx) / unit, (ms.dy - c.dy) / unit);

    for (var i = 0; i < n; i++) {
      grow[i] += ((i < active ? 1.0 : 0.0) - grow[i]) * math.min(1.0, dt * 3);
      final h = _home(i, t, e);
      fx[i] = (h.dx - x[i]) * stiff - vx[i] * 3.4 +
          math.sin(t * 1.3 + i * 1.7 + y[i] * 3.1) * turb * 2.0;
      fy[i] = (h.dy - y[i]) * stiff - vy[i] * 3.4 - dna.buoyancy * 0.6 +
          math.cos(t * 1.1 + i * 2.3 + x[i] * 2.7) * turb * 2.0;
    }
    // Surface tension: blobs repel when overlapping and cling at mid range.
    for (var i = 0; i < n; i++) {
      if (grow[i] < 0.05) continue;
      for (var j = i + 1; j < n; j++) {
        if (grow[j] < 0.05) continue;
        final dx = x[j] - x[i], dy = y[j] - y[i];
        final d2 = dx * dx + dy * dy;
        final rest = (r[i] * grow[i] + r[j] * grow[j]) * 0.85;
        final reach = rest * 2.4;
        if (d2 >= reach * reach || d2 < 1e-8) continue;
        final d = math.sqrt(d2);
        final mag = d < rest
            ? -(rest - d) * 22
            : (d - rest) * cohesion * (1 - (d - rest) / (reach - rest));
        final ux = dx / d, uy = dy / d;
        fx[i] += ux * mag;
        fy[i] += uy * mag;
        fx[j] -= ux * mag;
        fy[j] -= uy * mag;
      }
    }
    for (var i = 0; i < n; i++) {
      if (m != null) {
        final dx = x[i] - m.dx, dy = y[i] - m.dy;
        final d = math.sqrt(dx * dx + dy * dy) + 1e-6;
        const reach = 0.42;
        if (d < reach) {
          final s = 1 - d / reach;
          // The cursor repels; holding the button grabs instead.
          final push = s * s * (f.pressed ? -26.0 : 11.0);
          fx[i] += dx / d * push;
          fy[i] += dy / d * push;
        }
      }
      vx[i] = (vx[i] + fx[i] * dt).clamp(-6.0, 6.0);
      vy[i] = (vy[i] + fy[i] * dt).clamp(-6.0, 6.0);
      x[i] = (x[i] + vx[i] * dt).clamp(-1.5, 1.5);
      y[i] = (y[i] + vy[i] * dt).clamp(-1.5, 1.5);
    }
  }

  @override
  void paint(Canvas canvas) {
    final rect = Offset.zero & f.size;
    final unit = f.scale * 0.42;
    final c = f.center;
    final c0 = col[0], c1 = col[1], c2 = col[2];
    for (var i = 0; i < n; i++) {
      px[i] = c.dx + x[i] * unit;
      py[i] = c.dy + y[i] * unit;
      rr[i] = grow[i] < 0.03 ? 0 : r[i] * unit * grow[i];
    }

    if (f.bloom) {
      for (var i = 0; i < n; i++) {
        if (rr[i] < 0.5) continue;
        _glowPaint
          ..color = c0.withValues(alpha: (0.16 * glow).clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, rr[i] * 0.9);
        canvas.drawCircle(Offset(px[i], py[i]), rr[i] * 1.7, _glowPaint);
      }
    }

    // Fused body: blur, then threshold the alpha.
    canvas.saveLayer(rect, _goo);
    for (var i = 0; i < n; i++) {
      if (rr[i] < 0.5) continue;
      _blob
        ..color = Color.lerp(c0, c1, mix[i])!.withValues(alpha: weight.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rr[i] * 0.42);
      canvas.drawCircle(Offset(px[i], py[i]), rr[i] * 1.12, _blob);
    }
    for (var i = 0; i < n; i++) {
      if (rr[i] < 0.5) continue;
      for (var j = i + 1; j < n; j++) {
        if (rr[j] < 0.5) continue;
        final dx = px[j] - px[i], dy = py[j] - py[i];
        final reach = (rr[i] + rr[j]) * 1.7;
        final d2 = dx * dx + dy * dy;
        if (d2 >= reach * reach) continue;
        final w = 1 - math.sqrt(d2) / reach;
        final thin = math.min(rr[i], rr[j]);
        _strand
          ..color = Color.lerp(c0, c1, (mix[i] + mix[j]) / 2)!.withValues(alpha: weight.clamp(0.0, 1.0))
          ..strokeWidth = thin * 1.6 * w
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, thin * 0.3);
        canvas.drawLine(Offset(px[i], py[i]), Offset(px[j], py[j]), _strand);
      }
    }
    canvas.restore();

    // Lighting on each lobe.
    final mouse = f.mouse;
    for (var i = 0; i < n; i++) {
      if (rr[i] < 0.5) continue;
      final cpt = Offset(px[i], py[i]);
      final r0 = rr[i] * 0.95;
      var lx = -0.55, ly = -0.6;
      if (mouse != null) {
        final dx = mouse.dx - cpt.dx, dy = mouse.dy - cpt.dy;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist > 1) {
          lx = lx * 0.5 + dx / dist * 0.45;
          ly = ly * 0.5 + dy / dist * 0.45;
        }
      }
      final base = Color.lerp(c0, c1, mix[i])!;
      final hi = Color.lerp(base, const Color(0xFFFFFFFF), 0.55)!;
      final lo = Color.lerp(base, dna.background, 0.65)!;
      _shade.shader = RadialGradient(
        center: Alignment(lx * 0.55, ly * 0.55),
        radius: 0.95,
        colors: [
          hi.withValues(alpha: 0.85 * weight),
          base.withValues(alpha: 0.35 * weight),
          lo.withValues(alpha: 0.75 * weight),
        ],
        stops: const [0, 0.5, 1],
      ).createShader(Rect.fromCircle(center: cpt, radius: r0));
      canvas.drawCircle(cpt, r0, _shade);

      // Two-tone rim: the cool accent all round, the hot colour toward the light.
      _rim
        ..strokeWidth = r0 * 0.12
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r0 * 0.05)
        ..color = c2.withValues(alpha: (0.55 * glow).clamp(0.0, 1.0));
      canvas.drawCircle(cpt, r0 * 0.93, _rim);
      _rim.color = c0.withValues(alpha: (0.4 * glow).clamp(0.0, 1.0));
      canvas.drawCircle(cpt + Offset(lx, ly) * (r0 * 0.07), r0 * 0.93, _rim);

      _spec
        ..color = Color.fromRGBO(255, 255, 255, 0.6 * weight)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r0 * 0.06);
      canvas.save();
      canvas.translate(cpt.dx + lx * r0 * 0.5, cpt.dy + ly * r0 * 0.5);
      canvas.rotate(math.atan2(ly, lx) + math.pi / 2);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r0 * 0.5, height: r0 * 0.28), _spec);
      canvas.restore();
    }
  }
}

// -----------------------------------------------------------------------------
// 2. Curl particle flow: thousands of 3D particles advected through a
// divergence-free curl-noise field. Each is drawn as a streak along its
// velocity, so the field shows up as glowing flow lines.
// -----------------------------------------------------------------------------
class _CurlLayer extends _Layer {
  _CurlLayer(super.dna, super.f, super.seed) {
    final e = dna.emitterFor(f.mode);
    for (var i = 0; i < cap; i++) {
      final q = rng.nextDouble();
      ci[i] = q < 0.5 ? 0 : (q < 0.85 ? 1 : 2);
      _spawn(i, e);
    }
    // Pre-warm so the field is already full of streams when the view opens.
    for (var s = 0; s < 40; s++) {
      _advance(0.06, f.t - 2.4 + s * 0.06);
    }
  }

  late final int cap = ((f.thumb ? 520 : 3400) * dna.detail).round();
  late final Float32List x = Float32List(cap), y = Float32List(cap), z = Float32List(cap);
  late final Float32List vx = Float32List(cap), vy = Float32List(cap), vz = Float32List(cap);
  late final Float32List age = Float32List(cap), life = Float32List(cap);
  late final Uint8List ci = Uint8List(cap);
  late final _Buckets lines = _Buckets(cap, lines: true);
  late final List<Color> _hot = [for (final c in col) Color.lerp(c, const Color(0xFFFFFFFF), 0.7)!];
  final _Proj proj = _Proj();
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _bloomLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  void _spawn(int i, VfxEmitter e) {
    life[i] = 1.6 + 2.8 * rng.nextDouble();
    age[i] = 0;
    vx[i] = 0;
    vy[i] = 0;
    vz[i] = 0;
    switch (e) {
      case VfxEmitter.point:
        final a = rng.nextDouble() * _tau, b = rng.nextDouble() * 2 - 1;
        final s = math.sqrt(1 - b * b);
        x[i] = math.cos(a) * s * 0.05;
        y[i] = b * 0.05;
        z[i] = math.sin(a) * s * 0.05;
        vx[i] = math.cos(a) * s * 0.9;
        vy[i] = b * 0.9;
        vz[i] = math.sin(a) * s * 0.9;
      case VfxEmitter.ring:
        final a = rng.nextDouble() * _tau;
        final rad = 0.55 + 0.06 * (rng.nextDouble() - 0.5);
        x[i] = math.cos(a) * rad;
        y[i] = (rng.nextDouble() - 0.5) * 0.08;
        z[i] = math.sin(a) * rad;
      case VfxEmitter.sphere:
        final a = rng.nextDouble() * _tau, b = rng.nextDouble() * 2 - 1;
        final s = math.sqrt(1 - b * b), rad = 0.5 * (0.8 + 0.2 * rng.nextDouble());
        x[i] = math.cos(a) * s * rad;
        y[i] = b * rad;
        z[i] = math.sin(a) * s * rad;
      case VfxEmitter.line:
        x[i] = -0.9 + 1.8 * rng.nextDouble();
        y[i] = -0.65;
        z[i] = (rng.nextDouble() - 0.5) * 0.3;
      case VfxEmitter.plane:
        x[i] = (rng.nextDouble() - 0.5) * 1.9;
        y[i] = -0.6;
        z[i] = (rng.nextDouble() - 0.5) * 1.9;
    }
  }

  void _advance(double dt, double t) {
    final p = f.params;
    final e = dna.emitterFor(f.mode);
    final active = (cap * (0.35 + 0.65 * p.density)).round();
    final amp = 0.45 + 1.1 * p.turbulence * (dna.denoise ? 0.75 : 1.0);
    final swirl = p.coherence;
    // Low coherence means a finer, busier field.
    final k = 1.7 + (1 - p.coherence) * 1.3;
    final k7 = k * 0.7;
    final a = t * 0.35, b = t * 0.27, c = t * 0.31;
    final follow = math.min(1.0, dt * 2.8);

    double? mx, my;
    final ms = f.mouse;
    if (ms != null && f.size.shortestSide > 0) {
      final unit = f.scale * 0.5 * 0.95;
      mx = (ms.dx - f.center.dx) / unit;
      my = (f.center.dy - ms.dy) / unit;
    }

    for (var i = 0; i < active; i++) {
      age[i] += dt;
      final px = x[i], py = y[i], pz = z[i];
      if (age[i] > life[i] || px.abs() > 1.8 || py.abs() > 1.6 || pz.abs() > 1.8) {
        _spawn(i, e);
        continue;
      }
      // Curl of the vector potential A = (sin(ky+a)cos(.7kz-b),
      // sin(kz+c)cos(.7kx+a), sin(kx+b)cos(.7ky-c)).
      final sya = math.sin(k * py + a), cya = math.cos(k * py + a);
      final szb = math.sin(k7 * pz - b), czb = math.cos(k7 * pz - b);
      final szc = math.sin(k * pz + c), czc = math.cos(k * pz + c);
      final sxa = math.sin(k7 * px + a), cxa = math.cos(k7 * px + a);
      final sxb = math.sin(k * px + b), cxb = math.cos(k * px + b);
      final syc = math.sin(k7 * py - c), cyc = math.cos(k7 * py - c);
      var tx = (sxb * -syc * 0.7 - czc * cxa) * amp;
      var ty = (sya * -szb * 0.7 - cxb * cyc) * amp;
      var tz = (szc * -sxa * 0.7 - cya * czb) * amp;
      // Coherence winds the whole field into one rotation about the y axis.
      tx += -pz * 0.6 * swirl;
      tz += px * 0.6 * swirl;
      ty += dna.buoyancy * 0.45;

      final m1 = mx, m2 = my;
      if (m1 != null && m2 != null) {
        final dx = px - m1, dy = py - m2;
        final d = math.sqrt(dx * dx + dy * dy + pz * pz * 0.5) + 1e-6;
        if (d < 0.3) {
          final s = 1 - d / 0.3;
          final push = s * s * (f.pressed ? -2.2 : 1.6);
          tx += dx / d * push * 3;
          ty += dy / d * push * 3;
          tz += pz / d * push * 3;
        }
      }
      vx[i] += (tx - vx[i]) * follow;
      vy[i] += (ty - vy[i]) * follow;
      vz[i] += (tz - vz[i]) * follow;
      x[i] = px + vx[i] * dt;
      y[i] = py + vy[i] * dt;
      z[i] = pz + vz[i] * dt;
    }
  }

  @override
  void step() {
    final dt = f.dt.clamp(0.0, 0.05);
    if (dt > 0) _advance(dt, f.t);
  }

  @override
  void paint(Canvas canvas) {
    final t = f.t;
    final ms = f.mouse;
    final nx = ms == null ? 0.0 : (ms.dx / f.size.width - 0.5);
    final ny = ms == null ? 0.0 : (ms.dy / f.size.height - 0.5);
    proj.set(
      yaw: 0.35 * math.sin(t * 0.12) + nx * 0.4,
      pitch: 0.22 + ny * 0.2,
      dist: 3.2,
      center: f.center,
      scale: f.scale * 0.5 * 0.95,
    );
    final active = (cap * (0.35 + 0.65 * f.params.density)).round();
    final trail = dna.has(VfxFx.motionTrails) ? 0.22 : 0.09;
    lines.clear();
    for (var i = 0; i < active; i++) {
      final a = math.sin(math.pi * (age[i] / life[i]).clamp(0.0, 1.0));
      final tier = a < 0.35 ? 0 : (a < 0.7 ? 1 : 2);
      proj.project(x[i], y[i], z[i]);
      final hx = proj.x, hy = proj.y;
      proj.project(x[i] - vx[i] * trail, y[i] - vy[i] * trail, z[i] - vz[i] * trail);
      lines.line(ci[i], tier, hx, hy, proj.x, proj.y);
    }
    final w = weight;
    _line
      ..blendMode = f.bloom ? BlendMode.plus : BlendMode.srcOver
      ..strokeWidth = f.thumb ? 1.0 : 1.5;
    lines.draw(canvas, _line, col, const [0.25, 0.55, 0.95], w);
    _line.strokeWidth = f.thumb ? 0.6 : 0.8;
    lines.draw(canvas, _line, _hot, const [0, 0, 0.9], w, minTier: 2);
    if (f.bloom && !f.thumb) {
      _bloomLine
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      lines.draw(canvas, _bloomLine, col, [0, 0.07 * dna.glow, 0.15 * dna.glow], w, minTier: 1);
    }
  }
}

// -----------------------------------------------------------------------------
// 3. Shockwave rings: expanding energy rings with a chromatic-split edge,
// radial debris, a birth flash and camera shake. Fully analytic in time, so
// scrubbing the timeline re-poses it. Clicking fires an extra ring.
// -----------------------------------------------------------------------------
class _ShockLayer extends _Layer {
  _ShockLayer(super.dna, super.f, super.seed);

  static const double _life = 3.4;
  static const double _interval = 2.1;

  final List<({double birth, Offset pos})> _clicks = [];
  late final int _debrisPer = f.thumb ? 26 : 110;
  late final _Buckets _debris = _Buckets(_debrisPer * 8, lines: false);
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;
  final Paint _fill = Paint()..blendMode = BlendMode.plus;
  final Paint _pts = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  List<({double birth, Offset pos, int id})> _active(double t) {
    final out = <({double birth, Offset pos, int id})>[];
    final kMin = math.max(0, ((t - _life) / _interval).floor());
    final kMax = (t / _interval).floor();
    // The scheduled rings drift toward the cursor, a little, for parallax.
    final m = f.mouse;
    final origin = m == null ? f.center : f.center + (m - f.center) * 0.12;
    for (var k = kMin; k <= kMax; k++) {
      final birth = k * _interval;
      if (t - birth >= _life) continue;
      final jx = (_h01(k * 31 + dna.hash % 997) - 0.5) * f.scale * 0.14;
      final jy = (_h01(k * 57 + dna.hash % 991) - 0.5) * f.scale * 0.1;
      out.add((birth: birth, pos: origin.translate(jx, jy), id: k));
    }
    for (var i = 0; i < _clicks.length; i++) {
      final c = _clicks[i];
      if (t - c.birth >= 0 && t - c.birth < _life) {
        out.add((birth: c.birth, pos: c.pos, id: 100000 + i));
      }
    }
    return out;
  }

  @override
  void step() {
    final m = f.mouse;
    if (f.justPressed && m != null) _clicks.add((birth: f.t, pos: m));
    _clicks.removeWhere((c) => f.t - c.birth > _life + 0.2 || c.birth > f.t + 0.1);
  }

  @override
  void prepare() {
    if (f.thumb) return;
    final amp = f.scale * 0.013 * (0.5 + f.params.turbulence);
    var sx = 0.0, sy = 0.0;
    for (final r in _active(f.t)) {
      final age = f.t - r.birth;
      if (age > 0.9) continue;
      final a = amp * math.exp(-age * 6.5);
      sx += math.sin(age * 95 + r.id) * a;
      sy += math.cos(age * 83 + r.id * 2) * a;
    }
    f.shake += Offset(sx, sy) * weight;
  }

  @override
  void paint(Canvas canvas) {
    final t = f.t;
    _debris.clear();
    for (final r in _active(t)) {
      _ring(canvas, t - r.birth, r.pos, r.id);
    }
    _debris.draw(
      canvas,
      _pts,
      col,
      const [0.35, 0.7, 1.0],
      weight,
      widths: f.thumb ? const [1.0, 1.4, 1.8] : const [1.2, 1.8, 2.4],
    );
  }

  void _ring(Canvas canvas, double age, Offset pos, int id) {
    final u = age / _life;
    final fade = math.pow(1 - u, 1.6).toDouble();
    final radius = f.scale * 0.82 * (1 - math.exp(-age * 1.9));
    final g = glow;

    if (age < 1.2) {
      final e = math.exp(-age * 3.8) * g;
      final rad = f.scale * (0.12 + 0.5 * age);
      _fill.shader = RadialGradient(colors: [
        Color.fromRGBO(255, 255, 255, (0.9 * e).clamp(0.0, 1.0)),
        col[0].withValues(alpha: (0.5 * e).clamp(0.0, 1.0)),
        col[0].withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: pos, radius: rad));
      canvas.drawCircle(pos, rad, _fill);
    }
    if (radius < 1) return;

    // Mode 0 faces the camera, mode 1 lies flat like a ground shockwave, and
    // mode 2 nests a tilted echo ring inside a face-on one.
    final flats = switch (f.mode) {
      0 => const [1.0],
      1 => const [0.34],
      _ => const [1.0, 0.34],
    };
    final w = f.scale * (0.010 + 0.045 * u) * (dna.has(VfxFx.motionTrails) ? 1.4 : 1.0);
    final disp = 0.012 + 0.03 * f.params.dispersion;
    for (var i = 0; i < flats.length; i++) {
      _oval(canvas, pos, i == 0 ? radius : radius * 0.7, flats[i], w, fade, disp);
    }
    final flat = flats.first;

    final tier = fade > 0.6 ? 2 : (fade > 0.3 ? 1 : 0);
    // Density thins the debris out; turbulence scatters it further from the front.
    final debris = (_debrisPer * (0.3 + 0.7 * f.params.density)).round();
    final scatter = 0.15 + 0.5 * f.params.turbulence;
    for (var j = 0; j < debris; j++) {
      final a = _h01(id * 977 + j * 13 + 5) * _tau;
      final rad = radius * (0.9 + scatter * _h01(id * 131 + j * 7));
      final fall = age * age * f.scale * 0.05 * (0.4 + _h01(j + id)) * (1 - dna.buoyancy * 1.2);
      _debris.point(
        j % 3,
        tier,
        pos.dx + math.cos(a) * rad,
        pos.dy + math.sin(a) * rad * flat + fall,
      );
    }
  }

  /// One ring front: a blurred glow, a chromatic-split edge and a faint
  /// refractive band. [flat] is the vertical squash (1 = facing the camera).
  void _oval(Canvas canvas, Offset pos, double radius, double flat, double w, double fade, double disp) {
    final ry = radius * flat;
    if (f.bloom) {
      _stroke
        ..strokeWidth = w * 3.4
        ..blendMode = BlendMode.plus
        ..color = col[1].withValues(alpha: (0.30 * fade * glow).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 1.3);
      canvas.drawOval(Rect.fromCenter(center: pos, width: radius * 2, height: ry * 2), _stroke);
    }
    _stroke
      ..maskFilter = null
      ..blendMode = BlendMode.plus;
    // Hot colour outermost, accent innermost.
    for (var ch = 0; ch < 3; ch++) {
      final s = 1 + (1 - ch) * disp;
      _stroke
        ..strokeWidth = w * (ch == 1 ? 1.0 : 0.75)
        ..color = col[ch].withValues(alpha: (0.85 * fade * weight).clamp(0.0, 1.0));
      canvas.drawOval(Rect.fromCenter(center: pos, width: radius * 2 * s, height: ry * 2 * s), _stroke);
    }
    _stroke
      ..strokeWidth = w * 5
      ..color = Color.fromRGBO(255, 255, 255, 0.04 * fade * weight);
    canvas.drawOval(Rect.fromCenter(center: pos, width: radius * 2, height: ry * 2), _stroke);
  }
}

// -----------------------------------------------------------------------------
// 4. Neural plexus: nodes orbiting in 3D, linked by laser filaments whose
// brightness follows distance, with data pulses running along the strongest
// links. Nodes near the cursor throw filaments to it.
// -----------------------------------------------------------------------------
class _PlexusLayer extends _Layer {
  _PlexusLayer(super.dna, super.f, super.seed) {
    final dir = (dna.hash & 2) == 0 ? 1.0 : -1.0;
    for (var i = 0; i < n; i++) {
      hr[i] = rng.nextDouble();
      hi[i] = rng.nextDouble();
      hz[i] = rng.nextDouble();
      phi0[i] = rng.nextDouble() * _tau;
      omega[i] = dir * (0.12 + 0.3 * rng.nextDouble());
      rho[i] = 0.35 + 0.45 * hr[i];
      incl[i] = math.pi * hi[i];
      tz[i] = math.pi * hz[i];
      grow[i] = 1;
    }
  }

  late final int n = ((f.thumb ? 22 : 70) * dna.detail).round();
  late final Float64List hr = Float64List(n), hi = Float64List(n), hz = Float64List(n);
  late final Float64List phi0 = Float64List(n), omega = Float64List(n);
  late final Float64List rho = Float64List(n), incl = Float64List(n), tz = Float64List(n);
  late final Float64List grow = Float64List(n);
  late final Float64List px = Float64List(n), py = Float64List(n), pz = Float64List(n);
  late final Float64List sx = Float64List(n), sy = Float64List(n), sk = Float64List(n);
  double _ys = 1, _zs = 1, _thr = 0.45;
  late final _Buckets edges = _Buckets(n * (n - 1) ~/ 2 + n, lines: true);
  late final _Buckets pulses = _Buckets(n * 3, lines: false);
  late final _Buckets nodes = _Buckets(n, lines: false);
  final _Proj proj = _Proj();
  final Paint _p = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _bloomPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  @override
  void step() {
    final dt = f.dt.clamp(0.0, 0.05);
    if (dt <= 0) return;
    final p = f.params;
    final active = math.max(6, (n * (0.45 + 0.55 * p.density)).round());
    final (lo, hiR, im, tzm, ysT, zsT) = switch (dna.emitterFor(f.mode)) {
      VfxEmitter.sphere => (0.35, 0.8, math.pi, math.pi, 1.0, 1.0),
      VfxEmitter.ring => (0.55, 0.8, 0.3, 0.25, 1.0, 1.0),
      VfxEmitter.point => (0.08, 0.42, math.pi, math.pi, 1.0, 1.0),
      VfxEmitter.line => (0.25, 0.85, math.pi, math.pi, 0.22, 0.5),
      VfxEmitter.plane => (0.3, 0.9, 0.12, 0.15, 0.6, 1.0),
    };
    final k = math.min(1.0, dt * 2.2);
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      rho[i] += (lo + (hiR - lo) * hr[i] - rho[i]) * k;
      incl[i] += (im * hi[i] - incl[i]) * k;
      tz[i] += (tzm * hz[i] - tz[i]) * k;
      grow[i] += ((i < active ? 1.0 : 0.0) - grow[i]) * math.min(1.0, dt * 3);
      sum += rho[i];
    }
    _ys += (ysT - _ys) * k;
    _zs += (zsT - _zs) * k;
    // Filaments reach as far as the cloud is wide.
    _thr = (0.30 + 0.28 * p.coherence) * (sum / n / 0.55).clamp(0.45, 1.2);
  }

  @override
  void paint(Canvas canvas) {
    final t = f.t;
    final p = f.params;
    final jit = 0.035 * p.turbulence * (dna.denoise ? 0.5 : 1.0);
    for (var i = 0; i < n; i++) {
      final phi = phi0[i] + omega[i] * t;
      final cx = rho[i] * math.cos(phi), cz = rho[i] * math.sin(phi);
      final si = math.sin(incl[i]), ci = math.cos(incl[i]);
      final y1 = -cz * si, z1 = cz * ci;
      final ts = math.sin(tz[i]), tc = math.cos(tz[i]);
      px[i] = cx * tc - y1 * ts + jit * math.sin(t * 1.7 + i * 2.1);
      py[i] = (cx * ts + y1 * tc) * _ys + jit * math.cos(t * 1.3 + i * 1.9);
      pz[i] = z1 * _zs + jit * math.sin(t * 1.1 + i * 3.1);
    }
    final ms = f.mouse;
    final nx = ms == null ? 0.0 : (ms.dx / f.size.width - 0.5);
    final ny = ms == null ? 0.0 : (ms.dy / f.size.height - 0.5);
    proj.set(
      yaw: t * 0.18 + nx * 0.6,
      pitch: 0.35 + 0.1 * math.sin(t * 0.2) + ny * 0.3,
      dist: 3.0,
      center: f.center,
      scale: f.scale * 0.5 * 0.95,
    );
    for (var i = 0; i < n; i++) {
      proj.project(px[i], py[i], pz[i]);
      sx[i] = proj.x;
      sy[i] = proj.y;
      sk[i] = proj.k;
    }

    edges.clear();
    pulses.clear();
    nodes.clear();
    final thr2 = _thr * _thr;
    for (var i = 0; i < n; i++) {
      if (grow[i] < 0.3) continue;
      for (var j = i + 1; j < n; j++) {
        if (grow[j] < 0.3) continue;
        final dx = px[j] - px[i], dy = py[j] - py[i], dz = pz[j] - pz[i];
        final d2 = dx * dx + dy * dy + dz * dz;
        if (d2 >= thr2) continue;
        final ratio = math.sqrt(d2) / _thr;
        final tier = ratio < 0.45 ? 2 : (ratio < 0.75 ? 1 : 0);
        edges.line(2 - tier, tier, sx[i], sy[i], sx[j], sy[j]);
        if (tier >= 1 && (i * 31 + j * 17) % 5 == 0) {
          final ph = _fract(t * 0.5 + _h01(i * 131 + j));
          pulses.point(0, 2, sx[i] + (sx[j] - sx[i]) * ph, sy[i] + (sy[j] - sy[i]) * ph);
        }
      }
      if (ms != null) {
        // Holding the button throws filaments from much further away.
        final reach = f.scale * (f.pressed ? 0.55 : 0.3);
        final dx = sx[i] - ms.dx, dy = sy[i] - ms.dy;
        if (dx * dx + dy * dy < reach * reach) {
          edges.line(0, 2, sx[i], sy[i], ms.dx, ms.dy);
        }
      }
      final tier = sk[i] < 0.85 ? 0 : (sk[i] < 1.1 ? 1 : 2);
      nodes.point(i % 3, tier, sx[i], sy[i]);
    }

    final w = weight;
    final s = f.thumb ? 0.5 : 1.0;
    _p
      ..blendMode = f.bloom ? BlendMode.plus : BlendMode.srcOver
      ..strokeWidth = (f.thumb ? 0.8 : 1.1);
    edges.draw(canvas, _p, col, const [0.22, 0.45, 0.85], w);
    pulses.draw(canvas, _p, col, const [0, 0, 1.0], w, widths: [3 * s, 3 * s, 4 * s]);
    nodes.draw(canvas, _p, col, const [0.55, 0.8, 1.0], w, widths: [3 * s, 5 * s, 7 * s]);
    if (f.bloom && !f.thumb) {
      _bloomPaint
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      edges.draw(canvas, _bloomPaint, col, [0, 0.10 * dna.glow, 0.22 * dna.glow], w, minTier: 1);
      nodes.draw(canvas, _bloomPaint, col, [0.12 * dna.glow, 0.2 * dna.glow, 0.32 * dna.glow], w,
          widths: const [10, 16, 22]);
    }
  }
}

// -----------------------------------------------------------------------------
// 5. Vortex attractor: matter on logarithmic spiral arms falls into a glowing
// singularity. Analytic in time. The core follows the cursor; holding the
// button makes it collapse harder.
// -----------------------------------------------------------------------------
class _VortexLayer extends _Layer {
  _VortexLayer(super.dna, super.f, super.seed) {
    for (var i = 0; i < n; i++) {
      th0[i] = (i % arms) / arms * _tau + (rng.nextDouble() - 0.5) * 0.55;
      ph[i] = rng.nextDouble();
      rate[i] = 0.06 + 0.05 * rng.nextDouble();
      zj[i] = rng.nextDouble() * 2 - 1;
    }
  }

  static const double _outer = 1.25;
  static const double _inner = 0.045;

  late final int n = ((f.thumb ? 380 : 2300) * dna.detail).round();
  late final int arms = 2 + (dna.hash >> 4) % 3;
  late final double dir = (dna.hash & 1) == 0 ? 1.0 : -1.0;
  late final Float64List th0 = Float64List(n), ph = Float64List(n);
  late final Float64List rate = Float64List(n), zj = Float64List(n);
  late final _Buckets lines = _Buckets(n, lines: true);
  late final List<Color> _hot = [for (final c in col) Color.lerp(c, const Color(0xFFFFFFFF), 0.7)!];
  final _Proj proj = _Proj();
  Offset _core = Offset.zero;
  double _pull = 0;
  double _wx = 0, _wy = 0, _wz = 0, _wr = 0;
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _bloomLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;
  final Paint _fill = Paint()..blendMode = BlendMode.plus;

  @override
  void step() {
    final dt = f.dt.clamp(0.0, 0.05);
    if (dt <= 0) return;
    final ms = f.mouse;
    final unit = f.scale * 0.5 * 0.95;
    final target = ms == null
        ? Offset.zero
        : Offset((ms.dx - f.center.dx) / unit, (ms.dy - f.center.dy) / unit) * 0.55;
    _core += (target - _core) * math.min(1.0, dt * 4);
    _pull += ((f.pressed ? 1.0 : 0.0) - _pull) * math.min(1.0, dt * 5);
  }

  /// World position of arm angle [arm] at infall progress [u] (0 = rim, 1 = core).
  /// Coherence tightens the spiral, turbulence makes the matter wobble.
  void _place(double u, double arm, double jitter, [int i = 0]) {
    final p = f.params;
    final r = _inner + _outer * math.pow(1 - u, 1.9);
    final th = arm +
        dir * (0.9 + 0.9 * p.coherence) * math.log((_outer + _inner) / r) +
        p.turbulence * 0.3 * math.sin(f.t * 2 + i * 0.7) * (r / _outer);
    _wx = r * math.cos(th);
    _wz = r * math.sin(th);
    _wy = f.mode == 2 ? (r / _outer) * 1.1 - 0.55 : jitter * 0.09 * (r / _outer);
    _wr = r;
  }

  @override
  void paint(Canvas canvas) {
    final t = f.t;
    final unit = f.scale * 0.5 * 0.95;
    final c = f.center + _core * unit;
    proj.set(
      yaw: f.mode == 2 ? t * 0.25 * dir : t * 0.1 * dir,
      pitch: switch (f.mode) { 0 => 1.05, 1 => 0.3, _ => 0.12 },
      dist: 3.0,
      center: c,
      scale: unit,
    );
    final trail = dna.has(VfxFx.motionTrails) ? 0.024 : 0.012;
    final active = (n * (0.4 + 0.6 * f.params.density)).round();
    lines.clear();
    for (var i = 0; i < active; i++) {
      final u = _fract(t * rate[i] + ph[i]);
      _place(u, th0[i], zj[i], i);
      proj.project(_wx, _wy, _wz);
      final hx = proj.x, hy = proj.y;
      final ratio = _wr / _outer;
      final ci = ratio > 0.55 ? 2 : (ratio > 0.2 ? 1 : 0);
      final tier = u < 0.4 ? 0 : (u < 0.8 ? 1 : 2);
      _place(math.max(0.0, u - trail), th0[i], zj[i], i);
      proj.project(_wx, _wy, _wz);
      lines.line(ci, tier, hx, hy, proj.x, proj.y);
    }

    final w = weight;
    final g = glow;
    proj.project(0, 0, 0);
    final core = Offset(proj.x, proj.y);

    // Accretion ribbons along each arm.
    final ribbon = Path();
    for (var a = 0; a < arms; a++) {
      final arm = a / arms * _tau;
      for (var s = 0; s <= 48; s++) {
        _place(s / 48 * 0.97, arm, 0);
        proj.project(_wx, _wy, _wz);
        s == 0 ? ribbon.moveTo(proj.x, proj.y) : ribbon.lineTo(proj.x, proj.y);
      }
    }
    _line
      ..style = PaintingStyle.stroke
      ..blendMode = BlendMode.plus
      ..shader = null
      ..strokeWidth = f.thumb ? 1.0 : 2.0
      ..color = col[1].withValues(alpha: (0.30 * w).clamp(0.0, 1.0))
      ..maskFilter = null;
    canvas.drawPath(ribbon, _line);
    if (f.bloom && !f.thumb) {
      _bloomLine
        ..strokeWidth = 8
        ..color = col[1].withValues(alpha: (0.12 * g).clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawPath(ribbon, _bloomLine);
    }

    // Jets along the spin axis.
    if (f.mode == 1) {
      final len = f.scale * (0.5 + 0.1 * math.sin(t * 2));
      for (final sign in const [-1.0, 1.0]) {
        _bloomLine
          ..strokeWidth = 4
          ..color = col[0].withValues(alpha: (0.5 * g).clamp(0.0, 1.0))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawLine(core, core + Offset(0, sign * len), _bloomLine);
      }
    }

    _line
      ..blendMode = f.bloom ? BlendMode.plus : BlendMode.srcOver
      ..strokeWidth = f.thumb ? 1.0 : 1.5;
    lines.draw(canvas, _line, col, const [0.25, 0.55, 0.95], w);
    _line.strokeWidth = f.thumb ? 0.6 : 0.8;
    lines.draw(canvas, _line, _hot, const [0, 0, 0.9], w, minTier: 2);

    // Singularity: glow, event horizon, photon ring.
    final coreR = f.scale * (0.16 + 0.03 * math.sin(t * 3) + 0.05 * _pull) * g.clamp(0.6, 1.6);
    _fill.shader = RadialGradient(colors: [
      Color.fromRGBO(255, 255, 255, (0.95 * w).clamp(0.0, 1.0)),
      col[0].withValues(alpha: (0.8 * w).clamp(0.0, 1.0)),
      col[1].withValues(alpha: (0.25 * w).clamp(0.0, 1.0)),
      col[1].withValues(alpha: 0),
    ], stops: const [0, 0.12, 0.45, 1]).createShader(Rect.fromCircle(center: core, radius: coreR));
    canvas.drawCircle(core, coreR, _fill);
    final horizon = coreR * (0.2 + 0.05 * _pull);
    canvas.drawCircle(core, horizon, Paint()..color = dna.background.withValues(alpha: w.clamp(0.0, 1.0)));
    _line
      ..maskFilter = null
      ..blendMode = BlendMode.plus
      ..strokeWidth = f.thumb ? 1.0 : 1.8
      ..color = col[0].withValues(alpha: (0.9 * w).clamp(0.0, 1.0));
    canvas.drawCircle(core, horizon * 1.25, _line);

    if (f.bloom && !f.thumb) {
      _bloomLine
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      lines.draw(canvas, _bloomLine, col, [0, 0.07 * dna.glow, 0.15 * dna.glow], w, minTier: 1);
    }
  }
}

// -----------------------------------------------------------------------------
// 6. Cyber grid wave: a perspective wireframe terrain (or tunnel, or hanging
// cloth) undulating with summed sine harmonics. The cursor drops ripples in.
// -----------------------------------------------------------------------------
class _GridLayer extends _Layer {
  _GridLayer(super.dna, super.f, super.seed);

  late final int cols = ((f.thumb ? 14 : 34) * dna.detail).round();
  late final int rows = ((f.thumb ? 10 : 26) * dna.detail).round();
  late final Float32List gx = Float32List((cols + 1) * (rows + 1));
  late final Float32List gy = Float32List((cols + 1) * (rows + 1));
  late final Float32List gk = Float32List((cols + 1) * (rows + 1));
  final _Proj proj = _Proj();
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _bloomLine = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;
  final Paint _horizon = Paint()..blendMode = BlendMode.plus;

  double _height(double x, double z, double t, double amp, double coh) {
    final clean = math.sin(x * 2.3 + t * 1.1) * math.cos(z * 1.8 - t * 0.8) +
        0.55 * math.sin(math.sqrt(x * x + z * z) * 5.2 - t * 2.6);
    final noisy = math.sin(x * 7.1 + z * 4.3 + t * 1.9 + math.sin(z * 5.7 - t * 1.3)) * 0.7 +
        math.sin(x * 3.3 - z * 8.2 - t * 2.2) * 0.5;
    return amp * (clean * (0.4 + 0.6 * coh) + noisy * (1 - coh) * 0.9);
  }

  /// Projects the whole lattice; [flip] mirrors it into the ceiling.
  void _fill(double t, bool flip) {
    final p = f.params;
    final amp = (0.10 + 0.3 * p.turbulence) * (dna.denoise ? 0.8 : 1.0);
    final ms = f.mouse;
    final sc = f.scale;
    final ripple = f.pressed ? 0.22 : 0.09;
    for (var ri = 0; ri <= rows; ri++) {
      final v = ri / rows;
      for (var ci = 0; ci <= cols; ci++) {
        final u = ci / cols;
        double wx, wy, wz;
        if (f.mode == 2) {
          wx = -1.2 + 2.4 * u;
          wy = -0.8 + 1.6 * v;
          wz = _height(wx, wy, t, amp, p.coherence) * 1.6;
        } else {
          wx = -1.6 + 3.2 * u;
          wz = -1.0 + 4.2 * v;
          final h = _height(wx, wz, t, amp, p.coherence);
          wy = flip ? 0.42 - h : -0.42 + h;
        }
        proj.project(wx, wy, wz);
        var sy = proj.y;
        if (ms != null) {
          final d = math.sqrt(math.pow(proj.x - ms.dx, 2) + math.pow(sy - ms.dy, 2)) / sc;
          sy -= math.exp(-d * 5) * math.sin(d * 26 - t * 7) * ripple * sc * 0.5;
        }
        final idx = ri * (cols + 1) + ci;
        gx[idx] = proj.x;
        gy[idx] = sy;
        gk[idx] = proj.k;
      }
    }
  }

  double _alpha(double k) => 0.18 + 0.8 * ((k - 0.35) / 1.0).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas) {
    final t = f.t;
    final ms = f.mouse;
    final nx = ms == null ? 0.0 : (ms.dx / f.size.width - 0.5);
    final cloth = f.mode == 2;
    proj.set(
      yaw: (cloth ? 0.45 : 0.22) * math.sin(t * 0.22) + nx * 0.3,
      pitch: switch (f.mode) { 0 => 0.40, 1 => 0.04, _ => 0.15 },
      dist: cloth ? 2.8 : 2.6,
      center: f.center,
      scale: f.scale * 0.5 * 0.9,
    );

    if (!cloth) {
      // Horizon glow where the far edge of the floor meets the void.
      proj.project(0, -0.42, 3.2);
      final hy = proj.y, band = f.scale * 0.12;
      _horizon.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          col[2].withValues(alpha: 0),
          col[2].withValues(alpha: (0.35 * glow).clamp(0.0, 1.0)),
          col[2].withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTRB(0, hy - band, f.size.width, hy + band));
      canvas.drawRect(Rect.fromLTRB(0, hy - band, f.size.width, hy + band), _horizon);
    }

    _lattice(canvas, t, false);
    if (f.mode == 1) _lattice(canvas, t, true);
  }

  void _lattice(Canvas canvas, double t, bool flip) {
    _fill(t, flip);
    final w = weight;
    final stride = cols + 1;
    // Density thins the lattice: every line, every other, every third.
    final d = f.params.density;
    final step = d < 0.34 ? 3 : (d < 0.67 ? 2 : 1);
    _line.strokeWidth = f.thumb ? 1.0 : 1.3;
    _bloomLine
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final glowPaths = Path();

    // Rows run across the lattice; depth is constant along each.
    for (var ri = 0; ri <= rows; ri += step) {
      final path = Path();
      var kSum = 0.0;
      for (var ci = 0; ci <= cols; ci++) {
        final i = ri * stride + ci;
        ci == 0 ? path.moveTo(gx[i], gy[i]) : path.lineTo(gx[i], gy[i]);
        kSum += gk[i];
      }
      final a = _alpha(kSum / (cols + 1)) * w;
      _line.color = col[0].withValues(alpha: a.clamp(0.0, 1.0));
      canvas.drawPath(path, _line);
      if (ri.isEven) glowPaths.addPath(path, Offset.zero);
    }
    // Columns recede, so split them into near / mid / far chunks to fade.
    final chunk = math.max(1, rows ~/ 3);
    for (var ci = 0; ci <= cols; ci += step) {
      for (var r0 = 0; r0 < rows; r0 += chunk) {
        final r1 = math.min(rows, r0 + chunk);
        final path = Path();
        var kSum = 0.0;
        for (var ri = r0; ri <= r1; ri++) {
          final i = ri * stride + ci;
          ri == r0 ? path.moveTo(gx[i], gy[i]) : path.lineTo(gx[i], gy[i]);
          kSum += gk[i];
        }
        final a = _alpha(kSum / (r1 - r0 + 1)) * w * 0.85;
        _line.color = col[1].withValues(alpha: a.clamp(0.0, 1.0));
        canvas.drawPath(path, _line);
        if (ci.isEven && r0 == 0) glowPaths.addPath(path, Offset.zero);
      }
    }
    if (f.bloom && !f.thumb) {
      _bloomLine.color = col[0].withValues(alpha: (0.18 * glow).clamp(0.0, 1.0));
      canvas.drawPath(glowPaths, _bloomLine);
    }
  }
}

/// Procedural effect synthesised from a [VfxDna]: a deep atmospheric backdrop,
/// the compiled physics layers, then post-FX.
///
/// Like a [VfxSim], the owning view drives it: it calls [step] every frame,
/// feeds it the pointer ([mouse], normalised 0..1, and [pressed]) and the live
/// [params]; the transport ([playback]) supplies the seed (re-lays-out the
/// effect) and the mode (reshapes its topology: each of the three modes puts
/// the emitter geometry, camera and spawn shape somewhere different).
///
/// [SimParams] map onto the effect as follows: turbulence = noise amplitude,
/// coherence = cohesion / field alignment, density = how many particles, nodes
/// or blobs are live, dispersion = RGB split.
class GenerativeVfxPainter extends CustomPainter {
  GenerativeVfxPainter({
    required this.dna,
    required this.params,
    this.playback,
    super.repaint,
    this.thumb = false,
  }) {
    _f
      ..thumb = thumb
      ..params = params
      ..mode = playback?.mode ?? 0
      ..bloom = dna.has(VfxFx.additiveBloom);
    _build(playback?.seed ?? dna.seed);
  }

  final VfxDna dna;
  final bool thumb;
  SimParams params;
  Playback? playback;

  /// Pointer position normalised to the canvas (0..1), null when outside.
  Offset? mouse;
  bool pressed = false;

  /// Simulated seconds; the owning view sets this from the timeline clock.
  double time = 0;

  final _Frame _f = _Frame();
  late List<_Layer> _layers;
  int _seed = 0;
  Offset? _prevMouse;
  bool _wasPressed = false;

  final Paint _bg = Paint();
  final Paint _glowPaint = Paint();
  final Paint _shaft = Paint()..blendMode = BlendMode.plus;
  final Paint _overlay = Paint()..style = PaintingStyle.stroke;
  Shader? _vignette;
  Size? _vignetteSize;
  Float32List? _scan;
  Float32List? _grid;
  Size? _overlaySize;

  void _build(int seed) {
    _seed = seed;
    final solvers = dna.layers;
    _layers = [
      for (var i = 0; i < solvers.length; i++)
        _make(solvers[i], seed + i * 7919)
          ..weight = i == solvers.length - 1 ? 1.0 : 0.66 - 0.12 * (solvers.length - 2 - i),
    ];
  }

  _Layer _make(VfxSolver s, int seed) => switch (s) {
        VfxSolver.metaballFluid => _MetaballLayer(dna, _f, seed),
        VfxSolver.curlParticleFlow => _CurlLayer(dna, _f, seed),
        VfxSolver.shockwaveRings => _ShockLayer(dna, _f, seed),
        VfxSolver.neuralPlexus => _PlexusLayer(dna, _f, seed),
        VfxSolver.vortexAttractor => _VortexLayer(dna, _f, seed),
        VfxSolver.cyberGridWave => _GridLayer(dna, _f, seed),
      };

  /// Advances the simulation by [dt] seconds.
  void step(double dt, Size size) {
    if (size.isEmpty) return;
    final pb = playback;
    final seed = pb?.seed ?? dna.seed;
    _f
      ..size = size
      ..params = params
      ..mode = pb?.mode ?? 0;
    if (seed != _seed) _build(seed);

    time += dt;
    _f
      ..t = time
      ..dt = dt
      ..pressed = pressed
      ..justPressed = pressed && !_wasPressed;
    _wasPressed = pressed;

    final m = mouse;
    final px = m == null ? null : Offset(m.dx * size.width, m.dy * size.height);
    _f
      ..mouse = px
      ..mouseVel = (px != null && _prevMouse != null && dt > 0)
          ? (px - _prevMouse!) / dt
          : Offset.zero;
    _prevMouse = px;

    for (final l in _layers) {
      l.step();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.clipRect(rect);
    _f
      ..size = size
      ..t = time
      ..mode = playback?.mode ?? 0;
    _f.shake = Offset.zero;
    for (final l in _layers) {
      l.prepare();
    }

    final split = thumb
        ? 0.0
        : math.max(params.dispersion, dna.has(VfxFx.chromaticSplit) ? 0.3 : 0.0);
    if (split < 0.03) {
      _scene(canvas, size);
    } else {
      paintChannelSplit(canvas, rect, split * 7, () => _scene(canvas, size));
    }

    if (!thumb) {
      if (dna.has(VfxFx.scanlines)) _scanlines(canvas, size);
      if (dna.has(VfxFx.wireframeOverlay)) _hud(canvas, size);
    }
    _vignetteOverlay(canvas, size);
  }

  void _scene(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(_f.shake.dx, _f.shake.dy);
    _backdrop(canvas, size);
    for (final l in _layers) {
      l.paint(canvas);
    }
    canvas.restore();
  }

  void _backdrop(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).inflate(24);
    _bg.color = dna.background;
    canvas.drawRect(rect, _bg);

    final t = _f.t;
    final g = dna.glow * (dna.volumetric ? 1.3 : 1.0);
    final w = size.width, h = size.height, big = math.max(w, h);
    final c = dna.colors;

    final c1 = Offset(w * (0.5 + 0.06 * math.sin(t * 0.21)), h * (0.46 + 0.04 * math.cos(t * 0.17)));
    _glowPaint.shader = RadialGradient(colors: [
      c[0].withValues(alpha: (0.30 * g).clamp(0.0, 1.0)),
      c[1].withValues(alpha: (0.11 * g).clamp(0.0, 1.0)),
      c[1].withValues(alpha: 0),
    ]).createShader(Rect.fromCircle(center: c1, radius: big * 0.72));
    canvas.drawRect(rect, _glowPaint);

    final c2 = Offset(w * (0.2 + 0.05 * math.cos(t * 0.13)), h * (0.82 + 0.04 * math.sin(t * 0.19)));
    _glowPaint.shader = RadialGradient(colors: [
      c[2].withValues(alpha: (0.22 * g).clamp(0.0, 1.0)),
      c[2].withValues(alpha: 0),
    ]).createShader(Rect.fromCircle(center: c2, radius: big * 0.6));
    canvas.drawRect(rect, _glowPaint);

    if (dna.volumetric) {
      // Crepuscular shafts raking down from above.
      for (var s = 0; s < 3; s++) {
        final x0 = w * (0.25 + 0.25 * s) + math.sin(t * 0.15 + s * 2) * w * 0.05;
        final shaft = Rect.fromLTRB(x0 - w * 0.14, 0, x0 + w * 0.14, h);
        _shaft.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c[0].withValues(alpha: (0.07 * g).clamp(0.0, 1.0)), c[0].withValues(alpha: 0)],
        ).createShader(shaft);
        canvas.drawPath(
          Path()
            ..moveTo(x0 - w * 0.02, -10)
            ..lineTo(x0 + w * 0.02, -10)
            ..lineTo(x0 + w * 0.14, h)
            ..lineTo(x0 - w * 0.14, h)
            ..close(),
          _shaft,
        );
      }
    }
  }

  /// Rebuilds the cached overlay line buffers when the canvas size changes.
  void _prepareOverlays(Size size) {
    if (_overlaySize == size) return;
    _overlaySize = size;
    final scan = <double>[];
    for (var y = 0.5; y < size.height; y += 3) {
      scan.addAll([0, y, size.width, y]);
    }
    _scan = Float32List.fromList(scan);
    final grid = <double>[];
    for (var x = 0.0; x < size.width; x += 56) {
      grid.addAll([x, 0, x, size.height]);
    }
    for (var y = 0.0; y < size.height; y += 56) {
      grid.addAll([0, y, size.width, y]);
    }
    _grid = Float32List.fromList(grid);
  }

  void _scanlines(Canvas canvas, Size size) {
    _prepareOverlays(size);
    _overlay
      ..strokeWidth = 1
      ..blendMode = BlendMode.srcOver
      ..shader = null
      ..color = const Color(0x2A000000);
    canvas.drawRawPoints(PointMode.lines, _scan!, _overlay);
    // A faint bright band rolling down the screen.
    final band = size.height * 0.16;
    final y = (_f.t * 90) % (size.height + band * 2) - band;
    final r = Rect.fromLTWH(0, y - band / 2, size.width, band);
    canvas.drawRect(
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            dna.colors[0].withValues(alpha: 0),
            dna.colors[0].withValues(alpha: 0.07),
            dna.colors[0].withValues(alpha: 0),
          ],
        ).createShader(r),
    );
  }

  void _hud(Canvas canvas, Size size) {
    _prepareOverlays(size);
    final c = dna.colors[0];
    _overlay
      ..strokeWidth = 1
      ..shader = null
      ..blendMode = BlendMode.plus
      ..color = c.withValues(alpha: 0.06);
    canvas.drawRawPoints(PointMode.lines, _grid!, _overlay);

    _overlay
      ..strokeWidth = 1.5
      ..color = c.withValues(alpha: 0.55);
    const inset = 14.0, len = 22.0;
    final w = size.width, h = size.height;
    final corners = Path()
      ..moveTo(inset, inset + len)..lineTo(inset, inset)..lineTo(inset + len, inset)
      ..moveTo(w - inset - len, inset)..lineTo(w - inset, inset)..lineTo(w - inset, inset + len)
      ..moveTo(inset, h - inset - len)..lineTo(inset, h - inset)..lineTo(inset + len, h - inset)
      ..moveTo(w - inset - len, h - inset)..lineTo(w - inset, h - inset)..lineTo(w - inset, h - inset - len);
    canvas.drawPath(corners, _overlay);

    final m = _f.mouse;
    if (m != null) {
      _overlay
        ..strokeWidth = 1.2
        ..color = c.withValues(alpha: 0.8);
      canvas.drawCircle(m, 16, _overlay);
      canvas.drawRawPoints(
        PointMode.lines,
        Float32List.fromList([
          m.dx - 26, m.dy, m.dx - 10, m.dy, //
          m.dx + 10, m.dy, m.dx + 26, m.dy,
          m.dx, m.dy - 26, m.dx, m.dy - 10,
          m.dx, m.dy + 10, m.dx, m.dy + 26,
        ]),
        _overlay,
      );
    }
  }

  void _vignetteOverlay(Canvas canvas, Size size) {
    if (_vignetteSize != size) {
      _vignetteSize = size;
      _vignette = RadialGradient(
        radius: 0.85,
        colors: const [Color(0x00000000), Color(0x8C000000)],
        stops: const [0.55, 1],
      ).createShader(Offset.zero & size);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = _vignette);
  }

  @override
  bool shouldRepaint(covariant GenerativeVfxPainter old) => !identical(old, this);
}
