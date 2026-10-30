import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'vfx_sims.dart';

int _c8(double v) => (v * 255).round().clamp(0, 255);

int argb(double r, double g, double b) =>
    0xFF000000 | (_c8(r) << 16) | (_c8(g) << 8) | _c8(b);

double _hash(int x, int y) {
  var h = (x * 374761393 + y * 668265263) & 0xFFFFFFFF;
  h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF;
  return (h ^ (h >> 16)) / 4294967295.0;
}

double valueNoise(double x, double y) {
  final xi = x.floor(), yi = y.floor();
  final fx = x - xi, fy = y - yi;
  final ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
  final a = _hash(xi, yi), b = _hash(xi + 1, yi);
  final c = _hash(xi, yi + 1), d = _hash(xi + 1, yi + 1);
  return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy;
}

double fbm(double x, double y, [int octaves = 3]) {
  var v = 0.0, amp = 0.5;
  for (var i = 0; i < octaves; i++) {
    v += amp * valueNoise(x, y);
    x = x * 2.03 + 1.7;
    y = y * 2.03 + 9.2;
    amp *= 0.5;
  }
  return v;
}

/// Smooth surfaces rendered as a vertex-coloured triangle grid.
abstract class GridSim extends VfxSim {
  GridSim({super.thumb, required this.cols, required this.rows}) {
    final vc = (cols + 1) * (rows + 1);
    positions = Float32List(vc * 2);
    colors = Int32List(vc);
    final idx = Uint16List(cols * rows * 6);
    var k = 0;
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final a = j * (cols + 1) + i, b = a + 1;
        final c = a + cols + 1, d = c + 1;
        idx[k++] = a;
        idx[k++] = b;
        idx[k++] = c;
        idx[k++] = b;
        idx[k++] = d;
        idx[k++] = c;
      }
    }
    indices = idx;
  }

  final int cols, rows;
  late final Float32List positions;
  late final Int32List colors;
  late final Uint16List indices;

  int vertex(int i, int j) => j * (cols + 1) + i;

  /// Fill [colors] for the current frame.
  void shade(Size size);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    for (var j = 0; j <= rows; j++) {
      for (var i = 0; i <= cols; i++) {
        final k = vertex(i, j);
        positions[k * 2] = i / cols * size.width;
        positions[k * 2 + 1] = j / rows * size.height;
      }
    }
    shade(size);
    final v = Vertices.raw(VertexMode.triangles, positions,
        colors: colors, indices: indices);
    canvas.drawVertices(v, BlendMode.dst, Paint());
    v.dispose();
  }
}

// -----------------------------------------------------------------------------
// VACUUM_CLOTH: a shrink-wrapped membrane (damped wave height field).
// -----------------------------------------------------------------------------
class ClothSim extends GridSim {
  ClothSim({super.thumb}) : super(cols: thumb ? 24 : 72, rows: thumb ? 24 : 54) {
    final vc = (cols + 1) * (rows + 1);
    _h = Float32List(vc);
    _v = Float32List(vc);
    _crinkle = Float32List(vc * 2);
    final rng = math.Random(11);
    for (var i = 0; i < vc * 2; i++) {
      _crinkle[i] = rng.nextDouble() - 0.5;
    }
  }

  late final Float32List _h, _v, _crinkle;

  @override
  Color get background => const Color(0xFF111114);

  static double _bump(double u, double v, double cx, double cy, double r) {
    final dx = u - cx, dy = v - cy;
    return math.exp(-(dx * dx + dy * dy) / (r * r));
  }

  @override
  void step(double dt, Size size) {
    super.step(dt, size);
    if (size.isEmpty) return;
    dt = dt.clamp(0.0, 1 / 30) / 2;
    final breathe = 0.82 + 0.18 * math.sin(t * 1.3);
    final p = pointer;
    final pu = p == null ? -9.0 : p.dx / size.width;
    final pv = p == null ? -9.0 : p.dy / size.height;
    final push = pressed ? 1.3 : 0.55;
    for (var s = 0; s < 2; s++) {
      for (var j = 1; j < rows; j++) {
        final v = j / rows;
        for (var i = 1; i < cols; i++) {
          final u = i / cols;
          final k = vertex(i, j);
          final base = math.max(
                math.max(_bump(u, v, 0.33, 0.4, 0.17), _bump(u, v, 0.68, 0.36, 0.15)),
                _bump(u, v, 0.52, 0.72, 0.2) * 0.9,
              ) *
              breathe;
          final du = u - pu, dv = v - pv;
          final force = -push * math.exp(-(du * du + dv * dv) / 0.006);
          final lap = _h[k - 1] + _h[k + 1] + _h[k - cols - 1] + _h[k + cols + 1] - 4 * _h[k];
          _v[k] = (_v[k] + (lap * 260 - (_h[k] - base - force) * 22) * dt) * 0.985;
        }
      }
      for (var k = 0; k < _h.length; k++) {
        _h[k] += _v[k] * dt;
      }
    }
  }

  @override
  void shade(Size size) {
    final slope = cols * 0.16;
    for (var j = 0; j <= rows; j++) {
      for (var i = 0; i <= cols; i++) {
        final k = vertex(i, j);
        final l = i > 0 ? _h[k - 1] : _h[k];
        final r = i < cols ? _h[k + 1] : _h[k];
        final u = j > 0 ? _h[k - cols - 1] : _h[k];
        final d = j < rows ? _h[k + cols + 1] : _h[k];
        final hk = _h[k].clamp(0.0, 1.5);
        var nx = -(r - l) * slope + _crinkle[k * 2] * 0.35 * hk;
        var ny = -(d - u) * slope + _crinkle[k * 2 + 1] * 0.35 * hk;
        final inv = 1 / math.sqrt(nx * nx + ny * ny + 1);
        nx *= inv;
        ny *= inv;
        final nz = inv;
        final diff = math.max(0.0, -0.4 * nx - 0.6 * ny + 0.7 * nz);
        final sh = math.max(0.0, -0.21 * nx - 0.31 * ny + 0.93 * nz);
        final spec = math.pow(sh, 36).toDouble();
        final lift = 0.45 + 0.55 * math.min(1.0, hk * 1.4);
        final c = (0.07 + 0.6 * diff * diff) * lift + 1.1 * spec;
        colors[k] = argb(c + 0.1 * nx * lift, c, c * 1.04 + 0.12 * ny.abs() * lift);
      }
    }
  }
}

// -----------------------------------------------------------------------------
// CAUSTICS_LOOP: refracted light through a moving water surface.
// -----------------------------------------------------------------------------
class CausticsSim extends GridSim {
  CausticsSim({super.thumb}) : super(cols: thumb ? 28 : 104, rows: thumb ? 28 : 72);

  @override
  Color get background => const Color(0xFF0B4F8A);

  static double _caustic(double px, double py, double time) {
    var ix = px, iy = py, c = 1.0;
    const inten = 0.005;
    for (var n = 0; n < 5; n++) {
      final tt = time * (1 - 3.5 / (n + 1));
      final nx = px + math.cos(tt - ix) + math.sin(tt + iy);
      final ny = py + math.sin(tt - iy) + math.cos(tt + ix);
      ix = nx;
      iy = ny;
      final a = px / (math.sin(ix + tt) / inten);
      final b = py / (math.cos(iy + tt) / inten);
      c += 1 / math.sqrt(a * a + b * b);
    }
    c /= 5;
    c = 1.17 - math.pow(c, 1.4);
    return math.pow(c.abs(), 8).toDouble().clamp(0.0, 1.0);
  }

  @override
  void shade(Size size) {
    final aspect = size.width / size.height;
    final p = pointer;
    final pu = p == null ? 0.0 : p.dx / size.width;
    final pv = p == null ? 0.0 : p.dy / size.height;
    final time = t * 0.5 + 23;
    for (var j = 0; j <= rows; j++) {
      final v = j / rows;
      for (var i = 0; i <= cols; i++) {
        final u = i / cols;
        var x = u * aspect * math.pi * 2 - 250;
        var y = v * math.pi * 2 - 250;
        if (p != null) {
          final du = (u - pu) * aspect, dv = v - pv;
          final d = math.sqrt(du * du + dv * dv) + 1e-4;
          final w = math.sin(d * 34 - t * 7) * 0.22 * math.exp(-d * 5);
          x += du / d * w;
          y += dv / d * w;
        }
        final c = _caustic(x, y, time);
        final depth = 0.15 * v;
        final r = 0.04 + 0.1 * c + 0.85 * c * c - depth * 0.2;
        final g = 0.31 + 0.55 * c + 0.2 * c * c - depth;
        final b = 0.54 + 0.4 * c - depth * 0.6;
        colors[vertex(i, j)] = argb(r, g, b);
      }
    }
  }
}

// -----------------------------------------------------------------------------
// MARBLE_TURBULENCE: domain-warped FBM marble with a cursor vortex.
// -----------------------------------------------------------------------------
class MarbleSim extends GridSim {
  MarbleSim({super.thumb}) : super(cols: thumb ? 26 : 84, rows: thumb ? 26 : 60);

  @override
  Color get background => const Color(0xFFE9E9EC);

  @override
  void shade(Size size) {
    final aspect = size.width / size.height;
    final p = pointer;
    final pu = p == null ? 0.0 : p.dx / size.width * aspect * 3;
    final pv = p == null ? 0.0 : p.dy / size.height * 3;
    for (var j = 0; j <= rows; j++) {
      for (var i = 0; i <= cols; i++) {
        var x = i / cols * aspect * 3;
        var y = j / rows * 3;
        if (p != null) {
          final dx = x - pu, dy = y - pv;
          final d = math.sqrt(dx * dx + dy * dy);
          final a = (pressed ? 4.0 : 2.2) * math.exp(-d * 2.2);
          final ca = math.cos(a), sa = math.sin(a);
          x = pu + dx * ca - dy * sa;
          y = pv + dx * sa + dy * ca;
        }
        final qx = fbm(x + 0.1 * t, y);
        final qy = fbm(x + 5.2, y + 1.3 - 0.08 * t);
        final r = fbm(x + 4 * qx, y + 4 * qy + 0.05 * t);
        final vein = math.sin((x + y * 0.4) * 3 + r * 7);
        final m = math.pow(vein.abs(), 0.3).toDouble();
        final base = 0.84 + 0.14 * qx;
        final dark = 1 - m;
        colors[vertex(i, j)] = argb(
          base - dark * 0.55,
          base - dark * 0.56,
          base + 0.015 - dark * 0.48,
        );
      }
    }
  }
}

// -----------------------------------------------------------------------------
// WIREFRAME_MESH: displaced UV sphere drawn as depth-sorted line batches.
// -----------------------------------------------------------------------------
class WireframeSim extends VfxSim {
  WireframeSim({super.thumb}) {
    _lat = thumb ? 9 : 16;
    _lon = thumb ? 14 : 28;
    final vc = (_lat + 1) * _lon;
    _theta = Float32List(vc);
    _phi = Float32List(vc);
    for (var a = 0; a <= _lat; a++) {
      for (var b = 0; b < _lon; b++) {
        _theta[a * _lon + b] = a / _lat * math.pi;
        _phi[a * _lon + b] = b / _lon * math.pi * 2;
      }
    }
    final edges = <int>[];
    for (var a = 0; a <= _lat; a++) {
      for (var b = 0; b < _lon; b++) {
        final k = a * _lon + b;
        edges
          ..add(k)
          ..add(a * _lon + (b + 1) % _lon);
        if (a < _lat) {
          edges
            ..add(k)
            ..add(k + _lon);
        }
      }
    }
    _edges = Int32List.fromList(edges);
    _sx = Float32List(vc);
    _sy = Float32List(vc);
    _sz = Float32List(vc);
    _front = Float32List(edges.length * 2);
    _back = Float32List(edges.length * 2);
  }

  late final int _lat, _lon;
  late final Float32List _theta, _phi, _sx, _sy, _sz, _front, _back;
  late final Int32List _edges;
  final double _yaw = 0, _pitch = -0.35;

  // Jelly: every vertex is a spring in screen space. `_bx`/`_by` hold the
  // undeformed projection from the last paint, `_ox`/`_oy` the displacement.
  late final Float32List _bx = Float32List(_sx.length);
  late final Float32List _by = Float32List(_sx.length);
  late final Float32List _ox = Float32List(_sx.length);
  late final Float32List _oy = Float32List(_sx.length);
  late final Float32List _vx = Float32List(_sx.length);
  late final Float32List _vy = Float32List(_sx.length);

  @override
  Color get background => const Color(0xFF0B0B0C);

  @override
  void step(double dt, Size size) {
    super.step(dt, size);
    if (size.isEmpty) return;
    dt = dt.clamp(0.0, 1 / 30);
    final reach = math.min(size.width, size.height) * 0.26;
    final p = pointer;
    final q = p == null ? null : Offset(size.width - p.dx, p.dy);
    const sub = 2;
    final h = dt / sub;
    for (var s = 0; s < sub; s++) {
      for (var k = 0; k < _ox.length; k++) {
        final cx = _bx[k] + _ox[k], cy = _by[k] + _oy[k];
        var fx = -38 * _ox[k] - 4.2 * _vx[k];
        var fy = -38 * _oy[k] - 4.2 * _vy[k];
        if (p != null && q != null) {
          // Pull toward the nearer of the pointer and its mirror image.
          final d1 = (cx - p.dx) * (cx - p.dx) + (cy - p.dy) * (cy - p.dy);
          final d2 = (cx - q.dx) * (cx - q.dx) + (cy - q.dy) * (cy - q.dy);
          final tgt = d1 <= d2 ? p : q;
          final d = math.sqrt(math.min(d1, d2));
          if (d < reach) {
            final f = 1 - d / reach;
            final kp = pressed ? 80.0 : 12.0;
            fx += kp * f * (tgt.dx - cx);
            fy += kp * f * (tgt.dy - cy);
          }
        }
        _vx[k] += fx * h;
        _vy[k] += fy * h;
      }
      for (var k = 0; k < _ox.length; k++) {
        _ox[k] += _vx[k] * h;
        _oy[k] += _vy[k] * h;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, m = math.min(w, h);
    if (m <= 0) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final yaw = _yaw + t * 0.4;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final cp = math.cos(_pitch), sp = math.sin(_pitch);
    final scale = m * 0.34;
    for (var k = 0; k < _theta.length; k++) {
      final th = _theta[k], ph = _phi[k];
      final r = 1 + 0.2 * math.sin(3 * th + t) * math.cos(2 * ph - t * 0.6);
      final x = r * math.sin(th) * math.cos(ph);
      final y = r * math.cos(th);
      final z = r * math.sin(th) * math.sin(ph);
      final x1 = x * cy - z * sy;
      final z1 = x * sy + z * cy;
      final y1 = y * cp - z1 * sp;
      final z2 = y * sp + z1 * cp;
      final persp = 4 / (4 - z2);
      _bx[k] = w / 2 + x1 * scale * persp;
      _by[k] = h / 2 + y1 * scale * persp;
      _sx[k] = _bx[k] + _ox[k];
      _sy[k] = _by[k] + _oy[k];
      _sz[k] = z2;
    }

    var nf = 0, nb = 0;
    for (var e = 0; e < _edges.length; e += 2) {
      final a = _edges[e], b = _edges[e + 1];
      if (_sz[a] + _sz[b] >= 0) {
        _front[nf++] = _sx[a];
        _front[nf++] = _sy[a];
        _front[nf++] = _sx[b];
        _front[nf++] = _sy[b];
      } else {
        _back[nb++] = _sx[a];
        _back[nb++] = _sy[a];
        _back[nb++] = _sx[b];
        _back[nb++] = _sy[b];
      }
    }
    canvas.drawRawPoints(
      PointMode.lines,
      Float32List.sublistView(_back, 0, nb),
      Paint()
        ..color = const Color(0x997C3AED)
        ..strokeWidth = 1,
    );
    canvas.drawRawPoints(
      PointMode.lines,
      Float32List.sublistView(_front, 0, nf),
      Paint()
        ..color = const Color(0xFFFF5A1F)
        ..strokeWidth = thumb ? 1.1 : 1.5,
    );
  }
}
