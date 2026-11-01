import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../state/studio_controller.dart';

/// Color of a single visible wavelength, [nm] clamped to 380..700 (Bruton).
Color wavelengthToColor(double nm, {double alpha = 1}) {
  final w = nm.clamp(380.0, 700.0);
  double r = 0, g = 0, b = 0;
  if (w < 440) {
    r = -(w - 440) / 60;
    b = 1;
  } else if (w < 490) {
    g = (w - 440) / 50;
    b = 1;
  } else if (w < 510) {
    g = 1;
    b = -(w - 510) / 20;
  } else if (w < 580) {
    r = (w - 510) / 70;
    g = 1;
  } else if (w < 645) {
    r = 1;
    g = -(w - 645) / 65;
  } else {
    r = 1;
  }
  // Sensitivity rolls off at both ends of the spectrum.
  final f = w < 420 ? 0.35 + 0.65 * (w - 380) / 40 : (w > 680 ? 0.35 + 0.65 * (700 - w) / 20 : 1.0);
  return Color.from(alpha: alpha, red: r * f, green: g * f, blue: b * f);
}

/// A shared clock for the live scenes.
///
/// It owns one [Ticker] that runs only while [sync] is told to animate, so a
/// paused studio (and every widget test) schedules no frames. [time] holds
/// seconds and keeps its value across pauses.
class SceneClock {
  SceneClock(TickerProvider vsync) {
    _ticker = vsync.createTicker(_onTick);
  }

  /// The phase a scene shows before it has ever animated: fixed, so paused
  /// and test renders are deterministic.
  static const double restingPhase = 3.7;

  late final Ticker _ticker;
  final ValueNotifier<double> time = ValueNotifier(restingPhase);
  double _origin = restingPhase;

  bool get running => _ticker.isActive;

  void _onTick(Duration elapsed) => time.value = _origin + elapsed.inMicroseconds / 1e6;

  void sync({required bool animate}) {
    if (animate && !_ticker.isActive) {
      _origin = time.value;
      _ticker.start();
    } else if (!animate && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void dispose() {
    _ticker.dispose();
    time.dispose();
  }
}

/// A real-time procedural optical simulation, one per [ProceduralSceneKind].
///
/// It redraws at display rate and responds to the studio: camera orbit, zoom
/// and focus point, the optics parameters (IOR bends and disperses the light,
/// aperture sets bokeh and glow size, focal distance sets the depth-of-field
/// plane, caustics energy sets intensity and bloom, max bounces sets the
/// internal ray or harmonic count) and the probe wavelength. With
/// `studio.animateShader` off it holds one fixed phase.
class ProceduralSceneCanvas extends StatefulWidget {
  const ProceduralSceneCanvas({super.key, required this.studio, required this.kind});

  final StudioController studio;
  final ProceduralSceneKind kind;

  @override
  State<ProceduralSceneCanvas> createState() => _ProceduralSceneCanvasState();
}

class _ProceduralSceneCanvasState extends State<ProceduralSceneCanvas> with SingleTickerProviderStateMixin {
  late final SceneClock _clock = SceneClock(this);

  @override
  void initState() {
    super.initState();
    _clock.sync(animate: widget.studio.animateShader);
  }

  @override
  void didUpdateWidget(ProceduralSceneCanvas old) {
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
    return Semantics(
      image: true,
      label: 'Live procedural ${widget.kind.name} optical simulation',
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: ProceduralScenePainter(
            kind: widget.kind,
            time: _clock.time,
            orbit: s.orbit,
            zoom: s.cameraZoom,
            focus: s.focusPoint,
            ior: s.param('ior'),
            aperture: s.param('aperture'),
            focalDistance: s.param('focal_distance'),
            causticsEnergy: s.param('caustics_energy'),
            bounces: s.maxBounces,
            wavelengthNm: s.wavelengthNm,
          ),
        ),
      ),
    );
  }
}

/// Everything a scene draws from, resolved for one frame.
class SceneFrame {
  SceneFrame({
    required this.canvas,
    required this.size,
    required this.t,
    required this.orbit,
    required this.zoom,
    required this.focus,
    required this.ior,
    required this.aperture,
    required this.focalDistance,
    required this.energy,
    required this.bounces,
    required this.nm,
  });

  final Canvas canvas;
  final Size size;
  final double t;
  final Offset orbit;
  final double zoom;

  /// Focus point in pixels.
  final Offset focus;
  final double ior;
  final double aperture;
  final double focalDistance;
  final double energy;
  final int bounces;
  final double nm;

  double get w => size.width;
  double get h => size.height;
  double get unit => size.shortestSide;

  /// Bokeh scale: wide open (small f-number) makes big discs, up to about 3x
  /// the stopped-down size.
  double get bokehScale => math.pow(16 / aperture.clamp(1.0, 16.0), 0.42).toDouble();

  /// Depth (0 near, 1 far) of the focal plane.
  double get focalDepth => (focalDistance / 10).clamp(0.0, 1.0);

  Color get probeColor => wavelengthToColor(nm);
}

double _rand(int i, int salt) {
  final x = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
  return x - x.floorToDouble();
}

class ProceduralScenePainter extends CustomPainter {
  ProceduralScenePainter({
    required this.kind,
    required this.time,
    required this.orbit,
    required this.zoom,
    required this.focus,
    required this.ior,
    required this.aperture,
    required this.focalDistance,
    required this.causticsEnergy,
    required this.bounces,
    required this.wavelengthNm,
  }) : super(repaint: Listenable.merge([time, orbit, zoom, focus]));

  final ProceduralSceneKind kind;
  final ValueListenable<double> time;
  final ValueListenable<Offset> orbit;
  final ValueListenable<double> zoom;
  final ValueListenable<Offset> focus;
  final double ior;
  final double aperture;
  final double focalDistance;
  final double causticsEnergy;
  final int bounces;
  final double wavelengthNm;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final f = SceneFrame(
      canvas: canvas,
      size: size,
      t: time.value,
      orbit: orbit.value,
      zoom: zoom.value,
      focus: Offset(focus.value.dx * size.width, focus.value.dy * size.height),
      ior: ior,
      aperture: aperture,
      focalDistance: focalDistance,
      energy: causticsEnergy,
      bounces: bounces,
      nm: wavelengthNm,
    );
    switch (kind) {
      case ProceduralSceneKind.causticWave:
        _causticWave(f);
      case ProceduralSceneKind.spectralPrism:
        _spectralPrism(f);
      case ProceduralSceneKind.liquidChrome:
        _liquidChrome(f);
      case ProceduralSceneKind.blackHoleLensing:
        _blackHole(f);
      case ProceduralSceneKind.emeraldSubsurface:
        _emerald(f);
      case ProceduralSceneKind.soapFilmIridescence:
        _soapFilm(f);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ProceduralScenePainter old) =>
      old.kind != kind ||
      old.ior != ior ||
      old.aperture != aperture ||
      old.focalDistance != focalDistance ||
      old.causticsEnergy != causticsEnergy ||
      old.bounces != bounces ||
      old.wavelengthNm != wavelengthNm;
}

// ---------------------------------------------------------------- helpers

/// Fills the stage with a vertical gradient. Stops are spread evenly, since
/// `Gradient.linear` only accepts a stop-less list of exactly two colors.
void _fillBackground(SceneFrame f, List<Color> colors) {
  final stops = [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)];
  f.canvas.drawRect(
    Offset.zero & f.size,
    Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, f.h), colors, stops),
  );
}

/// Zooms the scene about the focus point.
void _zoomAboutFocus(SceneFrame f) {
  f.canvas.translate(f.focus.dx, f.focus.dy);
  f.canvas.scale(f.zoom);
  f.canvas.translate(-f.focus.dx, -f.focus.dy);
}

Paint _glow(Color c, double width, double sigma) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma)
  ..blendMode = BlendMode.plus;

Paint _line(Color c, double width, {BlendMode mode = BlendMode.srcOver}) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..blendMode = mode;

void _bokeh(SceneFrame f, {required int count, required List<Color> palette, double alpha = 0.12, int salt = 1}) {
  for (var i = 0; i < count; i++) {
    final depth = _rand(i, salt);
    // Parallax: nearer discs slide farther as the camera orbits.
    final px = (_rand(i, salt + 1) * f.w * 1.2 - f.w * 0.1) - f.orbit.dx * (0.15 + depth * 0.9);
    final py = (_rand(i, salt + 2) * f.h * 1.2 - f.h * 0.1) - f.orbit.dy * (0.1 + depth * 0.5) +
        math.sin(f.t * 0.3 + i) * 6;
    // Discs sharpen toward the focal plane and bloom away from it.
    final blur = (depth - f.focalDepth).abs();
    final r = math.min(64.0, (5 + 18 * depth) * f.bokehScale * (0.6 + blur));
    final c = Color.lerp(palette[i % palette.length], f.probeColor, 0.18)!;
    final a = alpha * (0.5 + 0.6 * blur) * (0.6 + 0.4 * f.energy.clamp(0.0, 2.0));
    final center = Offset(px, py);
    f.canvas.drawCircle(center, r, Paint()..color = c.withValues(alpha: a.clamp(0.0, 0.4)));
    f.canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = c.withValues(alpha: (a * 2.2).clamp(0.0, 0.6)),
    );
  }
}

// ------------------------------------------------------------ caustic wave

void _causticWave(SceneFrame f) {
  _fillBackground(f, const [Color(0xFF0B0612), Color(0xFF1B0A27), Color(0xFF0A1020)]);
  f.canvas.save();
  _zoomAboutFocus(f);

  const palette = [Color(0xFF8A2BE2), Color(0xFFFF2D78), Color(0xFFE879F9), Color(0xFF22D3EE)];
  _bokeh(f, count: 24, palette: palette, salt: 3);

  final ribbons = 8 + f.bounces ~/ 4;
  final shift = f.orbit.dx * 0.012;
  final tilt = f.orbit.dy * 0.0018;
  final amp = f.h * (0.07 + 0.05 * f.energy.clamp(0.0, 2.0));
  // IOR tightens the interference: a denser medium bends the waves harder.
  final freq = 0.006 + 0.0035 * f.ior;
  for (var k = 0; k < ribbons; k++) {
    final u = k / (ribbons - 1);
    final base = f.h * (0.12 + 0.76 * u);
    final path = Path();
    for (var x = -20.0; x <= f.w + 20; x += 8) {
      final y = base +
          amp * math.sin(x * freq + f.t * (0.5 + 0.08 * k) + k * 0.9 + shift) +
          amp * 0.55 * math.sin(x * freq * 2.3 - f.t * 0.7 + k * 1.7 - shift * 1.4) +
          (x - f.w / 2) * tilt * (u - 0.5) * 6;
      x == -20.0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final width = f.h * (0.045 + 0.05 * math.sin(k * 1.3 + f.t * 0.4).abs());
    final c0 = palette[k % 4], c1 = palette[(k + 1) % 4], c2 = palette[(k + 2) % 4];
    // Additive blending stacks fast where ribbons cross, so each one is kept
    // translucent: overlaps glow without clipping to white.
    final shader = ui.Gradient.linear(
      const Offset(0, 0),
      Offset(f.w, 0),
      [c0.withValues(alpha: 0.26), c1.withValues(alpha: 0.34), c2.withValues(alpha: 0.26)],
      const [0.0, 0.5, 1.0],
    );
    // Soft glow, glass body, then the specular edge.
    f.canvas.drawPath(path, _glow(c1.withValues(alpha: 0.10 * (0.6 + 0.4 * f.energy)), width * 2.2, 14));
    f.canvas.drawPath(path, _line(Colors.white, width)..shader = shader..blendMode = BlendMode.plus);
    f.canvas.save();
    f.canvas.translate(0, -width * 0.28);
    f.canvas.drawPath(path, _line(Colors.white.withValues(alpha: 0.3), width * 0.1, mode: BlendMode.plus));
    f.canvas.restore();
  }
  f.canvas.restore();
}

// ----------------------------------------------------------- spectral prism

void _spectralPrism(SceneFrame f) {
  _fillBackground(f, const [Color(0xFF06070D), Color(0xFF0B0C16)]);
  final floorY = f.h * 0.84;
  f.canvas.drawRect(
    Rect.fromLTRB(0, floorY, f.w, f.h),
    Paint()..shader = ui.Gradient.linear(Offset(0, floorY), Offset(0, f.h), const [Color(0xFF14121F), Color(0xFF05050A)]),
  );
  f.canvas.save();
  _zoomAboutFocus(f);

  // Equilateral prism, turned by the camera orbit.
  final size = f.unit * 0.3;
  final center = Offset(f.w * 0.46 + (f.focus.dx - f.w / 2) * 0.25, f.h * 0.47);
  final rot = f.orbit.dx * 0.004;
  // Apex, bottom-left, bottom-right: so face 0 (apex to bottom-left) is the
  // LEFT face the beam enters, and face 2 (bottom-right to apex) is the right.
  final verts = [
    for (final a in const [-math.pi / 2, 5 * math.pi / 6, math.pi / 6])
      center + Offset(math.cos(a + rot), math.sin(a + rot)) * size,
  ];
  final centroid = (verts[0] + verts[1] + verts[2]) / 3;
  // Faces: AB (left), BC (base), CA (right), with outward unit normals.
  final faces = <(Offset, Offset, Offset)>[];
  for (var i = 0; i < 3; i++) {
    final a = verts[i], b = verts[(i + 1) % 3];
    final e = (b - a) / (b - a).distance;
    var n = Offset(-e.dy, e.dx);
    // Point the normal away from the centroid.
    final outward = (a + b) / 2 - centroid;
    if (n.dx * outward.dx + n.dy * outward.dy < 0) n = -n;
    faces.add((a, b, n));
  }

  // Cauchy dispersion: n(lambda) = ior + B (1/lambda^2 - 1/0.55^2), lambda in
  // um. B scales with IOR so a denser glass fans the spectrum wider.
  final bCoef = 0.022 * f.ior;
  double nOf(double nm) {
    final um = nm / 1000;
    return f.ior + bCoef * (1 / (um * um) - 1 / (0.55 * 0.55));
  }

  Offset? refract(Offset d, Offset nOut, double index) {
    var n = nOut;
    var eta = 1 / index;
    if (d.dx * n.dx + d.dy * n.dy > 0) {
      n = -n;
      eta = index;
    }
    final cosi = -(d.dx * n.dx + d.dy * n.dy);
    final k = 1 - eta * eta * (1 - cosi * cosi);
    if (k < 0) return null;
    final g = eta * cosi - math.sqrt(k);
    return d * eta + n * g;
  }

  ({double t, Offset p, int face})? nearestHit(Offset o, Offset d, int skip) {
    ({double t, Offset p, int face})? best;
    for (var i = 0; i < 3; i++) {
      if (i == skip) continue;
      final (a, b, _) = faces[i];
      final r = b - a;
      final den = d.dx * r.dy - d.dy * r.dx;
      if (den.abs() < 1e-9) continue;
      final t = ((a.dx - o.dx) * r.dy - (a.dy - o.dy) * r.dx) / den;
      final u = ((a.dx - o.dx) * d.dy - (a.dy - o.dy) * d.dx) / den;
      if (t > 1e-3 && u >= 0 && u <= 1 && (best == null || t < best.t)) {
        best = (t: t, p: o + d * t, face: i);
      }
    }
    return best;
  }

  // The collimated beam enters the left face, its height following the focus
  // point. Its angle is the minimum-deviation incidence for a 60 degree prism,
  // sin(theta) = n / 2, so a normal glass fans the spectrum cleanly. Above
  // n = 2 no angle works: the light is totally internally reflected, which is
  // what a dense, diamond-like prism really does.
  final entryT = (0.5 + (f.focus.dy / f.h - 0.5) * 0.5).clamp(0.2, 0.8);
  final p1 = verts[0] + (verts[1] - verts[0]) * entryT;
  final faceN = faces[0].$3;
  final incidence = math.asin((f.ior / 2).clamp(0.3, 0.97));
  // Direction making that angle with the face normal, rotating toward "up".
  final incident = Offset(-faceN.dx, -faceN.dy);
  final cosI = math.cos(-incidence), sinI = math.sin(-incidence);
  final beamDir = Offset(incident.dx * cosI - incident.dy * sinI, incident.dx * sinI + incident.dy * cosI);
  final beamStart = p1 - beamDir * f.w;

  // Prism body first, so rays draw over the glass.
  final body = Path()..addPolygon(verts, true);
  f.canvas.drawPath(
    body,
    Paint()..shader = ui.Gradient.linear(verts[0], verts[1], [Colors.white.withValues(alpha: 0.10), const Color(0xFF8AB4FF).withValues(alpha: 0.05)]),
  );

  // Incoming white beam with bloom.
  final glowW = 6 + 26 / f.aperture.clamp(1.0, 16.0);
  f.canvas.drawLine(beamStart, p1, _glow(Colors.white.withValues(alpha: 0.35 * (0.5 + 0.5 * f.energy)), glowW, 8));
  f.canvas.drawLine(beamStart, p1, _line(Colors.white, 3));

  const bands = 16;
  final nearest = ((f.nm - 380) / 320 * (bands - 1)).round().clamp(0, bands - 1);
  final interiorRays = <Path>[];
  for (var i = 0; i < bands; i++) {
    final nm = 380.0 + 320.0 * i / (bands - 1);
    final idx = nOf(nm);
    final d0 = refract(beamDir, faceN, idx);
    if (d0 == null) continue;
    var d = d0 / d0.distance;
    var o = p1;
    var skip = 0;
    final inside = Path()..moveTo(o.dx, o.dy);
    final maxHops = 1 + f.bounces.clamp(1, 8);
    Offset? exit;
    Offset? exitDir;
    for (var hop = 0; hop < maxHops; hop++) {
      final hit = nearestHit(o, d, skip);
      if (hit == null) break;
      inside.lineTo(hit.p.dx, hit.p.dy);
      final out = refract(d, faces[hit.face].$3, idx);
      if (out != null) {
        exit = hit.p;
        exitDir = out / out.distance;
        break;
      }
      // Total internal reflection: bounce and keep going.
      final nn = faces[hit.face].$3;
      final dn = d.dx * nn.dx + d.dy * nn.dy;
      d = d - nn * (2 * dn);
      o = hit.p;
      skip = hit.face;
    }
    if (i == 0 || i % 5 == 0) interiorRays.add(inside);
    if (exit == null || exitDir == null) continue;

    final color = wavelengthToColor(nm);
    // Run to the floor (or the far edge) and light the caustic hotspot.
    var len = f.w * 1.4;
    if (exitDir.dy > 0.001) len = math.min(len, (floorY - exit.dy) / exitDir.dy);
    final end = exit + exitDir * len;
    final probe = i == nearest;
    final energyGain = 0.55 + 0.45 * f.energy.clamp(0.0, 2.0);
    f.canvas.drawLine(exit, end, _glow(color.withValues(alpha: (probe ? 0.5 : 0.16) * energyGain), glowW * (probe ? 1.4 : 1), 7));
    f.canvas.drawLine(exit, end, _line(color.withValues(alpha: probe ? 1 : 0.8), probe ? 3.6 : 2.2, mode: BlendMode.plus));
    if (exitDir.dy > 0.001 && end.dy >= floorY - 1) {
      f.canvas.drawOval(
        Rect.fromCenter(center: Offset(end.dx, floorY), width: 46 * energyGain, height: 8),
        Paint()
          ..color = color.withValues(alpha: 0.5 * energyGain)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
          ..blendMode = BlendMode.plus,
      );
    }
  }

  // Internal bounces show up as faint white chords.
  for (final path in interiorRays) {
    f.canvas.drawPath(path, _line(Colors.white.withValues(alpha: 0.28), 1.2, mode: BlendMode.plus));
  }
  // Glass edges.
  f.canvas.drawPath(body, _line(const Color(0xFFCFE0FF).withValues(alpha: 0.6), 1.4));
  f.canvas.drawCircle(p1, 7, Paint()..color = Colors.white.withValues(alpha: 0.5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  f.canvas.restore();
}

// ------------------------------------------------------------ liquid chrome

void _liquidChrome(SceneFrame f) {
  _fillBackground(f, const [Color(0xFF090A10), Color(0xFF14151D)]);
  f.canvas.save();
  _zoomAboutFocus(f);

  final ribbons = 6 + f.bounces ~/ 3;
  final scroll = f.orbit.dy * 0.35;
  final dispersion = ((f.ior - 1) / 2).clamp(0.0, 1.0);
  for (var k = 0; k < ribbons; k++) {
    final u = k / (ribbons - 1);
    final base = f.h * (0.1 + 0.8 * u);
    final path = Path();
    for (var x = -30.0; x <= f.w + 30; x += 10) {
      final y = base +
          f.h * 0.09 * math.sin(x * 0.0065 + f.t * 0.45 + k * 1.1 + f.orbit.dx * 0.008) +
          f.h * 0.045 * math.sin(x * 0.0175 - f.t * 0.8 + k * 2.3);
      x == -30.0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final width = f.h * (0.085 + 0.04 * math.sin(k * 0.9 + f.t * 0.3).abs());
    // Out-of-focus ribbons soften with the aperture.
    final depth = u;
    final blur = (depth - f.focalDepth).abs() * (16 / f.aperture.clamp(1.0, 16.0)) * 3;

    final y0 = base - width * 2 + scroll, y1 = base + width * 2 + scroll;
    // Studio-softbox reflection bands, scrolling with the camera.
    final shader = ui.Gradient.linear(Offset(0, y0), Offset(0, y1), const [
      Color(0xFF1B1D26),
      Color(0xFFF2F6FF),
      Color(0xFF7C8AA6),
      Color(0xFFFFFFFF),
      Color(0xFF2A2D3A),
      Color(0xFF9FB2D6),
      Color(0xFF14151D),
    ], const [0.0, 0.18, 0.38, 0.52, 0.7, 0.86, 1.0]);
    final body = _line(Colors.white, width)
      ..shader = shader
      ..maskFilter = blur > 0.4 ? MaskFilter.blur(BlurStyle.normal, blur) : null;
    f.canvas.drawPath(path, body);

    // Chromatic dispersion fringes at the ribbon edges.
    final fringe = 2 + 5 * dispersion;
    f.canvas.save();
    f.canvas.translate(0, -width / 2);
    f.canvas.drawPath(path, _line(const Color(0xFFFF2D78).withValues(alpha: 0.35 * dispersion + 0.1), 1.6, mode: BlendMode.plus));
    f.canvas.translate(0, fringe);
    f.canvas.drawPath(path, _line(const Color(0xFF22D3EE).withValues(alpha: 0.35 * dispersion + 0.1), 1.6, mode: BlendMode.plus));
    // Fresnel rim glint.
    f.canvas.translate(0, -fringe - width * 0.18);
    f.canvas.drawPath(path, _line(Colors.white.withValues(alpha: 0.55), 1.1, mode: BlendMode.plus));
    f.canvas.restore();
  }
  // Caustic bloom follows the energy.
  f.canvas.drawCircle(
    f.focus,
    f.unit * 0.3,
    Paint()
      ..shader = ui.Gradient.radial(f.focus, f.unit * 0.3, [
        Color.lerp(const Color(0xFF8A2BE2), f.probeColor, 0.3)!.withValues(alpha: 0.10 * f.energy.clamp(0.0, 2.0)),
        Colors.transparent,
      ])
      ..blendMode = BlendMode.plus,
  );
  f.canvas.restore();
}

// ------------------------------------------------------------- black hole

void _blackHole(SceneFrame f) {
  f.canvas.drawRect(Offset.zero & f.size, Paint()..color = const Color(0xFF02030A));
  f.canvas.save();
  _zoomAboutFocus(f);

  final c = Offset(f.w * 0.5 + (f.focus.dx - f.w / 2) * 0.2 - f.orbit.dx * 0.15, f.h * 0.5 - f.orbit.dy * 0.1);
  final rs = f.unit * 0.13;
  // IOR drives how hard spacetime bends the light.
  final lens = 0.8 + 0.5 * f.ior.clamp(1.0, 3.0);

  // Lensed starfield: sources sit farther out than they appear.
  for (var i = 0; i < 260; i++) {
    final px = _rand(i, 5) * f.w * 1.1 - f.w * 0.05, py = _rand(i, 6) * f.h * 1.1 - f.h * 0.05;
    final d = Offset(px, py) - c;
    final r = d.distance;
    if (r < rs * 0.9) continue;
    final warped = c + d / r * (r + lens * rs * rs / r);
    final b = 0.3 + 0.7 * _rand(i, 7) * _rand(i, 7);
    final tint = Color.lerp(Colors.white, f.probeColor, 0.25)!;
    f.canvas.drawCircle(warped, 0.6 + 1.3 * _rand(i, 8), Paint()..color = tint.withValues(alpha: b));
  }

  const approaching = Color(0xFF7A78FF);
  const receding = Color(0xFFFF5A36);
  final swirl = f.t * 0.55;
  // A sweep from receding (rose/amber) through to approaching (violet-blue).
  // [gain] scales its opacity; it is baked into the colors because a shader
  // overrides the paint's own color.
  Shader dopplerSweep(Rect rect, double heat, [double gain = 1]) => ui.Gradient.sweep(
    rect.center,
    [
      receding.withValues(alpha: 0.9 * gain),
      Color.lerp(receding, approaching, 0.5)!.withValues(alpha: 0.35 * gain),
      approaching.withValues(alpha: (0.95 + 0.05 * heat) * gain),
      Color.lerp(receding, approaching, 0.5)!.withValues(alpha: 0.35 * gain),
      receding.withValues(alpha: 0.9 * gain),
    ],
    const [0.0, 0.25, 0.5, 0.75, 1.0],
    TileMode.clamp,
    // Plasma swirl: the bright lobe drifts around the disk.
    swirl,
    swirl + 2 * math.pi,
  );

  final tilt = 0.22 + f.orbit.dy * 0.0006;
  final rings = 26 + f.bounces;
  void diskHalf({required bool nearSide}) {
    for (var i = 0; i < rings; i++) {
      final u = i / (rings - 1);
      final rho = rs * (1.6 + 3.6 * u);
      final rect = Rect.fromCenter(center: c, width: rho * 2, height: rho * 2 * tilt);
      final heat = math.exp(-u * 2.6);
      final gain = 0.2 * (0.5 + 0.5 * f.energy.clamp(0.0, 2.0)) * (0.3 + heat);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rs * 0.22
        ..blendMode = BlendMode.plus
        ..shader = dopplerSweep(rect, heat, gain);
      // Near side crosses in front of the hole (lower half), far side behind.
      f.canvas.drawArc(rect, nearSide ? 0 : math.pi, math.pi, false, paint);
    }
  }

  diskHalf(nearSide: false);
  // Lensed image of the disk's far side, bent over the shadow.
  final lensedRect = Rect.fromCircle(center: c, radius: rs * 1.34);
  f.canvas.drawCircle(
    c,
    rs * 1.34,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rs * 0.34
      ..shader = dopplerSweep(lensedRect, 0.6, 0.6 * (0.5 + 0.5 * f.energy.clamp(0.0, 2.0)))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, rs * 0.12)
      ..blendMode = BlendMode.plus,
  );
  // Event-horizon shadow.
  f.canvas.drawCircle(c, rs, Paint()..color = const Color(0xFF000000));
  diskHalf(nearSide: true);

  // Photon ring: razor thin and strongly Doppler-beamed.
  final ringRect = Rect.fromCircle(center: c, radius: rs * 1.03);
  f.canvas.drawCircle(
    c,
    rs * 1.03,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..shader = dopplerSweep(ringRect, 1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
      ..blendMode = BlendMode.plus,
  );
  f.canvas.drawCircle(
    c,
    rs * 1.03,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = dopplerSweep(ringRect, 1)
      ..blendMode = BlendMode.plus,
  );

  // Plasma filaments spiralling in.
  for (var k = 0; k < 6; k++) {
    final path = Path();
    for (var s = 0.0; s <= 1.0; s += 0.02) {
      final theta = swirl * 1.3 + k * math.pi / 3 + s * 2 * math.pi * 1.4;
      final rr = rs * (4.8 - 3.0 * s);
      final p = c + Offset(math.cos(theta) * rr, math.sin(theta) * rr * tilt);
      s == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    f.canvas.drawPath(path, _line(Colors.white.withValues(alpha: 0.14 * f.energy.clamp(0.0, 2.0)), 1, mode: BlendMode.plus));
  }
  f.canvas.restore();
}

// ----------------------------------------------------------------- emerald

void _emerald(SceneFrame f) {
  _fillBackground(f, const [Color(0xFF031412), Color(0xFF062A22), Color(0xFF031412)]);
  f.canvas.save();
  _zoomAboutFocus(f);

  const golds = [Color(0xFFE6C42E), Color(0xFF59F27A), Color(0xFF26D9B0), Color(0xFFF29A26)];
  _bokeh(f, count: 26, palette: golds, alpha: 0.07, salt: 9);

  final c = Offset(f.w * 0.5 + (f.focus.dx - f.w / 2) * 0.2 - f.orbit.dx * 0.2, f.h * 0.5 - f.orbit.dy * 0.12);
  final radius = f.unit * 0.34;
  const sides = 10;
  final rot = f.orbit.dx * 0.003 + f.t * 0.08;

  Offset vert(int i, double r, double extra) {
    final a = rot + extra + i * 2 * math.pi / sides;
    return c + Offset(math.cos(a) * r, math.sin(a) * r * 1.18);
  }

  // Subsurface glow behind the stone.
  f.canvas.drawCircle(
    c,
    radius * 1.55,
    Paint()
      ..shader = ui.Gradient.radial(c, radius * 1.55, [
        const Color(0xFF59F27A).withValues(alpha: 0.28 * (0.5 + 0.5 * f.energy.clamp(0.0, 2.0))),
        Colors.transparent,
      ])
      ..blendMode = BlendMode.plus,
  );

  // Facets: a triangle fan, each lit by its angle to a drifting light.
  final lightAngle = f.t * 0.6;
  for (var i = 0; i < sides; i++) {
    final a = vert(i, radius, 0), b = vert(i + 1, radius, 0);
    final mid = rot + (i + 0.5) * 2 * math.pi / sides;
    final lit = 0.5 + 0.5 * math.cos(mid - lightAngle);
    final facet = Path()..addPolygon([c, a, b], true);
    f.canvas.drawPath(
      facet,
      Paint()
        ..shader = ui.Gradient.radial(c, radius, [
          Color.lerp(const Color(0xFF0F7A4C), const Color(0xFFB8FFD0), lit * 0.6)!.withValues(alpha: 0.85),
          Color.lerp(const Color(0xFF053B28), const Color(0xFF2FD07E), lit)!.withValues(alpha: 0.9),
        ]),
    );
    f.canvas.drawPath(facet, _line(Colors.white.withValues(alpha: 0.10 + 0.2 * lit), 1));
  }

  // Internal caustic veins: golden-green filaments through the crystal.
  final veins = 6 + f.bounces;
  for (var k = 0; k < veins; k++) {
    final a = vert(k, radius * 0.92, 0.1);
    final b = vert(k * 3 + 2, radius * 0.4, f.t * 0.2);
    final mid = Offset.lerp(a, b, 0.5)! + Offset(math.sin(f.t + k) * 8, math.cos(f.t * 0.8 + k) * 8);
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
    f.canvas.drawPath(path, _glow(const Color(0xFFE6C42E).withValues(alpha: 0.4 * f.energy.clamp(0.0, 2.0)), 3, 3));
    f.canvas.drawPath(path, _line(const Color(0xFFFFE680).withValues(alpha: 0.7), 1.1, mode: BlendMode.plus));
  }

  // Bright table facet and rim.
  final table = Path();
  for (var i = 0; i < sides; i++) {
    final p = vert(i, radius * 0.45, f.t * 0.05);
    i == 0 ? table.moveTo(p.dx, p.dy) : table.lineTo(p.dx, p.dy);
  }
  table.close();
  f.canvas.drawPath(table, Paint()..color = const Color(0xFFCFFFE0).withValues(alpha: 0.18));
  f.canvas.drawPath(table, _line(Colors.white.withValues(alpha: 0.5), 1.2));
  final outline = Path();
  for (var i = 0; i < sides; i++) {
    final p = vert(i, radius, 0);
    i == 0 ? outline.moveTo(p.dx, p.dy) : outline.lineTo(p.dx, p.dy);
  }
  outline.close();
  f.canvas.drawPath(outline, _line(const Color(0xFFD9FFE9).withValues(alpha: 0.85), 1.8));
  f.canvas.restore();
}

// ----------------------------------------------------------- soap film

void _soapFilm(SceneFrame f) {
  _fillBackground(f, const [Color(0xFF070810), Color(0xFF0E0F1A)]);
  f.canvas.save();
  _zoomAboutFocus(f);

  const cols = 64, rows = 40;
  final positions = Float32List((cols + 1) * (rows + 1) * 2);
  final colors = Int32List((cols + 1) * (rows + 1));
  final center = Offset(f.w * 0.5 + (f.focus.dx - f.w / 2) * 0.2, f.h * 0.5);
  final bubble = f.unit * 0.42;
  final tint = f.probeColor;
  // Film thickness (nm) varies with gravity drainage and flowing eddies.
  for (var j = 0; j <= rows; j++) {
    for (var i = 0; i <= cols; i++) {
      final u = i / cols, v = j / rows;
      final x = u * f.w, y = v * f.h;
      final gx = (x - center.dx) / bubble, gy = (y - center.dy) / bubble;
      final r2 = gx * gx + gy * gy;
      final thickness = 260 +
          190 * v +
          110 * math.sin(u * 7.0 + f.t * 0.7 + f.orbit.dx * 0.01) * math.cos(v * 5.5 - f.t * 0.5) +
          60 * math.sin((u + v) * 11 + f.t);
      // Viewing angle grows toward the bubble's rim and with the camera tilt.
      final cosT = math.cos(math.min(1.2, math.sqrt(r2) * 0.9 + f.orbit.dy.abs() * 0.002));
      double channel(double lambda) =>
          0.5 - 0.5 * math.cos(4 * math.pi * f.ior * thickness * cosT / lambda);
      final r = channel(650) * (0.85 + 0.15 * tint.r);
      final g = channel(540) * (0.85 + 0.15 * tint.g);
      final b = channel(450) * (0.85 + 0.15 * tint.b);
      final idx = j * (cols + 1) + i;
      positions[idx * 2] = x;
      positions[idx * 2 + 1] = y;
      colors[idx] = Color.from(alpha: 1, red: r, green: g, blue: b).toARGB32();
    }
  }
  final indices = Uint16List(cols * rows * 6);
  var n = 0;
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      final a = j * (cols + 1) + i, b = a + 1, c = a + cols + 1, d = c + 1;
      indices
        ..[n++] = a
        ..[n++] = b
        ..[n++] = c
        ..[n++] = b
        ..[n++] = d
        ..[n++] = c;
    }
  }
  f.canvas.drawVertices(
    ui.Vertices.raw(ui.VertexMode.triangles, positions, colors: colors, indices: indices),
    BlendMode.srcOver,
    Paint(),
  );

  // Shape the film into a bubble: darkness outside, glints on the rim.
  f.canvas.drawRect(
    Offset.zero & f.size,
    Paint()
      ..shader = ui.Gradient.radial(center, bubble * 1.05, [
        Colors.transparent,
        Colors.transparent,
        const Color(0xFF070810),
      ], const [0.0, 0.93, 1.0]),
  );
  final rim = Rect.fromCircle(center: center, radius: bubble * 0.96);
  f.canvas.drawArc(rim, math.pi * 1.05, math.pi * 0.45, false, _line(Colors.white.withValues(alpha: 0.7), 3));
  f.canvas.drawArc(rim.deflate(8), math.pi * 1.1, math.pi * 0.25, false, _line(Colors.white.withValues(alpha: 0.35), 1.6));
  f.canvas.drawCircle(center, bubble * 0.96, _line(Colors.white.withValues(alpha: 0.12 + 0.1 * f.energy.clamp(0.0, 2.0)), 1.2));
  f.canvas.restore();
}
