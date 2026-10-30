import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../theme/photon_theme.dart';

/// Black macOS-style folder with a tilted file-type sticker.
class FolderPainter extends CustomPainter {
  const FolderPainter({required this.tag, required this.tagColor});

  final String tag;
  final Color tagColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final top = h * 0.14;
    final r = Radius.circular(w * 0.08);
    final back = Paint()..color = const Color(0xFF1A1A1A);

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, top - h * 0.07, w * 0.42, h * 0.2),
          Radius.circular(w * 0.06)),
      back,
    );
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, top, w, h * 0.78), r), back);

    final front = Rect.fromLTWH(0, top + h * 0.1, w, h * 0.68);
    canvas.drawRRect(
      RRect.fromRectAndRadius(front, r),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF333333), Color(0xFF0C0C0C)],
        ).createShader(front),
    );
    canvas.drawLine(
      Offset(w * 0.06, front.top + 1),
      Offset(w * 0.94, front.top + 1),
      Paint()
        ..color = const Color(0x40FFFFFF)
        ..strokeWidth = 1,
    );

    // Sticker.
    canvas.save();
    canvas.translate(w * 0.72, front.top + front.height * 0.66);
    canvas.rotate(-0.08);
    final tagRect =
        Rect.fromCenter(center: Offset.zero, width: w * 0.38, height: h * 0.17);
    canvas.drawRect(tagRect, Paint()..color = tagColor);
    final tp = TextPainter(
      text: TextSpan(
        text: tag,
        style: PT.mono(
          size: w * 0.095,
          color: PC.white,
          weight: FontWeight.w700,
          spacing: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    tp.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FolderPainter old) =>
      old.tag != tag || old.tagColor != tagColor;
}

/// Planet-with-orbit glyph used in the Gravity pill.
class GravityGlyphPainter extends CustomPainter {
  const GravityGlyphPainter({required this.on, this.color = PC.ink});

  final bool on;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c = Offset(w * 0.5, h * 0.5);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.25);
    canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: w * 0.95, height: h * 0.34),
        stroke);
    canvas.restore();
    canvas.drawCircle(c, w * 0.2, Paint()..color = color);
    final moon = on ? Offset(w * 0.78, h * 0.86) : Offset(w * 0.86, h * 0.22);
    canvas.drawCircle(moon, w * 0.08, Paint()..color = on ? PC.blue : color);
  }

  @override
  bool shouldRepaint(covariant GravityGlyphPainter old) =>
      old.on != on || old.color != color;
}

/// Animated black-and-white halftone torus knot for the prompt drawer banner.
class HalftoneBannerPainter extends CustomPainter {
  HalftoneBannerPainter(this.time) : super(repaint: time);

  final ValueListenable<double> time;

  static final Float32List _pts = _knot(9000);
  static Float32List _depth = Float32List(0);
  static Float32List _light = Float32List(0);
  static final List<Float32List> _buf = List.generate(4, (_) => Float32List(0));
  static final Int32List _cnt = Int32List(4);

  static Float32List _knot(int n) {
    final out = Float32List(n * 3);
    final rng = math.Random(5);
    for (var i = 0; i < n; i++) {
      final u = rng.nextDouble() * math.pi * 2;
      final v = rng.nextDouble() * math.pi * 2;
      // (2,3) torus knot tube.
      final r = 0.9 + 0.38 * math.cos(3 * u);
      final cx = r * math.cos(2 * u);
      final cy = r * math.sin(2 * u);
      final cz = 0.38 * math.sin(3 * u);
      out[i * 3] = cx + 0.17 * math.cos(v) * math.cos(2 * u);
      out[i * 3 + 1] = cy + 0.17 * math.cos(v) * math.sin(2 * u);
      out[i * 3 + 2] = cz + 0.17 * math.sin(v);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF000000));
    const cell = 6.0;
    final cols = (size.width / cell).ceil(), rows = (size.height / cell).ceil();
    final cells = cols * rows;
    if (_depth.length < cells) {
      _depth = Float32List(cells);
      _light = Float32List(cells);
      for (var b = 0; b < 4; b++) {
        _buf[b] = Float32List(cells * 2);
      }
    }
    _depth.fillRange(0, cells, -99);
    _light.fillRange(0, cells, -1);

    final yaw = t * 0.6, pitch = 0.5 + 0.25 * math.sin(t * 0.4);
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final scale = size.height * 0.3;
    final ox = size.width / 2, oy = size.height / 2;
    final p = _pts;
    for (var i = 0; i < p.length; i += 3) {
      final x = p[i], y = p[i + 1], z = p[i + 2];
      final x1 = x * cy - z * sy;
      final z1 = x * sy + z * cy;
      final y1 = y * cp - z1 * sp;
      final z2 = y * sp + z1 * cp;
      final col = ((ox + x1 * scale) / cell).floor();
      final row = ((oy + y1 * scale) / cell).floor();
      if (col < 0 || row < 0 || col >= cols || row >= rows) continue;
      final k = row * cols + col;
      if (z2 > _depth[k]) {
        _depth[k] = z2;
        _light[k] = (0.35 + 0.65 * ((z2 + 1.4) / 2.8)).clamp(0.0, 1.0);
      }
    }

    _cnt.fillRange(0, 4, 0);
    for (var k = 0; k < cells; k++) {
      final l = _light[k];
      if (l < 0) continue;
      final b = (l * 4).floor().clamp(0, 3);
      final c = _cnt[b];
      _buf[b][c * 2] = (k % cols + 0.5) * cell;
      _buf[b][c * 2 + 1] = (k ~/ cols + 0.5) * cell;
      _cnt[b] = c + 1;
    }
    const greys = [Color(0xFF4A4A4A), Color(0xFF7D7D7D), Color(0xFFB8B8B8), Color(0xFFFFFFFF)];
    final paint = Paint()..strokeCap = StrokeCap.square;
    for (var b = 0; b < 4; b++) {
      if (_cnt[b] == 0) continue;
      paint
        ..color = greys[b]
        ..strokeWidth = cell * (0.4 + b * 0.16);
      canvas.drawRawPoints(PointMode.points,
          Float32List.sublistView(_buf[b], 0, _cnt[b] * 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant HalftoneBannerPainter old) => old.time != time;
}

/// Minimal telemetry sparkline.
class SparklinePainter extends CustomPainter {
  const SparklinePainter({required this.values, this.color = PC.blue});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce(math.max), minV = values.reduce(math.min);
    final span = (maxV - minV).abs() < 1e-6 ? 1.0 : maxV - minV;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - (values[i] - minV) / span * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant SparklinePainter old) => old.values != values;
}
