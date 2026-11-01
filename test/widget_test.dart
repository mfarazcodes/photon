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
import 'package:photon/widgets/bvh_ray_overlay.dart';
import 'package:photon/widgets/mac_window_viewport.dart';
import 'package:photon/widgets/photon_primitives.dart';
import 'package:photon/widgets/pixel_loupe_probe.dart';
import 'package:photon/widgets/procedural_scene_canvas.dart';
import 'package:photon/widgets/projects_sidebar.dart';
import 'package:photon/widgets/rauno_tick_scrubber.dart';
import 'package:photon/widgets/spatial_canvas.dart';

/// A socket that never touches the network.
class _FakeSocket extends RenderSocket {
  int connects = 0;

  @override
  void connect() => connects++;
}

/// Pumps the app at [size] with an offline controller (no socket, no network).
Future<StudioController> _pumpStudio(
  WidgetTester tester,
  Size size, {
  StudioController? controller,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // animateShader off: live scenes hold a fixed phase instead of scheduling a
  // frame forever, so tests settle.
  final studio = controller ?? StudioController(autoConnect: false, animateShader: false);
  await tester.pumpWidget(PhotonApp(controller: studio));
  await tester.pump(const Duration(milliseconds: 300));
  return studio;
}

/// Scrolls [finder] into view (the header and the account modal scroll), then
/// taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

Future<void> _tapText(WidgetTester tester, String text) => _tap(tester, find.text(text));

Future<void> _tapKey(WidgetTester tester, Key key) => _tap(tester, find.byKey(key));

/// Tears the tree down so the controller's ticker and the repeating pip
/// animations do not outlive the test.
Future<void> _teardown(WidgetTester tester, StudioController studio) async {
  // Let gesture timers fire before the tree goes away.
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

/// Rasterizes the [RepaintBoundary] behind [key] to raw RGBA.
Future<ByteData> _capture(WidgetTester tester, GlobalKey key) async {
  final data = await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    return (await image.toByteData())!;
  });
  return data!;
}

Color _pixel(ByteData data, int width, int x, int y) {
  final o = (y * width + x) * 4;
  return Color.fromARGB(data.getUint8(o + 3), data.getUint8(o), data.getUint8(o + 1), data.getUint8(o + 2));
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
  return _pixel(await _capture(tester, key), 4, 2, 2);
}

int _channel(double v) => (v * 255).round();

DotMatrixPainter _dotPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((p) => p.painter)
    .whereType<DotMatrixPainter>()
    .single;

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
    for (final label in ['SPLIT', 'VIEWPORT', 'OPTICS']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('PROJECTS'), findsOneWidget);
    for (final project in kDefaultProjects) {
      expect(find.text(project.name), findsOneWidget, reason: project.name);
    }
    // The mark appears in the header and in the dock.
    expect(find.byType(PhotonLogoMark), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    await _teardown(tester, studio);
  });

  testWidgets('companion layout reflows without overflow on a narrow window', (tester) async {
    final studio = await _pumpStudio(tester, const Size(390, 844));

    expect(find.text('PROJECTS'), findsOneWidget);
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

  testWidgets('launches in Dark Studio and the theme toggle reaches Daylight Lab', (tester) async {
    final studio = await _pumpStudio(tester, const Size(1280, 800));
    expect(studio.darkGrading, isTrue);
    var theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF18191C));
    expect(theme.extension<PhotonTokens>()!.colors.substrate, const Color(0xFF141417));
    expect(theme.extension<PhotonTokens>()!.colors.border, const Color(0xFF2A2B30));

    await _tapText(tester, 'DAYLIGHT');
    // MaterialApp animates theme changes: one frame to start, one to finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(studio.darkGrading, isFalse);
    theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.scaffoldBackgroundColor, PhotonPalette.daylight.canvas);
    expect(theme.extension<PhotonTokens>()!.colors.isDark, isFalse);

    await _tapText(tester, 'DARK GRADING');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(studio.darkGrading, isTrue);
    expect(tester.takeException(), isNull);

    await _teardown(tester, studio);
  });

  testWidgets('dragging a project card onto the viewport loads it', (tester) async {
    final studio = await _pumpStudio(tester, const Size(1280, 800));
    expect(studio.activeProjectId, 'caustic_study_04');

    final from = tester.getCenter(find.text('GOLD_ATELIER_BSDF'));
    final to = tester.getCenter(find.text('SCENE_VIEWPORT.rt')) + const Offset(0, 200);
    final gesture = await tester.startGesture(from);
    await tester.pump();
    await gesture.moveTo(from + const Offset(40, 0));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));

    expect(studio.activeProjectId, 'gold_atelier_bsdf');
    expect(studio.param('ior'), 1.45);
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

    test('launches inside the first project', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      expect(studio.darkGrading, isTrue);
      expect(studio.projects.map((p) => p.name), [
        'CAUSTIC_STUDY_04',
        'GOLD_ATELIER_BSDF',
        'VOLUMETRIC_PRISM',
        'CHROME_CAUSTICS',
        'ACRYLIC_LENS_ARRAY',
        'KERR_PHOTON_RING',
        'THIN_FILM_IRIS',
      ]);
      expect(studio.liveShaderEnabled, isTrue, reason: 'the first project is dynamic');
      expect(studio.activeProjectId, 'caustic_study_04');
      expect(studio.param('ior'), 2.253);
      expect(studio.targetSamples, 256);
      expect(studio.integrator, IntegratorMode.unidirectional);
      expect(studio.toast.value, isNull, reason: 'the launch load is silent');
    });

    test('selecting a project loads its parameters and integrator', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.selectProject('volumetric_prism');
      expect(studio.param('ior'), 1.78);
      expect(studio.targetSamples, 1024);
      expect(studio.maxBounces, 16);
      expect(studio.integrator, IntegratorMode.sppm);
      expect(studio.samples.value, 0);
      expect(studio.toast.value, 'PROJECT LOADED · VOLUMETRIC_PRISM');

      studio.selectProject('nope');
      expect(studio.activeProjectId, 'volumetric_prism');
      expect(studio.toast.value, 'UNKNOWN PROJECT');
    });

    test('edits are kept per project', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.setParam('aperture', 9.0);
      studio.setIntegrator(IntegratorMode.restir);
      studio.selectProject('chrome_caustics');
      expect(studio.param('aperture'), 5.6);

      studio.selectProject('caustic_study_04');
      expect(studio.param('aperture'), 9.0);
      expect(studio.integrator, IntegratorMode.restir);
    });

    test('createNewProject snapshots the live studio and selects it', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.setParam('ior', 1.9);
      studio.createNewProject();
      expect(studio.projects, hasLength(8));
      final created = studio.activeProject!;
      expect(created.name, 'UNTITLED_08');
      expect(created.code, 'PRJ-08');
      expect(created.status, ProjectStatus.draft);
      expect(created.ior, 1.9);
      expect(studio.projects.first.id, created.id);

      studio.createNewProject('  MY_SHOT  ');
      expect(studio.activeProject!.name, 'MY_SHOT');
    });

    test('duplicate and delete keep a valid active project', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.duplicateProject('gold_atelier_bsdf');
      expect(studio.projects, hasLength(8));
      expect(studio.projects[2].name, 'GOLD_ATELIER_BSDF_COPY');

      studio.deleteProject('caustic_study_04');
      expect(studio.projects.any((p) => p.id == 'caustic_study_04'), isFalse);
      expect(studio.projects.any((p) => p.id == studio.activeProjectId), isTrue);
      expect(studio.toast.value, 'PROJECT DELETED · CAUSTIC_STUDY_04');

      for (final p in studio.projects.skip(1).toList()) {
        studio.deleteProject(p.id);
      }
      expect(studio.projects, hasLength(1));
      studio.deleteProject(studio.projects.single.id);
      expect(studio.projects, hasLength(1), reason: 'the last project cannot be deleted');
      expect(studio.toast.value, 'KEEP AT LEAST ONE PROJECT');
    });

    test('loadAsset routes a project id to the project loader', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.loadAsset('chrome_caustics');
      expect(studio.activeProjectId, 'chrome_caustics');

      studio.loadAsset('GOLD_ROUGH.bsdf');
      expect(studio.loadedAsset?.fileName, 'GOLD_ROUGH.bsdf');
    });

    test('integrator cycles through all four modes and wraps', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      final seen = <IntegratorMode>[studio.integrator];
      for (var i = 0; i < 4; i++) {
        studio.cycleIntegrator();
        seen.add(studio.integrator);
      }
      expect(seen, [
        IntegratorMode.unidirectional,
        IntegratorMode.bidirectional,
        IntegratorMode.sppm,
        IntegratorMode.restir,
        IntegratorMode.unidirectional,
      ]);
      expect(IntegratorMode.bidirectional.label, 'BIDIRECTIONAL PT');
      expect(IntegratorMode.restir.solverCaption, 'Spatiotemporal');
      expect(studio.toast.value, 'INTEGRATOR · UNIDIRECTIONAL PT');
    });

    test('bounces step through 4/8/12/16/24/32 and wrap', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      final seen = <int>[studio.maxBounces];
      for (var i = 0; i < 6; i++) {
        studio.cycleMaxBounces();
        seen.add(studio.maxBounces);
      }
      expect(seen, [12, 16, 24, 32, 4, 8, 12]);

      studio.nudgeMaxBounces(1);
      expect(studio.maxBounces, 13);
      studio.cycleMaxBounces();
      expect(studio.maxBounces, 16, reason: 'an off-step value rounds up to the next step');
    });

    test('panel window state: collapse, maximize, reset', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.toggleViewportCollapsed();
      studio.toggleOpticsCollapsed();
      expect(studio.viewportCollapsed, isTrue);
      expect(studio.opticsCollapsed, isTrue);

      studio.toggleMaximizedPanel('viewport');
      expect(studio.maximizedPanel, 'viewport');
      expect(studio.viewportCollapsed, isFalse, reason: 'maximizing expands the panel');
      expect(studio.opticsCollapsed, isTrue);
      studio.toggleMaximizedPanel('viewport');
      expect(studio.maximizedPanel, isNull);

      studio.setParam('aperture', 9);
      studio.resetAllParams();
      for (final p in kOpticsParams) {
        expect(studio.param(p.id), p.initial, reason: p.id);
      }
      expect(studio.toast.value, 'OPTICS RESET TO DEFAULT');

      studio.orbitBy(10, 10);
      studio.setAbSplit(0.8);
      studio.setFalseColor(true);
      studio.setLoupe(true);
      studio.resetViewportStage();
      expect(studio.orbit.value, Offset.zero);
      expect(studio.abSplit.value, 0.5);
      expect(studio.falseColorEnabled, isFalse);
      expect(studio.loupeEnabled, isFalse);
      expect(studio.toast.value, 'VIEWPORT RESET');
    });
  });

  group('dot-matrix background', () {
    testWidgets('is the dark charcoal grid by default and follows the pointer', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final painter = _dotPainter(tester);
      expect(painter.color, const Color(0xFF2E3036));
      expect(painter.highlight, Colors.white);
      expect(painter.tint, const Color(0xFFB57BFF));
      expect(painter.pointerPos.value, isNull);

      final mouse = await _mouse(tester);
      await mouse.moveTo(const Offset(420, 310));
      await tester.pump();
      expect(painter.pointerPos.value, const Offset(420, 310));

      await mouse.moveTo(const Offset(640, 90));
      await tester.pump();
      expect(painter.pointerPos.value, const Offset(640, 90));

      await _teardown(tester, studio);
    });

    testWidgets('daylight mode uses the light grid', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      await _tapText(tester, 'DAYLIGHT');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_dotPainter(tester).color, const Color(0xFFD0D0D8));
      await _teardown(tester, studio);
    });

    test('falloff is squared, 1 at the cursor and 0 at 170px', () {
      expect(DotMatrixPainter.proximity(0), 1);
      expect(DotMatrixPainter.proximity(85), closeTo(0.25, 1e-9));
      expect(DotMatrixPainter.proximity(170), 0);
      expect(DotMatrixPainter.proximity(400), 0);
    });

    testWidgets('lights the dot under the pointer and leaves distant dots alone', (tester) async {
      final pos = ValueNotifier<Offset?>(const Offset(104, 104));
      addTearDown(pos.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 400,
                height: 200,
                child: ColoredBox(
                  color: Colors.black,
                  child: DotMatrixSubstrate(
                    color: const Color(0xFF2E3036),
                    highlight: Colors.white,
                    tint: const Color(0xFFB57BFF),
                    pointerPos: pos,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      var data = await _capture(tester, key);
      final lit = _pixel(data, 400, 104, 104);
      final far = _pixel(data, 400, 392, 104);
      expect(_channel(lit.r), greaterThan(200), reason: 'the dot at the cursor is near white');
      expect(_channel(far.r), lessThan(40), reason: 'a dot 288px away stays charcoal');

      pos.value = null;
      await tester.pump();
      data = await _capture(tester, key);
      expect(_channel(_pixel(data, 400, 104, 104).r), lessThan(40), reason: 'no pointer, no spotlight');
    });

    test('the dot grid is rebuilt only when the size changes', () {
      final cache = DotGridCache();
      final a = cache.coordsFor(const Size(48, 32));
      expect(a.length, 12, reason: '3 columns x 2 rows x (x, y)');
      expect(cache.columns, 3);
      expect(cache.rows, 2);
      expect(a.sublist(0, 4), [8, 8, 24, 8]);
      expect(identical(cache.coordsFor(const Size(48, 32)), a), isTrue);

      final b = cache.coordsFor(const Size(1280, 800));
      expect(identical(a, b), isFalse);
      expect(b.length, 80 * 50 * 2);
      expect(cache.coordsFor(Size.zero), isEmpty);
    });
  });

  group('projects sidebar', () {
    testWidgets('lists the projects with telemetry and marks the active one', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));

      expect(tester.getSize(find.byType(ProjectsSidebar)).width, ProjectsSidebar.width);
      expect(find.text('.pht · Dispersion Rig'), findsOneWidget);
      expect(find.text('256 SPP · IOR 2.253'), findsOneWidget);
      expect(find.text('512 SPP · IOR 1.450'), findsOneWidget);
      expect(find.text('1024 SPP · IOR 1.780'), findsOneWidget);
      expect(find.text('ACTIVE · 2m ago'), findsOneWidget);
      expect(find.text('RENDERED · 1h ago'), findsOneWidget);
      expect(find.text('DRAFT · Yesterday'), findsOneWidget);
      expect(find.byKey(const Key('new-project-btn')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('tapping a project loads its parameters', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));

      await tester.tap(find.byKey(const ValueKey('project-gold_atelier_bsdf')));
      await tester.pump();

      expect(studio.activeProjectId, 'gold_atelier_bsdf');
      expect(studio.param('ior'), 1.45);
      expect(studio.targetSamples, 512);
      expect(find.text('Vulkan RT • 512 SPP'), findsOneWidget);
      expect(studio.toast.value, 'PROJECT LOADED · GOLD_ATELIER_BSDF');

      await _tapKey(tester, const ValueKey('project-chrome_caustics'));
      await tester.pump();
      expect(studio.integrator, IntegratorMode.bidirectional);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('+ NEW adds a project from the current settings', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(studio.projects, hasLength(7));

      await tester.tap(find.byKey(const Key('new-project-btn')));
      await tester.pump();

      expect(studio.projects, hasLength(8));
      expect(studio.activeProject!.name, 'UNTITLED_08');
      expect(find.text('UNTITLED_08'), findsOneWidget);
      expect(find.text('8'), findsOneWidget, reason: 'the count badge');
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('hovering a card reveals duplicate and delete', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final mouse = await _mouse(tester);
      const id = 'gold_atelier_bsdf';
      expect(find.byKey(const ValueKey('project-del-$id')), findsNothing);

      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('project-$id'))));
      await tester.pump();
      expect(find.byKey(const ValueKey('project-del-$id')), findsOneWidget);
      expect(find.byKey(const ValueKey('project-dup-$id')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('project-dup-$id')));
      await tester.pump();
      expect(studio.projects, hasLength(8));
      expect(find.text('GOLD_ATELIER_BSDF_COPY'), findsOneWidget);

      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('project-$id'))));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('project-del-$id')));
      await tester.pump();
      expect(studio.projects.any((p) => p.id == id), isFalse);
      expect(find.text('GOLD_ATELIER_BSDF'), findsNothing);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('the companion carousel loads projects too', (tester) async {
      final studio = await _pumpStudio(tester, const Size(390, 844));
      await tester.tap(find.byKey(const ValueKey('project-caustic_study_04')));
      await tester.pump();
      expect(studio.activeProjectId, 'caustic_study_04');
      await tester.tap(find.byKey(const Key('new-project-btn')));
      await tester.pump();
      expect(studio.projects, hasLength(8));
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('lists all seven projects with dynamic and static badges', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      for (final p in kDefaultProjects) {
        expect(find.text(p.name), findsOneWidget, reason: p.name);
      }
      expect(studio.projects.where((p) => p.isDynamic), hasLength(5));
      expect(find.text('⚡ DYNAMIC'), findsNWidgets(5));
      expect(find.text('\u{1F5BC} STATIC'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('DYNAMIC and STATIC filters narrow the list; ALL restores it', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      const dynamicNames = {
        'CAUSTIC_STUDY_04',
        'VOLUMETRIC_PRISM',
        'CHROME_CAUSTICS',
        'KERR_PHOTON_RING',
        'THIN_FILM_IRIS',
      };
      const staticNames = {'GOLD_ATELIER_BSDF', 'ACRYLIC_LENS_ARRAY'};

      await tester.tap(find.byKey(const Key('project-filter-dynamic')));
      await tester.pump();
      for (final n in dynamicNames) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      for (final n in staticNames) {
        expect(find.text(n), findsNothing, reason: n);
      }

      await tester.tap(find.byKey(const Key('project-filter-static')));
      await tester.pump();
      for (final n in staticNames) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      for (final n in dynamicNames) {
        expect(find.text(n), findsNothing, reason: n);
      }

      await tester.tap(find.byKey(const Key('project-filter-all')));
      await tester.pump();
      for (final n in {...dynamicNames, ...staticNames}) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the search field filters by name, and an empty result says so', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      await tester.enterText(find.byKey(const Key('project-search')), 'kerr');
      await tester.pump();
      expect(find.text('KERR_PHOTON_RING'), findsOneWidget);
      expect(find.text('CAUSTIC_STUDY_04'), findsNothing);

      await tester.enterText(find.byKey(const Key('project-search')), 'zzzz');
      await tester.pump();
      expect(find.text('NO PROJECTS MATCH'), findsOneWidget);

      // Filter and search combine.
      await tester.enterText(find.byKey(const Key('project-search')), 'prism');
      await tester.tap(find.byKey(const Key('project-filter-static')));
      await tester.pump();
      expect(find.text('NO PROJECTS MATCH'), findsOneWidget, reason: 'VOLUMETRIC_PRISM is dynamic');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });
  });

  group('window pips', () {
    testWidgets('viewport: red resets, yellow collapses, green maximizes', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));

      // Red: reset the stage.
      studio
        ..orbitBy(30, 30)
        ..setAbSplit(0.8)
        ..setFalseColor(true)
        ..setLoupe(true);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pip-close-viewport')));
      await tester.pump();
      expect(studio.orbit.value, Offset.zero);
      expect(studio.abSplit.value, 0.5);
      expect(studio.falseColorEnabled, isFalse);
      expect(studio.loupeEnabled, isFalse);
      expect(studio.toast.value, 'VIEWPORT RESET');

      // Yellow: only the titlebar remains; the optics panel is still there.
      await tester.tap(find.byKey(const ValueKey('pip-minimize-viewport')));
      await tester.pump();
      expect(studio.viewportCollapsed, isTrue);
      expect(find.byKey(AbRenderWipe.curtainKey), findsNothing);
      expect(find.text('SCENE_VIEWPORT.rt'), findsOneWidget);
      expect(find.text('OPTICS_PARAMETERS'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('pip-minimize-viewport'))).height, lessThan(MacTitlebar.height));
      await tester.tap(find.byKey(const ValueKey('pip-minimize-viewport')));
      await tester.pump();
      expect(studio.viewportCollapsed, isFalse);
      expect(find.byKey(AbRenderWipe.curtainKey), findsOneWidget);

      // Green: the viewport takes the whole center column.
      await tester.tap(find.byKey(const ValueKey('pip-zoom-viewport')));
      await tester.pump();
      expect(studio.maximizedPanel, 'viewport');
      expect(find.text('OPTICS_PARAMETERS'), findsNothing);
      expect(find.text('SCENE_VIEWPORT.rt'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pip-zoom-viewport')));
      await tester.pump();
      expect(studio.maximizedPanel, isNull);
      expect(find.text('OPTICS_PARAMETERS'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('optics: red resets, yellow collapses, green maximizes', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));

      studio.setParam('aperture', 9);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pip-close-optics')));
      await tester.pump();
      for (final p in kOpticsParams) {
        expect(studio.param(p.id), p.initial, reason: p.id);
      }
      expect(studio.toast.value, 'OPTICS RESET TO DEFAULT');

      await tester.tap(find.byKey(const ValueKey('pip-minimize-optics')));
      await tester.pump();
      expect(studio.opticsCollapsed, isTrue);
      expect(find.byKey(const ValueKey('scrub-aperture')), findsNothing);
      expect(find.text('OPTICS_PARAMETERS'), findsOneWidget);
      expect(find.text('SCENE_VIEWPORT.rt'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pip-minimize-optics')));
      await tester.pump();
      expect(find.byKey(const ValueKey('scrub-aperture')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pip-zoom-optics')));
      await tester.pump();
      expect(studio.maximizedPanel, 'optics');
      expect(find.text('SCENE_VIEWPORT.rt'), findsNothing);
      expect(find.byKey(const ValueKey('scrub-aperture')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pip-zoom-optics')));
      await tester.pump();
      expect(find.text('SCENE_VIEWPORT.rt'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('collapsing one panel gives the other the space', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final before = tester.getSize(find.byKey(const ValueKey('scrub-aperture'))).height;
      final viewportBefore = tester.getRect(find.byKey(const ValueKey('pip-zoom-viewport')));

      await tester.tap(find.byKey(const ValueKey('pip-minimize-optics')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pip-minimize-optics')));
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey('scrub-aperture'))).height, before);

      // With the optics panel collapsed the viewport grows downward.
      await tester.tap(find.byKey(const ValueKey('pip-minimize-optics')));
      await tester.pump();
      final stageHeightCollapsed = tester.getSize(find.byKey(AbRenderWipe.curtainKey)).height;
      await tester.tap(find.byKey(const ValueKey('pip-minimize-optics')));
      await tester.pump();
      final stageHeightSplit = tester.getSize(find.byKey(AbRenderWipe.curtainKey)).height;
      expect(stageHeightCollapsed, greaterThan(stageHeightSplit));
      expect(tester.getRect(find.byKey(const ValueKey('pip-zoom-viewport'))), viewportBefore);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('glyphs show on hover and tooltips name the actions', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final mouse = await _mouse(tester);

      double glyphOpacity() => tester
          .widget<AnimatedOpacity>(
            find.descendant(
              of: find.byKey(const ValueKey('pip-close-viewport')),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;

      expect(glyphOpacity(), 0);
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('pip-minimize-viewport'))));
      await tester.pump();
      expect(glyphOpacity(), 1, reason: 'the whole group reveals its glyphs');

      expect(find.byTooltip('Reset panel'), findsNWidgets(2));
      expect(find.byTooltip('Collapse / expand panel'), findsNWidgets(2));
      expect(find.byTooltip('Maximize / focus panel'), findsNWidgets(2));

      await mouse.moveTo(const Offset(640, 700));
      await tester.pump();
      expect(glyphOpacity(), 0);

      await _teardown(tester, studio);
    });

    testWidgets('the header workspace switch drives the same maximize state', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));

      await _tapText(tester, 'OPTICS');
      await tester.pump();
      expect(studio.maximizedPanel, 'optics');
      expect(find.text('SCENE_VIEWPORT.rt'), findsNothing);

      await _tapText(tester, 'VIEWPORT');
      await tester.pump();
      expect(studio.maximizedPanel, 'viewport');
      expect(find.text('OPTICS_PARAMETERS'), findsNothing);

      await _tapText(tester, 'SPLIT');
      await tester.pump();
      expect(studio.maximizedPanel, isNull);
      expect(find.text('OPTICS_PARAMETERS'), findsOneWidget);
      expect(find.text('SCENE_VIEWPORT.rt'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('companion layout honors collapse and maximize', (tester) async {
      final studio = await _pumpStudio(tester, const Size(390, 844));

      await tester.tap(find.byKey(const ValueKey('pip-minimize-viewport')));
      await tester.pump();
      expect(find.byKey(AbRenderWipe.curtainKey), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pip-minimize-viewport')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('pip-zoom-viewport')));
      await tester.pump();
      expect(find.text('OPTICS_PARAMETERS'), findsNothing);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });
  });

  group('viewport HUD', () {
    testWidgets('tapping 12 BOUNCES steps the depth to 16, then onward and around', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final pill = find.byKey(const Key('hud-bounces-pill'));
      expect(studio.maxBounces, 12);
      expect(find.text('12 BOUNCES'), findsOneWidget);

      await tester.tap(pill);
      await tester.pump();
      expect(studio.maxBounces, 16);
      expect(find.text('16 BOUNCES'), findsOneWidget);

      for (final expected in [24, 32, 4]) {
        await tester.tap(pill);
        await tester.pump();
        expect(studio.maxBounces, expected);
      }
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('scrolling or dragging the bounces pill adjusts it', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final pill = find.byKey(const Key('hud-bounces-pill'));

      final wheel = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(wheel.hover(tester.getCenter(pill)));
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, -24)));
      await tester.pump();
      expect(studio.maxBounces, 13, reason: 'wheel up adds one');
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 24)));
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 24)));
      await tester.pump();
      expect(studio.maxBounces, 11, reason: 'wheel down subtracts one each');

      final before = studio.maxBounces;
      await tester.drag(pill, const Offset(90, 0));
      await tester.pump();
      expect(studio.maxBounces, greaterThan(before));
      expect(studio.orbit.value, Offset.zero, reason: 'the HUD swallows the drag');
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('tapping UNIDIRECTIONAL PT cycles the integrator and the caustics readout', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final pill = find.byKey(const Key('hud-integrator-pill'));
      expect(studio.integrator, IntegratorMode.unidirectional);
      expect(find.text('UNIDIRECTIONAL PT'), findsOneWidget);
      expect(find.text('Cauchy'), findsOneWidget);

      await tester.tap(pill);
      await tester.pump();
      expect(studio.integrator, IntegratorMode.bidirectional);
      expect(find.text('BIDIRECTIONAL PT'), findsOneWidget);
      expect(find.text('BiDir MIS'), findsOneWidget);
      expect(find.text('Cauchy'), findsNothing);

      await tester.tap(pill);
      await tester.pump();
      expect(find.text('Photon Map'), findsOneWidget);
      expect(find.text('SPPM CAUSTICS'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('the status pill reconnects and refreshes the stream', (tester) async {
      final socket = _FakeSocket();
      final studio = await _pumpStudio(
        tester,
        const Size(1280, 800),
        controller: StudioController(socket: socket, autoConnect: false),
      );
      studio.handleMessage({'frame': base64Encode([1, 2, 3])});
      await tester.pump();
      expect(studio.frame.value, isNotNull);

      await tester.tap(find.byKey(const Key('hud-link-pill')));
      await tester.pump();
      expect(socket.connects, 1);
      expect(studio.frame.value, isNull);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('the HUD still fits a narrow stage', (tester) async {
      final studio = await _pumpStudio(tester, const Size(390, 844));
      await tester.tap(find.byKey(const Key('hud-integrator-pill')));
      await tester.pump();
      expect(studio.integrator, IntegratorMode.bidirectional);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });
  });

  group('viewport tools', () {
    testWidgets('A/B wipe curtain drag moves the split; double-tap resets it', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final curtain = find.byKey(AbRenderWipe.curtainKey);
      expect(curtain, findsOneWidget);
      expect(studio.abSplit.value, 0.5);
      expect(tester.getSize(find.ancestor(of: curtain, matching: find.byType(Positioned)).first).width, 56);

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

    testWidgets('the curtain jumps to the pointer on press, following its exact X', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final curtain = find.byKey(AbRenderWipe.curtainKey);
      final center = tester.getCenter(curtain);

      // Press 20px right of the divider (still inside the 56px zone).
      final gesture = await tester.startGesture(center + const Offset(20, 0));
      await tester.pump();
      final stage = tester.getRect(find.ancestor(of: curtain, matching: find.byType(LayoutBuilder)).first);
      expect(studio.abSplit.value, closeTo((center.dx + 20 - stage.left) / stage.width, 1e-6));

      await gesture.moveTo(center + const Offset(200, 5));
      await tester.pump();
      expect(studio.abSplit.value, closeTo((center.dx + 200 - stage.left) / stage.width, 1e-6));
      await gesture.up();
      await tester.pump();
      expect(studio.orbit.value, Offset.zero);

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
      // Stills only: the first project opens on its live shader.
      studio.setLiveShader(false);
      await tester.pump();

      List<Image> renders() => tester
          .widgetList<Image>(find.byType(Image))
          .where((i) => i.image is AssetImage && (i.image as AssetImage).assetName == MacWindowViewport.fallbackAsset)
          .toList();

      expect(renders(), isNotEmpty);
      expect(renders().every((i) => i.fit == BoxFit.cover), isTrue);

      await _tapText(tester, 'DAYLIGHT');
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

  group('fast double tap', () {
    PointerDownEvent down(int ms, {Offset at = const Offset(10, 10)}) =>
        PointerDownEvent(position: at, timeStamp: Duration(milliseconds: ms));
    PointerUpEvent up(int ms, {Offset at = const Offset(10, 10)}) =>
        PointerUpEvent(position: at, timeStamp: Duration(milliseconds: ms));

    test('two quick taps are a double tap', () {
      final t = FastDoubleTap();
      expect(t.down(down(0)), isFalse);
      t.up(up(40));
      expect(t.down(down(180)), isTrue);
      t.up(up(220));
      expect(t.down(down(300)), isFalse, reason: 'the second tap was consumed; a third starts fresh');
    });

    test('a slow second tap is not a double tap', () {
      final t = FastDoubleTap();
      t.down(down(0));
      t.up(up(40));
      expect(t.down(down(40 + 300)), isFalse);
    });

    test('a drag followed quickly by another press is not a double tap', () {
      final t = FastDoubleTap();
      t.down(down(0));
      t.move(const PointerMoveEvent(position: Offset(80, 10), timeStamp: Duration(milliseconds: 20)));
      t.up(up(60, at: const Offset(80, 10)));
      expect(t.down(down(120)), isFalse);
    });

    test('a long press is not a tap', () {
      final t = FastDoubleTap();
      t.down(down(0));
      t.up(up(500));
      expect(t.down(down(560)), isFalse);
    });

    test('a cancelled press is forgotten', () {
      final t = FastDoubleTap();
      t.down(down(0));
      t.cancel();
      t.up(up(30));
      expect(t.down(down(80)), isFalse);
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

    testWidgets('scrubbing starts on the first pixel and scales with the card width', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final card = find.byKey(const ValueKey('scrub-aperture'));
      final width = tester.getSize(card).width;
      final start = studio.param('aperture');

      final gesture = await tester.startGesture(tester.getCenter(card));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.up();

      // No touch slop is swallowed: the full 30px counts, at 1.25x the range.
      final expected = (16.0 - 1.0) * (30 / width) * RaunoTickScrubber.coarseSensitivity;
      expect(studio.param('aperture') - start, closeTo(expected, 1e-9));

      await _teardown(tester, studio);
    });

    testWidgets('Shift engages 0.12x vernier scrubbing', (tester) async {
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

      expect(fine, closeTo(coarse * RaunoTickScrubber.fineSensitivity / RaunoTickScrubber.coarseSensitivity, 1e-9));
      await _teardown(tester, studio);
    });

    testWidgets('reversing after hitting the end responds immediately', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final card = find.byKey(const ValueKey('scrub-caustics_energy'));
      final width = tester.getSize(card).width;

      final gesture = await tester.startGesture(tester.getCenter(card));
      await gesture.moveBy(Offset(width * 2, 0)); // far past the maximum
      await tester.pump();
      expect(studio.param('caustics_energy'), 2.0);

      await gesture.moveBy(const Offset(-10, 0));
      await tester.pump();
      expect(studio.param('caustics_energy'), lessThan(2.0), reason: 'no overshoot to unwind');
      await gesture.up();

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
    testWidgets('is scaled up 1.2x', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));

      expect(tester.getSize(find.byKey(const ValueKey('proximity-monogram'))), const Size(40, 40));
      expect(tester.getSize(find.byKey(const ValueKey('proximity-link'))), const Size(40, 40));
      expect(tester.getSize(find.byKey(const ValueKey('proximity-send'))), const Size(40, 40));
      expect(tester.getSize(find.byKey(const Key('scene-prompt'))).height, 44);
      expect(tester.getSize(find.byKey(const ValueKey('pill-hit-RENDER PROMPT'))).height, 44);

      final prompt = tester.widget<TextField>(find.byKey(const Key('scene-prompt')));
      expect(prompt.style!.fontSize, 13.5);
      expect(prompt.cursorHeight, 18);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('Escape releases the prompt field; Ctrl+K takes it back', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final field = tester.widget<TextField>(find.byKey(const Key('scene-prompt')));
      const beam = ValueKey('dock-beam');

      await tester.tap(find.byKey(const Key('scene-prompt')));
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

  group('theme synchronization', () {
    test('palette values match the studio spec', () {
      expect(PhotonPalette.daylight.dock, const Color(0xFFFFFFFF));
      expect(PhotonPalette.daylight.onDock, const Color(0xFF0E0E10));
      expect(PhotonPalette.daylight.viewportMatte, const Color(0xFFE6E6EC));
      expect(PhotonPalette.grading.dock, const Color(0xFF101012));
      expect(PhotonPalette.grading.onDock, const Color(0xFFF3F3F5));
      expect(PhotonPalette.grading.canvas, const Color(0xFF18191C));
      expect(PhotonPalette.grading.substrate, const Color(0xFF141417));
      expect(PhotonPalette.grading.surface, const Color(0xFF1E1F22));
      expect(PhotonPalette.grading.border, const Color(0xFF2A2B30));
    });

    testWidgets('switching to Daylight re-skins the dock and the header, and back', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      Color? dockColor() =>
          (tester.widget<Container>(find.byKey(const ValueKey('dock-surface'))).decoration as BoxDecoration).color;
      BoxDecoration dockDecoration() =>
          tester.widget<Container>(find.byKey(const ValueKey('dock-surface'))).decoration! as BoxDecoration;
      Color? headerColor() => (tester.widget<AnimatedContainer>(find.byKey(const ValueKey('top-bar'))).decoration
              as BoxDecoration)
          .color;
      InputDecoration prompt() => tester.widget<TextField>(find.byKey(const Key('scene-prompt'))).decoration!;

      expect(dockColor(), const Color(0xFF101012));
      expect(headerColor(), PhotonPalette.grading.substrate);

      await _tapText(tester, 'DAYLIGHT');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(dockColor(), const Color(0xFFFFFFFF));
      expect((dockDecoration().border! as Border).top.color, PhotonPalette.daylight.border);
      expect(headerColor(), const Color(0xFFF9F9FB));
      expect(prompt().fillColor, PhotonPalette.daylight.canvas);
      expect(tester.widget<TextField>(find.byKey(const Key('scene-prompt'))).style!.color, const Color(0xFF0E0E10));
      expect(tester.takeException(), isNull);

      await _tapText(tester, 'DARK GRADING');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(dockColor(), const Color(0xFF101012));
      expect(headerColor(), PhotonPalette.grading.substrate);
      expect(prompt().fillColor, Colors.white.withValues(alpha: 0.08));

      await _teardown(tester, studio);
    });

    testWidgets('the Photon mark swaps its tile between the two themes', (tester) async {
      Future<Color> tile({required bool dark}) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox.square(dimension: 40, child: PhotonLogoMark(size: 40, isDark: dark)),
              ),
            ),
          ),
        );
        return _pixel(await _capture(tester, key), 40, 4, 20);
      }

      final dark = await tile(dark: true);
      final light = await tile(dark: false);
      expect(_channel(dark.r), lessThan(40), reason: 'Matte Carbon tile');
      expect(_channel(light.r), greaterThan(230), reason: 'alabaster tile');
    });

    testWidgets('the mark follows the ambient theme when not forced', (tester) async {
      final key = GlobalKey();
      Future<Color> sample(Brightness b) async {
        await tester.pumpWidget(
          Theme(
            data: ThemeData(brightness: b),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: RepaintBoundary(
                  key: key,
                  child: const SizedBox.square(dimension: 40, child: PhotonLogoMark(size: 40)),
                ),
              ),
            ),
          ),
        );
        return _pixel(await _capture(tester, key), 40, 4, 20);
      }

      expect(_channel((await sample(Brightness.dark)).r), lessThan(40));
      expect(_channel((await sample(Brightness.light)).r), greaterThan(230));
    });

    testWidgets('toggling the theme tells the native window to restyle its caption', (tester) async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('photon/window');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(calls, isEmpty, reason: 'launch is already dark; nothing to send');

      await _tapText(tester, 'DAYLIGHT');
      await tester.pump();
      expect(calls.single.method, 'setDarkTheme');
      expect(calls.single.arguments, false);

      await _tapText(tester, 'DARK GRADING');
      await tester.pump();
      expect(calls, hasLength(2));
      expect(calls.last.arguments, true);

      studio.setDarkGrading(true);
      expect(calls, hasLength(2), reason: 'no change, no call');
      await _teardown(tester, studio);
    });

    testWidgets('a missing native channel is harmless', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setDarkGrading(false);
      studio.setDarkGrading(true);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });
  });

  group('live procedural scenes', () {
    /// Paints [kind] at 480x300 and returns the raw pixels.
    Future<ByteData> render(WidgetTester tester, StudioController studio, ProceduralSceneKind kind) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(width: 480, height: 300, child: ProceduralSceneCanvas(studio: studio, kind: kind)),
            ),
          ),
        ),
      );
      return _capture(tester, key);
    }

    int fingerprint(ByteData d) => Object.hashAll(d.buffer.asUint8List());

    for (final kind in ProceduralSceneKind.values) {
      testWidgets('${kind.name} paints real content and reacts to the camera', (tester) async {
        final studio = StudioController(autoConnect: false, animateShader: false);
        final base = await render(tester, studio, kind);

        // Content: plenty of lit pixels and a varied palette.
        final bytes = base.buffer.asUint8List();
        var lit = 0;
        final palette = <int>{};
        for (var i = 0; i < bytes.length; i += 4 * 7) {
          if (bytes[i] > 60 || bytes[i + 1] > 60 || bytes[i + 2] > 60) lit++;
          palette.add((bytes[i] >> 4) << 8 | (bytes[i + 1] >> 4) << 4 | bytes[i + 2] >> 4);
        }
        expect(lit, greaterThan(100), reason: '${kind.name} should not be a blank canvas');
        expect(palette.length, greaterThan(8), reason: '${kind.name} should use more than a flat color');

        // The same inputs give the same frame (deterministic, nothing animating).
        expect(fingerprint(await render(tester, studio, kind)), fingerprint(base));

        // Orbiting the camera changes the picture.
        studio.orbitBy(90, 40);
        expect(fingerprint(await render(tester, studio, kind)), isNot(fingerprint(base)), reason: 'orbit');
        studio.resetOrbit();

        // Zoom changes it too.
        studio.setCameraZoom(1.8);
        expect(fingerprint(await render(tester, studio, kind)), isNot(fingerprint(base)), reason: 'zoom');
        studio.resetCameraZoom();

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        studio.dispose();
      });
    }

    // One optics parameter each scene is documented to respond to.
    const driver = {
      ProceduralSceneKind.causticWave: 'ior',
      ProceduralSceneKind.spectralPrism: 'ior',
      ProceduralSceneKind.liquidChrome: 'ior',
      ProceduralSceneKind.blackHoleLensing: 'ior',
      ProceduralSceneKind.emeraldSubsurface: 'aperture',
      ProceduralSceneKind.soapFilmIridescence: 'ior',
    };
    for (final entry in driver.entries) {
      testWidgets('${entry.key.name} responds to ${entry.value}', (tester) async {
        final studio = StudioController(autoConnect: false, animateShader: false);
        final base = fingerprint(await render(tester, studio, entry.key));
        final def = kOpticsParams.firstWhere((p) => p.id == entry.value);
        studio.setParam(entry.value, def.min + (def.max - def.min) * 0.8);
        expect(fingerprint(await render(tester, studio, entry.key)), isNot(base));
        await tester.pumpWidget(const SizedBox.shrink());
        studio.dispose();
      });
    }

    testWidgets('the prism highlights the probe wavelength', (tester) async {
      final studio = StudioController(autoConnect: false, animateShader: false);
      final blue = fingerprint(await render(tester, studio, ProceduralSceneKind.spectralPrism));
      studio.setWavelengthNm(650);
      expect(fingerprint(await render(tester, studio, ProceduralSceneKind.spectralPrism)), isNot(blue));
      await tester.pumpWidget(const SizedBox.shrink());
      studio.dispose();
    });

    testWidgets('a paused studio runs no ticker; resuming starts one', (tester) async {
      final studio = StudioController(autoConnect: false, animateShader: false);
      await render(tester, studio, ProceduralSceneKind.causticWave);
      expect(tester.hasRunningAnimations, isFalse, reason: 'nothing may schedule frames while paused');

      studio.setAnimateShader(true);
      await render(tester, studio, ProceduralSceneKind.causticWave);
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 200));

      studio.setAnimateShader(false);
      await render(tester, studio, ProceduralSceneKind.causticWave);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      studio.dispose();
    });

    testWidgets('the LIVE SHADER toggle swaps the still render for the procedural canvas', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(find.byType(ProceduralSceneCanvas), findsWidgets);
      expect(tester.hasRunningAnimations, isTrue, reason: 'the crosshair and pips animate regardless');

      await _tapKey(tester, const Key('toggle-live-shader'));
      await tester.pump();
      expect(studio.liveShaderEnabled, isFalse);
      expect(find.byType(ProceduralSceneCanvas), findsNothing);

      await _tapKey(tester, const Key('toggle-live-shader'));
      await tester.pump();
      expect(studio.liveShaderEnabled, isTrue);
      expect(find.byType(ProceduralSceneCanvas), findsWidgets);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the still is the active project\'s own render, not a fixed image', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setLiveShader(false);

      Set<String> stageAssets() => tester
          .widgetList<Image>(find.descendant(of: find.byType(MacWindowViewport), matching: find.byType(Image)))
          .map((i) => i.image)
          .whereType<AssetImage>()
          .map((i) => i.assetName)
          .toSet();

      await tester.pump();
      expect(stageAssets(), {'assets/images/caustic_wave.jpg'});
      for (final project in studio.projects) {
        studio.selectProject(project.id);
        studio.setLiveShader(false);
        await tester.pump();
        expect(stageAssets(), {project.previewAsset}, reason: project.name);
      }
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('dynamic projects open live and static ones open on their still', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      for (final project in studio.projects) {
        await _tapKey(tester, ValueKey('project-${project.id}'));
        await tester.pump();
        expect(studio.liveShaderEnabled, project.isDynamic, reason: project.name);
        expect(find.byType(ProceduralSceneCanvas), project.isDynamic ? findsWidgets : findsNothing);
      }
      await _teardown(tester, studio);
    });

    testWidgets('the HUD play/pause pill appears with the live shader and flips animation', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(find.byKey(const Key('hud-shader-play')), findsOneWidget);
      expect(find.text('PAUSED'), findsOneWidget, reason: 'tests run with animation off');

      await tester.tap(find.byKey(const Key('hud-shader-play')));
      await tester.pump();
      expect(studio.animateShader, isTrue);
      expect(find.text('SHADER'), findsOneWidget);

      await tester.tap(find.byKey(const Key('hud-shader-play')));
      await tester.pump();
      expect(studio.animateShader, isFalse);

      studio.setLiveShader(false);
      await tester.pump();
      expect(find.byKey(const Key('hud-shader-play')), findsNothing);
      await _teardown(tester, studio);
    });

    test('wavelengths map to their physical colors', () {
      final violet = wavelengthToColor(380);
      final blue = wavelengthToColor(470);
      final green = wavelengthToColor(540);
      final yellow = wavelengthToColor(590);
      final red = wavelengthToColor(650);
      expect(violet.b, greaterThan(violet.g));
      expect(blue.b, greaterThan(blue.r));
      expect(green.g, greaterThan(green.r));
      expect(green.g, greaterThan(green.b));
      expect(yellow.r, greaterThan(0.9));
      expect(yellow.g, greaterThan(0.6));
      expect(red.r, greaterThan(red.g));
      expect(red.b, 0);
      // Clamped outside the visible band.
      expect(wavelengthToColor(100), wavelengthToColor(380));
      expect(wavelengthToColor(2000), wavelengthToColor(700));
    });
  });

  group('ray-path and BVH overlay', () {
    testWidgets('the BVH / RAYS toggle shows and hides the overlay', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(find.byType(BvhRayOverlay), findsNothing);

      await _tapKey(tester, const Key('toggle-bvh-rays'));
      await tester.pump();
      expect(studio.bvhOverlayEnabled, isTrue);
      expect(find.byType(BvhRayOverlay), findsOneWidget);

      await _tapKey(tester, const Key('toggle-bvh-rays'));
      await tester.pump();
      expect(find.byType(BvhRayOverlay), findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('it draws boxes and rays, and follows orbit, IOR and bounces', (tester) async {
      final studio = StudioController(autoConnect: false, animateShader: false);
      Future<int> fingerprint() async {
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: Colors.black,
                  child: SizedBox(width: 480, height: 300, child: BvhRayOverlay(studio: studio)),
                ),
              ),
            ),
          ),
        );
        final d = await _capture(tester, key);
        final bytes = d.buffer.asUint8List();
        var lit = 0;
        for (var i = 0; i < bytes.length; i += 4) {
          if (bytes[i] + bytes[i + 1] + bytes[i + 2] > 90) lit++;
        }
        expect(lit, greaterThan(200), reason: 'wireframes and rays are visible');
        return Object.hashAll(bytes);
      }

      final base = await fingerprint();
      studio.orbitBy(70, 30);
      expect(await fingerprint(), isNot(base), reason: 'the boxes turn with the camera');
      studio.resetOrbit();
      studio.setParam('ior', 2.9);
      expect(await fingerprint(), isNot(base), reason: 'Snell bends the rays by the IOR');
      studio.setParam('ior', 2.253);
      studio.setParam('max_bounces', 3);
      final few = await fingerprint();
      studio.setParam('max_bounces', 30);
      expect(await fingerprint(), isNot(few), reason: 'more bounces, more internal segments');
      studio.setFocusPoint(const Offset(0.25, 0.7));
      expect(await fingerprint(), isNot(few), reason: 'rays aim at the focus point');

      await tester.pumpWidget(const SizedBox.shrink());
      studio.dispose();
    });
  });

  group('wavelength, zoom and focus', () {
    final pillKey = find.byKey(const Key('hud-wavelength-pill'));

    testWidgets('the wavelength pill steps through the spectrum and scrubs by drag', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(find.text('λ: 540nm | IOR: 2.253'), findsOneWidget);

      for (final nm in [590, 650, 380, 470, 540]) {
        await tester.tap(pillKey);
        await tester.pump();
        expect(studio.wavelengthNm, nm.toDouble());
        expect(find.text('λ: ${nm}nm | IOR: 2.253'), findsOneWidget);
      }

      final before = studio.wavelengthNm;
      await tester.drag(pillKey, const Offset(60, 0));
      await tester.pump();
      expect(studio.wavelengthNm, greaterThan(before));
      await tester.drag(pillKey, const Offset(4000, 0));
      await tester.pump();
      expect(studio.wavelengthNm, 700);
      await tester.drag(pillKey, const Offset(-4000, 0));
      await tester.pump();
      expect(studio.wavelengthNm, 380);
      expect(studio.orbit.value, Offset.zero, reason: 'the pill swallows the drag');
      await _teardown(tester, studio);
    });

    testWidgets('the scroll wheel zooms the stage within 0.5x to 4x, and the zoom tag resets it', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(find.text('ZOOM 1.00×'), findsOneWidget);

      final wheel = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(wheel.hover(_stagePoint(tester)));
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, -150)));
      await tester.pump();
      expect(studio.cameraZoom.value, greaterThan(1.1), reason: 'wheel up zooms in');
      expect(find.text('ZOOM ${studio.cameraZoom.value.toStringAsFixed(2)}×'), findsOneWidget);

      await tester.sendEventToBinding(wheel.scroll(const Offset(0, -9000)));
      await tester.pump();
      expect(studio.cameraZoom.value, 4.0);
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 90000)));
      await tester.pump();
      expect(studio.cameraZoom.value, 0.5);

      await tester.tap(find.byKey(const Key('hud-zoom-pill')));
      await tester.pump();
      expect(studio.cameraZoom.value, 1.0);
      expect(find.text('ZOOM 1.00×'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('double-tapping the stage moves the focus point and pulls focus to its depth', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final stage = tester.getRect(
        find.ancestor(of: find.byKey(AbRenderWipe.curtainKey), matching: find.byType(LayoutBuilder)).first,
      );
      expect(studio.focusPoint.value, const Offset(0.5, 0.5));
      final focalBefore = studio.param('focal_distance');
      final point = _stagePoint(tester);

      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 100));
      expect(studio.focusPoint.value, const Offset(0.5, 0.5), reason: 'one tap is not enough');

      await tester.tapAt(point);
      await tester.pump();
      final uv = Offset((point.dx - stage.left) / stage.width, (point.dy - stage.top) / stage.height);
      expect(studio.focusPoint.value.dx, closeTo(uv.dx, 1e-6));
      expect(studio.focusPoint.value.dy, closeTo(uv.dy, 1e-6));
      expect(studio.param('focal_distance'), isNot(focalBefore));
      expect(studio.param('focal_distance'), closeTo(0.4 + (1 - uv.dy) * 4.6, 1e-6));

      // The probe follows the focus point.
      expect(tester.getCenter(pillKey).dx, closeTo(point.dx, 1.0));
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('Shift+click sets the focus point in one press', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final point = _stagePoint(tester) + const Offset(60, -40);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(point);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(studio.focusPoint.value, isNot(const Offset(0.5, 0.5)));
      await _teardown(tester, studio);
    });

    testWidgets('the focus point and zoom do not move the A/B curtain or fight a curtain double-tap', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setAbSplit(0.7);
      await tester.pump();
      final curtain = find.byKey(AbRenderWipe.curtainKey);
      await tester.tap(curtain);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(curtain);
      await tester.pump();
      expect(studio.abSplit.value, 0.5, reason: 'the curtain resets');
      expect(studio.focusPoint.value, const Offset(0.5, 0.5), reason: 'and the stage ignores that double-tap');
      await _teardown(tester, studio);
    });

    test('controller: wavelength, zoom and focus are clamped, and the viewport reset clears them', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.setWavelengthNm(100);
      expect(studio.wavelengthNm, 380);
      studio.setWavelengthNm(9000);
      expect(studio.wavelengthNm, 700);
      studio.setWavelengthNm(700);
      studio.stepWavelength();
      expect(studio.wavelengthNm, 380, reason: 'wraps after the red');

      studio.setCameraZoom(99);
      expect(studio.cameraZoom.value, 4.0);
      studio.setCameraZoom(0.01);
      expect(studio.cameraZoom.value, 0.5);

      studio.setFocusPoint(const Offset(2, -1));
      expect(studio.focusPoint.value, const Offset(1, 0));
      expect(studio.param('focal_distance'), closeTo(5.0, 1e-9), reason: 'top of frame is far');
      studio.setFocusPoint(const Offset(0, 1));
      expect(studio.param('focal_distance'), closeTo(0.4, 1e-9), reason: 'bottom is near');

      studio.setBvhOverlay(true);
      studio.resetViewportStage();
      expect(studio.cameraZoom.value, 1.0);
      expect(studio.focusPoint.value, const Offset(0.5, 0.5));
      expect(studio.bvhOverlayEnabled, isFalse);
    });
  });

  group('undo, redo and snapshots', () {
    test('undo restores the previous optics, redo reapplies, a new edit clears redo', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);
      expect(studio.canUndo, isFalse);
      expect(studio.canRedo, isFalse);

      studio.setParam('aperture', 6);
      expect(studio.canUndo, isTrue);
      studio.undo();
      expect(studio.param('aperture'), 1.4);
      expect(studio.canUndo, isFalse);
      expect(studio.canRedo, isTrue);

      studio.redo();
      expect(studio.param('aperture'), 6);
      studio.undo();
      studio.setParam('ior', 1.2);
      expect(studio.canRedo, isFalse, reason: 'a fresh edit forks history');

      // Undo and redo with nothing to do are harmless.
      studio.undo();
      studio.undo();
      studio.redo();
      studio.redo();
      studio.redo();
    });

    test('scrubbing one parameter is a single undo step', () {
      var clock = DateTime(2026, 1, 1);
      final studio = StudioController(autoConnect: false, now: () => clock);
      addTearDown(studio.dispose);

      for (final v in [2.0, 3.0, 4.0, 5.0]) {
        studio.setParam('aperture', v);
        clock = clock.add(const Duration(milliseconds: 40));
      }
      studio.undo();
      expect(studio.param('aperture'), 1.4, reason: 'the whole drag undoes at once');
      expect(studio.canUndo, isFalse);

      studio.redo();
      clock = clock.add(const Duration(seconds: 2));
      studio.setParam('aperture', 9);
      studio.undo();
      expect(studio.param('aperture'), 5.0, reason: 'after a pause it is a new step');
    });

    test('different parameters are separate steps', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);
      studio.setParam('aperture', 6);
      studio.setParam('ior', 1.2);
      studio.undo();
      expect(studio.param('ior'), 2.253);
      expect(studio.param('aperture'), 6);
      studio.undo();
      expect(studio.param('aperture'), 1.4);
    });

    test('undo crosses project switches and integrator changes', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.selectProject('volumetric_prism');
      expect(studio.activeProjectId, 'volumetric_prism');
      studio.setIntegrator(IntegratorMode.restir);
      studio.undo();
      expect(studio.integrator, IntegratorMode.sppm);
      studio.undo();
      expect(studio.activeProjectId, 'caustic_study_04');
      expect(studio.param('ior'), 2.253);
      expect(studio.integrator, IntegratorMode.unidirectional);
      expect(studio.liveShaderEnabled, isTrue);
    });

    test('the history is bounded', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);
      // Alternate parameters so nothing coalesces.
      for (var i = 0; i < 100; i++) {
        studio.setParam(i.isEven ? 'aperture' : 'ior', 1.5 + i * 0.01);
      }
      var steps = 0;
      while (studio.canUndo) {
        studio.undo();
        steps++;
      }
      expect(steps, 60);
    });

    test('snapshots capture the optics and restore them (undoably)', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);
      expect(studio.snapshots, isEmpty);

      studio.setParam('ior', 1.9);
      studio.setParam('aperture', 7);
      studio.setIntegrator(IntegratorMode.restir);
      studio.captureSnapshot();
      studio.captureSnapshot();
      expect(studio.snapshots.map((s) => s.label), ['TAKE 01', 'TAKE 02']);
      final take = studio.snapshots.first;
      expect(take.projectName, 'CAUSTIC_STUDY_04');
      expect(take.ior, 1.9);
      expect(take.aperture, 7);
      expect(take.spp, 256);
      expect(take.integrator, IntegratorMode.restir);

      studio.setParam('ior', 2.8);
      studio.setIntegrator(IntegratorMode.sppm);
      studio.restoreSnapshot(take.id);
      expect(studio.param('ior'), 1.9);
      expect(studio.integrator, IntegratorMode.restir);
      expect(studio.toast.value, 'TAKE RESTORED · TAKE 01');

      studio.undo();
      expect(studio.param('ior'), 2.8, reason: 'restoring a take can be undone');
      studio.restoreSnapshot('no-such-take');
      expect(studio.param('ior'), 2.8);
    });

    testWidgets('SNAPSHOT adds a take to the filmstrip and tapping it restores the optics', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(find.text('TAKE 01'), findsNothing);
      studio.setParam('ior', 1.9);
      await tester.pump();

      await _tapKey(tester, const Key('viewport-snapshot-btn'));
      await tester.pump();
      expect(studio.snapshots, hasLength(1));
      expect(find.text('TAKE 01'), findsOneWidget);

      studio.setParam('ior', 2.6);
      await tester.pump();
      await _tapKey(tester, const Key('viewport-snapshot-btn'));
      await tester.pump();
      expect(find.text('TAKE 02'), findsOneWidget);

      await tester.tap(find.byKey(const Key('take-take_1')));
      await tester.pump();
      expect(studio.param('ior'), 1.9);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the filmstrip fits a narrow stage', (tester) async {
      final studio = await _pumpStudio(tester, const Size(390, 844));
      for (var i = 0; i < 6; i++) {
        studio.captureSnapshot();
      }
      studio.setFalseColor(true);
      await tester.pump();
      expect(find.text('TAKE 01'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('UNDO and REDO buttons step the history and dim when unavailable', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final undo = find.byKey(const Key('optics-undo-btn'));
      final redo = find.byKey(const Key('optics-redo-btn'));
      expect(find.text('UNDO'), findsOneWidget);
      expect(find.text('REDO'), findsOneWidget);
      expect(studio.canUndo, isFalse);

      studio.setParam('aperture', 6);
      await tester.pump();
      expect(studio.canUndo, isTrue);

      await tester.tap(undo);
      await tester.pump();
      expect(studio.param('aperture'), 1.4);
      expect(studio.canRedo, isTrue);

      await tester.tap(redo);
      await tester.pump();
      expect(studio.param('aperture'), 6);

      // Tapping a dimmed button does nothing.
      studio.undo();
      await tester.pump();
      await tester.tap(undo);
      await tester.pump();
      expect(studio.param('aperture'), 1.4);
      await _teardown(tester, studio);
    });

    testWidgets('Ctrl+Z, Ctrl+Y and Ctrl+Shift+Z drive the history', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setParam('aperture', 6);
      await tester.pump();

      Future<void> chord(LogicalKeyboardKey key, {bool shift = false}) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      await chord(LogicalKeyboardKey.keyZ);
      expect(studio.param('aperture'), 1.4);
      await chord(LogicalKeyboardKey.keyY);
      expect(studio.param('aperture'), 6);
      await chord(LogicalKeyboardKey.keyZ);
      expect(studio.param('aperture'), 1.4);
      await chord(LogicalKeyboardKey.keyZ, shift: true);
      expect(studio.param('aperture'), 6, reason: 'Ctrl+Shift+Z redoes');
      await _teardown(tester, studio);
    });

    testWidgets('undo leaves a focused text field alone', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setParam('aperture', 6);
      await tester.tap(find.byKey(const Key('scene-prompt')));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(studio.param('aperture'), 6, reason: 'Ctrl+Z belongs to the text field here');
      await _teardown(tester, studio);
    });
  });

  group('command palette', () {
    final modal = find.byKey(const Key('command-palette-modal'));

    testWidgets('the header button and Ctrl+P open it; Escape and Ctrl+P close it', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(modal, findsNothing);

      await _tapKey(tester, const Key('command-palette-btn'));
      await tester.pump();
      expect(modal, findsOneWidget);
      expect(studio.commandPaletteOpen, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(modal, findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(modal, findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(modal, findsNothing, reason: 'Ctrl+P toggles');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('a backdrop click closes it', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setCommandPaletteOpen(true);
      await tester.pump();
      expect(modal, findsOneWidget);
      await tester.tapAt(const Offset(20, 780));
      await tester.pump();
      expect(modal, findsNothing);
      await _teardown(tester, studio);
    });

    testWidgets('it lists every action and filters as you type', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setCommandPaletteOpen(true);
      await tester.pump();
      for (final id in [
        'theme',
        'live-shader',
        'bvh',
        'ab-wipe',
        'loupe',
        'false-color',
        'account',
        'reset-optics',
        'recenter',
        'load-caustic_study_04',
      ]) {
        await tester.ensureVisible(find.byKey(Key('palette-action-$id')));
        expect(find.byKey(Key('palette-action-$id')), findsOneWidget, reason: id);
      }

      await tester.enterText(find.byKey(const Key('command-palette-input')), 'kerr');
      await tester.pump();
      expect(find.byKey(const Key('palette-action-load-kerr_photon_ring')), findsOneWidget);
      expect(find.byKey(const Key('palette-action-theme')), findsNothing);

      await tester.enterText(find.byKey(const Key('command-palette-input')), 'zzzz');
      await tester.pump();
      expect(find.text('NO MATCHING COMMANDS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('Enter runs the highlighted action; the arrow keys move the highlight', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setCommandPaletteOpen(true);
      await tester.pump();

      await tester.enterText(find.byKey(const Key('command-palette-input')), 'kerr');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(studio.activeProjectId, 'kerr_photon_ring');
      expect(modal, findsNothing, reason: 'running an action closes the palette');

      studio.setCommandPaletteOpen(true);
      await tester.pump();
      await tester.enterText(find.byKey(const Key('command-palette-input')), 'toggle');
      await tester.pump();
      expect(studio.liveShaderEnabled, isTrue);
      // Order: theme, live shader, BVH, A/B wipe, loupe, false color.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(studio.liveShaderEnabled, isFalse, reason: 'one arrow down lands on Live Shader');
      expect(studio.darkGrading, isTrue);

      studio.setCommandPaletteOpen(true);
      await tester.pump();
      await tester.enterText(find.byKey(const Key('command-palette-input')), 'toggle');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(studio.falseColorEnabled, isTrue, reason: 'arrow up from the first row wraps to the last');
      await _teardown(tester, studio);
    });

    testWidgets('clicking actions toggles the tools, the theme and opens the account console', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));

      Future<void> run(String id) async {
        studio.setCommandPaletteOpen(true);
        await tester.pump();
        await _tapKey(tester, Key('palette-action-$id'));
        await tester.pump();
        expect(modal, findsNothing, reason: id);
      }

      await run('bvh');
      expect(studio.bvhOverlayEnabled, isTrue);
      await run('loupe');
      expect(studio.loupeEnabled, isTrue);
      await run('ab-wipe');
      expect(studio.abWipeEnabled, isFalse);
      await run('theme');
      expect(studio.darkGrading, isFalse);
      await tester.pump(const Duration(milliseconds: 400));
      await run('theme');
      expect(studio.darkGrading, isTrue);
      await tester.pump(const Duration(milliseconds: 400));

      studio.setParam('aperture', 6);
      await run('reset-optics');
      expect(studio.param('aperture'), kOpticsParams.first.initial);
      studio.orbitBy(50, 50);
      await run('recenter');
      expect(studio.orbit.value, Offset.zero);

      await run('account');
      expect(studio.accountModalOpen, isTrue);
      expect(find.byKey(const Key('account-modal')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });
  });

  group('account console', () {
    final modal = find.byKey(const Key('account-modal'));

    Future<StudioController> openAccount(WidgetTester tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      await _tapKey(tester, const Key('account-pill-btn'));
      await tester.pump();
      return studio;
    }

    test('the seeded account matches the studio profile', () {
      final a = StudioAccount.initial();
      expect(a.displayName, 'Mohd Faraz');
      expect(a.handle, '@mfarazcodes');
      expect(a.email, 'faraz@photon.studio');
      expect(a.role, 'Lead Rendering Architect');
      expect(a.organization, 'Photon Spatial Labs');
      expect(a.workspaceId, 'WS-IND-0492');
      expect(a.tier, PlanTier.pro);
      expect(a.authMethod, AuthMethod.passkey);
      expect(a.twoFactorEnabled, isTrue);
      expect(a.hardwareKeyBound, isTrue);
      expect(a.gpuHoursUsed, 842.5);
      expect(a.storageUsedGb, 128.4);
      expect(a.storageLimitGb, 500.0);
      expect(a.initials, 'MF');
      expect(a.apiKeys.map((k) => k.label), ['Stitch MCP Bridge Key', 'Local C++ Engine Socket Key']);
      expect(a.apiKeys[0].secret, startsWith('pht_mcp_98a7f2'));
      expect(a.apiKeys[0].secret, endsWith('c41e'));
      expect(a.apiKeys[1].secret, startsWith('pht_eng_44b1d0'));
      expect(a.apiKeys[1].secret, endsWith('889a'));
      expect(a.apiKeys[0].masked, 'pht_mcp_98a7f2••••••••c41e');
      expect(a.sessions, hasLength(3));
      expect(a.sessions.where((s) => s.isCurrent), hasLength(1));
      expect(a.sessions.first.device, 'Windows 11 · Motobook 60 (Local Studio)');

      expect(PlanTier.indie.label, 'INDIE LAB');
      expect(PlanTier.pro.price, '\$49 / mo');
      expect(PlanTier.enterprise.quota, 'Unlimited Dedicated Nodes');
      expect(PlanTier.pro.gpuHours, 1000);
      expect(AuthMethod.passkey.label, 'WebAuthn Passkey · Hardware Enclave');
      expect(AuthMethod.apiKey.label, 'Local CLI / MCP Bearer Token');
    });

    test('controller actions update the account and announce themselves', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.setPlanTier(PlanTier.enterprise);
      expect(studio.account.tier, PlanTier.enterprise);
      expect(studio.toast.value, 'PLAN UPDATED · ENTERPRISE CLUSTER');

      studio.setAuthMethod(AuthMethod.ssoSaml);
      expect(studio.account.authMethod, AuthMethod.ssoSaml);
      expect(studio.toast.value, 'AUTH PROTOCOL · Enterprise SAML 2.0 SSO');

      studio.toggleTwoFactor();
      expect(studio.account.twoFactorEnabled, isFalse);
      studio.toggleTwoFactor();
      expect(studio.account.twoFactorEnabled, isTrue);
      studio.toggleHardwareKey();
      expect(studio.account.hardwareKeyBound, isFalse);

      studio.updateAccountProfile(displayName: '  Faraz M  ', organization: 'Atelier', role: 'Director');
      expect(studio.account.displayName, 'Faraz M');
      expect(studio.account.organization, 'Atelier');
      expect(studio.account.role, 'Director');
      expect(studio.account.initials, 'FM');
      studio.updateAccountProfile(displayName: '   ', organization: '');
      expect(studio.account.displayName, 'Faraz M', reason: 'blank edits are ignored');
      expect(studio.account.organization, 'Atelier');
    });

    test('rotating a key issues a new deterministic secret and keeps its kind', () {
      final a = StudioController(autoConnect: false);
      final b = StudioController(autoConnect: false);
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      final old = a.account.apiKeys.first;
      a.rotateApiKey(old.id);
      b.rotateApiKey(old.id);
      final fresh = a.account.apiKeys.first;
      expect(fresh.secret, isNot(old.secret));
      expect(fresh.secret, startsWith('pht_mcp_'));
      expect(fresh.secret, b.account.apiKeys.first.secret, reason: 'deterministic');
      expect(fresh.prefix, fresh.secret.substring(0, fresh.prefix.length));
      expect(fresh.lastUsed, 'just now');
      expect(a.toast.value, 'API KEY ROTATED');
      expect(a.account.apiKeys[1].secret, startsWith('pht_eng_44b1d0'), reason: 'other keys are untouched');

      a.rotateApiKey(old.id);
      expect(a.account.apiKeys.first.secret, isNot(fresh.secret), reason: 'each rotation differs');
      a.rotateApiKey('no-such-key');
    });

    test('creating keys and revoking sessions', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.createApiKey('  CI Runner  ');
      studio.createApiKey('');
      expect(studio.account.apiKeys.map((k) => k.label), [
        'Stitch MCP Bridge Key',
        'Local C++ Engine Socket Key',
        'CI Runner',
        'Untitled Key',
      ]);
      expect(studio.account.apiKeys[2].secret, startsWith('pht_usr_'));
      expect(studio.account.apiKeys[2].secret, isNot(studio.account.apiKeys[3].secret));
      expect(studio.toast.value, 'API KEY CREATED');

      studio.revokeSession('ses_local');
      expect(studio.account.sessions, hasLength(3), reason: 'this device stays signed in');
      studio.revokeSession('ses_node');
      expect(studio.account.sessions.map((s) => s.id), ['ses_local', 'ses_mcp']);
      expect(studio.toast.value, 'SESSION REVOKED');
      studio.revokeSession('ses_node');
      expect(studio.account.sessions, hasLength(2));
    });

    test('the modal and the palette are mutually exclusive', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);
      studio.setCommandPaletteOpen(true);
      studio.setAccountModalOpen(true);
      expect(studio.commandPaletteOpen, isFalse);
      studio.setCommandPaletteOpen(true);
      expect(studio.accountModalOpen, isFalse);
      studio.setCommandPaletteOpen(false);
      studio.toggleAccountModal();
      expect(studio.accountModalOpen, isTrue);
      studio.toggleAccountModal();
      expect(studio.accountModalOpen, isFalse);
    });

    testWidgets('the header pill shows the avatar, name and tier, and opens the console', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(find.byKey(const Key('account-pill-btn')), findsOneWidget);
      expect(find.text('MOHD FARAZ'), findsOneWidget);
      expect(find.text('MF'), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
      expect(modal, findsNothing);

      await _tapKey(tester, const Key('account-pill-btn'));
      await tester.pump();
      expect(modal, findsOneWidget);
      expect(studio.accountModalOpen, isTrue);

      expect(find.text('Mohd Faraz'), findsOneWidget);
      expect(find.text('@mfarazcodes'), findsOneWidget);
      expect(find.text('faraz@photon.studio'), findsOneWidget);
      expect(find.text('Lead Rendering Architect · Photon Spatial Labs'), findsOneWidget);
      expect(find.text('WS-IND-0492'), findsOneWidget);
      expect(find.text('STUDIO PRO'), findsWidgets);
      expect(find.text('\$49 / mo'), findsOneWidget);
      expect(find.text('WebAuthn Passkey · Hardware Enclave'), findsOneWidget);
      expect(find.text('842.5 / 1,000 hrs · 84%'), findsOneWidget);
      expect(find.text('128.4 / 500 GB · 26%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('Escape, a backdrop click and the red pip each dismiss it', (tester) async {
      final studio = await openAccount(tester);
      expect(modal, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(modal, findsNothing);

      studio.setAccountModalOpen(true);
      await tester.pump();
      await tester.tapAt(const Offset(20, 400));
      await tester.pump();
      expect(modal, findsNothing);

      studio.setAccountModalOpen(true);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pip-close-account')));
      await tester.pump();
      expect(modal, findsNothing);

      // A click on the sheet itself does not dismiss it.
      studio.setAccountModalOpen(true);
      await tester.pump();
      await tester.tap(find.text('ACCOUNT_CONSOLE'));
      await tester.pump();
      expect(modal, findsOneWidget);
      await _teardown(tester, studio);
    });

    testWidgets('plan tiers switch live, and the quota bars follow', (tester) async {
      final studio = await openAccount(tester);

      await _tapKey(tester, const Key('tier-enterprise'));
      await tester.pump();
      expect(studio.account.tier, PlanTier.enterprise);
      expect(find.text('842.5 / 10,000 hrs · 8%'), findsOneWidget);
      expect(find.text('ENT'), findsWidgets);
      // The status strip inside the console (the viewport HUD shows it too).
      expect(
        find.descendant(of: modal, matching: find.text('PLAN UPDATED · ENTERPRISE CLUSTER')),
        findsOneWidget,
      );

      await _tapKey(tester, const Key('tier-indie'));
      await tester.pump();
      expect(studio.account.tier, PlanTier.indie);
      expect(find.textContaining('OVER QUOTA'), findsOneWidget);
      expect(find.textContaining('/ 64 hrs'), findsOneWidget);

      await _tapKey(tester, const Key('tier-pro'));
      await tester.pump();
      expect(find.text('842.5 / 1,000 hrs · 84%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('authentication protocol and security toggles', (tester) async {
      final studio = await openAccount(tester);

      await _tapKey(tester, const Key('auth-ssoSaml'));
      await tester.pump();
      expect(studio.account.authMethod, AuthMethod.ssoSaml);
      expect(find.text('Enterprise SAML 2.0 SSO'), findsOneWidget);
      expect(find.text('WebAuthn Passkey · Hardware Enclave'), findsNothing);

      expect(studio.account.twoFactorEnabled, isTrue);
      await _tapKey(tester, const Key('account-2fa-toggle'));
      await tester.pump();
      expect(studio.account.twoFactorEnabled, isFalse);
      expect(find.text('Disabled'), findsOneWidget);
      await _tapKey(tester, const Key('account-2fa-toggle'));
      await tester.pump();
      expect(studio.account.twoFactorEnabled, isTrue);

      await _tapKey(tester, const Key('account-hwkey-toggle'));
      await tester.pump();
      expect(studio.account.hardwareKeyBound, isFalse);
      expect(find.text('JWT SESSION · TLS 1.3 · Ed25519 Signed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('API keys: reveal, copy, rotate and create', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final studio = await openAccount(tester);
      final key = studio.account.apiKeys.first;

      // Masked until revealed.
      expect(find.text(key.masked), findsOneWidget);
      expect(find.text(key.secret), findsNothing);
      await _tapKey(tester, Key('reveal-key-${key.id}'));
      await tester.pump();
      expect(find.text(key.secret), findsOneWidget);
      expect(find.text(key.masked), findsNothing);
      await _tapKey(tester, Key('reveal-key-${key.id}'));
      await tester.pump();
      expect(find.text(key.masked), findsOneWidget);

      await _tapKey(tester, Key('copy-key-${key.id}'));
      await tester.pump();
      expect(copied, key.secret);
      expect(find.descendant(of: modal, matching: find.text('KEY COPIED TO CLIPBOARD')), findsOneWidget);

      await _tapKey(tester, Key('rotate-key-${key.id}'));
      await tester.pump();
      final rotated = studio.account.apiKeys.first;
      expect(rotated.secret, isNot(key.secret));
      expect(find.text(rotated.masked), findsOneWidget);
      expect(find.descendant(of: modal, matching: find.text('API KEY ROTATED')), findsOneWidget);

      await _tapKey(tester, const Key('create-api-key-btn'));
      await tester.pump();
      expect(studio.account.apiKeys, hasLength(3));
      expect(find.text('Studio Key 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('a clipboard failure is reported, not thrown', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        // Only the clipboard fails; MaterialApp makes its own platform calls.
        if (call.method == 'Clipboard.setData') throw PlatformException(code: 'denied');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final studio = await openAccount(tester);
      await _tapKey(tester, Key('copy-key-${studio.account.apiKeys.first.id}'));
      await tester.pump();
      expect(find.descendant(of: modal, matching: find.text('CLIPBOARD UNAVAILABLE')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('sessions: remote ones can be revoked, this device cannot', (tester) async {
      final studio = await openAccount(tester);
      expect(find.text('THIS DEVICE'), findsOneWidget);
      expect(find.byKey(const Key('revoke-session-ses_local')), findsNothing);
      expect(find.text('NVIDIA L40S Render Node · ap-south-1'), findsOneWidget);
      expect(find.text('Claude Code MCP Agent · stdio'), findsOneWidget);

      await _tapKey(tester, const Key('revoke-session-ses_node'));
      await tester.pump();
      expect(studio.account.sessions.map((s) => s.id), ['ses_local', 'ses_mcp']);
      expect(find.text('NVIDIA L40S Render Node · ap-south-1'), findsNothing);
      expect(find.descendant(of: modal, matching: find.text('SESSION REVOKED')), findsOneWidget);

      await _tapKey(tester, const Key('revoke-session-ses_mcp'));
      await tester.pump();
      expect(studio.account.sessions.map((s) => s.id), ['ses_local']);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('EDIT PROFILE edits the name and organization live', (tester) async {
      final studio = await openAccount(tester);
      expect(find.byKey(const Key('account-name-field')), findsNothing);

      await _tapKey(tester, const Key('account-edit-profile-btn'));
      await tester.pump();
      expect(find.text('DONE'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('account-name-field'))).controller!.text, 'Mohd Faraz');

      await tester.enterText(find.byKey(const Key('account-name-field')), 'Faraz Mohd');
      await tester.pump();
      expect(studio.account.displayName, 'Faraz Mohd');
      expect(find.text('FARAZ MOHD'), findsOneWidget, reason: 'the header pill follows live');
      expect(find.text('FM'), findsWidgets);

      await tester.enterText(find.byKey(const Key('account-org-field')), 'Atelier Optics');
      await tester.pump();
      expect(studio.account.organization, 'Atelier Optics');
      expect(find.text('Lead Rendering Architect · Atelier Optics'), findsOneWidget);

      await _tapKey(tester, const Key('account-edit-profile-btn'));
      await tester.pump();
      expect(find.byKey(const Key('account-name-field')), findsNothing);
      expect(find.text('Faraz Mohd'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the ACCOUNT workspace shows the console in place of the viewport', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      await _tapText(tester, 'ACCOUNT');
      await tester.pump();
      expect(studio.maximizedPanel, 'account');
      expect(find.text('ACCOUNT_CONSOLE'), findsOneWidget);
      expect(find.text('SCENE_VIEWPORT.rt'), findsNothing);
      expect(find.text('OPTICS_PARAMETERS'), findsNothing);
      expect(find.text('Mohd Faraz'), findsOneWidget);
      expect(modal, findsNothing, reason: 'embedded, not a modal');

      // Its red pip returns to the split workspace.
      await tester.tap(find.byKey(const ValueKey('pip-close-account')));
      await tester.pump();
      expect(studio.maximizedPanel, isNull);
      expect(find.text('SCENE_VIEWPORT.rt'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the console lays out in one column on a narrow window', (tester) async {
      final studio = await _pumpStudio(tester, const Size(390, 844));
      await _tapKey(tester, const Key('account-pill-btn'));
      await tester.pump();
      expect(modal, findsOneWidget);
      expect(find.text('Mohd Faraz'), findsOneWidget);
      studio.setAccountModalOpen(false);
      studio.setMaximizedPanel('account');
      await tester.pump();
      expect(find.text('ACCOUNT_CONSOLE'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });
  });
}
