import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// docked: icons sit on their spatial grid.
/// falling: rigid-body simulation under gravity.
/// returning: spring interpolation back to the grid.
enum GravityPhase { docked, falling, returning }

enum PhysicsMode { standard, zeroG, vortex }

Offset _rot(Offset v, double a) {
  final c = math.cos(a), s = math.sin(a);
  return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
}

double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

/// An oriented box with unit mass.
class Body {
  Body(this.id, this.size);

  final String id;
  final Size size;

  Offset home = Offset.zero;
  Offset pos = Offset.zero;
  Offset vel = Offset.zero;
  double angle = 0;
  double spin = 0;

  bool dragging = false;
  Offset grabLocal = Offset.zero;
  Offset pointer = Offset.zero;

  SpringSimulation? _sx, _sy, _sa;
  double _delay = 0;

  double get inertia =>
      (size.width * size.width + size.height * size.height) / 12.0;

  /// Collision radius used for body-to-body contacts.
  double get radius => (size.width + size.height) * 0.23;
}

class GravityEngine extends ChangeNotifier {
  GravityEngine();

  static const double gravity = 2600;
  static const double restitution = 0.34;
  static const double friction = 0.55;
  // Critically damped (ratio 1.0): the return glides home with no overshoot.
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 120,
    ratio: 1.0,
  );
  static const double _maxSpin = 14;
  static const Tolerance _posTol = Tolerance(distance: 0.4, velocity: 4);
  static const Tolerance _angTol = Tolerance(distance: 0.004, velocity: 0.04);

  final Map<String, Body> bodies = {};

  /// User-dragged home positions, stored as fractions of the canvas.
  final Map<String, Offset> pinned = {};

  /// Static axis-aligned obstacles (the explore dock) that falling bodies
  /// bounce off and pile around. Canvas coordinates.
  final List<Rect> obstacles = [];

  PhysicsMode mode = PhysicsMode.standard;

  /// Phase changes are picked up by the next [step]; they never notify
  /// synchronously so they are safe to call from build-time callbacks.
  GravityPhase phase = GravityPhase.docked;
  Size bounds = Size.zero;
  double _clock = 0;
  final math.Random _rng = math.Random(42);

  bool get needsTicks => phase != GravityPhase.docked;

  Body body(String id, Size size) =>
      bodies.putIfAbsent(id, () => Body(id, size));

  /// Called during layout with the docked target of each body.
  void setHome(String id, Offset home) {
    final b = bodies[id];
    if (b == null) return;
    b.home = home;
    if (phase == GravityPhase.docked && !b.dragging) {
      b.pos = home;
      b.angle = 0;
    }
  }

  /// Called with the live canvas size. When the window resizes mid-fall,
  /// bodies are pulled back inside so none can end up below the floor.
  void setBounds(Size size) {
    if (size == bounds) return;
    final old = bounds;
    bounds = size;
    if (old.isEmpty || phase == GravityPhase.docked) return;
    for (final b in bodies.values) {
      final rx = math.min(b.size.width, b.size.height) / 2 + 4;
      b.pos = Offset(
        b.pos.dx.clamp(rx, math.max(rx, size.width - rx)),
        b.pos.dy.clamp(rx, math.max(rx, size.height - rx)),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Phase transitions
  // ---------------------------------------------------------------------------

  void drop() {
    phase = GravityPhase.falling;
    for (final b in bodies.values) {
      b.vel = Offset((_rng.nextDouble() - 0.5) * 220, -_rng.nextDouble() * 260);
      b.spin = (_rng.nextDouble() - 0.5) * 4;
    }
  }

  void lift() {
    phase = GravityPhase.returning;
    _clock = 0;
    var i = 0;
    for (final b in bodies.values) {
      b.dragging = false;
      _armSprings(b, i++ * 0.035);
    }
  }

  void _armSprings(Body b, double delay) {
    // Unwind the angle so the spring takes the short way home.
    var a = b.angle % (2 * math.pi);
    if (a > math.pi) a -= 2 * math.pi;
    b.angle = a;
    b._delay = _clock + delay;
    b._sx = SpringSimulation(_spring, b.pos.dx, b.home.dx, b.vel.dx,
        tolerance: _posTol);
    b._sy = SpringSimulation(_spring, b.pos.dy, b.home.dy, b.vel.dy,
        tolerance: _posTol);
    b._sa = SpringSimulation(_spring, a, 0, b.spin, tolerance: _angTol);
  }

  // ---------------------------------------------------------------------------
  // Dragging
  // ---------------------------------------------------------------------------

  void beginDrag(String id, Offset pointer) {
    final b = bodies[id];
    if (b == null) return;
    b.dragging = true;
    b.pointer = pointer;
    b.grabLocal = _rot(pointer - b.pos, -b.angle);
    b.vel = Offset.zero;
    notifyListeners();
  }

  void updateDrag(String id, Offset pointer) {
    final b = bodies[id];
    if (b == null || !b.dragging) return;
    final delta = pointer - b.pointer;
    b.pointer = pointer;
    if (phase == GravityPhase.falling) {
      // Moving the pivot makes the hanging icon trail behind and swing.
      final r = _rot(-b.grabLocal, b.angle);
      final iPivot = b.inertia + r.distanceSquared;
      b.spin += (r.dy * delta.dx - r.dx * delta.dy) / iPivot * 1.2;
    } else {
      b.pos = pointer - _rot(b.grabLocal, b.angle);
      if (phase == GravityPhase.docked) {
        b.home = b.pos;
        if (bounds.width > 0 && bounds.height > 0) {
          pinned[id] =
              Offset(b.pos.dx / bounds.width, b.pos.dy / bounds.height);
        }
      }
    }
    notifyListeners();
  }

  void endDrag(String id, Offset velocity) {
    final b = bodies[id];
    if (b == null) return;
    b.dragging = false;
    if (phase == GravityPhase.falling) {
      final speed = velocity.distance;
      const maxSpeed = 4200.0;
      b.vel = speed > maxSpeed ? velocity / speed * maxSpeed : velocity;
      // Angular impulse from the throw: the pointer velocity applied at the
      // grab point turns the body around its centre.
      final r = b.pointer - b.pos;
      final lever = b.inertia + r.distanceSquared;
      b.spin = (b.spin + _cross(r, b.vel) / lever * 0.5).clamp(-_maxSpin, _maxSpin);
    } else if (phase == GravityPhase.returning) {
      _armSprings(b, 0);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Simulation
  // ---------------------------------------------------------------------------

  void step(double dt) {
    if (phase == GravityPhase.docked || bounds.isEmpty) return;
    dt = dt.clamp(0.0, 1 / 30);
    _clock += dt;

    if (phase == GravityPhase.returning) {
      var done = true;
      for (final b in bodies.values) {
        final t = _clock - b._delay;
        if (b.dragging || t < 0) {
          done = false;
          continue;
        }
        final sx = b._sx, sy = b._sy, sa = b._sa;
        if (sx == null || sy == null || sa == null) continue;
        b.pos = Offset(sx.x(t), sy.x(t));
        b.vel = Offset(sx.dx(t), sy.dx(t));
        b.angle = sa.x(t);
        if (!sx.isDone(t) || !sy.isDone(t) || !sa.isDone(t)) done = false;
      }
      if (done) {
        phase = GravityPhase.docked;
        for (final b in bodies.values) {
          b
            ..pos = b.home
            ..vel = Offset.zero
            ..angle = 0
            ..spin = 0;
        }
      }
      notifyListeners();
      return;
    }

    const substeps = 4;
    final h = dt / substeps;
    final list = bodies.values.toList(growable: false);
    for (var s = 0; s < substeps; s++) {
      for (final b in list) {
        if (b.dragging) {
          _swing(b, h);
        } else {
          _integrate(b, h);
        }
      }
      _collideBodies(list);
      for (final b in list) {
        if (b.dragging) continue;
        _collideBounds(b);
        _collideRects(b);
      }
    }
    notifyListeners();
  }

  void _integrate(Body b, double h) {
    if (mode == PhysicsMode.standard) {
      b.vel = Offset(b.vel.dx, b.vel.dy + gravity * h) * (1 - 0.12 * h);
      b.spin *= 1 - 0.9 * h;
    } else if (mode == PhysicsMode.zeroG) {
      b.vel *= (1 - 0.05 * h);
      b.spin *= (1 - 0.05 * h);
    } else if (mode == PhysicsMode.vortex) {
      final center = Offset(bounds.width / 2, bounds.height / 2);
      final d = center - b.pos;
      final dist = math.max(d.distance, 10.0);
      final pull = d / dist * (4000000 / math.max(dist, 100.0));
      b.vel += pull * h;
      b.vel *= (1 - 0.4 * h);
      b.spin *= 1 - 0.6 * h;
    }
    b.pos += b.vel * h;
    b.angle += b.spin * h;
  }

  /// While held, the body hangs from the grab point like a pendulum.
  void _swing(Body b, double h) {
    final prev = b.pos;
    final r = _rot(-b.grabLocal, b.angle);
    final iPivot = b.inertia + r.distanceSquared;
    
    if (mode == PhysicsMode.standard) {
      b.spin += r.dx * gravity / iPivot * h;
    } else if (mode == PhysicsMode.vortex) {
      final center = Offset(bounds.width / 2, bounds.height / 2);
      final d = center - b.pos;
      final dist = math.max(d.distance, 10.0);
      final pull = d / dist * (4000000 / math.max(dist, 100.0));
      // Torque from radial pull
      b.spin += _cross(r, pull) / iPivot * h;
    }
    
    b.spin *= 1 - 3.2 * h;
    b.angle += b.spin * h;
    b.pos = b.pointer + _rot(-b.grabLocal, b.angle);
    if (h > 0) b.vel = (b.pos - prev) / h;
  }

  void _collideBodies(List<Body> list) {
    for (var i = 0; i < list.length; i++) {
      final a = list[i];
      for (var j = i + 1; j < list.length; j++) {
        final b = list[j];
        final d = b.pos - a.pos;
        final dist = d.distance;
        final minDist = a.radius + b.radius;
        if (dist >= minDist || dist < 1e-4) continue;
        final wa = a.dragging ? 0.0 : 1.0;
        final wb = b.dragging ? 0.0 : 1.0;
        final w = wa + wb;
        if (w == 0) continue;

        final n = d / dist;
        final pen = minDist - dist;
        a.pos -= n * (pen * wa / w);
        b.pos += n * (pen * wb / w);

        final rel = b.vel - a.vel;
        final vn = _dot(rel, n);
        if (vn >= 0) continue;
        final e = vn.abs() < 140 ? 0.0 : restitution;
        final j0 = -(1 + e) * vn / w;
        a.vel -= n * (j0 * wa);
        b.vel += n * (j0 * wb);

        // Tangential friction rolls the boxes against each other.
        final t = Offset(-n.dy, n.dx);
        final vt = _dot(rel, t);
        final jt = (-vt / w).clamp(-j0 * 0.4, j0 * 0.4);
        a.vel -= t * (jt * wa);
        b.vel += t * (jt * wb);
        a.spin -= a.radius * jt * wa / a.inertia * 0.5;
        b.spin -= b.radius * jt * wb / b.inertia * 0.5;
      }
    }
  }

  void _collideBounds(Body b) {
    final hw = b.size.width / 2, hh = b.size.height / 2;
    final floor = bounds.height - 4;
    final right = bounds.width - 4;
    const left = 4.0, top = 4.0;
    const corners = [Offset(-1, -1), Offset(1, -1), Offset(1, 1), Offset(-1, 1)];
    for (final c in corners) {
      final r = _rot(Offset(c.dx * hw, c.dy * hh), b.angle);
      final p = b.pos + r;
      if (p.dy > floor) _contact(b, r, p.dy - floor, const Offset(0, -1));
      if (p.dy < top) _contact(b, r, top - p.dy, const Offset(0, 1));
      if (p.dx < left) _contact(b, r, left - p.dx, const Offset(1, 0));
      if (p.dx > right) _contact(b, r, p.dx - right, const Offset(-1, 0));
    }
  }

  static const List<Offset> _corners = [
    Offset(-1, -1),
    Offset(1, -1),
    Offset(1, 1),
    Offset(-1, 1),
  ];

  /// Box-vs-AABB: any corner inside an obstacle is pushed out along the axis
  /// of least penetration.
  void _collideRects(Body b) {
    if (obstacles.isEmpty) return;
    final hw = b.size.width / 2, hh = b.size.height / 2;
    final reach = math.sqrt(hw * hw + hh * hh);
    for (final o in obstacles) {
      if (b.pos.dx + reach < o.left ||
          b.pos.dx - reach > o.right ||
          b.pos.dy + reach < o.top ||
          b.pos.dy - reach > o.bottom) {
        continue;
      }
      for (final c in _corners) {
        final r = _rot(Offset(c.dx * hw, c.dy * hh), b.angle);
        final p = b.pos + r;
        if (!o.contains(p)) continue;
        final dTop = p.dy - o.top, dBottom = o.bottom - p.dy;
        final dLeft = p.dx - o.left, dRight = o.right - p.dx;
        final m = math.min(math.min(dTop, dBottom), math.min(dLeft, dRight));
        if (m == dTop) {
          _contact(b, r, dTop, const Offset(0, -1));
        } else if (m == dBottom) {
          _contact(b, r, dBottom, const Offset(0, 1));
        } else if (m == dLeft) {
          _contact(b, r, dLeft, const Offset(-1, 0));
        } else {
          _contact(b, r, dRight, const Offset(1, 0));
        }
      }
    }
  }

  /// Impulse response for a box corner [r] penetrating a wall with normal [n].
  void _contact(Body b, Offset r, double pen, Offset n) {
    b.pos += n * pen;
    final inertia = b.inertia;
    final vc = b.vel + Offset(-b.spin * r.dy, b.spin * r.dx);
    final vn = _dot(vc, n);
    if (vn >= 0) return;

    final rn = _cross(r, n);
    final e = vn.abs() < 120 && mode == PhysicsMode.standard ? 0.0 : (mode == PhysicsMode.zeroG ? 1.0 : restitution);
    final j = -(1 + e) * vn / (1 + rn * rn / inertia);
    b.vel += n * j;
    b.spin += rn * j / inertia;

    final t = Offset(-n.dy, n.dx);
    final vc2 = b.vel + Offset(-b.spin * r.dy, b.spin * r.dx);
    final rt = _cross(r, t);
    final jt = (-_dot(vc2, t) / (1 + rt * rt / inertia))
        .clamp(-friction * j, friction * j);
    b.vel += t * jt;
    b.spin += rt * jt / inertia;

    // Settle resting contacts so piles don't jitter.
    if (b.vel.distance < 22 && b.spin.abs() < 0.35) {
      b.vel *= 0.6;
      b.spin *= 0.6;
    }
  }
}
