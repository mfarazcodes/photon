import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photon/main.dart';
import 'package:photon/services/render_socket.dart';
import 'package:photon/state/studio_controller.dart';
import 'package:photon/theme/photon_theme.dart';
import 'package:photon/widgets/ab_render_wipe.dart';
import 'package:photon/widgets/mac_window_viewport.dart';
import 'package:photon/widgets/pixel_loupe_probe.dart';
import 'package:photon/widgets/rauno_tick_scrubber.dart';
import 'package:photon/widgets/spatial_canvas.dart';

/// Pumps the app at [size] with an offline controller (no socket, no network).
Future<StudioController> _pumpStudio(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final studio = StudioController(autoConnect: false);
  await tester.pumpWidget(PhotonApp(controller: studio));
  await tester.pump(const Duration(milliseconds: 300));
  return studio;
}

/// Tears the tree down so the controller's ticker and the repeating pip
/// animations do not outlive the test.
Future<void> _teardown(WidgetTester tester, StudioController studio) async {
  // Let gesture timers (a double-tap tracker arms a 40ms one per pointer) fire
  // before the tree goes away.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox.shrink());
  studio.dispose();
}

/// A point inside the viewport stage, clear of the A/B curtain.
Offset _stagePoint(WidgetTester tester) =>
    tester.getCenter(find.text('SCENE_VIEWPORT.rt')) + const Offset(-250, 150);

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

/// Renders [child] in a 4x4 box and returns the center pixel.
Future<Color> _renderedColor(WidgetTester tester, Widget child) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(width: 4, height: 4, child: child),
        ),
      ),
    ),
  );
  final color = await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = (await image.toByteData())!;
    final offset = (2 * image.width + 2) * 4;
    return Color.fromARGB(
      data.getUint8(offset + 3),
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
  });
  return color!;
}

int _channel(double v) => (v * 255).round();

void main() {
  testWidgets('desktop layout shows every studio region', (tester) async {
    final studio = await _pumpStudio(tester, const Size(1280, 800));

    expect(find.text('PHOTON VFX STUDIO®'), findsOneWidget);
    expect(find.text('SCENE_VIEWPORT.rt'), findsOneWidget);
    expect(find.text('OPTICS_PARAMETERS'), findsOneWidget);
    expect(find.text('Vulkan RT • 256 SPP'), findsOneWidget);
    expect(find.text('CONVERGING'), findsOneWidget);
    expect(find.text('EXPORT EXR'), findsOneWidget);
    expect(find.textContaining('RENDER PROMPT'), findsOneWidget);
    for (final label in ['APERTURE', 'FOCAL DISTANCE', 'IOR', 'MAX BOUNCES', 'SAMPLES PER PIXEL', 'CAUSTICS ENERGY']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    for (final asset in kSceneAssets) {
      expect(find.text(asset.name), findsOneWidget, reason: asset.name);
    }
    expect(tester.takeException(), isNull);

    await _teardown(tester, studio);
  });

  testWidgets('companion layout reflows without overflow on a narrow window', (tester) async {
    final studio = await _pumpStudio(tester, const Size(390, 844));

    expect(find.text('ACTIVE SCENE ASSETS'), findsOneWidget);
    expect(find.text('SCENE_VIEWPORT.rt'), findsOneWidget);
    expect(find.text('OPTICS_PARAMETERS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _teardown(tester, studio);
  });

  testWidgets('short desktop windows scroll instead of overflowing', (tester) async {
    final studio = await _pumpStudio(tester, const Size(1000, 560));
    expect(tester.takeException(), isNull);
    await _teardown(tester, studio);
  });

  testWidgets('theme toggle switches to dark grading', (tester) async {
    final studio = await _pumpStudio(tester, const Size(1280, 800));
    expect(studio.darkGrading, isFalse);

    await tester.tap(find.text('DARK GRADING'));
    // MaterialApp animates theme changes: one frame to start, one to finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(studio.darkGrading, isTrue);
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.scaffoldBackgroundColor, PhotonPalette.grading.canvas);
    expect(theme.extension<PhotonTokens>()!.colors.isDark, isTrue);
    expect(tester.takeException(), isNull);

    await _teardown(tester, studio);
  });

  testWidgets('dragging an asset onto the viewport loads it', (tester) async {
    final studio = await _pumpStudio(tester, const Size(1280, 800));
    expect(studio.loadedAsset, isNull);

    final from = tester.getCenter(find.text('GOLD_ROUGH'));
    final to = tester.getCenter(find.text('SCENE_VIEWPORT.rt')) + const Offset(0, 200);
    final gesture = await tester.startGesture(from);
    await tester.pump();
    await gesture.moveTo(from + const Offset(40, 0));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));

    expect(studio.loadedAsset?.fileName, 'GOLD_ROUGH.bsdf');
    expect(tester.takeException(), isNull);

    await _teardown(tester, studio);
  });

  testWidgets('panning the viewport orbits the camera', (tester) async {
    final studio = await _pumpStudio(tester, const Size(1280, 800));
    expect(studio.orbit.value, Offset.zero);

    final stage = tester.getCenter(find.text('SCENE_VIEWPORT.rt')) + const Offset(0, 150);
    await tester.dragFrom(stage, const Offset(60, 20));
    await tester.pump();

    expect(studio.orbit.value.dx, greaterThan(0));
    expect(studio.orbit.value.dy, greaterThan(0));

    await _teardown(tester, studio);
  });

  group('StudioController', () {
    test('clamps parameters and restarts convergence on change', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.setParam('aperture', 99);
      expect(studio.param('aperture'), 16.0);

      studio.setParam('max_bounces', 7.4);
      expect(studio.maxBounces, 7);

      studio.setParam('samples_per_pixel', 64);
      expect(studio.targetSamples, 64);
      expect(studio.samples.value, 0);
    });

    test('prompts report offline instead of silently dropping', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      expect(studio.sendPrompt('   '), isFalse);
      expect(studio.toast.value, contains('DESCRIBE'));
      expect(studio.sendPrompt('liquid glass on chrome'), isFalse);
      expect(studio.toast.value, contains('OFFLINE'));
    });

    test('keeps the last frame when the stream goes quiet, and fps decays to 0', () {
      var clock = DateTime(2026, 1, 1);
      final studio = StudioController(autoConnect: false, now: () => clock);
      addTearDown(studio.dispose);

      final payload = base64Encode([1, 2, 3, 4]);
      studio.handleMessage({'frame': payload});
      clock = clock.add(const Duration(milliseconds: 16));
      studio.handleMessage({'frame': payload});
      expect(studio.fps.value, greaterThan(50));
      final held = studio.frame.value;
      expect(held, isNotNull);

      clock = clock.add(const Duration(seconds: 4));
      studio.debugTick();

      expect(studio.fps.value, 0);
      expect(studio.frame.value, same(held), reason: 'a finished render must stay on screen');

      studio.resetFrames();
      expect(studio.frame.value, isNull);
    });

    test('losing the link drops held frames', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.socket.link.value = RenderLink.live;
      studio.handleMessage({'frame': base64Encode([9, 9]), 'raw_frame': base64Encode([8, 8])});
      expect(studio.frame.value, isNotNull);
      expect(studio.rawFrame.value, isNotNull);

      studio.socket.link.value = RenderLink.offline;
      expect(studio.frame.value, isNull);
      expect(studio.rawFrame.value, isNull);
    });

    test('decodes raw_frame and ignores undecodable payloads', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.handleMessage({'raw_frame': base64Encode([5, 6, 7])});
      expect(studio.rawFrame.value, [5, 6, 7]);
      expect(studio.frame.value, isNull);

      studio.handleMessage({'frame': '***not base64***', 'raw_frame': 42});
      expect(studio.frame.value, isNull);
      expect(studio.rawFrame.value, [5, 6, 7]);
    });

    test('the timer stops when converged and idle, and restarts on change', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.setParam('samples_per_pixel', 16);
      expect(studio.tickerActive, isTrue);
      for (var i = 0; i < 200 && studio.tickerActive; i++) {
        studio.debugTick();
      }
      expect(studio.converged, isTrue);
      expect(studio.tickerActive, isFalse);

      studio.setParam('aperture', 2.0);
      expect(studio.tickerActive, isTrue);
    });

    test('a held frame keeps the timer alive until the idle check clears fps', () {
      var clock = DateTime(2026, 1, 1);
      final studio = StudioController(autoConnect: false, now: () => clock);
      addTearDown(studio.dispose);

      studio.setParam('samples_per_pixel', 16);
      for (var i = 0; i < 200 && studio.converged == false; i++) {
        studio.debugTick();
      }
      studio.handleMessage({'frame': base64Encode([1])});
      studio.debugTick();
      expect(studio.tickerActive, isTrue);

      clock = clock.add(const Duration(seconds: 4));
      studio.debugTick();
      expect(studio.tickerActive, isFalse);
    });

    test('A/B split is clamped and resettable', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      expect(studio.abWipeEnabled, isTrue);
      expect(studio.abSplit.value, 0.5);
      studio.setAbSplit(2);
      expect(studio.abSplit.value, 0.95);
      studio.setAbSplit(-1);
      expect(studio.abSplit.value, 0.05);
      studio.resetAbSplit();
      expect(studio.abSplit.value, 0.5);

      studio.setAbWipeEnabled(false);
      expect(studio.abWipeEnabled, isFalse);
    });

    test('false color and loupe toggle independently', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      expect(studio.falseColorEnabled, isFalse);
      expect(studio.loupeEnabled, isFalse);
      studio.toggleFalseColor();
      expect(studio.falseColorEnabled, isTrue);
      expect(studio.loupeEnabled, isFalse);
      studio.toggleLoupe();
      expect(studio.loupeEnabled, isTrue);
      studio.setFalseColor(false);
      studio.setLoupe(false);
      expect(studio.falseColorEnabled, isFalse);
      expect(studio.loupeEnabled, isFalse);
    });

    test('resetOrbit recenters the camera and restarts convergence', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.orbitBy(40, -25);
      expect(studio.orbit.value, const Offset(40, -25));
      for (var i = 0; i < 5; i++) {
        studio.debugTick();
      }
      expect(studio.samples.value, greaterThan(0));

      studio.resetOrbit();
      expect(studio.orbit.value, Offset.zero);
      expect(studio.samples.value, 0);
    });
  });

  group('viewport tools', () {
    testWidgets('A/B wipe curtain drag moves the split; double-tap resets it', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final curtain = find.byKey(AbRenderWipe.curtainKey);
      expect(curtain, findsOneWidget);
      expect(studio.abSplit.value, 0.5);

      await tester.drag(curtain, const Offset(120, 0));
      await tester.pump();
      expect(studio.abSplit.value, greaterThan(0.5));
      expect(studio.orbit.value, Offset.zero, reason: 'dragging the curtain must not orbit');

      await tester.drag(curtain, const Offset(-2000, 0));
      await tester.pump();
      expect(studio.abSplit.value, closeTo(0.05, 1e-9));

      await tester.tap(curtain);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(curtain);
      await tester.pump();
      expect(studio.abSplit.value, 0.5);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('A/B WIPE toggle removes the curtain and the noise pass', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      bool hasNoise() => find
          .byWidgetPredicate((w) => w is CustomPaint && w.painter is MonteCarloNoisePainter)
          .evaluate()
          .isNotEmpty;
      expect(find.text('RAW PT'), findsOneWidget);
      expect(find.text('OIDN DENOISED'), findsOneWidget);
      expect(hasNoise(), isTrue);

      await tester.tap(find.text('A/B WIPE'));
      await tester.pump();

      expect(studio.abWipeEnabled, isFalse);
      expect(find.byKey(AbRenderWipe.curtainKey), findsNothing);
      expect(hasNoise(), isFalse);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('FALSE COLOR and LOUPE titlebar toggles flip controller state', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(find.text('100+ IRE CLIP'), findsNothing);

      await tester.tap(find.text('FALSE COLOR'));
      await tester.pump();
      expect(studio.falseColorEnabled, isTrue);
      expect(find.text('100+ IRE CLIP'), findsOneWidget);

      await tester.tap(find.text('LOUPE'));
      await tester.pump();
      expect(studio.loupeEnabled, isTrue);

      await tester.tap(find.text('FALSE COLOR'));
      await tester.tap(find.text('LOUPE'));
      await tester.pump();
      expect(studio.falseColorEnabled, isFalse);
      expect(studio.loupeEnabled, isFalse);
      expect(find.text('100+ IRE CLIP'), findsNothing);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('the loupe follows the pointer and reports probe telemetry', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final mouse = await _mouse(tester);
      const lens = ValueKey('pixel-loupe');

      await mouse.moveTo(_stagePoint(tester));
      await tester.pump();
      expect(studio.probePosition.value, isNotNull);
      expect(find.byKey(lens), findsNothing, reason: 'loupe is off');

      await tester.tap(find.text('LOUPE'));
      await mouse.moveTo(_stagePoint(tester) + const Offset(30, 10));
      await tester.pump();
      expect(find.byKey(lens), findsOneWidget);
      expect(find.textContaining('XY: ('), findsOneWidget);
      expect(find.textContaining('cd/m²'), findsOneWidget);
      expect(find.textContaining('IRE:'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await mouse.moveTo(const Offset(4, 4));
      await tester.pump();
      expect(studio.probePosition.value, isNull);
      expect(find.byKey(lens), findsNothing);

      await _teardown(tester, studio);
    });

    testWidgets('holding Alt opens the loupe without the toggle', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final mouse = await _mouse(tester);
      await mouse.moveTo(_stagePoint(tester));
      await tester.pump();
      expect(find.byKey(const ValueKey('pixel-loupe')), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(find.byKey(const ValueKey('pixel-loupe')), findsOneWidget);
      expect(studio.loupeEnabled, isFalse);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(find.byKey(const ValueKey('pixel-loupe')), findsNothing);

      await _teardown(tester, studio);
    });

    testWidgets('narrow windows move the tools to a strip and survive every tool on', (tester) async {
      final studio = await _pumpStudio(tester, const Size(390, 844));
      for (final label in ['A/B WIPE', 'LOUPE', 'FALSE COLOR']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('FALSE COLOR'));
      await tester.tap(find.text('LOUPE'));
      final mouse = await _mouse(tester);
      await mouse.moveTo(tester.getCenter(find.text('SCENE_VIEWPORT.rt')) + const Offset(0, 90));
      await tester.pump();

      expect(find.text('100+ IRE CLIP'), findsOneWidget);
      expect(find.byKey(const ValueKey('pixel-loupe')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('the render always uses BoxFit.cover, in both studio modes', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));

      List<Image> renders() => tester
          .widgetList<Image>(find.byType(Image))
          .where((i) => i.image is AssetImage && (i.image as AssetImage).assetName == MacWindowViewport.fallbackAsset)
          .toList();

      expect(renders(), isNotEmpty);
      expect(renders().every((i) => i.fit == BoxFit.cover), isTrue);

      await tester.tap(find.text('DARK GRADING'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(renders(), isNotEmpty);
      expect(renders().every((i) => i.fit == BoxFit.cover), isTrue);

      await _teardown(tester, studio);
    });

    testWidgets('minimap click recenters the camera', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.orbitBy(120, 60);
      await tester.pump();
      expect(studio.orbit.value, isNot(Offset.zero));

      await tester.tap(find.byType(RaunoViewportMinimap));
      await tester.pump();
      expect(studio.orbit.value, Offset.zero);

      await _teardown(tester, studio);
    });
  });

  group('false color and probe math', () {
    testWidgets('maps luma to the IRE scale on rendered pixels', (tester) async {
      Future<Color> render(int gray, {bool enabled = true}) => _renderedColor(
        tester,
        FalseColorShaderWrapper(enabled: enabled, child: ColoredBox(color: Color.fromARGB(255, gray, gray, gray))),
      );
      void expectRgb(Color c, int r, int g, int b, {int tol = 8}) {
        expect(_channel(c.r), inInclusiveRange(r - tol, r + tol), reason: 'R of $c');
        expect(_channel(c.g), inInclusiveRange(g - tol, g + tol), reason: 'G of $c');
        expect(_channel(c.b), inInclusiveRange(b - tol, b + tol), reason: 'B of $c');
      }

      expectRgb(await render(0), 0, 0, 255); // 0 IRE: cursor blue
      expectRgb(await render(46), 0, 255, 179); // 18%: cyan / green
      expectRgb(await render(179), 255, 253, 3); // 70 IRE: signal yellow
      expectRgb(await render(255), 255, 45, 120); // clip: caustic rose (#FF2D78)

      // Disabled is a pass-through.
      expectRgb(await render(128, enabled: false), 128, 128, 128, tol: 1);
    });

    test('radiance is deterministic and responds to IOR and caustics energy', () {
      const uv = Offset(0.3, 0.6);
      final a = sampleRadiance(uv: uv, ior: 1.542, causticsEnergy: 1);
      final b = sampleRadiance(uv: uv, ior: 1.542, causticsEnergy: 1);
      expect(a.r, b.r);
      expect(a.g, b.g);
      expect(a.b, b.b);

      expect(sampleRadiance(uv: uv, ior: 2.4, causticsEnergy: 1).r, isNot(a.r));
      expect(sampleRadiance(uv: uv, ior: 1.542, causticsEnergy: 2).luminance, greaterThan(a.luminance));
      expect(sampleRadiance(uv: const Offset(0.8, 0.1), ior: 1.542, causticsEnergy: 1).r, isNot(a.r));
    });

    test('clipping is flagged once any channel exceeds 1.0', () {
      expect(const RadianceSample(1.14, 0.42, 0.98).clipped, isTrue);
      expect(const RadianceSample(0.9, 0.42, 0.98).clipped, isFalse);
      expect(const RadianceSample(0.18, 0.18, 0.18).ev, closeTo(0, 1e-9));
      expect(const RadianceSample(0.36, 0.36, 0.36).ev, closeTo(1, 1e-9));
    });

    test('stage position maps to render UV with a centered cover fit', () {
      // A stage wider than 16:9 crops top and bottom. Fitted to 1600px wide the
      // image is 900px tall, so a 400px stage hides 250px above and below.
      const wide = Size(1600, 400);
      expect(renderUv(const Offset(0.5, 0.5), wide), const Offset(0.5, 0.5));
      final topLeft = renderUv(Offset.zero, wide);
      expect(topLeft.dx, 0);
      expect(topLeft.dy, closeTo(250 / 900, 1e-9));

      // A taller stage crops the sides instead: a 400px square shows the middle
      // 400 of a 711px-wide image, so each side hides about 155px.
      const tall = Size(400, 400);
      final left = renderUv(Offset.zero, tall);
      expect(left.dy, 0);
      expect(left.dx, closeTo((400 * 16 / 9 - 400) / 2 / (400 * 16 / 9), 1e-9));
    });

    test('the loupe stays inside the stage and flips near the edges', () {
      const stage = Size(800, 400);
      const col = Size(PixelLoupeOverlay.readoutWidth, PixelLoupeOverlay.columnHeight);
      for (final p in const [Offset(10, 10), Offset(790, 390), Offset(400, 200), Offset(0, 400), Offset(800, 0)]) {
        final o = PixelLoupeOverlay.placement(p, stage);
        expect(o.dx, inInclusiveRange(PixelLoupeOverlay.margin, stage.width - col.width - PixelLoupeOverlay.margin));
        expect(o.dy, inInclusiveRange(PixelLoupeOverlay.margin, stage.height - col.height - PixelLoupeOverlay.margin));
      }
      // Near the right edge the lens moves to the left of the pointer.
      expect(PixelLoupeOverlay.placement(const Offset(790, 100), stage).dx, lessThan(790));
      // A stage shorter than the lens column clamps instead of throwing.
      expect(() => PixelLoupeOverlay.placement(const Offset(50, 50), const Size(300, 120)), returnsNormally);
    });
  });

  group('parameter scrubbers', () {
    testWidgets('dragging any card scrubs its value; double-tap resets to initial', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));

      for (final p in kOpticsParams) {
        final card = find.byKey(ValueKey('scrub-${p.id}'));
        expect(card, findsOneWidget, reason: p.id);
        final before = studio.param(p.id);

        await tester.drag(card, const Offset(100, 0));
        await tester.pump();
        expect(studio.param(p.id), greaterThan(before), reason: '${p.id} should scrub right');

        await tester.tap(card);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(card);
        await tester.pump();
        expect(studio.param(p.id), p.initial, reason: '${p.id} should reset on double-tap');
      }
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('Shift engages 0.1x vernier scrubbing', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final card = find.byKey(const ValueKey('scrub-aperture'));
      final start = studio.param('aperture');

      await tester.drag(card, const Offset(100, 0));
      final coarse = studio.param('aperture') - start;
      expect(coarse, greaterThan(0));
      studio.setParam('aperture', start);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.drag(card, const Offset(100, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      final fine = studio.param('aperture') - start;

      expect(fine, closeTo(coarse * 0.1, 1e-9));
      await _teardown(tester, studio);
    });

    testWidgets('arrow keys nudge a focused card', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final card = find.byKey(const ValueKey('scrub-max_bounces'));

      await tester.tap(card);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(studio.param('max_bounces'), 13);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(studio.param('max_bounces'), 11);

      await _teardown(tester, studio);
    });

    testWidgets('scrubbing exposes slider semantics without asserting', (tester) async {
      final handle = tester.ensureSemantics();
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(tester.takeException(), isNull);
      handle.dispose();
      await _teardown(tester, studio);
    });
  });

  group('command dock', () {
    testWidgets('Escape releases the prompt field; Ctrl+K takes it back', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final field = tester.widget<TextField>(find.byType(TextField));
      const beam = ValueKey('dock-beam');

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(field.focusNode!.hasFocus, isTrue);
      expect(find.byKey(beam), findsOneWidget, reason: 'the beam runs while focused');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(field.focusNode!.hasFocus, isFalse);
      expect(find.byKey(beam), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(field.focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('items swell toward the pointer and settle when it leaves', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final mouse = await _mouse(tester);

      double scaleOf(Finder item) => tester
          .widgetList<Transform>(find.descendant(of: item, matching: find.byType(Transform)))
          .map((t) => t.transform.getMaxScaleOnAxis())
          .fold(1.0, math.max);

      final monogram = find.byKey(const ValueKey('proximity-monogram'));
      final send = find.byKey(const ValueKey('proximity-send'));
      expect(scaleOf(monogram), closeTo(1, 1e-9));

      await mouse.moveTo(tester.getCenter(monogram));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(scaleOf(monogram), closeTo(1.16, 0.01));
      expect(scaleOf(send), lessThan(1.01), reason: 'a distant item barely moves');

      await mouse.moveTo(const Offset(4, 4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(scaleOf(monogram), closeTo(1, 1e-6));

      await _teardown(tester, studio);
    });

    testWidgets('neighbouring quick pills share one continuous hit strip', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      const labels = ['RENDER PROMPT', 'BSDF SHADERS', 'SCENE ARCHIVE', 'CAMERA OPTICS'];
      final rects = [for (final l in labels) tester.getRect(find.byKey(ValueKey('pill-hit-$l')))];

      for (var i = 0; i < rects.length - 1; i++) {
        expect(rects[i + 1].left - rects[i].right, closeTo(0, 0.01), reason: '${labels[i]} → ${labels[i + 1]}');
      }

      // The padding that used to be dead space between pills now triggers one.
      await tester.tapAt(Offset(rects.first.right - 1, rects.first.center.dy));
      await tester.pump();
      expect(studio.toast.value, contains('DESCRIBE'));

      await _teardown(tester, studio);
    });
  });

  test('the dot grid is rebuilt only when the size changes', () {
    final cache = DotGridCache();
    final a = cache.coordsFor(const Size(48, 32));
    expect(a.length, 12, reason: '3 columns x 2 rows x (x, y)');
    expect(a.sublist(0, 4), [8, 8, 24, 8]);
    expect(identical(cache.coordsFor(const Size(48, 32)), a), isTrue);

    final b = cache.coordsFor(const Size(1280, 800));
    expect(identical(a, b), isFalse);
    expect(b.length, 80 * 50 * 2);
    expect(cache.coordsFor(Size.zero), isEmpty);
  });
}
