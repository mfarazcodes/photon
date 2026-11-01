import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photon/main.dart';
import 'package:photon/state/studio_controller.dart';
import 'package:photon/theme/photon_theme.dart';

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
  await tester.pumpWidget(const SizedBox.shrink());
  studio.dispose();
}

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
  });
}
