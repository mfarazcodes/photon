import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photon/main.dart';
import 'package:photon/models/desktop_node.dart';
import 'package:photon/models/vfx_dna.dart';
import 'package:photon/state/workspace_controller.dart';
import 'package:photon/widgets/desktop_canvas.dart';
import 'package:photon/widgets/sim_view.dart';
import 'package:photon/windows/compositor_window.dart';
import 'package:photon/windows/vfx_viewport_window.dart';

Future<void> pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<WorkspaceController> boot(WidgetTester tester) async {
  // The test font (Ahem) is much wider than Segoe UI, so test at 1920x1080.
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const PhotonApp(connectEngine: false));
  await pumpFrames(tester, 5);
  return WorkspaceScope.read(tester.element(find.byType(DesktopCanvas)));
}

DesktopNode node(WorkspaceController ws, String id) =>
    ws.nodes.firstWhere((n) => n.id == id);

void main() {
  testWidgets('boots, toggles gravity, opens a window and the explore menu',
      (tester) async {
    await boot(tester);

    expect(find.text('PHOTON VFX STUDIO®'), findsOneWidget);
    expect(find.text('PHOTON_ENGINE_V3.4'), findsOneWidget);
    expect(find.text('LIQUID_MORPH.vfx'), findsOneWidget);
    expect(find.text('EXPLORE'), findsOneWidget);
    // The notification toast was removed for good.
    expect(find.text('Cloud GPU Ready'), findsNothing);

    await tester.tap(find.text('Gravity'));
    await pumpFrames(tester, 40);
    await tester.tap(find.text('Gravity'));
    await pumpFrames(tester, 150);

    await tester.tap(find.text('CHROME_SHADER.frag'));
    await pumpFrames(tester, 30);
    expect(find.text('CHROME_SHADER.FRAG'), findsOneWidget);

    await tester.tap(find.text('EXPLORE'));
    await pumpFrames(tester, 40);
    expect(find.text('RECENT RENDERS'), findsOneWidget);
  });

  testWidgets('keyboard: Space toggles gravity, Ctrl+N the prompt drawer, Esc closes',
      (tester) async {
    final ws = await boot(tester);

    expect(ws.gravity, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(ws.gravity, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(ws.gravity, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(ws.overlay, StudioOverlay.promptDrawer);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(ws.overlay, StudioOverlay.none);

    ws.openNode(node(ws, 'chrome_shader'));
    ws.openNode(node(ws, 'wireframe_mesh'));
    await pumpFrames(tester, 10);
    expect(ws.windows, hasLength(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(ws.windows, hasLength(1), reason: 'Esc closes only the topmost window');
    expect(ws.windows.single.node!.id, 'chrome_shader');
  });

  testWidgets('Space does not toggle gravity while typing in the prompt field',
      (tester) async {
    final ws = await boot(tester);
    ws.openOverlay(StudioOverlay.promptDrawer);
    await pumpFrames(tester, 45);
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(ws.gravity, isFalse);
  });

  testWidgets('windows: z-order focus and drag clamping', (tester) async {
    final ws = await boot(tester);
    ws.openNode(node(ws, 'chrome_shader'));
    ws.openNode(node(ws, 'volumetric_fog'));
    await pumpFrames(tester, 10);
    expect(ws.topWindow!.node!.id, 'volumetric_fog');

    // Clicking inside the back window promotes it.
    ws.focus('node:chrome_shader');
    expect(ws.topWindow!.node!.id, 'chrome_shader');

    final vp = ws.viewport;
    expect(vp, isNot(Size.zero));
    final w = ws.topWindow!;
    // Far up: the title bar stops at the bottom of the pill bar.
    ws.dragWindow(w.id, const Offset(0, -9000));
    expect(w.rectIn(vp).top, greaterThanOrEqualTo(kWindowMinTop - 0.01));
    // Far right and far left: part of the window stays reachable.
    ws.dragWindow(w.id, const Offset(9000, 0));
    expect(w.rectIn(vp).left, lessThanOrEqualTo(vp.width - 119));
    ws.dragWindow(w.id, const Offset(-18000, 0));
    expect(w.rectIn(vp).right, greaterThanOrEqualTo(119));
    // Far down: the title bar stays on screen.
    ws.dragWindow(w.id, const Offset(0, 18000));
    expect(w.rectIn(vp).top, lessThanOrEqualTo(vp.height - 55));
  });

  testWidgets('traffic lights show × − + on hover; yellow minimizes, green maximizes',
      (tester) async {
    final ws = await boot(tester);
    ws.openNode(node(ws, 'chrome_shader'));
    await pumpFrames(tester, 30);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('×')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('−'), findsOneWidget);
    expect(find.text('+'), findsOneWidget);

    await tester.tap(find.text('+'));
    await pumpFrames(tester, 5);
    expect(ws.windows.single.maximized, isTrue);
    await tester.tap(find.text('+'));
    await pumpFrames(tester, 5);
    expect(ws.windows.single.maximized, isFalse);

    await tester.tap(find.text('−'));
    await pumpFrames(tester, 30);
    expect(ws.windows.single.minimized, isTrue);
    // Clicking the node on the desktop restores it.
    await tester.tap(find.text('CHROME_SHADER.frag'));
    await pumpFrames(tester, 30);
    expect(ws.windows.single.minimized, isFalse);

    await tester.tap(find.text('×'));
    await pumpFrames(tester, 40);
    expect(ws.windows, isEmpty);
  });

  testWidgets('prompt -> 4 s render with telemetry -> new node + seeded viewport',
      (tester) async {
    final ws = await boot(tester);
    final before = ws.nodes.length;

    // An empty prompt is rejected with an inline error.
    ws.openOverlay(StudioOverlay.promptDrawer);
    await pumpFrames(tester, 45);
    expect(ws.submitPrompt(), isFalse);
    await tester.pump();
    expect(find.text('A scene prompt is required to render.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'pink liquid slime splash');
    await tester.pump();
    await tester.tap(find.text('Launch Render Job'));
    await tester.pump();

    expect(ws.overlay, StudioOverlay.none);
    expect(ws.renderDropdownOpen, isTrue, reason: 'render queue card opens');
    expect(ws.renderQueue.hasUserJob, isTrue);
    expect(ws.renderQueue.progress, lessThan(0.1));

    await tester.pump(const Duration(seconds: 2));
    final mid = ws.renderQueue.progress;
    expect(mid, inInclusiveRange(0.4, 0.6), reason: '2 s of a 4 s render');
    expect(ws.renderQueue.vram, inInclusiveRange(40, 99));
    expect(ws.renderQueue.fps, greaterThan(0));
    expect(ws.nodes.length, before);

    await tester.pump(const Duration(milliseconds: 2400));
    await pumpFrames(tester, 10);
    expect(ws.renderQueue.hasUserJob, isFalse);
    expect(ws.nodes.length, before + 1);
    final made = ws.nodes.last;
    expect(made.generated, isTrue);
    expect(made.label, 'PINK_LIQUID_SLIME.vfx');
    expect(made.sim, SimKind.liquid);
    expect(made.params, isNotNull);
    // The viewport opens seeded with the prompt title.
    expect(ws.topWindow!.node!.id, made.id);
    await pumpFrames(tester, 40);
    expect(find.text('PINK_LIQUID_SLIME.VFX'), findsOneWidget);
    // The form was cleared for the next prompt.
    expect(ws.draft.prompt.text, isEmpty);
  });

  testWidgets('generated renders get their own compiled effect, close the queue and '
      'replace the previous render window', (tester) async {
    final ws = await boot(tester);
    Iterable<SimView> generative() =>
        tester.widgetList<SimView>(find.byType(SimView)).where((s) => s.dna != null);
    int renderWindows() => ws.windows
        .where((w) => w.type == WindowType.viewport && (w.node?.generated ?? false))
        .length;

    // The default desktop only ever uses the preset sims.
    expect(generative(), isEmpty);
    ws.openNode(node(ws, 'chrome_shader'));
    await pumpFrames(tester, 10);
    expect(generative(), isEmpty);

    ws.draft.prompt.text = 'Neon cyberpunk fluid simulation';
    expect(ws.submitPrompt(), isTrue);
    await tester.pump();
    // The queue pill already previews the compiled effect, not a preset.
    expect(ws.renderQueue.current.dna?.primary, VfxSolver.metaballFluid);
    expect(generative(), isNotEmpty);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 2400));
    await pumpFrames(tester, 10);

    final first = ws.nodes.last;
    expect(first.generated, isTrue);
    expect(first.dna?.paletteName, 'neon');
    expect(first.solver, isNotEmpty);
    expect(ws.renderDropdownOpen, isFalse, reason: 'queue dropdown closes on completion');
    expect(ws.topWindow!.node!.id, first.id);
    expect(renderWindows(), 1);
    expect(ws.windows.any((w) => w.id == 'node:chrome_shader'), isTrue,
        reason: 'built-in windows are left alone');

    // The viewport and the desktop icon both render the compiled DNA.
    final vp = find.byKey(ValueKey('vp:node:${first.id}'));
    expect(
      tester.widget<SimView>(find.descendant(of: vp, matching: find.byType(SimView))).dna,
      same(first.dna),
    );
    expect(generative().where((s) => identical(s.dna, first.dna)), hasLength(greaterThan(1)));

    // Generated effects get MODE 01/02/03 instead of the liquid shape names.
    for (final label in ['MODE 01', 'MODE 02', 'MODE 03']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('SPLASH'), findsNothing);
    for (final label in ['MODE 02', 'MODE 03', 'MODE 01']) {
      await tester.tap(find.text(label));
      await pumpFrames(tester, 15);
    }

    // A second render takes over the first one's window, where it was left.
    final id = ws.topWindow!.id;
    ws.dragWindow(id, const Offset(40, 30));
    ws.endDragWindow(id);
    final placed = ws.topWindow!.offset;
    ws.draft.prompt.text = 'Golden solar shockwave vortex';
    expect(ws.submitPrompt(), isTrue);
    await tester.pump();
    expect(renderWindows(), 1, reason: 'the old render stays until the new one lands');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 2400));
    await pumpFrames(tester, 10);

    final second = ws.nodes.last;
    expect(second.id, isNot(first.id));
    expect(second.dna?.paletteName, 'gold+fire');
    expect(second.dna?.primary, VfxSolver.shockwaveRings);
    expect(second.dna!.colors, isNot(first.dna!.colors));
    expect(ws.renderDropdownOpen, isFalse);
    expect(renderWindows(), 1, reason: 'replaced, not stacked');
    expect(ws.topWindow!.node!.id, second.id);
    expect(ws.topWindow!.offset, placed);
    expect(ws.nodes, contains(first), reason: 'the first render stays on the desktop');
  });

  testWidgets('viewport playback bar: pause, scrub, reroll, liquid shape toggle',
      (tester) async {
    final ws = await boot(tester);
    ws.openNode(node(ws, 'liquid_morph'));
    await pumpFrames(tester, 40);

    // The render-queue card also has a Pause icon, so scope to the viewport.
    final vp = find.byType(VfxViewportContent);
    Finder inVp(Finder f) => find.descendant(of: vp, matching: f);
    String frameLabel() =>
        tester.widget<Text>(inVp(find.textContaining('/240'))).data!;

    expect(inVp(find.byIcon(Icons.pause_rounded)), findsOneWidget);
    expect(inVp(find.textContaining('FPS')), findsOneWidget);
    final running = frameLabel();
    await pumpFrames(tester, 30);
    expect(frameLabel(), isNot(running), reason: 'timeline advances while playing');

    await tester.tap(inVp(find.byIcon(Icons.pause_rounded)));
    await pumpFrames(tester, 5);
    expect(inVp(find.byIcon(Icons.play_arrow_rounded)), findsOneWidget);
    final paused = frameLabel();
    await pumpFrames(tester, 30);
    expect(frameLabel(), paused, reason: 'paused timeline must hold still');

    // Click the timeline: it jumps to a later frame even while paused.
    final barRect = tester.getRect(inVp(find.byIcon(Icons.play_arrow_rounded)));
    await tester.tapAt(Offset(barRect.right + 260, barRect.center.dy));
    await pumpFrames(tester, 3);
    expect(frameLabel(), isNot(paused));

    await tester.tap(inVp(find.byIcon(Icons.casino_outlined)));
    await pumpFrames(tester, 3);

    for (final mode in ['SPLASH', 'TYPE', 'SPHERE']) {
      await tester.tap(find.text(mode));
      await pumpFrames(tester, 20);
    }
  });

  testWidgets('compositor: click expands a slice into a halftone split-screen',
      (tester) async {
    final ws = await boot(tester);
    ws.openNode(node(ws, 'render_passes'));
    await pumpFrames(tester, 40);
    expect(find.byType(CompositorContent), findsOneWidget);
    expect(find.byIcon(Icons.unfold_more_rounded), findsNothing);

    await tester.tap(find.byType(CompositorContent));
    // Step real frames so the expand (520 ms) and then the wipe (950 ms) run.
    await pumpFrames(tester, 40);
    await pumpFrames(tester, 90);
    // The split handle appears once the slice has expanded and wiped in.
    expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);

    final knob = tester.getCenter(find.byIcon(Icons.unfold_more_rounded));
    await tester.dragFrom(knob, const Offset(-120, 0));
    await tester.pump();
    expect(tester.getCenter(find.byIcon(Icons.unfold_more_rounded)).dx, lessThan(knob.dx - 60));
  });

  testWidgets('inspector sliders write the live shared shader params',
      (tester) async {
    final ws = await boot(tester);
    ws.openInspector();
    await pumpFrames(tester, 40);

    await tester.ensureVisible(find.text('Field Dynamics & Sliders'));
    await tester.tap(find.text('Field Dynamics & Sliders'));
    await pumpFrames(tester, 30);
    for (final label in [
      'Turbulence',
      'Coherence',
      'Particle Density',
      'Chromatic Dispersion',
      'Time Scale',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    final before = ws.params.turbulence;
    final slider = find.byType(Slider).first;
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(-150, 0));
    await tester.pump();
    expect(ws.params.turbulence, isNot(before));

    final dispersion = find.byType(Slider).at(3);
    await tester.ensureVisible(dispersion);
    await tester.drag(dispersion, const Offset(200, 0));
    await tester.pump();
    expect(ws.params.dispersion, greaterThan(0.05));
    // Pumping a few frames with dispersion on must not throw.
    await pumpFrames(tester, 10);
  });

  testWidgets('kinetic archive: opens with blur+fade, rows expand a 4-column strip',
      (tester) async {
    final ws = await boot(tester);
    ws.openOverlay(StudioOverlay.archive);
    await pumpFrames(tester, 8); // mid-transition (200 ms open)
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('VOLUMETRIC SHOCKWAVE'), findsOneWidget);

    await tester.tap(find.text('VOLUMETRIC SHOCKWAVE'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('01'), findsWidgets);
    expect(find.text('04'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(ws.overlay, StudioOverlay.none);
  });
}
