import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'photon_wordmark_painter.dart';

/// Animated decorations floating around the wordmark: pearls, a glass capsule,
/// a chrome ring, crystals and sparkles. Everything is drawn in code.
class PhotonFloaters extends StatefulWidget {
  const PhotonFloaters({super.key});

  @override
  State<PhotonFloaters> createState() => _PhotonFloatersState();
}

class _PhotonFloatersState extends State<PhotonFloaters>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _time = ValueNotifier(0);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => _time.value = e.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: PhotonFloatersPainter(_time), size: Size.infinite);
  }
}

class PhotonFloatersPainter extends CustomPainter {
  PhotonFloatersPainter(this.time) : super(repaint: time);

  final ValueListenable<double> time;
  Size? _size;
  WordmarkLayout? _layout;

  static const _pink = [Color(0xFFFFE3F2), Color(0xFFFF7FBF), Color(0xFFB02A7A)];
  static const _cyan = [Color(0xFFE6FBFF), Color(0xFF5ED6F5), Color(0xFF1C77B8)];
  static const _violet = [Color(0xFFF1EAFF), Color(0xFFA48CFF), Color(0xFF4B2BC4)];
  static const _lilac = [Color(0xFFFFFFFF), Color(0xFFDCD2FF), Color(0xFF8F84D8)];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (_size != size) {
      _size = size;
      _layout = WordmarkLayout.of(size);
    }
    final l = _layout!;
    final h = l.height;
    final t = time.value;

    Offset at(int i, double dx, double dy) =>
        l.letters[i].center + Offset(dx * h, dy * h);
    Offset bob(Offset o, double phase, [double amp = 0.035]) => o +
        Offset(math.sin(t * 0.6 + phase) * amp * h * 0.6,
            math.sin(t * 0.9 + phase * 1.7) * amp * h);

    // Crystals sit furthest back.
    _crystal(canvas, bob(at(1, 0.2, -0.88), 0.4), h * 0.22, 0.3 + 0.08 * math.sin(t * 0.7));
    _crystal(canvas, bob(at(4, 0.34, -0.84), 2.2), h * 0.17, -0.35 + 0.08 * math.sin(t * 0.6 + 1));
    _crystal(canvas, bob(at(5, -0.5, 0.84), 3.5), h * 0.15, -0.5 + 0.1 * math.sin(t * 0.8 + 2));

    _ring(canvas, bob(at(5, 0.02, -0.72), 1.1), h * 0.32, t);

    _pearl(canvas, bob(at(0, -0.12, -0.74), 0.0), h * 0.15, _pink);
    _pearl(canvas, bob(at(1, 0.52, 0.8), 1.4), h * 0.10, _cyan);
    _pearl(canvas, bob(at(3, -0.15, 0.84), 2.8), h * 0.14, _violet);
    _pearl(canvas, bob(at(2, 0.58, -0.8), 4.0), h * 0.085, _lilac);
    _pearl(canvas, bob(at(4, -0.1, 0.82), 5.1), h * 0.075, _pink);
    _pearl(canvas, bob(at(5, 0.62, 0.72), 6.2), h * 0.07, _cyan);
    _pearl(canvas, bob(at(0, -0.55, 0.62), 7.3), h * 0.065, _violet);

    _capsule(canvas, bob(at(2, 0.02, 0.0), 0.8, 0.02), h * 1.0, h * 0.25,
        -0.5 + 0.06 * math.sin(t * 0.7));

    const sparkles = [
      (0, 0.45, -0.85, 0.09, 0.0),
      (0, -0.55, 0.0, 0.07, 3.3),
      (1, -0.2, 0.72, 0.07, 1.3),
      (2, -0.42, 0.78, 0.10, 2.1),
      (3, 0.58, -0.72, 0.08, 0.7),
      (3, 0.52, 0.72, 0.06, 3.0),
      (4, 0.46, -0.86, 0.09, 4.1),
      (5, -0.58, -0.72, 0.07, 5.2),
    ];
    for (final (i, dx, dy, r, phase) in sparkles) {
      _sparkle(canvas, at(i, dx, dy), r * h, t, phase);
    }
  }

  void _pearl(Canvas canvas, Offset c, double r, List<Color> p) {
    final shadow = c + Offset(r * 0.25, r * 0.4);
    canvas.drawCircle(
      shadow,
      r * 1.05,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x2E301A80), Color(0x00301A80)],
        ).createShader(Rect.fromCircle(center: shadow, radius: r * 1.05)),
    );
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: p,
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.45, 0.65),
          radius: 0.75,
          colors: [Color(0x66FFD6F5), Color(0x00FFD6F5)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..color = const Color(0x33FFFFFF),
    );
    canvas.save();
    canvas.translate(c.dx - r * 0.38, c.dy - r * 0.42);
    canvas.rotate(-0.7);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 0.42, height: r * 0.22),
      Paint()..color = const Color(0xE6FFFFFF),
    );
    canvas.restore();
  }

  void _capsule(Canvas canvas, Offset c, double len, double th, double angle) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: len, height: th),
      Radius.circular(th * 0.28),
    );
    canvas.drawRRect(
      body.shift(Offset(th * 0.12, th * 0.4)),
      Paint()
        ..color = const Color(0x2A301A80)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, th * 0.22),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF4A32B8),
            Color(0xFFB9A8FF),
            Color(0xFFF4F0FF),
            Color(0xFF9884F0),
            Color(0xFF3A2596),
          ],
          stops: [0, 0.28, 0.45, 0.75, 1],
        ).createShader(body.outerRect),
    );
    for (final sx in const [-1.0, 1.0]) {
      canvas.drawRect(
        Rect.fromCenter(center: Offset(sx * len * 0.36, 0), width: len * 0.05, height: th),
        Paint()..color = const Color(0xAA2A1A7A),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, -th * 0.26), width: len * 0.82, height: th * 0.09),
        Radius.circular(th * 0.05),
      ),
      Paint()..color = const Color(0xCCFFFFFF),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0x663A2596),
    );
    canvas.restore();
  }

  void _ring(Canvas canvas, Offset c, double r, double t) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.5 + 0.15 * math.sin(t * 0.5));
    final squash = 0.42 + 0.12 * math.sin(t * 0.7);
    final rect = Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 2 * squash);
    final w = r * 0.26;
    canvas.drawOval(
      rect.shift(Offset(w * 0.3, w * 0.7)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = const Color(0x1F301A80),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..shader = SweepGradient(
          transform: GradientRotation(t * 0.6),
          colors: const [
            Color(0xFFFFFFFF),
            Color(0xFFB7A6FF),
            Color(0xFF5B34DB),
            Color(0xFFD9CEFF),
            Color(0xFFFFFFFF),
          ],
        ).createShader(rect),
    );
    canvas.drawOval(
      rect.shift(Offset(0, -w * 0.18)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.16
        ..color = const Color(0x8CFFFFFF),
    );
    canvas.restore();
  }

  void _crystal(Canvas canvas, Offset c, double s, double angle) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final top = Offset(0, -s), left = Offset(-s * 0.55, -s * 0.12);
    final right = Offset(s * 0.55, -s * 0.12), bottom = Offset(0, s * 0.95);
    final mid = Offset(s * 0.05, s * 0.16);
    void facet(Offset a, Offset b, Color color) {
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(mid.dx, mid.dy)
          ..close(),
        Paint()..color = color,
      );
    }

    facet(top, left, const Color(0xFFD3C5FF));
    facet(top, right, const Color(0xFF9A7BF7));
    facet(left, bottom, const Color(0xFF6D4AE8));
    facet(right, bottom, const Color(0xFF3F22B4));
    canvas.drawPath(
      Path()
        ..moveTo(top.dx, top.dy)
        ..lineTo(right.dx, right.dy)
        ..lineTo(bottom.dx, bottom.dy)
        ..lineTo(left.dx, left.dy)
        ..close(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0x66FFFFFF),
    );
    canvas.restore();
  }

  void _sparkle(Canvas canvas, Offset c, double r, double t, double phase) {
    final k = 0.75 + 0.25 * math.sin(t * 1.8 + phase);
    final R = r * k;
    canvas.drawCircle(
      c,
      R * 1.6,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x44A78BFF), Color(0x00A78BFF)],
        ).createShader(Rect.fromCircle(center: c, radius: R * 1.6)),
    );
    Path star(double rad) {
      final q = rad * 0.14;
      return Path()
        ..moveTo(c.dx, c.dy - rad)
        ..quadraticBezierTo(c.dx + q, c.dy - q, c.dx + rad, c.dy)
        ..quadraticBezierTo(c.dx + q, c.dy + q, c.dx, c.dy + rad)
        ..quadraticBezierTo(c.dx - q, c.dy + q, c.dx - rad, c.dy)
        ..quadraticBezierTo(c.dx - q, c.dy - q, c.dx, c.dy - rad)
        ..close();
    }

    canvas.drawPath(star(R), Paint()..color = const Color(0xFF7C5CF0));
    canvas.drawPath(star(R * 0.5), Paint()..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(covariant PhotonFloatersPainter oldDelegate) =>
      oldDelegate.time != time;
}
