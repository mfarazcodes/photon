import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photon/models/desktop_node.dart';
import 'package:photon/models/sim_params.dart';
import 'package:photon/painters/vfx_sims.dart';
import 'package:photon/physics/gravity_engine.dart';

const _size = Size(1280, 800);
final _dock = Rect.fromLTWH((1280 - 690) / 2, 800 - 18 - 76, 690, 76);

GravityEngine _desktop() {
  final e = GravityEngine()
    ..setBounds(_size)
    ..obstacles.add(_dock);
  for (var i = 0; i < 12; i++) {
    final id = 'n$i';
    e.body(id, kIconBox);
    e.setHome(id, Offset(150 + (i % 6) * 180.0, 140 + (i ~/ 6) * 210.0));
  }
  e.body(kCoreCardId, kCoreCardBox);
  e.setHome(kCoreCardId, const Offset(640, 390));
  return e;
}

void _run(GravityEngine e, int frames) {
  for (var i = 0; i < frames; i++) {
    e.step(1 / 60);
  }
}

void main() {
  test('gravity: everything lands inside the window and the dock is solid', () {
    final e = _desktop()..drop();
    _run(e, 900);
    for (final b in e.bodies.values) {
      expect(b.pos.dx, inInclusiveRange(0, _size.width), reason: b.id);
      expect(b.pos.dy, lessThan(_size.height), reason: b.id);
      // A body centre can never be inside the dock.
      expect(_dock.contains(b.pos), isFalse, reason: '${b.id} sank into the dock');
      expect(b.vel.distance, lessThan(80), reason: '${b.id} should have settled');
    }
    // The hero card rests on top of something solid (floor or dock), not floating.
    final card = e.bodies[kCoreCardId]!;
    expect(card.pos.dy, greaterThan(_size.height * 0.4));
  });

  test('gravity: a body dropped over the dock lands on it', () {
    final e = GravityEngine()
      ..setBounds(_size)
      ..obstacles.add(_dock);
    e.body('a', kIconBox);
    e.setHome('a', const Offset(640, 200));
    e.drop();
    e.bodies['a']!.vel = Offset.zero;
    e.bodies['a']!.spin = 0;
    _run(e, 600);
    final b = e.bodies['a']!;
    // Resting on the dock top (within a few px), not on the floor behind it.
    expect(b.pos.dy + kIconBox.height / 2, closeTo(_dock.top, 6));
  });

  test('throw: release velocity and angular spin go into the body', () {
    final e = _desktop()..drop();
    _run(e, 5);
    final b = e.bodies['n0']!;
    // Grab the top-right of the icon, so a sideways throw also spins it.
    e.beginDrag('n0', b.pos + const Offset(30, -50));
    e.updateDrag('n0', b.pos + const Offset(60, -50));
    e.endDrag('n0', const Offset(2400, -900));
    expect(b.dragging, isFalse);
    expect(b.vel.dx, greaterThan(1500));
    expect(b.spin.abs(), greaterThan(0.2));
    final x0 = b.pos.dx;
    _run(e, 20);
    expect(b.pos.dx, greaterThan(x0 + 100));
  });

  test('lift: position and angle return home without overshoot or snapping', () {
    final e = _desktop()..drop();
    _run(e, 900);
    final homes = {for (final b in e.bodies.values) b.id: b.home};
    e.lift();

    final n = e.bodies['n3']!;
    var prevDist = (n.pos - homes['n3']!).distance;
    var prevAngle = n.angle.abs();
    var jump = 0.0;
    for (var i = 0; i < 900 && e.phase != GravityPhase.docked; i++) {
      e.step(1 / 60);
      final dist = (n.pos - homes['n3']!).distance;
      // Critically damped: distance to home only ever shrinks (1px tolerance).
      expect(dist, lessThanOrEqualTo(prevDist + 1.0), reason: 'overshot at frame $i');
      jump = math.max(jump, prevDist - dist);
      prevDist = dist;
      // The angle also eases to 0 rather than snapping.
      expect(n.angle.abs(), lessThanOrEqualTo(prevAngle + 0.02));
      prevAngle = n.angle.abs();
    }
    expect(e.phase, GravityPhase.docked);
    for (final b in e.bodies.values) {
      expect((b.pos - homes[b.id]!).distance, lessThan(0.5), reason: b.id);
      expect(b.angle, 0);
    }
    expect(jump, lessThan(80), reason: 'no single-frame snap');
  });

  test('resize: bodies are pulled back inside a smaller window mid-fall', () {
    final e = _desktop()..drop();
    _run(e, 30);
    e.setBounds(const Size(600, 400));
    for (final b in e.bodies.values) {
      final r = math.min(b.size.width, b.size.height) / 2;
      expect(b.pos.dx, lessThanOrEqualTo(600 - r + 1), reason: b.id);
      expect(b.pos.dy, lessThanOrEqualTo(400 - r + 1), reason: b.id);
    }
    _run(e, 600);
    for (final b in e.bodies.values) {
      expect(b.pos.dy, lessThan(400), reason: b.id);
    }
  });

  test('liquid: morph modes move the blobs to different shapes', () {
    const size = Size(700, 540);
    final sim = LiquidSim();
    // Axis blob 3 is the top droplet of the splash and the bottom of the sphere.
    const axis3 = 2 * 14 + 3;
    sim.mode = 0;
    for (var i = 0; i < 120; i++) {
      sim.step(1 / 60, size);
    }
    final sphereV = sim.v[axis3];
    sim.mode = 1;
    for (var i = 0; i < 240; i++) {
      sim.step(1 / 60, size);
    }
    final splashV = sim.v[axis3];
    expect(sphereV, greaterThan(0.55));
    expect(splashV, lessThan(0.35));
    sim.mode = 2;
    for (var i = 0; i < 240; i++) {
      sim.step(1 / 60, size);
    }
    // Inflated "H": the left stem blobs line up vertically near u = 0.33.
    expect(sim.u[0], closeTo(0.33, 0.06));
    expect(sim.u[2 * 6], closeTo(0.33, 0.06));
    expect((sim.v[0] - sim.v[2 * 6]).abs(), greaterThan(0.3));
    for (var i = 0; i < LiquidSim.n; i++) {
      expect(sim.u[i].isFinite && sim.v[i].isFinite, isTrue);
    }
  });

  test('liquid: specular droplets are repelled by the cursor', () {
    const size = Size(700, 540);
    final sim = LiquidSim();
    for (var i = 0; i < 120; i++) {
      sim.step(1 / 60, size);
    }
    // Droplet pair k = 11 -> left blob index 22.
    const drop = 2 * 11;
    final start = Offset(sim.u[drop], sim.v[drop]);
    final before = (start - Offset(start.dx - 0.04, start.dy)).distance;
    sim.pointer = Offset((start.dx - 0.04) * size.width, start.dy * size.height);
    for (var i = 0; i < 40; i++) {
      sim.step(1 / 60, size);
    }
    final after = (Offset(sim.u[drop], sim.v[drop]) - Offset(start.dx - 0.04, start.dy)).distance;
    expect(after, greaterThan(before + 0.03), reason: 'droplet should flee the pointer');
  });

  test('params: density thins the swarm, turbulence changes the motion', () {
    const size = Size(700, 540);
    final dense = SwarmSim()..params = SimParams(density: 1);
    final thin = SwarmSim()..params = SimParams(density: 0);
    // Only active agents move; the thin swarm leaves most of them untouched.
    final startX = List<double>.from(thin.x);
    for (var i = 0; i < 60; i++) {
      dense.step(1 / 60, size);
      thin.step(1 / 60, size);
    }
    var movedThin = 0, movedDense = 0;
    for (var i = 0; i < thin.n; i++) {
      if ((thin.x[i] - startX[i]).abs() > 1e-6) movedThin++;
      if ((dense.x[i] - startX[i]).abs() > 1e-6) movedDense++;
    }
    expect(movedThin, lessThan(movedDense * 0.5));

    final calm = SwarmSim()..params = SimParams(turbulence: 0);
    final wild = SwarmSim()..params = SimParams(turbulence: 1);
    for (var i = 0; i < 90; i++) {
      calm.step(1 / 60, size);
      wild.step(1 / 60, size);
    }
    var diff = 0.0;
    for (var i = 0; i < calm.n; i++) {
      diff += (calm.x[i] - wild.x[i]).abs();
    }
    expect(diff, greaterThan(0.5));
  });

  test('playback: scrub, pause and reroll', () {
    final pb = Playback(seed: 1);
    pb.advance(1.0);
    expect(pb.frame, 24);
    pb.scrubTo(100);
    expect(pb.frame, 100);
    pb.togglePlay();
    pb.advance(5);
    expect(pb.frame, 100, reason: 'paused clock must not advance');
    final old = pb.seed;
    pb.reroll();
    expect(pb.seed, isNot(old));
  });
}
