import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../state/studio_controller.dart';
import 'procedural_scene_canvas.dart';

/// Diagnostic vector overlay: the BVH and the light paths through the scene.
///
/// * Three levels of axis-aligned bounding boxes (root in cyan, mid nodes in
///   violet, leaf primitives in rose), perspective-projected and turning with
///   the camera orbit and zoom.
/// * Five primary camera rays cast at the focus point. At the surface each
///   shows its normal N, the reflected ray R, and the transmitted ray T, bent
///   by Snell's law with the live IOR and followed through up to
///   `maxBounces` internal reflections (total internal reflection included),
///   with photon packets travelling along the paths.
class BvhRayOverlay extends StatefulWidget {
  const BvhRayOverlay({super.key, required this.studio});

  final StudioController studio;

  @override
  State<BvhRayOverlay> createState() => _BvhRayOverlayState();
}

class _BvhRayOverlayState extends State<BvhRayOverlay> with SingleTickerProviderStateMixin {
  late final SceneClock _clock = SceneClock(this);

  @override
  void initState() {
    super.initState();
    _clock.sync(animate: widget.studio.animateShader);
  }

  @override
  void didUpdateWidget(BvhRayOverlay old) {
    super.didUpdateWidget(old);
    _clock.sync(animate: widget.studio.animateShader);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.studio;
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: BvhRayPainter(
          time: _clock.time,
          orbit: s.orbit,
          zoom: s.cameraZoom,
          focus: s.focusPoint,
          ior: s.param('ior'),
          bounces: s.maxBounces.clamp(1, 8),
        ),
      ),
    );
  }
}

/// A traced ray as a polyline plus how it should be drawn.
class _Path {
  _Path(this.points, this.color);

  final List<Offset> points;
  final Color color;

  double get length {
    var l = 0.0;
    for (var i = 0; i + 1 < points.length; i++) {
      l += (points[i + 1] - points[i]).distance;
    }
    return l;
  }

  Offset at(double distance) {
    var d = distance;
    for (var i = 0; i + 1 < points.length; i++) {
      final seg = (points[i + 1] - points[i]).distance;
      if (d <= seg) return Offset.lerp(points[i], points[i + 1], seg == 0 ? 0 : d / seg)!;
      d -= seg;
    }
    return points.last;
  }
}

class BvhRayPainter extends CustomPainter {
  BvhRayPainter({
    required this.time,
    required this.orbit,
    required this.zoom,
    required this.focus,
    required this.ior,
    required this.bounces,
  }) : super(repaint: Listenable.merge([time, orbit, zoom, focus]));

  final ValueListenable<double> time;
  final ValueListenable<Offset> orbit;
  final ValueListenable<double> zoom;
  final ValueListenable<Offset> focus;
  final double ior;
  final int bounces;

  static const _cyan = Color(0xFF22D3EE);
  static const _violet = Color(0xFF8A2BE2);
  static const _rose = Color(0xFFFF2D78);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = Offset(focus.value.dx * size.width, focus.value.dy * size.height);
    _paintBoxes(canvas, size, center);
    _paintRays(canvas, size, center);
  }

  // ------------------------------------------------------------- BVH boxes

  void _paintBoxes(Canvas canvas, Size size, Offset center) {
    final yaw = 0.55 + orbit.value.dx * 0.012;
    final pitch = 0.42 + orbit.value.dy * 0.008;
    final focal = size.shortestSide * 0.95 * zoom.value;

    Offset project(double x, double y, double z) {
      final cy = math.cos(yaw), sy = math.sin(yaw), cp = math.cos(pitch), sp = math.sin(pitch);
      final x1 = x * cy + z * sy, z1 = -x * sy + z * cy;
      final y2 = y * cp - z1 * sp, z2 = y * sp + z1 * cp;
      final k = focal / (z2 + 3.4);
      return center + Offset(x1 * k, y2 * k);
    }

    void box(double cx, double cy, double cz, double half, Color color, double width) {
      final v = <Offset>[
        for (var i = 0; i < 8; i++)
          project(cx + ((i & 1) == 0 ? -half : half), cy + ((i & 2) == 0 ? -half : half), cz + ((i & 4) == 0 ? -half : half)),
      ];
      final p = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width;
      // Edges join corners that differ in exactly one bit.
      for (var i = 0; i < 8; i++) {
        for (final bit in const [1, 2, 4]) {
          final j = i ^ bit;
          if (j > i) canvas.drawLine(v[i], v[j], p);
        }
      }
    }

    // Level 0: the root bounds.
    box(0, 0, 0, 1.0, _cyan, 1.4);
    // Level 1: four mid-level nodes (alternate octants).
    const mids = [
      [0.5, 0.5, 0.5],
      [-0.5, 0.5, -0.5],
      [0.5, -0.5, -0.5],
      [-0.5, -0.5, 0.5],
    ];
    for (final m in mids) {
      box(m[0], m[1], m[2], 0.46, _violet, 1.1);
      // Level 2: two leaf primitives inside each mid node.
      box(m[0] - 0.22 * m[0].sign, m[1], m[2], 0.17, _rose, 1.0);
      box(m[0] + 0.22 * m[0].sign, m[1] - 0.2 * m[1].sign, m[2] + 0.1 * m[2].sign, 0.14, _rose, 1.0);
    }
  }

  // ------------------------------------------------------------------ rays

  void _paintRays(Canvas canvas, Size size, Offset focusPx) {
    final r0 = size.shortestSide * 0.12 * zoom.value;
    final focusRing = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(focusPx, r0, focusRing);

    final paths = <_Path>[];
    final normals = <(Offset, Offset)>[];
    const rayCount = 5;
    for (var i = 0; i < rayCount; i++) {
      final origin = Offset(size.width * (0.12 + 0.19 * i), size.height * 1.02);
      final aim = focusPx + Offset((i - (rayCount - 1) / 2) * r0 * 0.42, 0);
      final d = (aim - origin) / (aim - origin).distance;

      final hit = _circleHit(origin, d, focusPx, r0, nearest: true);
      if (hit == null) {
        paths.add(_Path([origin, origin + d * size.height * 1.2], Colors.white.withValues(alpha: 0.4)));
        continue;
      }
      paths.add(_Path([origin, hit], Colors.white.withValues(alpha: 0.75)));
      final nOut = (hit - focusPx) / r0;
      normals.add((hit, nOut));

      // Reflected ray.
      final dn = d.dx * nOut.dx + d.dy * nOut.dy;
      final refl = d - nOut * (2 * dn);
      paths.add(_Path([hit, hit + refl * 78], _rose.withValues(alpha: 0.9)));

      // Transmitted ray, then up to `bounces` internal hits.
      // Entering the medium: the outward normal already faces the ray.
      final trans = _refract(d, nOut, 1 / ior);
      if (trans == null) continue;
      final inside = <Offset>[hit];
      var pos = hit;
      var dir = trans;
      for (var b = 0; b < bounces; b++) {
        final next = _circleHit(pos, dir, focusPx, r0, nearest: false);
        if (next == null) break;
        inside.add(next);
        final nHere = (next - focusPx) / r0;
        // Leaving: flip the outward normal to face the ray.
        final out = _refract(dir, -nHere, ior);
        if (out != null) {
          // Part of the light exits here, and each bounce carries less of it.
          final fade = (0.95 * math.pow(0.62, b)).clamp(0.22, 0.95).toDouble();
          paths.add(_Path([next, next + out * 92], _violet.withValues(alpha: fade)));
        }
        // The rest reflects inside (all of it on total internal reflection)
        // and goes round again. A circle never traps a ray by TIR alone, so
        // this partial reflection is what the bounce count shows.
        final dd = dir.dx * nHere.dx + dir.dy * nHere.dy;
        dir = dir - nHere * (2 * dd);
        pos = next;
      }
      paths.add(_Path(inside, _cyan.withValues(alpha: 0.95)));
    }

    for (final p in paths) {
      final line = Paint()
        ..color = p.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(p.points.first.dx, p.points.first.dy);
      for (final q in p.points.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(path, line);
    }

    // Surface normals N at each entry point.
    for (final (pt, n) in normals) {
      canvas.drawLine(
        pt,
        pt + n * 26,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(pt, 2.4, Paint()..color = Colors.white);
    }

    // Photon packets riding the paths.
    final t = time.value;
    for (var i = 0; i < paths.length; i++) {
      final p = paths[i];
      final len = p.length;
      if (len < 4) continue;
      final u = (t * 0.45 + i * 0.137) % 1.0;
      final pos = p.at(len * u);
      canvas.drawCircle(
        pos,
        5.5,
        Paint()
          ..color = p.color.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(pos, 2.4, Paint()..color = Colors.white);
    }
  }

  /// First (or far) intersection of a ray with a circle.
  static Offset? _circleHit(Offset o, Offset d, Offset c, double r, {required bool nearest}) {
    final oc = o - c;
    final b = oc.dx * d.dx + oc.dy * d.dy;
    final cc = oc.dx * oc.dx + oc.dy * oc.dy - r * r;
    final disc = b * b - cc;
    if (disc < 0) return null;
    final sq = math.sqrt(disc);
    final t = nearest ? -b - sq : -b + sq;
    if (t <= 1e-3) return null;
    return o + d * t;
  }

  /// Snell refraction of unit [d] at a surface whose unit normal [n] faces
  /// against the ray; [eta] is n1 / n2. Returns null on total internal
  /// reflection.
  static Offset? _refract(Offset d, Offset n, double eta) {
    final cosi = -(d.dx * n.dx + d.dy * n.dy);
    final k = 1 - eta * eta * (1 - cosi * cosi);
    if (k < 0) return null;
    final f = eta * cosi - math.sqrt(k);
    final out = d * eta + n * f;
    return out / out.distance;
  }

  @override
  bool shouldRepaint(BvhRayPainter old) => old.ior != ior || old.bounces != bounces;
}
