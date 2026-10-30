import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'vfx_surface_sims.dart' show argb;

const List<String> kPassNames = ['Beauty', 'Normals', 'Z-Depth', 'Bloom', 'Wireframe'];

/// Renders the same core + ring scene through one of five render passes.
/// The scene is centred on [size] and sized by its height, so narrow
/// accordion slices reveal more of it as they widen.
class PassPainter extends CustomPainter {
  PassPainter({required this.pass, required this.time, this.splitWipe = false, this.mouseX})
      : super(repaint: time);

  final int pass;
  final ValueListenable<double> time;

  /// Expanded/selected slice: depth rings on the left, a crisp white-on-black
  /// hex dot matrix on the right, divided by an angled boundary.
  final bool splitWipe;

  /// Normalised 0..1 mouse X; when null the boundary drifts with [time].
  final double? mouseX;

  @override
  void paint(Canvas canvas, Size size) => splitWipe
      ? paintDepthDotWipe(canvas, size, time.value, mouseX)
      : paintPass(canvas, size, pass, time.value);

  @override
  bool shouldRepaint(covariant PassPainter old) =>
      old.pass != pass || old.time != time || old.splitWipe != splitWipe || old.mouseX != mouseX;
}

final Paint _wipeFill = Paint();
final Paint _wipeRing = Paint()..style = PaintingStyle.stroke;
final Paint _wipeDot = Paint()..color = const Color(0xFFFFFFFF);

/// Diagonal split: soft out-of-focus depth rings | procedural hex dot-matrix.
void paintDepthDotWipe(Canvas canvas, Size size, double t, double? mouseX) {
  final w = size.width, h = size.height;
  if (w <= 0 || h <= 0) return;
  const tilt = 0.32;
  final frac = mouseX ?? (0.5 + 0.12 * math.sin(t * 0.7));
  double lineX(double y) => w * frac + (y - h / 2) * tilt;
  final left = Path()
    ..moveTo(0, 0)
    ..lineTo(lineX(0), 0)
    ..lineTo(lineX(h), h)
    ..lineTo(0, h)
    ..close();
  final right = Path()
    ..moveTo(lineX(0), 0)
    ..lineTo(w, 0)
    ..lineTo(w, h)
    ..lineTo(lineX(h), h)
    ..close();

  // Left: smooth out-of-focus depth rings.
  canvas.save();
  canvas.clipPath(left);
  _wipeFill.color = const Color(0xFF14121C);
  canvas.drawRect(Offset.zero & size, _wipeFill);
  final c = Offset(w * 0.28, h * 0.5);
  for (var i = 1; i <= 9; i++) {
    final r = i * math.min(w, h) * 0.085 + 6 * math.sin(t + i);
    final shade = 0.18 + 0.5 * (1 - i / 9);
    _wipeRing
      ..strokeWidth = 10 + i * 3.0
      ..color = Color.fromRGBO(150, 130, 255, shade * 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + i * 1.6);
    canvas.drawCircle(c, r, _wipeRing);
  }
  _wipeRing.maskFilter = null;
  canvas.restore();

  // Right: crisp white-on-black hexagonal dot matrix.
  canvas.save();
  canvas.clipPath(right);
  _wipeFill.color = const Color(0xFF000000);
  canvas.drawRect(Offset.zero & size, _wipeFill);
  const cell = 13.0;
  final rows = (h / (cell * 0.866)).ceil() + 1;
  for (var j = 0; j < rows; j++) {
    final y = j * cell * 0.866;
    final stagger = j.isOdd ? cell / 2 : 0.0;
    final lx = lineX(y);
    for (var x = lx - cell + stagger; x < w + cell; x += cell) {
      final d = x - lx;
      if (d < -cell) continue;
      final k = (d / (w * 0.5)).clamp(0.0, 1.0);
      final wave = 0.5 + 0.5 * math.sin(t * 1.5 + x * 0.03 + y * 0.02);
      canvas.drawCircle(Offset(x, y), cell * (0.12 + 0.36 * (0.35 + 0.65 * k) * wave), _wipeDot);
    }
  }
  canvas.restore();

  _wipeDot.color = const Color(0xFFFFFFFF);
  _wipeRing
    ..strokeWidth = 2
    ..color = const Color(0xFFFFFFFF);
  canvas.drawLine(Offset(lineX(0), 0), Offset(lineX(h), h), _wipeRing);
}

void paintPass(Canvas canvas, Size size, int pass, double t) {
  final rect = Offset.zero & size;
  final c = rect.center;
  final r = math.min(size.height * 0.27, size.width * 0.9 + size.height * 0.12);
  final ring = Rect.fromCenter(center: Offset.zero, width: r * 3.3, height: r * 0.95);
  const tilt = -0.32;

  void ringArc(Paint paint, {required bool front}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt);
    canvas.drawArc(ring, front ? 0 : math.pi, math.pi, false, paint);
    canvas.restore();
  }

  switch (pass) {
    case 0: // Beauty
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B1035), Color(0xFF07040F)],
          ).createShader(rect),
      );
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [Color(0xFFD946EF), Color(0xFF8B5CF6), Color(0xFF22D3EE)],
        ).createShader(Rect.fromCenter(center: c, width: r * 3.3, height: r));
      ringArc(ringPaint, front: false);
      final hl = Alignment(-0.35 + 0.15 * math.sin(t * 0.7), -0.45);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: hl,
            radius: 1.1,
            colors: const [
              Color(0xFFE0FDFF),
              Color(0xFF22D3EE),
              Color(0xFF7C3AED),
              Color(0xFF2E1065),
            ],
            stops: const [0, 0.16, 0.55, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      ringArc(ringPaint, front: true);
    case 1: // Normals
      canvas.drawRect(rect, Paint()..color = const Color(0xFF8080FF));
      final back = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..color = const Color(0xFF9C8CF0);
      ringArc(back, front: false);
      _normalDisc(canvas, c, r, t);
      ringArc(back..color = const Color(0xFF6FD0F5), front: true);
    case 2: // Z-Depth
      canvas.drawRect(rect, Paint()..color = const Color(0xFF000000));
      final depthRing = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..color = const Color(0xFF3C3C3C);
      ringArc(depthRing, front: false);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.1, -0.1),
            colors: [Color(0xFFFFFFFF), Color(0xFF9A9A9A), Color(0xFF2E2E2E)],
            stops: [0, 0.6, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      ringArc(depthRing..color = const Color(0xFFB5B5B5), front: true);
    case 3: // Bloom
      canvas.drawRect(rect, Paint()..color = const Color(0xFF020104));
      final pulse = 1 + 0.06 * math.sin(t * 2);
      canvas.drawCircle(
          c,
          r * 1.7 * pulse,
          Paint()
            ..color = const Color(0x88D946EF)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.7));
      canvas.drawCircle(
          c,
          r * 1.1,
          Paint()
            ..color = const Color(0xAA22D3EE)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.4));
      final glowRing = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.22
        ..color = const Color(0xCCB98CFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12);
      ringArc(glowRing, front: false);
      ringArc(glowRing, front: true);
      canvas.drawCircle(
          c,
          r * 0.55 * pulse,
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.25));
    default: // Wireframe
      canvas.drawRect(rect, Paint()..color = const Color(0xFF0A0A0A));
      final wire = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xCC22D3EE);
      canvas.drawCircle(c, r, wire);
      for (var i = 1; i < 8; i++) {
        final y = -r + i * r / 4;
        final half = math.sqrt(math.max(0, r * r - y * y));
        canvas.drawOval(
            Rect.fromCenter(center: c + Offset(0, y), width: half * 2, height: half * 0.35),
            wire);
      }
      for (var i = 0; i < 6; i++) {
        final a = t * 0.6 + i * math.pi / 6;
        final wdt = (math.cos(a) * r * 2).abs();
        canvas.drawOval(Rect.fromCenter(center: c, width: wdt, height: r * 2), wire);
      }
      ringArc(
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFFFFFFFF),
        front: true,
      );
      ringArc(wire..color = const Color(0x66FFFFFF), front: false);
  }
}

/// Tangent-space normal map of the sphere, drawn as a coloured grid.
void _normalDisc(Canvas canvas, Offset c, double r, double t) {
  const n = 22;
  final pos = Float32List((n + 1) * (n + 1) * 2);
  final col = Int32List((n + 1) * (n + 1));
  final idx = Uint16List(n * n * 6);
  final spin = 0.25 * math.sin(t * 0.5);
  for (var j = 0; j <= n; j++) {
    for (var i = 0; i <= n; i++) {
      var dx = i / n * 2 - 1, dy = j / n * 2 - 1;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d > 1) {
        dx /= d;
        dy /= d;
      }
      final nz = math.sqrt(math.max(0, 1 - dx * dx - dy * dy));
      final k = j * (n + 1) + i;
      pos[k * 2] = c.dx + dx * r;
      pos[k * 2 + 1] = c.dy + dy * r;
      final nx = dx * math.cos(spin) - nz * math.sin(spin) * 0.3;
      col[k] = argb(nx * 0.5 + 0.5, -dy * 0.5 + 0.5, nz * 0.5 + 0.5);
    }
  }
  var k = 0;
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      final a = j * (n + 1) + i, b = a + 1, cc = a + n + 1, d = cc + 1;
      idx[k++] = a;
      idx[k++] = b;
      idx[k++] = cc;
      idx[k++] = b;
      idx[k++] = d;
      idx[k++] = cc;
    }
  }
  final v = Vertices.raw(VertexMode.triangles, pos, colors: col, indices: idx);
  canvas.drawVertices(v, BlendMode.dst, Paint());
  v.dispose();
}
