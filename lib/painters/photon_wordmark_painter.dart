import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';

/// Where one letter of the wordmark ended up after the twist.
class LetterPlacement {
  const LetterPlacement(this.char, this.center, this.angle);

  final String char;
  final Offset center;
  final double angle;
}

/// Geometry of the giant "PHOTON" lettering: a mono-line centre path per
/// letter, each tilted and lifted so the word reads as playfully twisted.
/// Shared by the wordmark and the floating decorations so they line up.
class WordmarkLayout {
  WordmarkLayout._(this.height, this.tube, this.letters, this.path);

  /// Total letter height (tube included) and tube thickness, in pixels.
  final double height;
  final double tube;
  final List<LetterPlacement> letters;
  final Path path;

  static const String text = 'PHOTON';
  static const double _tube = 0.25;
  static const double _gap = 0.03;

  static const Map<String, double> _widths = {
    'P': 0.56,
    'H': 0.60,
    'O': 0.68,
    'T': 0.62,
    'N': 0.60,
  };

  // The twist: per-letter tilt (radians), lift (letter heights) and scale.
  static const List<double> _tilt = [-0.17, 0.10, -0.08, 0.19, -0.13, 0.10];
  static const List<double> _lift = [-0.03, 0.07, -0.08, 0.03, 0.08, -0.05];
  static const List<double> _scale = [1.0, 1.04, 1.09, 0.98, 1.06, 1.0];

  static Path _letter(String c, double w, double h) {
    final p = Path();
    switch (c) {
      case 'P':
        final bh = h * 0.58;
        final r = bh / 2;
        p
          ..moveTo(0, h)
          ..lineTo(0, 0)
          ..lineTo(w - r, 0)
          ..arcToPoint(Offset(w - r, bh),
              radius: Radius.circular(r), clockwise: true)
          ..lineTo(0, bh);
      case 'H':
        p
          ..moveTo(0, 0)
          ..lineTo(0, h)
          ..moveTo(w, 0)
          ..lineTo(w, h)
          ..moveTo(0, h / 2)
          ..lineTo(w, h / 2);
      case 'O':
        p.addOval(Rect.fromLTWH(0, 0, w, h));
      case 'T':
        p
          ..moveTo(0, 0)
          ..lineTo(w, 0)
          ..moveTo(w / 2, 0)
          ..lineTo(w / 2, h);
      default: // N
        p
          ..moveTo(0, h)
          ..lineTo(0, 0)
          ..lineTo(w, h)
          ..lineTo(w, 0);
    }
    return p;
  }

  static WordmarkLayout of(Size size) {
    var unit = 0.0;
    for (final ch in text.split('')) {
      unit += _widths[ch]! + _tube + _gap;
    }
    unit -= _gap;

    final height = math.min(size.height * 0.66, size.width * 0.84 / unit);
    final t = height * _tube;
    final h = height - t;
    final totalW = unit * height;
    final cy = size.height * 0.47;

    var x = (size.width - totalW) / 2;
    final letters = <LetterPlacement>[];
    final word = Path();
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      final w = _widths[ch]! * height;
      final center = Offset(x + (w + t) / 2, cy + _lift[i] * height);
      final s = _scale[i], a = _tilt[i];
      final cosA = math.cos(a) * s, sinA = math.sin(a) * s;
      // Rotate/scale about the letter centre, then move it into place.
      final lx = w / 2, ly = h / 2;
      final m = Float64List.fromList([
        cosA, sinA, 0, 0, //
        -sinA, cosA, 0, 0,
        0, 0, 1, 0,
        center.dx - (cosA * lx - sinA * ly),
        center.dy - (sinA * lx + cosA * ly),
        0, 1,
      ]);
      word.addPath(_letter(ch, w, h).transform(m), Offset.zero);
      letters.add(LetterPlacement(ch, center, a));
      x += w + t + _gap * height;
    }
    return WordmarkLayout._(height, t, letters, word);
  }
}

/// Glossy violet tube rendering of the wordmark.
///
/// The tube is lit by stacking blurred, offset strokes inside the base stroke
/// (clipped with srcATop). It is static, so a RepaintBoundary caches it.
class PhotonWordmarkPainter extends CustomPainter {
  const PhotonWordmarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final layout = WordmarkLayout.of(size);
    final t = layout.tube;
    final word = layout.path;

    Paint stroke(double width, Color color, {double blur = 0, BlendMode? mode}) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width
        ..color = color;
      if (blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      if (mode != null) paint.blendMode = mode;
      return paint;
    }

    // Soft contact shadow on the studio floor.
    canvas.drawPath(
      word.shift(Offset(t * 0.16, t * 0.3)),
      stroke(t * 0.95, const Color(0x38301A80), blur: t * 0.3),
    );

    canvas.saveLayer((Offset.zero & size).inflate(t), Paint());
    canvas.drawPath(word, stroke(t, const Color(0xFF3F1FB8)));

    void lit(double width, Offset shift, Color color, double blur) {
      canvas.drawPath(
        word.shift(shift * t),
        stroke(width * t, color, blur: blur * t, mode: BlendMode.srcATop),
      );
    }

    lit(0.82, const Offset(-0.06, -0.08), const Color(0xFF5A2FE0), 0.16);
    lit(0.56, const Offset(-0.11, -0.15), const Color(0xFF7F5AF5), 0.15);
    lit(0.58, const Offset(0.20, 0.30), const Color(0x80E0A6F2), 0.18);
    lit(0.26, const Offset(-0.15, -0.21), const Color(0xCCBBA6FF), 0.12);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PhotonWordmarkPainter oldDelegate) => false;
}
