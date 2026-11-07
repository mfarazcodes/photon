import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photon/main.dart';
import 'package:photon/models/studio_project.dart';
import 'package:photon/models/prompt_result.dart';
import 'package:photon/services/file_dialog.dart';
import 'package:photon/services/render_socket.dart';
import 'package:photon/state/studio_controller.dart';
import 'package:photon/theme/photon_theme.dart';
import 'package:photon/widgets/ab_render_wipe.dart';
import 'package:photon/widgets/animated_profile_card.dart';
import 'package:photon/widgets/bvh_ray_overlay.dart';
import 'package:photon/widgets/card_deck_carousel.dart';
import 'package:photon/widgets/command_dock.dart';
import 'package:photon/widgets/intent_file_trigger.dart';
import 'package:photon/widgets/launch_hero_portal.dart';
import 'package:photon/widgets/mac_window_viewport.dart';
import 'package:photon/widgets/optics_inspector_deck.dart';
import 'package:photon/widgets/photon_primitives.dart';
import 'package:photon/widgets/pixel_loupe_probe.dart';
import 'package:photon/widgets/procedural_scene_canvas.dart';
import 'package:photon/widgets/progressive_flux_loader.dart';
import 'package:photon/widgets/projects_sidebar.dart';
import 'package:photon/widgets/rauno_tick_scrubber.dart';
import 'package:photon/widgets/shader_theme_switch.dart';
import 'package:photon/widgets/spatial_canvas.dart';
import 'package:photon/widgets/top_telemetry_bar.dart';

/// A socket that never touches the network.
class _FakeSocket extends RenderSocket {
  int connects = 0;

  @override
  void connect() => connects++;
}

/// A socket that records what it is sent, answers as if the engine were up (or
/// down, with [online]), and never opens a connection.
class _RecordingSocket extends RenderSocket {
  final List<Map<String, Object?>> sent = [];
  bool online = true;
  int connects = 0;
  int disconnects = 0;

  @override
  bool send(Map<String, Object?> message) {
    if (!online) return false;
    sent.add(message);
    return true;
  }

  @override
  void connect() => connects++;

  @override
  void disconnect() => disconnects++;
}

/// One circle a painter drew.
class _LoggedCircle {
  const _LoggedCircle(this.center, this.radius, this.paint);

  final Offset center;
  final double radius;
  final Paint paint;
}

/// A canvas that remembers only the circles drawn on it.
class _CircleLog implements Canvas {
  final List<_LoggedCircle> circles = [];

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add(_LoggedCircle(c, radius, paint));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A real 1x1 PNG.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// Decodes the logo artwork for real (asset loading is asynchronous in the test
/// binding) and pumps it in, so a capture shows the picture, not an empty tile.
Future<void> _logoReady(WidgetTester tester) async {
  final context = tester.element(find.byType(PhotonLogoMark).first);
  await tester.runAsync(() => precacheImage(const AssetImage(PhotonLogo.asset), context));
  await tester.pump();
}

/// The spinning dashed ring of the optical probe. (The Scaffold keeps a
/// RotationTransition of its own for the FAB, so `byType` would match two.)
final Finder _probeRing = find.byWidgetPredicate((w) => w is RotationTransition && w.child is CustomPaint);

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

/// Puts the studio in Dark Grading ([dark]) or Daylight Lab by tapping the one
/// theme icon, if it is not there already.
Future<void> _setTheme(WidgetTester tester, {required bool dark}) async {
  final icon = find.byType(ShaderThemeSwitch);
  if (tester.widget<ShaderThemeSwitch>(icon).dark != dark) await _tap(tester, icon);
}

Future<void> _tapKey(WidgetTester tester, Key key) => _tap(tester, find.byKey(key));

/// Advances [duration] in 20ms frames, after one frame to start whatever the
/// last event began. A ticker's clock starts at the first frame it sees, and an
/// animation that finishes one stage and begins the next needs a frame in
/// between, so one big `pump(duration)` would stop short of both.
Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  await tester.pump();
  for (var left = duration.inMilliseconds; left > 0; left -= 20) {
    await tester.pump(Duration(milliseconds: left < 20 ? left : 20));
  }
}

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
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0B0C10));
    expect(theme.extension<PhotonTokens>()!.colors.substrate, const Color(0xFF12141C));
    expect(theme.extension<PhotonTokens>()!.colors.border, const Color(0xFF262936));

    await _setTheme(tester, dark: false);
    // MaterialApp animates theme changes: one frame to start, one to finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(studio.darkGrading, isFalse);
    theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.scaffoldBackgroundColor, PhotonPalette.daylight.canvas);
    expect(theme.extension<PhotonTokens>()!.colors.isDark, isFalse);

    await _setTheme(tester, dark: true);
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
        'ACRYLIC_LENS_ARRAY',
        'KERR_PHOTON_RING',
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
      studio.selectProject('volumetric_prism');
      expect(studio.param('aperture'), 4.0);

      studio.selectProject('caustic_study_04');
      expect(studio.param('aperture'), 9.0);
      expect(studio.integrator, IntegratorMode.restir);
    });

    test('createNewProject keeps the live optics, selects it, and starts with no image at all', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);
      expect(studio.liveShaderEnabled, isTrue, reason: 'the first project is a live one');

      studio.setParam('ior', 1.9);
      studio.createNewProject();
      expect(studio.projects, hasLength(6));
      final created = studio.activeProject!;
      expect(created.name, 'UNTITLED_06');
      expect(created.code, 'PRJ-06');
      expect(created.status, ProjectStatus.draft);
      expect(created.ior, 1.9);
      expect(studio.projects.first.id, created.id);
      // Nothing is borrowed from the project it was made in.
      expect(created.previewAsset, kNoPreview);
      expect(created.hasImage, isFalse);
      expect([created.customBytes, created.localFilePath, created.externalUrl], [null, null, null]);
      expect(created.isDynamic, isFalse);
      expect(studio.liveShaderEnabled, isFalse, reason: 'no simulation the user did not ask for');
      expect(created.sceneType, 'Blank Project');

      studio.createNewProject('  MY_SHOT  ');
      expect(studio.activeProject!.name, 'MY_SHOT');
    });

    test('createNewProject keeps the name, the details and exactly the image it was given', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);
      studio.createNewProject('  Chronos Watch  ', '  A hero shot of a steel watch.\nSecond line.  ', _tinyPng, '/shots/chronos.png');
      var p = studio.activeProject!;
      expect(p.name, 'Chronos Watch');
      expect(p.description, 'A hero shot of a steel watch.\nSecond line.');
      expect(p.subtitle, 'A hero shot of a steel watch.', reason: 'the card shows the first line');
      expect(identical(p.customBytes, _tinyPng), isTrue);
      expect(p.localFilePath, '/shots/chronos.png');
      expect(p.hasImage, isTrue);
      expect(p.previewAsset, kNoPreview, reason: 'still no bundled picture behind it');
      expect(p.sceneType, 'Local Image');

      studio.createNewProject('Linked', '', null, null, 'https://cdn.example.com/a.png');
      p = studio.activeProject!;
      expect(p.externalUrl, 'https://cdn.example.com/a.png');
      expect(p.sceneType, 'Remote Image');
      expect(p.hasImage, isTrue);
      expect(p.subtitle, '.pht · ${studio.integrator.solverCaption}', reason: 'no details: the usual caption');
    });

    test('a blank project can be given an image later', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);
      studio.createNewProject('Blank');
      expect(studio.activeProject!.hasImage, isFalse);
      studio.setProjectImage(bytes: _tinyPng, path: '/x/pic.png');
      expect(studio.activeProject!.hasImage, isTrue);
      expect(identical(studio.activeProject!.customBytes, _tinyPng), isTrue);
      expect(studio.toast.value, 'IMAGE ADDED · Blank');
      studio.setProjectImage();
      expect(studio.activeProject!.hasImage, isTrue, reason: 'nothing given, nothing changed');
    });

    test('the sheet state is an overlay like the others, and a creation closes it', () {
      final studio = StudioController(autoConnect: false, animateShader: false);
      addTearDown(studio.dispose);
      expect(studio.newProjectSheetOpen, isFalse);
      studio.setNewProjectSheetOpen(true);
      expect(studio.newProjectSheetOpen, isTrue);
      expect(studio.sceneAnimationPaused, isTrue);
      studio.setExportModalOpen(true);
      expect(studio.newProjectSheetOpen, isFalse, reason: 'one overlay at a time');
      studio.setNewProjectSheetOpen(true);
      expect(studio.exportModalOpen, isFalse);
      studio.createNewProject('Done');
      expect(studio.newProjectSheetOpen, isFalse);
    });

    test('a project with no preview, bytes, file or link has no image; any one of them gives it one', () {
      final blank = kDefaultProjects.first.copyWith(previewAsset: kNoPreview);
      expect(blank.hasImage, isFalse);
      expect(blank.copyWith(customBytes: _tinyPng).hasImage, isTrue);
      expect(blank.copyWith(externalUrl: 'https://x/y.png').hasImage, isTrue);
      expect(blank.copyWith(localFilePath: '/a/b.JPG').hasImage, isTrue);
      expect(blank.copyWith(localFilePath: '/a/b.usd').hasImage, isFalse, reason: 'a scene file is not a picture');
      expect(kDefaultProjects.every((p) => p.hasImage), isTrue);
      expect(blank.copyWith(description: 'About it').description, 'About it');
    });

    test('duplicate and delete keep a valid active project', () {
      final studio = StudioController(autoConnect: false);
      addTearDown(studio.dispose);

      studio.duplicateProject('gold_atelier_bsdf');
      expect(studio.projects, hasLength(6));
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

      studio.loadAsset('kerr_photon_ring');
      expect(studio.activeProjectId, 'kerr_photon_ring');

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
      expect(painter.color, const Color(0xFF262936));
      expect(painter.highlight, const Color(0xFFF0F1FA));
      expect(painter.tint, const Color(0xFF6878FF));
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
      await _setTheme(tester, dark: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_dotPainter(tester).color, const Color(0xFFD0D3E2));
      expect(_dotPainter(tester).highlight, const Color(0xFF14151B));
      expect(_dotPainter(tester).tint, const Color(0xFF1A2FFB));
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
      expect(find.text('RENDERED · 2d ago'), findsOneWidget);
      expect(find.text('ACTIVE · 5h ago'), findsOneWidget);
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

      await _tapKey(tester, const ValueKey('project-volumetric_prism'));
      await tester.pump();
      expect(studio.integrator, IntegratorMode.sppm);
      expect(tester.takeException(), isNull);

      await _teardown(tester, studio);
    });

    testWidgets('+ NEW opens the popup; it adds nothing until the project is created', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(studio.projects, hasLength(5));

      await tester.tap(find.byKey(const Key('new-project-btn')));
      await tester.pump();
      expect(studio.newProjectSheetOpen, isTrue);
      expect(find.byKey(const Key('new-project-modal')), findsOneWidget);
      expect(studio.projects, hasLength(5), reason: 'no project yet');

      await tester.enterText(find.byKey(const Key('new-project-name')), 'MY_SHOT');
      await _tapKey(tester, const Key('new-project-create'));
      await tester.pump();

      expect(studio.projects, hasLength(6));
      expect(studio.activeProject!.name, 'MY_SHOT');
      expect(find.byKey(const Key('new-project-modal')), findsNothing);
      expect(find.text('MY_SHOT'), findsOneWidget);
      expect(find.text('6'), findsOneWidget, reason: 'the count badge');
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
      expect(studio.projects, hasLength(6));
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
      expect(find.byKey(const Key('new-project-modal')), findsOneWidget, reason: 'the popup opens here too');
      await tester.enterText(find.byKey(const Key('new-project-name')), 'COMPANION_SHOT');
      await _tapKey(tester, const Key('new-project-create'));
      await tester.pump();
      expect(studio.projects, hasLength(6));
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    test('the curated templates are exactly five: three dynamic, two static', () {
      expect(kDefaultProjects.map((p) => (p.id, p.code, p.isDynamic, p.sceneKind, p.previewAsset)), [
        ('caustic_study_04', 'PRJ-01', true, ProceduralSceneKind.causticWave, 'assets/images/caustic_wave.jpg'),
        ('gold_atelier_bsdf', 'PRJ-02', false, ProceduralSceneKind.liquidChrome, 'assets/images/gold_bsdf_sphere.jpg'),
        ('volumetric_prism', 'PRJ-03', true, ProceduralSceneKind.spectralPrism, 'assets/images/volumetric_prism.png'),
        ('acrylic_lens_array', 'PRJ-04', false, ProceduralSceneKind.emeraldSubsurface, 'assets/images/emerald_subsurface.png'),
        ('kerr_photon_ring', 'PRJ-05', true, ProceduralSceneKind.blackHoleLensing, 'assets/images/blackhole_lensing.png'),
      ]);
      expect(kDefaultProjects.where((p) => p.isDynamic), hasLength(3));
      expect(kDefaultProjects.where((p) => !p.isDynamic), hasLength(2));
      expect(kDefaultProjects.map((p) => p.name), [
        'CAUSTIC_STUDY_04',
        'GOLD_ATELIER_BSDF',
        'VOLUMETRIC_PRISM',
        'ACRYLIC_LENS_ARRAY',
        'KERR_PHOTON_RING',
      ]);
      for (final removed in ['chrome_caustics', 'thin_film_iris']) {
        expect(kDefaultProjects.any((p) => p.id == removed), isFalse, reason: removed);
      }
      // Every preview is a real, bundled asset.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final p in kDefaultProjects) {
        expect(File(p.previewAsset).existsSync(), isTrue, reason: p.previewAsset);
        expect(pubspec, contains(p.previewAsset));
      }
    });

    testWidgets('lists the five projects with dynamic and static badges', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      for (final p in kDefaultProjects) {
        expect(find.text(p.name), findsOneWidget, reason: p.name);
      }
      expect(studio.projects.where((p) => p.isDynamic), hasLength(3));
      expect(find.text('⚡ DYNAMIC'), findsNWidgets(3));
      expect(find.text('\u{1F5BC} STATIC'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('DYNAMIC and STATIC filters narrow the list; ALL restores it', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      const dynamicNames = {
        'CAUSTIC_STUDY_04',
        'VOLUMETRIC_PRISM',
        'KERR_PHOTON_RING',
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

      await _setTheme(tester, dark: false);
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
      // Lusion Light (Daylight Lab).
      const d = PhotonPalette.daylight;
      expect(d.brightness, Brightness.light);
      expect(
        [d.canvas, d.surface, d.substrate, d.carbon, d.onCarbon, d.violet, d.violetInk, d.rose],
        [
          const Color(0xFFF0F1FA),
          const Color(0xFFE4E6EF),
          const Color(0xFFFFFFFF),
          const Color(0xFF14151B),
          const Color(0xFFF0F1FA),
          const Color(0xFF1A2FFB),
          const Color(0xFF1A2FFB),
          const Color(0xFFFF4C41),
        ],
      );
      expect(
        [d.border, d.textMuted, d.ghost, d.hoverFill, d.dock, d.onDock, d.viewportMatte, d.shadow],
        [
          const Color(0xFFD8DAE8),
          const Color(0xFF686B7A),
          const Color(0xFF9EA1B2),
          const Color(0xFFE4E6EF),
          const Color(0xFFFFFFFF),
          const Color(0xFF14151B),
          const Color(0xFFE4E6EF),
          const Color(0xFF010103),
        ],
      );
      // Lusion Dark (Dark Grading).
      const g = PhotonPalette.grading;
      expect(g.brightness, Brightness.dark);
      expect(
        [g.canvas, g.surface, g.substrate, g.carbon, g.onCarbon, g.violet, g.violetInk, g.rose],
        [
          const Color(0xFF0B0C10),
          const Color(0xFF14151B),
          const Color(0xFF12141C),
          const Color(0xFFF0F1FA),
          const Color(0xFF0B0C10),
          const Color(0xFF1A2FFB),
          const Color(0xFF6878FF),
          const Color(0xFFFF4C41),
        ],
      );
      expect(
        [g.border, g.textMuted, g.ghost, g.hoverFill, g.dock, g.onDock, g.viewportMatte, g.shadow],
        [
          const Color(0xFF262936),
          const Color(0xFF8E92A4),
          const Color(0xFF4E5263),
          const Color(0xFF1E212D),
          const Color(0xFF08090D),
          const Color(0xFFF0F1FA),
          const Color(0xFF14151B),
          const Color(0xFF000000),
        ],
      );
    });

    test('the tier accents are Lusion cyan, blue and coral', () {
      expect([for (final t in PlanTier.values) t.color], [const Color(0xFF22D3EE), const Color(0xFF1A2FFB), const Color(0xFFFF4C41)]);
      expect(
        [for (final t in PhotonModelTier.values) t.accent],
        [const Color(0xFF22D3EE), const Color(0xFF1A2FFB), const Color(0xFFFF4C41)],
      );
    });

    test('the native window frame is painted with the Lusion colours', () {
      // COLORREF is 0x00BBGGRR.
      final source = File('windows/runner/win32_window.cpp').readAsStringSync();
      for (final entry in {
        '0x000D0908': '#08090D dark caption',
        '0x00FAF1F0': '#F0F1FA dark text / light caption',
        '0x00362926': '#262936 dark border',
        '0x001B1514': '#14151B light text',
        '0x00E8DAD8': '#D8DAE8 light border',
        '0x00100C0B': '#0B0C10 launch film caption',
        '0x009A4A5B': '#5B4A9A launch film border',
      }.entries) {
        expect(source, contains(entry.key), reason: entry.value);
      }
      // The window starts in the film's palette, and Dart can repaint it freely.
      expect(source, contains('UpdateFrame(window, true,'));
      expect(File('windows/runner/flutter_window.cpp').readAsStringSync(), contains('setFrameColors'));
      expect(source, contains('ReapplyFrame'), reason: 'a system colour change puts back the same frame');
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

      expect(dockColor(), const Color(0xFF08090D));
      expect(headerColor(), PhotonPalette.grading.substrate);

      await _setTheme(tester, dark: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(dockColor(), const Color(0xFFFFFFFF));
      expect((dockDecoration().border! as Border).top.color, PhotonPalette.daylight.border);
      expect(headerColor(), PhotonPalette.daylight.surface);
      expect(prompt().fillColor, PhotonPalette.daylight.canvas);
      expect(tester.widget<TextField>(find.byKey(const Key('scene-prompt'))).style!.color, const Color(0xFF14151B));
      expect(tester.takeException(), isNull);

      await _setTheme(tester, dark: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(dockColor(), const Color(0xFF08090D));
      expect(headerColor(), PhotonPalette.grading.substrate);
      expect(prompt().fillColor, Colors.white.withValues(alpha: 0.08));

      await _teardown(tester, studio);
    });

    testWidgets('the Photon mark is the same tile in both themes: it is the app\'s identity', (tester) async {
      final key = GlobalKey();
      Future<ByteData> render(PhotonPalette palette) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildPhotonTheme(palette),
            themeAnimationDuration: Duration.zero,
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: const SizedBox.square(dimension: 40, child: PhotonLogoMark(size: 40)),
              ),
            ),
          ),
        );
        await _logoReady(tester);
        return _capture(tester, key);
      }

      final dark = await render(PhotonPalette.grading);
      final light = await render(PhotonPalette.daylight);
      expect(dark.buffer.asUint8List(), light.buffer.asUint8List(), reason: 'pixel for pixel');
      expect(_channel(_pixel(light, 40, 6, 4).r), lessThan(40), reason: 'the dark navy tile even in Daylight Lab');
      expect(_pixel(light, 40, 0, 0).a, 0);
    });

    test('the native frame wears the launch film while it plays, the studio theme after', () {
      final studio = StudioController(autoConnect: false, animateShader: false, startInLandingPage: true);
      addTearDown(studio.dispose);
      expect(studio.nativeFrame, NativeFrame.film);
      studio.setDarkGrading(false);
      expect(studio.nativeFrame, NativeFrame.film, reason: 'the film plays in its own colours whichever theme is set');
      studio.enterPhotonStudio();
      expect(studio.nativeFrame, NativeFrame.daylight);
      studio.setDarkGrading(true);
      expect(studio.nativeFrame, NativeFrame.grading);
      studio.openLaunchPortal();
      expect(studio.nativeFrame, NativeFrame.film);

      expect(NativeFrame.film.caption, const Color(0xFF0B0C10), reason: 'the landing page\'s Lusion void');
      expect(NativeFrame.grading.toArguments(), {'dark': true, 'caption': 0x08090D, 'text': 0xF0F1FA, 'border': 0x262936});
      expect(NativeFrame.daylight.toArguments(), {'dark': false, 'caption': 0xF0F1FA, 'text': 0x14151B, 'border': 0xD8DAE8});
    });

    testWidgets('the window frame is sent as the app goes film, then theme, then film again', (tester) async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('photon/window');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      final studio = StudioController(autoConnect: false, animateShader: false, startInLandingPage: true);
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      expect(calls.single.method, 'setFrameColors');
      expect(calls.single.arguments, NativeFrame.film.toArguments(), reason: 'from the first frame');

      studio.setDarkGrading(false);
      expect(calls, hasLength(1), reason: 'the film is still playing: nothing changes');

      studio.enterPhotonStudio();
      expect(calls, hasLength(2));
      expect(calls.last.arguments, NativeFrame.daylight.toArguments(), reason: 'in the studio the frame follows the theme');

      studio.setDarkGrading(true);
      expect(calls.last.arguments, NativeFrame.grading.toArguments());
      studio.setDarkGrading(true);
      expect(calls, hasLength(3), reason: 'no change, no call');

      studio.openLaunchPortal();
      expect(calls.last.arguments, NativeFrame.film.toArguments());
      await _teardown(tester, studio);
    });

    testWidgets('a studio opened in the workspace (tests) starts on its theme\'s frame', (tester) async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('photon/window');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(calls.single.arguments, NativeFrame.grading.toArguments());
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
      studio.setProbeVisible(true); // the readout is off until the probe is
      await tester.pump();
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

      // The probe follows the focus point (once it is on).
      studio.setProbeVisible(true);
      await tester.pump();
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
      // Order: theme, live shader, BVH, A/B wipe, loupe, false color, probe.
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
      expect(studio.probeVisible, isTrue, reason: 'arrow up from the first row wraps to the last: Toggle Optical Focus Probe (off by default, so now on)');
      expect(studio.falseColorEnabled, isFalse);
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

    /// Opens the console from the name pill, on [tab] (IDENTITY by default).
    Future<StudioController> openAccount(WidgetTester tester, [ProfileTab tab = ProfileTab.identity]) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      await _tapKey(tester, const Key('account-pill-btn'));
      await _pumpFor(tester, const Duration(milliseconds: 300));
      if (tab != ProfileTab.identity) {
        await _tapKey(tester, Key(tab.keyName));
        await _pumpFor(tester, const Duration(milliseconds: 400));
      }
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

      // The plan and the auth live in the card's own tabs.
      await _tapKey(tester, const Key('profile-tab-plan'));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(find.text('STUDIO PRO · \$49/mo'), findsOneWidget);
      expect(find.text('\$49 / mo'), findsOneWidget);
      expect(find.text('842.5 / 1,000 GPU-hrs'), findsOneWidget);
      expect(find.text('842.5 / 1,000 hrs · 84%'), findsOneWidget);
      expect(find.text('128.4 / 500 GB USD Vault'), findsOneWidget);
      expect(find.text('128.4 / 500 GB · 26%'), findsOneWidget);
      await _tapKey(tester, const Key('profile-tab-auth'));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(find.text('WebAuthn Passkey · Hardware Enclave'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the name pill is the only way into the console from the header', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(find.text('ACCOUNT'), findsNothing, reason: 'no ACCOUNT segment in the workspace switch');
      for (final label in ['SPLIT', 'VIEWPORT', 'OPTICS', 'DECK']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.byKey(const Key('account-pill-btn')), findsOneWidget);
      expect(find.byKey(const Key('profile-card-trigger')), findsOneWidget);
      final pill = find.byKey(const Key('account-pill-btn'));
      for (final s in ['MF', 'MOHD FARAZ', 'PRO']) {
        expect(find.descendant(of: pill, matching: find.text(s)), findsOneWidget, reason: s);
      }
      // The old embedded workspace is gone: asking for it opens the console.
      studio.setMaximizedPanel('account');
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(studio.maximizedPanel, isNull);
      expect(studio.accountModalOpen, isTrue);
      expect(modal, findsOneWidget);
      expect(find.text('SCENE_VIEWPORT.rt'), findsOneWidget, reason: 'the workspace is untouched behind it');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the console is the blue profile card alone: no gray cards, no outer window', (tester) async {
      final studio = await openAccount(tester);
      expect(find.byKey(const Key('animated-profile-card')), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('animated-profile-card'))).width, lessThanOrEqualTo(560));
      expect(find.text('ACCOUNT_CONSOLE'), findsNothing);
      for (final gone in ['STUDIO IDENTITY & PROFILE', 'PLAN TIER & GPU CLUSTER QUOTA', 'AUTHENTICATION & SECURITY']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      expect(find.byKey(const ValueKey('pip-close-account')), findsOneWidget);
      expect(find.text('READY'), findsOneWidget, reason: 'the live status footer');
      await _teardown(tester, studio);
    });

    testWidgets('the footer reads out the latest action live', (tester) async {
      final studio = await openAccount(tester, ProfileTab.plan);
      expect(find.descendant(of: modal, matching: find.text('READY')), findsOneWidget);
      await _tapKey(tester, const Key('profile-tier-enterprise'));
      await tester.pump();
      expect(find.descendant(of: modal, matching: find.text('PLAN UPDATED · ENTERPRISE CLUSTER')), findsOneWidget);
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

      // A click on the card itself does not dismiss it.
      studio.setAccountModalOpen(true);
      await tester.pump();
      await tester.tap(find.text('Mohd Faraz'));
      await tester.pump();
      expect(modal, findsOneWidget);
      await _teardown(tester, studio);
    });

    testWidgets('plan tiers switch live, and the quota bars follow', (tester) async {
      final studio = await openAccount(tester, ProfileTab.plan);

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
      final studio = await openAccount(tester, ProfileTab.auth);

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

      final studio = await openAccount(tester, ProfileTab.auth);
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
      final studio = await openAccount(tester, ProfileTab.auth);
      await _tapKey(tester, Key('copy-key-${studio.account.apiKeys.first.id}'));
      await tester.pump();
      expect(find.descendant(of: modal, matching: find.text('CLIPBOARD UNAVAILABLE')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('sessions: remote ones can be revoked, this device cannot', (tester) async {
      final studio = await openAccount(tester, ProfileTab.auth);
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

    testWidgets('the close button closes the console and the workspace is where it was', (tester) async {
      final studio = await openAccount(tester);
      await tester.tap(find.byKey(const ValueKey('pip-close-account')));
      await tester.pump();
      expect(modal, findsNothing);
      expect(studio.accountModalOpen, isFalse);
      expect(find.text('SCENE_VIEWPORT.rt'), findsOneWidget);
      await _teardown(tester, studio);
    });

    testWidgets('a tall tab scrolls inside the window instead of overflowing', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1000, 560));
      await _tapKey(tester, const Key('account-pill-btn'));
      await _pumpFor(tester, const Duration(milliseconds: 300));
      await _tapKey(tester, const Key('profile-tab-auth'));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      final card = tester.getRect(find.byKey(const Key('animated-profile-card')));
      expect(card.height, lessThanOrEqualTo(560));
      // Everything is still reachable by scrolling.
      await _tapKey(tester, const Key('revoke-session-ses_mcp'));
      await tester.pump();
      expect(studio.account.sessions.map((s) => s.id), ['ses_local', 'ses_node']);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the console fits a narrow window, on every tab', (tester) async {
      final studio = await _pumpStudio(tester, const Size(390, 844));
      await _tapKey(tester, const Key('account-pill-btn'));
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(modal, findsOneWidget);
      expect(find.text('Mohd Faraz'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('animated-profile-card'))).width, lessThanOrEqualTo(390));
      for (final tab in ProfileTab.values) {
        await _tapKey(tester, Key(tab.keyName));
        await _pumpFor(tester, const Duration(milliseconds: 400));
      }
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    group('Lusion theme coordination', () {
      final surface = find.byKey(const Key('profile-card-surface'));

      /// The shell: hairline border and ambient shadow.
      BoxDecoration decoration(WidgetTester tester) => tester.widget<Container>(surface).decoration! as BoxDecoration;

      /// The backdrop: the three-stop architectural gradient inside the shell.
      List<Color> backdrop(WidgetTester tester) => tester
          .widgetList<DecoratedBox>(find.descendant(of: surface, matching: find.byType(DecoratedBox)))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.gradient)
          .whereType<LinearGradient>()
          .firstWhere((g) => g.colors.length == 3)
          .colors;

      Future<void> setTheme(WidgetTester tester, StudioController studio, {required bool dark}) async {
        studio.setDarkGrading(dark);
        await tester.pump();
        await _pumpFor(tester, const Duration(milliseconds: 500));
      }

      testWidgets('Dark Grading: the void-to-slate surface, a blue-accented hairline, off-white type', (tester) async {
        final studio = await openAccount(tester);
        final deco = decoration(tester);
        expect(backdrop(tester), [const Color(0xFF0B0C10), const Color(0xFF12141C), const Color(0xFF171A28)]);
        final border = (deco.border! as Border).top;
        expect(border.width, 1);
        const g = PhotonPalette.grading;
        expect(border.color, Color.alphaBlend(g.violet.withValues(alpha: 0.45), g.border), reason: 'c.border accented with the Lusion blue');
        expect(border.color, isNot(g.border));
        expect(deco.boxShadow!.single.color, g.violet.withValues(alpha: 0.22));
        final name = tester.widget<Text>(find.text('Mohd Faraz'));
        expect(name.style!.color, g.carbon, reason: 'crisp #F0F1FA');
        expect(tester.takeException(), isNull);
        await _teardown(tester, studio);
      });

      testWidgets('Daylight Lab: the white-to-lavender surface, the #D8DAE8 hairline, obsidian type', (tester) async {
        final studio = await openAccount(tester);
        await setTheme(tester, studio, dark: false);
        final deco = decoration(tester);
        expect(backdrop(tester), [const Color(0xFFFFFFFF), const Color(0xFFF0F1FA), const Color(0xFFE4E6EF)]);
        expect((deco.border! as Border).top.color, const Color(0xFFD8DAE8));
        expect(deco.boxShadow!.single.color, const Color(0xFF1A2FFB).withValues(alpha: 0.10));
        final name = tester.widget<Text>(find.text('Mohd Faraz'));
        expect(name.style!.color, const Color(0xFF14151B), reason: 'crisp #14151B');
        expect(tester.takeException(), isNull);
        await _teardown(tester, studio);
      });

      testWidgets('the drawer cards are frosted ink in the dark and white-on-lavender in the light', (tester) async {
        final studio = await openAccount(tester);
        BoxDecoration drawer() => tester
            .widgetList<Container>(find.descendant(of: find.byKey(const Key('animated-profile-card')), matching: find.byType(Container)))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.gradient is LinearGradient && d.borderRadius == BorderRadius.circular(14));
        expect((drawer().gradient! as LinearGradient).colors.first.a, lessThan(0.2), reason: 'a wash');
        await setTheme(tester, studio, dark: false);
        expect((drawer().gradient! as LinearGradient).colors, [const Color(0xFFFFFFFF), const Color(0xFFE4E6EF)]);
        expect((drawer().border! as Border).top.color, const Color(0xFFD8DAE8));
        await _teardown(tester, studio);
      });

      testWidgets('there is no cursor circle: nothing is drawn around the pointer', (tester) async {
        final studio = await openAccount(tester);
        final card = find.byKey(const Key('animated-profile-card'));
        final mouse = await _mouse(tester);
        await mouse.moveTo(tester.getCenter(card) + const Offset(40, 30));
        await tester.pump(const Duration(milliseconds: 60));

        // Run the aurora painter into a canvas that logs every circle.
        final aurora = tester
            .widgetList<CustomPaint>(find.descendant(of: surface, matching: find.byType(CustomPaint)))
            .map((c) => c.painter)
            .whereType<CustomPainter>()
            .firstWhere((p) => p.runtimeType.toString() == '_AuroraPainter');
        final log = _CircleLog();
        aurora.paint(log, tester.getSize(surface));
        expect(log.circles, hasLength(3), reason: 'just the three drifting blooms');
        for (final c in log.circles) {
          expect(c.paint.shader, isNotNull, reason: 'a soft gradient bloom');
          expect(c.paint.style, PaintingStyle.fill, reason: 'no stroked ring');
          expect(c.radius, greaterThan(100), reason: 'not a 28px ring');
        }
        expect(log.circles.where((c) => c.radius == 28), isEmpty);

        // Nor does it move with the pointer: the same canvas, the pointer elsewhere.
        await mouse.moveTo(tester.getTopLeft(card) + const Offset(30, 30));
        final again = _CircleLog();
        aurora.paint(again, tester.getSize(surface));
        expect(again.circles.length, 3);
        expect(tester.takeException(), isNull);
        await _teardown(tester, studio);
      });

      testWidgets('still: no backdrop blur, and nothing in the console moves', (tester) async {
        final studio = await openAccount(tester);
        expect(find.byType(BackdropFilter), findsNothing);
        final card = find.byKey(const Key('animated-profile-card'));
        // No tilt, no turning ring, no fades, no size or hover tweens inside the card.
        for (final moving in [RotationTransition, FadeTransition, ScaleTransition, SlideTransition, AnimatedContainer, AnimatedSwitcher, TweenAnimationBuilder<double>]) {
          expect(find.descendant(of: card, matching: find.byType(moving)), findsNothing, reason: '$moving');
        }
        // Walking up from the card there is no tilt Transform before the modal.
        var tilts = 0;
        tester.element(card).visitAncestorElements((e) {
          if (e.widget is Transform) tilts++;
          return e.widget.key != const Key('account-modal');
        });
        expect(tilts, 0);
        expect(tester.takeException(), isNull);
        await _teardown(tester, studio);
      });

      testWidgets('still: hovering, moving about, switching tabs and folding the curtain schedule no frames', (tester) async {
        final studio = StudioController(autoConnect: false);
        await _pumpStudio(tester, const Size(1280, 800), controller: studio);
        for (var i = 0; i < 500 && studio.tickerActive; i++) {
          studio.debugTick();
        }
        studio.setAccountModalOpen(true);
        await _pumpFor(tester, const Duration(milliseconds: 300));
        final card = find.byKey(const Key('animated-profile-card'));
        final mouse = await _mouse(tester);
        await mouse.moveTo(tester.getCenter(card));
        await tester.pump();
        await mouse.moveTo(tester.getCenter(card) + const Offset(60, 25));
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isFalse, reason: 'on the card: nothing is animating');
        // A tab change is one frame: the old tab is gone and the new one is there
        // (a cross-fade would leave both on screen part-way).
        expect(find.text('github.com/mfarazcodes'), findsOneWidget);
        await tester.tap(find.byKey(Key(ProfileTab.plan.keyName)));
        await tester.pump();
        expect(find.text('github.com/mfarazcodes'), findsNothing, reason: 'the old tab leaves in the same frame');
        expect(find.text('STUDIO PRO · \$49/mo'), findsOneWidget, reason: 'and the new one is already there');
        // And the curtain folds at once (a height tween would leave it part open).
        await tester.tap(find.byKey(Key(ProfileTab.plan.keyName)));
        await mouse.moveTo(const Offset(2, 2));
        await tester.pump();
        expect(find.text('STUDIO PRO · \$49/mo'), findsNothing, reason: 'folded in the same frame');
        await _teardown(tester, studio);
      });

      testWidgets('the glow is a still Lusion blue: stronger in the dark (0.18) than in the light (0.08)', (tester) async {
        final studio = await openAccount(tester);
        final auroraFinder = find.descendant(
          of: surface,
          matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_AuroraPainter'),
        );
        final darkPainter = tester.widget<CustomPaint>(auroraFinder).painter!;
        await setTheme(tester, studio, dark: false);
        final lightPainter = tester.widget<CustomPaint>(auroraFinder).painter!;
        expect((darkPainter as dynamic).isDark, isTrue);
        expect((darkPainter as dynamic).blue, PhotonPalette.grading.violet);
        expect((lightPainter as dynamic).isDark, isFalse);
        expect((lightPainter as dynamic).blue, PhotonPalette.daylight.violet);

        // Paint each on its own, and read the glow back at the first bloom's
        // centre (it is held at 0.25 of its old lap).
        Future<int> glowAlpha(CustomPainter painter) async {
          final key = GlobalKey();
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: RepaintBoundary(key: key, child: SizedBox(width: 560, height: 400, child: CustomPaint(painter: painter))),
              ),
            ),
          );
          final data = await _capture(tester, key);
          return (_pixel(data, 560, (0.34 * 560).round(), (0.155 * 400).round()).a * 255).round();
        }

        final dark = await glowAlpha(darkPainter);
        final light = await glowAlpha(lightPainter);
        expect(dark, inInclusiveRange(40, 75), reason: 'about 0.18 of 255');
        expect(light, inInclusiveRange(15, 35), reason: 'about 0.08 of 255');
        expect(dark, greaterThan(light * 1.8));
        await _teardown(tester, studio);
      });

      testWidgets('every tab is legible in both themes: type contrasts with the surface, nothing is stuck white', (tester) async {
        for (final dark in [true, false]) {
          for (final tab in ProfileTab.values) {
            final studio = await openAccount(tester, tab);
            if (!dark) await setTheme(tester, studio, dark: false);
            final palette = dark ? PhotonPalette.grading : PhotonPalette.daylight;
            // The surface is nearly the theme's own canvas end to end.
            final bg = dark ? const Color(0xFF12141C) : const Color(0xFFF0F1FA);
            final texts = find.descendant(of: find.byKey(const Key('animated-profile-card')), matching: find.byType(Text)).evaluate().toList();
            expect(texts, isNotEmpty);
            var checked = 0;
            for (final element in texts) {
              final text = element.widget as Text;
              final colour = text.style?.color;
              if (colour == null || colour.a == 0) continue;
              if (colour == palette.onCarbon) continue; // ink on a filled-ink chip (a selected choice)
              var inChip = false;
              element.visitAncestorElements((a) {
                if (a.widget.key.toString().contains('profile-tier-')) inChip = true;
                return !inChip;
              });
              if (inChip) continue; // the selected chip is a filled ink pill
              final seen = Color.alphaBlend(colour, bg);
              final lighter = math.max(seen.computeLuminance(), bg.computeLuminance());
              final darker = math.min(seen.computeLuminance(), bg.computeLuminance());
              final ratio = (lighter + 0.05) / (darker + 0.05);
              expect(ratio, greaterThan(2.8), reason: '"${text.data}" in ${dark ? 'dark' : 'light'} / ${tab.label}: $colour on $bg');
              if (!dark) {
                expect(colour == Colors.white, isFalse, reason: '"${text.data}" is hardcoded white in Daylight');
              }
              checked++;
            }
            expect(checked, greaterThan(5), reason: '${tab.label} ${dark ? 'dark' : 'light'}');
            expect(palette.isDark, dark);
            expect(tester.takeException(), isNull);
            await _teardown(tester, studio);
          }
        }
      });

      testWidgets('the accent is Lusion blue: the focused field, a switched-on toggle and the quota bar', (tester) async {
        final studio = await openAccount(tester, ProfileTab.auth);
        // 2FA is on in the seeded account: its toggle track is the brand blue.
        final toggle = find.byKey(const Key('profile-2fa-toggle'));
        final track = tester
            .widgetList<Container>(find.descendant(of: toggle, matching: find.byType(Container)))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.shape != BoxShape.circle && d.borderRadius != null);
        expect(track.color, PhotonPalette.grading.violet);
        await setTheme(tester, studio, dark: false);
        final lightTrack = tester
            .widgetList<Container>(find.descendant(of: toggle, matching: find.byType(Container)))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.shape != BoxShape.circle && d.borderRadius != null);
        expect(lightTrack.color, const Color(0xFF1A2FFB));
        expect(tester.takeException(), isNull);
        await _teardown(tester, studio);
      });

      test('no navy, cobalt or cyan gradient is left in the card', () {
        final source = File('lib/widgets/animated_profile_card.dart').readAsStringSync();
        for (final gone in ['0xFF0A192F', '0xFF1E3A8A', '0xFF2563EB', '0xFF06B6D4', 'AnimatedBlueProfileCard.navy', 'AnimatedBlueProfileCard.cobalt']) {
          expect(source.contains(gone), isFalse, reason: gone);
        }
        expect('Colors.white'.allMatches(source).length, lessThanOrEqualTo(1), reason: 'every white is derived from the theme; only a toggle knob stays white');
      });
    });

    testWidgets('every account control answers to its long-standing key and the card\'s own', (tester) async {
      final studio = await openAccount(tester, ProfileTab.plan);
      for (final tier in PlanTier.values) {
        expect(find.byKey(Key('tier-${tier.name}')), findsOneWidget);
        expect(find.byKey(Key('profile-tier-${tier.name}')), findsOneWidget);
      }
      await _tapKey(tester, const Key('profile-tier-enterprise'));
      await tester.pump();
      expect(studio.account.tier, PlanTier.enterprise);
      await _tapKey(tester, const Key('tier-indie'));
      await tester.pump();
      expect(studio.account.tier, PlanTier.indie);

      await _tapKey(tester, const Key('profile-tab-auth'));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      final first = studio.account.apiKeys.first;
      for (final k in ['account-2fa-toggle', 'profile-2fa-toggle', 'account-hwkey-toggle', 'create-api-key-btn', 'profile-copy-key-btn', 'profile-rotate-key-btn', 'copy-key-${first.id}', 'rotate-key-${first.id}', 'reveal-key-${first.id}']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      // The card's own keys address the first key only.
      await _tapKey(tester, const Key('profile-rotate-key-btn'));
      await tester.pump();
      expect(studio.account.apiKeys.first.secret, isNot(first.secret));
      await _tapKey(tester, const Key('profile-2fa-toggle'));
      await tester.pump();
      expect(studio.account.twoFactorEnabled, isFalse);
      expect(find.text('OFF'), findsOneWidget);
      await _tapKey(tester, const Key('account-2fa-toggle'));
      await tester.pump();
      expect(studio.account.twoFactorEnabled, isTrue);
      expect(find.text('ARMED'), findsOneWidget);
      for (final m in AuthMethod.values) {
        expect(find.byKey(Key('auth-${m.name}')), findsOneWidget, reason: m.name);
      }
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });
  });

  group('landing page', () {
    final portal = find.byKey(const Key('launch-hero-portal'));
    final takeMe = find.byKey(const Key('take-me-to-photon-btn'));

    Future<StudioController> pumpLanding(WidgetTester tester, {bool animate = false}) async {
      final studio = StudioController(autoConnect: false, animateShader: animate, startInLandingPage: true);
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      return studio;
    }

    test('the film and its four keyframes are bundled', () {
      expect(File('assets/videos/photon_hero.mp4').existsSync(), isTrue);
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/videos/photon_hero.mp4'));
      expect([for (final k in kHeroKeyframes) k.seconds], [0.5, 2.0, 4.2, 6.5]);
      for (final k in kHeroKeyframes) {
        expect(File(k.asset).existsSync(), isTrue, reason: k.asset);
        expect(pubspec, contains(k.asset));
      }
      expect(kHeroKeyframes.map((k) => k.asset).toList(), [
        'assets/images/hero_frame_01.jpg',
        'assets/images/hero_frame_02.jpg',
        'assets/images/hero_frame_03.jpg',
        'assets/images/hero_frame_04.jpg',
      ]);
    });

    test('the controller starts in the workspace or on the landing page, and enters the studio', () {
      final studio = StudioController(autoConnect: false, animateShader: false);
      addTearDown(studio.dispose);
      expect(studio.showLaunchPortal, isFalse, reason: 'tests land in the workspace');
      expect(studio.inStudioWorkspace, isTrue);

      studio.openLaunchPortal();
      expect(studio.showLaunchPortal, isTrue);
      expect(studio.inStudioWorkspace, isFalse);
      studio.enterPhotonStudio();
      expect(studio.showLaunchPortal, isFalse);
      expect(studio.inStudioWorkspace, isTrue);
      studio.toggleLaunchPortal();
      expect(studio.showLaunchPortal, isTrue);
      studio.dismissLaunchPortal();
      expect(studio.inStudioWorkspace, isTrue);

      final launching = StudioController(autoConnect: false, animateShader: false, startInLandingPage: true, startInDeckView: true);
      addTearDown(launching.dispose);
      expect(launching.showLaunchPortal, isTrue);
      expect(launching.inStudioWorkspace, isFalse);
      expect(launching.deckView, isTrue);
      var notified = 0;
      launching.addListener(() => notified++);
      launching.enterPhotonStudio();
      launching.enterPhotonStudio();
      expect(notified, 1, reason: 'entering twice changes nothing the second time');
    });

    test('the live scenes pause under any overlay', () {
      final studio = StudioController(autoConnect: false, animateShader: false);
      addTearDown(studio.dispose);
      expect(studio.sceneAnimationPaused, isFalse);
      studio.setAccountModalOpen(true);
      expect(studio.sceneAnimationPaused, isTrue);
      studio.setAccountModalOpen(false);
      studio.setCommandPaletteOpen(true);
      expect(studio.sceneAnimationPaused, isTrue);
      studio.setCommandPaletteOpen(false);
      studio.setIngestSheetOpen(true);
      expect(studio.sceneAnimationPaused, isTrue);
      studio.setIngestSheetOpen(false);
      studio.openLaunchPortal();
      expect(studio.sceneAnimationPaused, isTrue);
      studio.enterPhotonStudio();
      expect(studio.sceneAnimationPaused, isFalse);
    });

    testWidgets('launching shows the full-screen landing page with one way in and no player controls', (tester) async {
      final studio = await pumpLanding(tester);
      expect(studio.showLaunchPortal, isTrue);
      expect(portal, findsOneWidget);
      expect(tester.getSize(portal), const Size(1280, 800), reason: 'full bleed');

      expect(find.text('Physically Based Light Transport.'), findsNothing, reason: 'no headline over the film');
      expect(find.byKey(const Key('hero-headline')), findsNothing);
      expect(find.text("EDITION WINTER '26 // SPATIAL RAY-TRACING ENGINE"), findsOneWidget);
      expect(find.text('PHOTON®'), findsOneWidget);
      expect(find.text('Take me to Photon'), findsOneWidget);
      expect(takeMe, findsOneWidget);
      expect(find.byKey(const Key('enter-studio-btn')), findsOneWidget, reason: 'the compatibility alias');
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);

      // Not a player: no controls, timeline, timecode or reference button.
      for (final gone in ['hero-video-play-toggle', 'hero-scrubber', 'hero-timecode', 'hero-clock', 'hero-load-reference-btn', 'hero-chapter-0']) {
        expect(find.byKey(Key(gone)), findsNothing, reason: gone);
      }
      for (final text in ['PLAY', 'PAUSE', 'LOAD AS VIEWPORT REFERENCE', 'ENTER SPATIAL STUDIO →']) {
        expect(find.text(text), findsNothing, reason: text);
      }
      expect(find.textContaining('TC 00:'), findsNothing);
      expect(find.byType(Slider), findsNothing);

      // The studio is not on screen behind it.
      expect(find.text('SCENE_VIEWPORT.rt'), findsNothing);
      expect(find.text('OPTICS_PARAMETERS'), findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the backdrop is a vignetted film frame', (tester) async {
      final studio = await pumpLanding(tester);
      final vignette = tester.widget<DecoratedBox>(find.byKey(const Key('hero-vignette')));
      final gradient = (vignette.decoration as BoxDecoration).gradient! as RadialGradient;
      expect(gradient.colors.last, const Color(0xFF0B0C10), reason: '#0B0C10 at the edges');
      expect(gradient.colors.first.a, 0, reason: 'clear in the middle');
      final frames = tester.widgetList<Image>(find.descendant(of: find.byKey(const Key('hero-stage')), matching: find.byType(Image))).toList();
      expect(frames, hasLength(2), reason: 'both film layers are always in the tree');
      for (final f in frames) {
        expect(f.filterQuality, FilterQuality.medium);
      }
      String asset(Image i) => ((i.image as ResizeImage).imageProvider as AssetImage).assetName;
      expect(frames.map(asset), ['assets/images/hero_frame_01.jpg', 'assets/images/hero_frame_02.jpg']);
      await _teardown(tester, studio);
    });

    test('the Daylight grade is a 5x4 matrix that lifts, desaturates and washes lavender', () {
      final m = LaunchHeroPortal.daylightGrade;
      expect(m, hasLength(20));
      expect(m.sublist(15), [0, 0, 0, 1, 0], reason: 'alpha untouched');
      List<double> apply(double r, double g, double b) => [
        for (var row = 0; row < 3; row++) (m[row * 5] * r + m[row * 5 + 1] * g + m[row * 5 + 2] * b + m[row * 5 + 4]).clamp(0.0, 255.0),
      ];
      // Black is lifted to a luminous cool lavender-grey, not left black.
      final black = apply(0, 0, 0);
      expect(black, everyElement(inInclusiveRange(95, 115)));
      expect(black[2], greaterThan(black[0]), reason: 'cool: blue over red');
      // The film's deep violet shadows come up too, and white goes to white.
      expect(apply(20, 10, 30).every((v) => v > 100), isTrue);
      expect(apply(255, 255, 255), everyElement(greaterThan(240)));
      // Saturation is pulled in: a pure red's channels end up much closer together.
      final red = apply(255, 0, 0);
      expect(red[0] - red[1], lessThan(255 * 0.6));
      expect(red[0] - red[1], greaterThan(0), reason: 'still red, only quieter');
    });

    testWidgets('Dark Grading leaves the film ungraded; Daylight Lab grades it high-key on lavender', (tester) async {
      final studio = await pumpLanding(tester);
      final grade = find.byKey(const Key('hero-daylight-grade'));
      expect(studio.darkGrading, isTrue);
      expect(grade, findsNothing, reason: 'the original cinematic grade, no filter pass');
      Color vignetteEdge() =>
          (((tester.widget<DecoratedBox>(find.byKey(const Key('hero-vignette'))).decoration as BoxDecoration).gradient!) as RadialGradient).colors.last;
      expect(vignetteEdge(), const Color(0xFF0B0C10));
      expect(tester.widget<Text>(find.byKey(const Key('hero-wordmark'))).style!.color, Colors.white);

      studio.setDarkGrading(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(grade, findsOneWidget);
      final filtered = tester.widget<ColorFiltered>(grade);
      expect(filtered.colorFilter, ColorFilter.matrix(LaunchHeroPortal.daylightGrade));
      // Both film layers sit under the one filter.
      expect(find.descendant(of: grade, matching: find.byType(Image)), findsNWidgets(2));
      expect(vignetteEdge(), const Color(0xFFF0F1FA), reason: 'the lavender canvas at the edges');
      expect(tester.widget<Text>(find.text(LaunchHeroPortal.cta)).style!.color, const Color(0xFF14151B), reason: 'obsidian type on the bright film');
      expect(tester.widget<Text>(find.byKey(const Key('hero-wordmark'))).style!.color, const Color(0xFF14151B));
      expect(tester.takeException(), isNull);

      studio.setDarkGrading(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(grade, findsNothing, reason: 'and back to the dark film');
      expect(vignetteEdge(), const Color(0xFF0B0C10));
      await _teardown(tester, studio);
    });

    test('the loop is continuous at every segment boundary and at the wrap', () {
      const seg = LaunchHeroPortal.segmentSeconds;
      final count = kHeroKeyframes.length;
      for (var k = 1; k <= count * 2; k++) {
        final boundary = seg * k;
        final before = LaunchHeroPortal.layersAt(boundary - 1e-6);
        final after = LaunchHeroPortal.layersAt(boundary);
        // The incoming frame becomes the primary one...
        expect(after.primary, before.incoming, reason: 'boundary $k');
        // ...at exactly the scale it had a moment before: no jump.
        expect(after.primaryScale, closeTo(before.incomingScale, 1e-6), reason: 'boundary $k');
        expect(before.mix, closeTo(1, 1e-6), reason: 'it was fully faded in');
        expect(after.mix, 0, reason: 'the next incoming starts clear');
        expect(after.incomingScale, 1.0, reason: 'and un-scaled');
      }
      // The wrap: the loop's end is its start.
      final start = LaunchHeroPortal.layersAt(0);
      final wrap = LaunchHeroPortal.layersAt(seg * count);
      expect(wrap.primary, start.primary);
      expect(wrap.primaryScale, start.primaryScale);
      expect(start.primaryScale, closeTo(1 + LaunchHeroPortal.pushGain * LaunchHeroPortal.handoff, 1e-12));
    });

    test('the scales never jump: stepping the loop moves each layer a hair at a time', () {
      const seg = LaunchHeroPortal.segmentSeconds;
      var previous = LaunchHeroPortal.layersAt(0);
      for (var t = 0.001; t < seg * kHeroKeyframes.length * 2; t += 0.001) {
        final now = LaunchHeroPortal.layersAt(t);
        if (now.primary == previous.primary) {
          expect((now.primaryScale - previous.primaryScale).abs(), lessThan(1e-4), reason: 't=$t');
          expect((now.incomingScale - previous.incomingScale).abs(), lessThan(1e-4), reason: 't=$t');
        } else {
          expect(now.primaryScale, closeTo(previous.incomingScale, 1e-4), reason: 'hand-off at t=$t');
        }
        previous = now;
      }
    });

    test('the cross-fade is a smootherstep over 45% of a segment, flat at both ends', () {
      expect(LaunchHeroPortal.fadeShare, 0.45);
      const seg = LaunchHeroPortal.segmentSeconds;
      final fadeStart = seg * (1 - LaunchHeroPortal.fadeShare);
      expect(LaunchHeroPortal.layersAt(fadeStart - 0.01).mix, 0);
      expect(LaunchHeroPortal.layersAt(fadeStart).mix, 0);
      expect(LaunchHeroPortal.layersAt(fadeStart + seg * LaunchHeroPortal.fadeShare / 2).mix, closeTo(0.5, 1e-9));
      // Zero velocity at each end: the first and last hundredth barely move.
      expect(LaunchHeroPortal.layersAt(fadeStart + seg * LaunchHeroPortal.fadeShare * 0.01).mix, lessThan(1e-5));
      expect(LaunchHeroPortal.layersAt(seg - seg * LaunchHeroPortal.fadeShare * 0.01).mix, greaterThan(1 - 1e-5));
      var last = 0.0;
      for (var t = fadeStart; t <= seg; t += 0.01) {
        final m = LaunchHeroPortal.layersAt(t).mix;
        expect(m, greaterThanOrEqualTo(last), reason: 'monotonic');
        last = m;
      }
    });

    testWidgets('tapping Take me to Photon stops the landing animation and opens the studio', (tester) async {
      final studio = await pumpLanding(tester, animate: true);
      // The loop is running: its single ticker is the only thing scheduling frames.
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(takeMe);
      await tester.pump();
      expect(studio.inStudioWorkspace, isTrue);
      expect(studio.showLaunchPortal, isFalse);

      // Mid-transition the page is still there, fading; its ticker already stopped.
      await tester.pump(const Duration(milliseconds: 100));
      expect(portal, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(portal, findsNothing, reason: 'gone after the 260ms transition');

      expect(find.text('SCENE_VIEWPORT.rt'), findsOneWidget);
      expect(find.text('OPTICS_PARAMETERS'), findsOneWidget);
      expect(find.text('PROJECTS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the enter-studio-btn alias enters too, and the loop stops with the page', (tester) async {
      final studio = await pumpLanding(tester);
      await tester.tap(find.byKey(const Key('enter-studio-btn')));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(portal, findsNothing);
      expect(studio.inStudioWorkspace, isTrue);
      // Nothing of the page is left animating once the studio is up.
      expect(find.byKey(const Key('hero-stage')), findsNothing);
      await _teardown(tester, studio);
    });

    testWidgets('the loop cross-fades the keyframes in order, then wraps', (tester) async {
      final studio = await pumpLanding(tester, animate: true);
      Iterable<String> shown() => tester
          .widgetList<Image>(find.descendant(of: find.byKey(const Key('hero-stage')), matching: find.byType(Image)))
          .map((i) => ((i.image as ResizeImage).imageProvider as AssetImage).assetName.substring('assets/images/hero_frame_'.length, 'assets/images/hero_frame_'.length + 2));
      double incomingOpacity() => tester
          .widgetList<Opacity>(find.descendant(of: find.byKey(const Key('hero-stage')), matching: find.byType(Opacity)))
          .last
          .opacity;
      // _pumpStudio already ran 300ms: frame 1 is primary, frame 2 waits, clear.
      expect(shown().toList(), ['01', '02']);
      expect(incomingOpacity(), 0);
      await tester.pump(const Duration(milliseconds: 2900));
      expect(shown().toList(), ['01', '02'], reason: 'the same two layers throughout the fade');
      expect(incomingOpacity(), inExclusiveRange(0, 1), reason: 'cross-fading in the last 45% of a 4s segment');
      await tester.pump(const Duration(milliseconds: 1500));
      expect(shown().toList(), ['02', '03'], reason: 'frame 2 is primary, frame 3 is next');
      expect(incomingOpacity(), 0);
      // Round the loop and back to the start: always two layers, never a gap.
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(seconds: 1));
        expect(shown(), hasLength(2));
      }
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the SHOWCASE pill brings the landing page back', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(portal, findsNothing);
      await _tapKey(tester, const Key('open-launch-portal-btn'));
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(portal, findsOneWidget);
      expect(studio.inStudioWorkspace, isFalse);
      await tester.tap(takeMe);
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(portal, findsNothing);
      expect(find.text('SCENE_VIEWPORT.rt'), findsOneWidget);
      await _teardown(tester, studio);
    });

    testWidgets('PhotonApp opens on the landing page unless told otherwise', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final studio = StudioController(autoConnect: false, animateShader: false, startInLandingPage: true);
      await tester.pumpWidget(PhotonApp(controller: studio));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('launch-hero-portal')), findsOneWidget);
      expect(const PhotonApp().startInLandingPage, isTrue, reason: 'the app boots into the landing page');
      expect(const PhotonApp(startInLandingPage: false).startInLandingPage, isFalse);
      await _teardown(tester, studio);
    });

    testWidgets('a narrow window keeps the headline and the way in', (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final studio = StudioController(autoConnect: false, animateShader: false, startInLandingPage: true);
      await tester.pumpWidget(PhotonApp(controller: studio));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Physically Based Light Transport.'), findsNothing);
      expect(takeMe, findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });
  });

  group('landing page state', () {
    test('a workspace controller is already inside the studio', () {
      final studio = StudioController(autoConnect: false, animateShader: false);
      addTearDown(studio.dispose);
      expect(studio.showLaunchPortal, isFalse);
      expect(studio.inStudioWorkspace, isTrue);
    });

  });

  group('Intent file trigger and Progressive Flux Loader', () {
    final sheet = find.byKey(const Key('file-ingest-sheet'));
    final loader = find.byKey(const Key('progressive-flux-loader'));
    final phaseLabel = find.byKey(const Key('flux-phase-label'));

    String phaseText(WidgetTester tester) => tester.widget<StaggeredLetterText>(phaseLabel).text;

    test('the controller maps progress to the four phases', () {
      final studio = StudioController(autoConnect: false, animateShader: false);
      addTearDown(studio.dispose);
      expect(studio.isUploading, isFalse);
      expect(studio.uploadLoaderVisible, isFalse);
      studio.startFileUpload('CHRONOS_WATCH.usd', sizeMb: 112.4);
      expect(studio.isUploading, isTrue);
      expect(studio.uploadingFileName, 'CHRONOS_WATCH.usd');
      expect(studio.uploadProgress, 0);

      expect(StudioController.uploadPhases, [
        'PARSING USD SCENE GRAPH...',
        'BUILDING BVH OCTREE ACCELERATOR...',
        'COMPILING SPECTRAL BSDF SHADERS...',
        'CONVERGING FIRST LIGHT PASS...',
      ]);
      for (final (progress, phase) in [(0.0, 0), (0.24, 0), (0.25, 1), (0.54, 1), (0.55, 2), (0.84, 2), (0.85, 3), (0.99, 3)]) {
        studio.advanceUploadForTest(progress);
        expect(studio.uploadPhaseIndex, phase, reason: 'at $progress');
        expect(studio.uploadPhaseLabel, StudioController.uploadPhases[phase]);
        expect(studio.isUploading, isTrue);
      }

      studio.startFileUpload('OTHER.exr');
      expect(studio.uploadingFileName, 'CHRONOS_WATCH.usd', reason: 'one ingest at a time');
      expect(studio.toast.value, contains('INGEST IN PROGRESS'));
    });

    test('the studio ticker drives an upload to completion and adds the asset', () {
      final studio = StudioController(autoConnect: false, animateShader: false);
      addTearDown(studio.dispose);
      final before = studio.projects.length;
      studio.startFileUpload('CAUSTIC_POOL.exr', sizeMb: 64.8);
      expect(studio.tickerActive, isTrue);
      var ticks = 0;
      while (studio.isUploading && ticks < 200) {
        studio.debugTick();
        ticks++;
      }
      // 64.8 MB streams for 3.22s: 32 steps of 100ms.
      expect(ticks, inInclusiveRange(30, 34));
      expect(studio.isUploading, isFalse);
      expect(studio.uploadProgress, 1.0);
      expect(studio.projects.length, before + 1);
      expect(studio.activeProject!.name, 'CAUSTIC_POOL');
      expect(studio.activeProject!.subtitle, '.exr · 64.8 MB');
      expect(studio.activeProject!.sceneType, 'EXR Multi-Layer');
      expect(studio.promptResult!.kind, PromptResultKind.ingest);
      expect(studio.promptResult!.headline, startsWith('ASSET INGESTED · CAUSTIC_POOL.exr'));
      expect(studio.toast.value, 'ASSET INGESTED · CAUSTIC_POOL.exr');
    });

    test('staggered letters take 18ms per character', () {
      const text = StaggeredLetterText(text: 'ABCDE', style: TextStyle());
      expect(text.stagger, const Duration(milliseconds: 18));
      expect(text.totalDuration, const Duration(milliseconds: 18 * 4 + 260));
    });

    testWidgets('the folder triggers sit in the sidebar header and the dock', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(find.byKey(const Key('intent-file-trigger')), findsOneWidget);
      expect(find.byKey(const Key('intent-file-trigger-dock')), findsOneWidget);
      final header = tester.getRect(find.byKey(const Key('intent-file-trigger')));
      final newBtn = tester.getRect(find.byKey(const Key('new-project-btn')));
      expect(header.right, lessThanOrEqualTo(newBtn.left), reason: 'next to + NEW');
      expect(header.center.dy, closeTo(newBtn.center.dy, 4));
      final dock = tester.getRect(find.byKey(const Key('intent-file-trigger-dock')));
      expect(dock.right, lessThan(tester.getRect(find.byKey(const Key('scene-prompt'))).left));
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the ingest button is a modern spatial portal, not a retro folder', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final trigger = find.byKey(const Key('intent-file-trigger'));
      // No folder: no tab, no paper sheets, no flap.
      expect(find.descendant(of: trigger, matching: find.text('USD')), findsNothing);
      expect(find.descendant(of: trigger, matching: find.text('EXR')), findsNothing);
      expect(
        tester.widgetList<Transform>(find.descendant(of: trigger, matching: find.byType(Transform))).where((t) => t.transform.entry(3, 2) != 0),
        isEmpty,
      );
      expect(tester.getSize(trigger), IntentFileTrigger.baseSize * (tester.getSize(trigger).width / IntentFileTrigger.baseSize.width));
      expect(IntentFileTrigger.baseSize, const Size(36, 28));

      // A squircle chassis (radius 8) with a 1px hairline in the theme border.
      final box = tester.widgetList<DecoratedBox>(find.descendant(of: trigger, matching: find.byType(DecoratedBox))).first;
      final deco = box.decoration as BoxDecoration;
      expect(deco.borderRadius, BorderRadius.circular(8));
      expect((deco.border! as Border).top.color, PhotonPalette.grading.border);
      expect(deco.boxShadow, isEmpty, reason: 'no glow at rest');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('hovering lights the border Lusion blue, lifts the arrow 3.5px on a spring and spreads the nodes', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final trigger = find.byKey(const Key('intent-file-trigger'));
      dynamic art() => tester.widget<CustomPaint>(find.descendant(of: trigger, matching: find.byType(CustomPaint)).first).painter;
      BoxDecoration chassis() =>
          tester.widgetList<DecoratedBox>(find.descendant(of: trigger, matching: find.byType(DecoratedBox))).first.decoration as BoxDecoration;
      expect([art().spring, art().glow], [0.0, 0.0]);

      final mouse = await _mouse(tester);
      await mouse.moveTo(tester.getCenter(trigger));
      await tester.pump();
      // The spring overshoots: the arrow rises past its final height first.
      var peak = 0.0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        peak = math.max(peak, art().spring as double);
      }
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(art().spring, closeTo(1, 1e-6), reason: 'settles at the full 3.5px lift');
      expect(peak, greaterThan(1.02), reason: 'easeOutBack overshoots before settling');
      expect(art().glow, closeTo(1, 1e-6));
      expect((chassis().border! as Border).top.color, PhotonPalette.grading.violet, reason: 'Lusion Electric Blue');
      expect(chassis().boxShadow, isNotEmpty, reason: 'a soft blue glow');
      expect(chassis().boxShadow!.single.color.a, greaterThan(0.2));

      await mouse.moveTo(const Offset(5, 400));
      await _pumpFor(tester, const Duration(milliseconds: 700));
      expect([art().spring, art().glow], [0.0, 0.0], reason: 'closes again');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the portal artwork: a wireframe tray, a bold arrow and two orbital nodes', (tester) async {
      final key = GlobalKey();
      Future<ByteData> render({required bool dark, bool hover = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildPhotonTheme(dark ? PhotonPalette.grading : PhotonPalette.daylight),
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: key,
                  child: IntentFileTrigger(scale: 4, onTap: () {}),
                ),
              ),
            ),
          ),
        );
        if (hover) {
          final mouse = await _mouse(tester);
          await mouse.moveTo(tester.getCenter(find.byType(IntentFileTrigger)));
          await _pumpFor(tester, const Duration(milliseconds: 700));
        }
        return _capture(tester, key);
      }

      // 36x28 at 4x: 144x112. Art coordinates times four.
      final dark = await render(dark: true);
      bool near(Color c, int rgb, int tol) =>
          (_channel(c.r) - ((rgb >> 16) & 0xFF)).abs() <= tol &&
          (_channel(c.g) - ((rgb >> 8) & 0xFF)).abs() <= tol &&
          (_channel(c.b) - (rgb & 0xFF)).abs() <= tol;
      expect(near(_pixel(dark, 144, 72, 40), 0xF0F1FA, 6), isTrue, reason: 'the arrow shaft is off-white in Dark: ${_pixel(dark, 144, 72, 40)}');
      expect(near(_pixel(dark, 144, 28, 80), 0x1A2FFB, 12), isTrue, reason: 'the USD node is Lusion blue: ${_pixel(dark, 144, 28, 80)}');
      expect(near(_pixel(dark, 144, 116, 80), 0xFF4C41, 12), isTrue, reason: 'the EXR node is Lusion coral: ${_pixel(dark, 144, 116, 80)}');

      final light = await render(dark: false);
      expect(near(_pixel(light, 144, 72, 40), 0x14151B, 6), isTrue, reason: 'the arrow shaft is obsidian in Daylight');

      // On hover the arrow has gone up and the nodes have moved out: the shaft
      // is no longer where it was at the bottom, and the blue node has left.
      final hovered = await render(dark: true, hover: true);
      expect(near(_pixel(hovered, 144, 72, 80 - 12), 0xF0F1FA, 6), isFalse, reason: 'the shaft base lifted clear of y=17');
      expect(near(_pixel(hovered, 144, 28, 80), 0x1A2FFB, 12), isFalse, reason: 'the blue node moved outward');
      expect(near(_pixel(hovered, 144, 18, 80), 0x1A2FFB, 40), isTrue, reason: 'to about 2.5px further out');
    });

    testWidgets('clicking the trigger opens the ingest sheet; Escape and the backdrop close it', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      await _tapKey(tester, const Key('intent-file-trigger'));
      await tester.pump();
      expect(studio.ingestSheetOpen, isTrue);
      expect(sheet, findsOneWidget);
      for (final p in kIngestPresets) {
        expect(find.text(p.fileName), findsOneWidget, reason: p.fileName);
      }
      expect(kIngestPresets.map((p) => p.fileName), ['CHRONOS_WATCH.usd', 'CAUSTIC_POOL.exr', 'DIAMOND_BRDF.ior', 'STUDIO_SOFTBOX.hdr']);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(sheet, findsNothing);

      await _tapKey(tester, const Key('intent-file-trigger-dock'));
      await tester.pump();
      expect(sheet, findsOneWidget);
      await tester.tapAt(const Offset(20, 400));
      await tester.pump();
      expect(sheet, findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('choosing a file runs the loader through all four phases to 100%', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final before = studio.projects.length;
      await _tapKey(tester, const Key('intent-file-trigger'));
      await tester.pump();
      // 112 MB streams slowly enough (4.4s) for each phase to be seen.
      await _tapKey(tester, const Key('ingest-file-CHRONOS_WATCH.usd'));
      await tester.pump();

      expect(studio.isUploading, isTrue);
      expect(sheet, findsNothing, reason: 'the sheet closes once a file is chosen');
      expect(loader, findsOneWidget);
      expect(find.byKey(const Key('flux-file-badge')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('flux-file-badge'))).data, 'CHRONOS_WATCH.usd');
      expect(find.text('1.42 GB/s · PCIe 5.0 DMA'), findsOneWidget);
      expect(find.text('00%'), findsOneWidget);
      expect(phaseText(tester), 'PARSING USD SCENE GRAPH...');
      expect(find.text('PHASE 1/4'), findsOneWidget);

      // Each phase flies in letter by letter: 18ms apart, +10px, 0 opacity, blurred.
      final letters = find.descendant(of: phaseLabel, matching: find.byType(Opacity));
      expect(letters, findsNWidgets('PARSING USD SCENE GRAPH...'.length));
      expect(tester.widgetList<Opacity>(letters).every((o) => o.opacity < 1), isTrue, reason: 'nothing has landed at t=0');
      await tester.pump(const Duration(milliseconds: 200));
      final mid = tester.widgetList<Opacity>(letters).map((o) => o.opacity).toList();
      expect(mid.first, greaterThan(mid.last), reason: 'earlier letters land first');
      expect(mid.first, greaterThan(0.9));
      expect(mid.last, lessThan(0.5));
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(tester.widgetList<Opacity>(letters).every((o) => o.opacity == 1), isTrue);

      for (final (progress, phase, percent) in [(0.30, 1, '30%'), (0.60, 2, '60%'), (0.90, 3, '90%')]) {
        studio.advanceUploadForTest(progress);
        await tester.pump();
        expect(phaseText(tester), StudioController.uploadPhases[phase]);
        expect(find.text('PHASE ${phase + 1}/4'), findsOneWidget);
        expect(find.text(percent), findsOneWidget);
      }

      studio.advanceUploadForTest(1.0);
      await tester.pump();
      expect(studio.isUploading, isFalse);
      expect(find.text('100%'), findsOneWidget, reason: '100% stays up for a moment');
      expect(find.text('FIRST LIGHT READY'), findsOneWidget);
      expect(studio.projects.length, before + 1);
      expect(studio.activeProject!.name, 'CHRONOS_WATCH');
      expect(find.byKey(const Key('roller-prompt-result')), findsOneWidget, reason: 'the ingest result banner');
      expect(find.textContaining('ASSET INGESTED'), findsWidgets);

      await tester.pump(const Duration(milliseconds: 1600));
      expect(loader, findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the loader\'s fill follows progress and ends in a lit tip', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.startFileUpload('CHRONOS_WATCH.usd');
      studio.advanceUploadForTest(0.5);
      await _pumpFor(tester, const Duration(milliseconds: 300));
      final bar = tester.getSize(find.byKey(const Key('flux-bar')));
      final tip = find.byWidgetPredicate(
        (w) => w is DecoratedBox && w.decoration is BoxDecoration && ((w.decoration as BoxDecoration).boxShadow?.any((s) => s.blurRadius == 16 && s.spreadRadius == 2) ?? false),
      );
      expect(tip, findsOneWidget, reason: 'the photon flare: 16px blur, 2px spread');
      final barLeft = tester.getTopLeft(find.byKey(const Key('flux-bar'))).dx;
      // The ticker keeps streaming, and the fill glides a step behind it.
      expect(tester.getCenter(tip).dx - barLeft, closeTo(bar.width * studio.uploadProgress, bar.width * 0.05));
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });
  });

  group('Shader theme switch', () {
    /// The icon alone, 28x28, in [dark] or light; the colour at [at].
    Future<Color> iconColor(WidgetTester tester, {required bool dark, required Offset at}) async {
      tester.view.physicalSize = const Size(200, 100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPhotonTheme(dark ? PhotonPalette.grading : PhotonPalette.daylight),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: ShaderThemeSwitch(dark: dark, onChanged: (_) {}),
              ),
            ),
          ),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 400));
      return _pixel(await _capture(tester, key), 28, at.dx.round(), at.dy.round());
    }


    bool near(Color a, int rgb, [int tolerance = 2]) =>
        (_channel(a.r) - ((rgb >> 16) & 0xFF)).abs() <= tolerance &&
        (_channel(a.g) - ((rgb >> 8) & 0xFF)).abs() <= tolerance &&
        (_channel(a.b) - (rgb & 0xFF)).abs() <= tolerance;

    testWidgets('it is one 28px circular icon: no slider, no track, no labels', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(tester.getSize(find.byKey(const Key('shader-theme-switch'))), const Size(28, 28));
      expect(find.text('DAYLIGHT'), findsNothing);
      expect(find.text('DARK GRADING'), findsNothing);
      expect(find.byKey(const ValueKey('shader-theme-thumb')), findsNothing, reason: 'nothing slides');
      expect(ShaderThemeSwitch.width, 28);
      expect(ShaderThemeSwitch.height, 28);
      await _teardown(tester, studio);

      // A circle: the corners are clear, the rim is the 1px edge, the face a disc.
      final corner = await iconColor(tester, dark: true, at: const Offset(1, 1));
      expect(corner.a, 0, reason: 'a circle, not a capsule or a square');
      expect(near(await iconColor(tester, dark: true, at: const Offset(0, 14)), 0x262936, 12), isTrue, reason: '1px edge in Dark');
      expect(near(await iconColor(tester, dark: false, at: const Offset(0, 14)), 0xD8DAE8, 12), isTrue, reason: '1px edge in Daylight');
      expect(near(await iconColor(tester, dark: true, at: const Offset(4, 14)), 0x14151B, 4), isTrue, reason: 'obsidian disc');
      expect(near(await iconColor(tester, dark: false, at: const Offset(4, 14)), 0xFFFFFF, 4), isTrue, reason: 'white disc');
    });

    testWidgets('Dark Grading shows a crescent Moon, hollow in the middle', (tester) async {
      expect(near(await iconColor(tester, dark: true, at: const Offset(10, 14)), 0xF0F1FA, 10), isTrue, reason: 'the lunar limb');
      expect(near(await iconColor(tester, dark: true, at: const Offset(14, 14)), 0x14151B, 6), isTrue, reason: 'the bite out of it');
    });

    testWidgets('Daylight Lab shows a Sun: a disc and eight beams, in Lusion blue', (tester) async {
      expect(near(await iconColor(tester, dark: false, at: const Offset(14, 14)), 0x1A2FFB, 10), isTrue, reason: 'the solar disc');
      // The four straight beams (each is a 1px line on a pixel boundary, so look at both pixels).
      for (final beam in [
        [const Offset(13, 8), const Offset(14, 8)],
        [const Offset(13, 20), const Offset(14, 20)],
        [const Offset(8, 13), const Offset(8, 14)],
        [const Offset(20, 13), const Offset(20, 14)],
      ]) {
        var darkest = 255;
        for (final p in beam) {
          darkest = math.min(darkest, _channel((await iconColor(tester, dark: false, at: p)).r));
        }
        expect(darkest, lessThan(200), reason: 'a beam at ${beam.first}');
      }
      // The four diagonal beams: eight in all.
      for (final c in const [Offset(18, 10), Offset(18, 18), Offset(10, 10), Offset(10, 18)]) {
        var darkest = 255;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            darkest = math.min(darkest, _channel((await iconColor(tester, dark: false, at: c + Offset(dx.toDouble(), dy.toDouble()))).r));
          }
        }
        expect(darkest, lessThan(215), reason: 'a diagonal beam near $c');
      }
    });

    testWidgets('the Moon and Sun turn and cross-fade on a tap', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final icon = find.byKey(const ValueKey('shader-theme-icon'));
      double mix() => ((tester.widget<CustomPaint>(icon).painter! as dynamic).toggle.value as num).toDouble();
      expect(mix(), 0, reason: 'Dark: the Moon');
      studio.setDarkGrading(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      expect(mix(), inExclusiveRange(0.1, 0.9), reason: 'part way: both glyphs partly shown, mid-turn');
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(mix(), 1, reason: 'Daylight: the Sun');
      studio.setDarkGrading(true);
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(mix(), 0);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the icon has no idle ticker: at rest it schedules no frames', (tester) async {
      await iconColor(tester, dark: true, at: Offset.zero);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a tap always asks for the other mode, and says which in its tooltip', (tester) async {
      final asked = <bool>[];
      Future<void> pump({required bool dark}) => tester.pumpWidget(
        MaterialApp(
          theme: buildPhotonTheme(PhotonPalette.grading),
          home: Scaffold(body: Center(child: ShaderThemeSwitch(dark: dark, onChanged: asked.add))),
        ),
      );
      await pump(dark: true);
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'Switch to Daylight Lab');
      await tester.tap(find.byType(ShaderThemeSwitch));
      await pump(dark: false);
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'Switch to Dark Grading');
      await tester.tap(find.byType(ShaderThemeSwitch));
      expect(asked, [false, true], reason: 'dark -> asks for light; light -> asks for dark');
    });

    testWidgets('a tap on the icon toggles; the top bar, the dock and the window frame follow', (tester) async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('photon/window');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final toggle = find.byKey(const Key('shader-theme-switch'));
      expect(tester.getSize(toggle), const Size(28, 28));
      Color? barColor() => (tester.widget<AnimatedContainer>(find.byKey(const ValueKey('top-bar'))).decoration as BoxDecoration).color;
      Color? dockColor() => (tester.widget<Container>(find.byKey(const ValueKey('dock-surface'))).decoration as BoxDecoration).color;
      expect(barColor(), PhotonPalette.grading.substrate);
      expect(dockColor(), PhotonPalette.grading.dock);

      await _tapKey(tester, const Key('shader-theme-switch'));
      await tester.pump();
      await _pumpFor(tester, const Duration(milliseconds: 700));
      expect(studio.darkGrading, isFalse);
      expect(barColor(), PhotonPalette.daylight.surface);
      expect(dockColor(), const Color(0xFFFFFFFF));
      expect(calls.last.method, 'setFrameColors');
      expect(calls.last.arguments, NativeFrame.daylight.toArguments(), reason: 'the native frame goes light too');

      await _tapKey(tester, const Key('shader-theme-switch'));
      await tester.pump();
      await _pumpFor(tester, const Duration(milliseconds: 700));
      expect(studio.darkGrading, isTrue);
      expect(barColor(), PhotonPalette.grading.substrate);
      expect(dockColor(), PhotonPalette.grading.dock);
      expect(calls.last.arguments, NativeFrame.grading.toArguments());
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('every tap switches, however many times: it never sets a mode by itself', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      for (var i = 0; i < 4; i++) {
        final before = studio.darkGrading;
        await _tapKey(tester, const Key('shader-theme-switch'));
        await _pumpFor(tester, const Duration(milliseconds: 400));
        expect(studio.darkGrading, !before, reason: 'tap ${i + 1}');
      }
      expect(studio.darkGrading, isTrue);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });
  });

  group('Roller prompt result', () {
    final banner = find.byKey(const Key('roller-prompt-result'));

    PromptIntent parse(String s) => PromptIntent.parse(s);

    test('the prompt parser reads apertures, IOR, materials, scenes and solver words', () {
      expect(parse('85mm lens, f/2.8, shallow').params, {'aperture': 2.8});
      expect(parse('aperture 4').params, {'aperture': 4});
      expect(parse('aperture f/1.4').params, {'aperture': 1.4});
      expect(parse('set ior 2.4 please').params, {'ior': 2.4});
      expect(parse('a diamond ring').params, {'ior': 2.417});
      expect(parse('diamond with ior 2.1').params, {'ior': 2.1}, reason: 'an explicit number beats the material');
      expect(parse('window glass').params, {'ior': 1.52});
      expect(parse('512 spp').params, {'samples_per_pixel': 512});
      expect(parse('samples 128').params, {'samples_per_pixel': 128});
      expect(parse('16 bounces').params, {'max_bounces': 16});
      expect(parse('focus 1.8m').params, {'focal_distance': 1.8});
      expect(parse('Brushed gold BSDF, roughness 0.35, soft studio key light').roughness, 0.35);
      expect(parse('gold').projectId, 'gold_atelier_bsdf');
      expect(parse('liquid chrome').projectId, 'gold_atelier_bsdf');
      expect(parse('a black hole').projectId, 'kerr_photon_ring');
      expect(parse('prism').projectId, 'volumetric_prism');
      expect(parse('soap film').projectId, 'volumetric_prism');
      expect(parse('iridescent coating').projectId, 'volumetric_prism');
      expect(parse('thin film').projectId, 'volumetric_prism');
      // No keyword points at a project that no longer ships.
      final shipped = kDefaultProjects.map((p) => p.id).toSet();
      for (final prompt in ['black hole', 'kerr', 'prism', 'acrylic', 'iridescent', 'soap', 'thin film', 'chrome', 'gold', 'caustic']) {
        expect(shipped, contains(parse(prompt).projectId), reason: prompt);
      }
      expect(parse('bidirectional path tracing').integrator, IntegratorMode.bidirectional);
      expect(parse('photon map').integrator, IntegratorMode.sppm);
      expect(parse('make it prettier').isEmpty, isTrue);
      expect(parse('f/2.8 diamond gold').isEmpty, isFalse);
    });

    test('sendPrompt applies what it reads, as one undo step, and reports it', () {
      final studio = StudioController(autoConnect: false, animateShader: false);
      addTearDown(studio.dispose);
      expect(studio.promptResult, isNull);

      expect(studio.sendPrompt('diamond roughness 0.12'), isFalse, reason: 'offline');
      expect(studio.param('ior'), 2.417);
      final result = studio.promptResult!;
      expect(result.headline, 'PROMPT APPLIED · IOR 2.417 · ROUGHNESS 0.12 · 256 SPP');
      expect(result.kind, PromptResultKind.prompt);
      expect(result.dispatched, isFalse);
      expect(result.cells.map((c) => c.tag), ['KERNEL', 'SOLVER', 'DELTA', 'SPP', 'STATUS']);
      expect(result.cells.firstWhere((c) => c.tag == 'STATUS').value, 'LOCAL');
      expect(result.cells.firstWhere((c) => c.tag == 'SPP').value, '256');
      expect(studio.toast.value, contains('OFFLINE'));

      studio.sendPrompt('gold at f/5.6, ior 1.7, 512 spp, 9 bounces');
      expect(studio.activeProjectId, 'gold_atelier_bsdf');
      expect(studio.param('aperture'), 5.6);
      expect(studio.param('ior'), 1.7);
      expect(studio.targetSamples, 512);
      expect(studio.maxBounces, 9);
      expect(studio.promptResult!.id, greaterThan(result.id));
      expect(studio.promptResult!.headline, startsWith('PROMPT APPLIED · SCENE GOLD_ATELIER_BSDF'));
      expect(studio.promptResult!.headline, contains('APERTURE f/5.6'));
      expect(studio.promptResult!.headline, contains('MAX BOUNCES 9'));
      expect(studio.promptResult!.headline, endsWith('512 SPP'));

      studio.undo();
      expect(studio.activeProjectId, 'caustic_study_04', reason: 'the whole prompt is one undo step');
      expect(studio.param('ior'), 2.417);
    });

    test('a prompt with nothing to apply is queued, and can be dismissed', () {
      final studio = StudioController(autoConnect: false, animateShader: false);
      addTearDown(studio.dispose);
      studio.sendPrompt('something moody');
      expect(studio.promptResult!.headline, 'PROMPT QUEUED · 256 SPP');
      expect(studio.promptResult!.changes, isEmpty);
      expect(studio.canUndo, isFalse, reason: 'nothing changed');
      studio.dismissPromptResult();
      expect(studio.promptResult, isNull);
    });

    testWidgets('a dispatched prompt rolls, breaks, locks and reduces to a pill', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(banner, findsNothing);
      await tester.enterText(find.byKey(const Key('scene-prompt')), 'diamond f/2.8 roughness 0.12');
      await _tapKey(tester, const ValueKey('pill-hit-RENDER PROMPT'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(banner, findsOneWidget);
      expect(studio.param('ior'), 2.417);
      expect(studio.param('aperture'), 2.8);
      for (final tag in ['KERNEL', 'SOLVER', 'DELTA', 'SPP', 'STATUS']) {
        expect(find.text('[$tag]'), findsOneWidget, reason: tag);
      }
      final status = find.byKey(const ValueKey('roller-cell-STATUS'));
      // Stage 1: still spinning through telemetry tokens, tilted in 3D.
      expect(find.descendant(of: status, matching: find.text('LOCAL')), findsNothing);
      final drum = tester.widgetList<Transform>(find.descendant(of: status, matching: find.byType(Transform))).where((t) => t.transform.entry(3, 2) != 0).single;
      expect(drum.transform.entry(3, 2), closeTo(0.002, 1e-9), reason: 'perspective');

      // The drums lock one after another.
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.descendant(of: find.byKey(const ValueKey('roller-cell-KERNEL')), matching: find.text('CAUCHY')), findsOneWidget, reason: 'the first drum has locked');
      expect(find.descendant(of: status, matching: find.text('LOCAL')), findsNothing, reason: 'the last is still spinning');
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.descendant(of: status, matching: find.text('LOCAL')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('roller-cell-SPP')), matching: find.text('256')), findsOneWidget);
      final headline = tester.widget<Text>(find.byKey(const Key('roller-headline'))).data!;
      expect(headline, 'PROMPT APPLIED · IOR 2.417 · ROUGHNESS 0.12 · APERTURE f/2.8 · 256 SPP');

      // Stage 3: after the 1.8s hold it reduces to a compact pill.
      expect(find.byKey(const Key('roller-compact-label')), findsNothing);
      await _pumpFor(tester, const Duration(milliseconds: 1500));
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text('PROMPT ACTIVE · CLICK TO EXPAND'), findsOneWidget);
      expect(find.byKey(const Key('roller-headline')), findsNothing);
      expect(find.byKey(const Key('dismiss-roller-result')), findsOneWidget);

      // Click to expand, click to reduce again.
      await tester.tap(find.byKey(const Key('roller-compact-label')));
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const Key('roller-headline')), findsOneWidget);
      await tester.tap(find.byKey(const Key('roller-headline')));
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const Key('roller-compact-label')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dismiss-roller-result')));
      await tester.pump();
      expect(banner, findsNothing);
      expect(studio.promptResult, isNull);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the BREAK pulse splits the capsule outline in rose and cyan for 180ms', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.sendPrompt('f/4');
      await tester.pump();
      CustomPaint pulse() => tester.widgetList<CustomPaint>(find.descendant(of: banner, matching: find.byType(CustomPaint))).last;

      // Paint into a recorder at three moments and look for the two offset strokes.
      Future<Set<int>> strokeColors() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        pulse().painter!.paint(canvas, const Size(300, 60));
        final image = await tester.runAsync(() async {
          final picture = recorder.endRecording();
          final img = await picture.toImage(300, 60);
          return (await img.toByteData())!;
        });
        final colors = <int>{};
        for (var x = 0; x < 300; x++) {
          final c = _pixel(image!, 300, x, 30);
          if (c.a > 0.3) colors.add(c.toARGB32() & 0xFFFFFF);
        }
        return colors;
      }

      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(await strokeColors(), isEmpty, reason: 'still rolling');
      await tester.pump(const Duration(milliseconds: 590));
      final during = await strokeColors();
      expect(during.any((c) => (c >> 16) > 0xB0 && (c & 0xFF) < 0xB0), isTrue, reason: 'rose stroke');
      expect(during.any((c) => (c & 0xFF) > 0xB0 && (c >> 16) < 0x60), isTrue, reason: 'cyan stroke');
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(await strokeColors(), isEmpty, reason: 'the pulse has passed');
      await _teardown(tester, studio);
    });

    testWidgets('a new result rolls again, expanded', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.sendPrompt('f/4');
      await _pumpFor(tester, const Duration(seconds: 4));
      expect(find.byKey(const Key('roller-compact-label')), findsOneWidget);
      studio.sendPrompt('f/8');
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const Key('roller-headline')), findsOneWidget);
      expect(find.byKey(const Key('roller-compact-label')), findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });
  });

  group('Animated blue profile card', () {
    final card = find.byKey(const Key('animated-profile-card'));
    final modal = find.byKey(const Key('account-modal'));

    Future<StudioController> openCard(WidgetTester tester, {Size size = const Size(1280, 800)}) async {
      final studio = await _pumpStudio(tester, size);
      await _tapKey(tester, const Key('profile-card-trigger'));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      return studio;
    }

    testWidgets('the header chip shows MF, MOHD FARAZ and PRO, and opens the card', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      final chip = find.byKey(const Key('profile-card-trigger'));
      expect(chip, findsOneWidget);
      for (final s in ['MF', 'MOHD FARAZ', 'PRO']) {
        expect(find.descendant(of: chip, matching: find.text(s)), findsOneWidget, reason: s);
      }
      expect(card, findsNothing);
      await _tap(tester, chip);
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(modal, findsOneWidget);
      expect(card, findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the card shows the identity hero and the IDENTITY drawer', (tester) async {
      final studio = await openCard(tester);
      expect(find.text('Mohd Faraz'), findsOneWidget);
      expect(find.text('@mfarazcodes'), findsOneWidget);
      expect(find.text('VERIFIED LEAD ARCHITECT'), findsOneWidget);
      expect(find.text('WS-IND-0492'), findsOneWidget);
      expect(find.text('B.Tech CSE · Lead Rendering & VFX Architect'), findsOneWidget);
      expect(find.text('Photon Spatial Labs'), findsOneWidget);
      for (final tab in ProfileTab.values) {
        expect(find.byKey(Key(tab.keyName)), findsOneWidget, reason: tab.label);
      }
      expect(find.text('github.com/mfarazcodes'), findsOneWidget);
      expect(find.text('faraz@photon.studio'), findsOneWidget);
      expect(find.text('Motorola Motobook 60 · Windows 11 · Vulkan RT'), findsOneWidget);
      expect(find.byKey(const Key('account-edit-profile-btn')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('PLAN & QUOTA: tier switcher and animated quota bars', (tester) async {
      final studio = await openCard(tester);
      await _tapKey(tester, const Key('profile-tab-plan'));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.text('github.com/mfarazcodes'), findsNothing);
      expect(find.text('STUDIO PRO · \$49/mo'), findsOneWidget);
      expect(find.text('842.5 / 1,000 GPU-hrs'), findsOneWidget);
      expect(find.text('128.4 / 500 GB USD Vault'), findsOneWidget);
      for (final tier in PlanTier.values) {
        expect(find.byKey(Key('profile-tier-${tier.name}')), findsOneWidget);
      }

      await _tapKey(tester, const Key('profile-tier-enterprise'));
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(studio.account.tier, PlanTier.enterprise);
      expect(find.text('ENTERPRISE · \$299/mo'), findsOneWidget);
      expect(find.text('842.5 / 10,000 GPU-hrs'), findsOneWidget);

      await _tapKey(tester, const Key('profile-tier-indie'));
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(studio.account.tier, PlanTier.indie);
      expect(find.text('842.5 / 64 GPU-hrs'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('AUTH & KEYS: 2FA toggle and key rotation', (tester) async {
      final studio = await openCard(tester);
      await _tapKey(tester, const Key('profile-tab-auth'));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.text('WebAuthn Hardware Passkey + Ed25519 JWT'), findsOneWidget);
      expect(find.text('ARMED'), findsOneWidget);

      await _tapKey(tester, const Key('profile-2fa-toggle'));
      await tester.pump();
      expect(studio.account.twoFactorEnabled, isFalse);
      expect(find.text('OFF'), findsOneWidget);
      await _tapKey(tester, const Key('profile-2fa-toggle'));
      await tester.pump();
      expect(studio.account.twoFactorEnabled, isTrue);

      final before = studio.account.apiKeys.first;
      expect(tester.widget<Text>(find.byKey(const Key('profile-key-masked'))).data, before.masked);
      await _tapKey(tester, const Key('profile-rotate-key-btn'));
      await tester.pump();
      final after = studio.account.apiKeys.first;
      expect(after.secret, isNot(before.secret));
      expect(tester.widget<Text>(find.byKey(const Key('profile-key-masked'))).data, after.masked);
      expect(studio.toast.value, 'API KEY ROTATED');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('COPY puts the key on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final studio = await openCard(tester);
      await _tapKey(tester, const Key('profile-tab-auth'));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      await _tapKey(tester, const Key('profile-copy-key-btn'));
      await tester.pump();
      expect(copied, studio.account.apiKeys.first.secret);
      expect(studio.toast.value, 'KEY COPIED TO CLIPBOARD');
      await _teardown(tester, studio);
    });

    testWidgets('clicking the selected tab folds the curtain; another tab reopens it', (tester) async {
      final studio = await openCard(tester);
      expect(find.text('github.com/mfarazcodes'), findsOneWidget);
      await _tapKey(tester, const Key('profile-tab-identity'));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.text('github.com/mfarazcodes'), findsNothing, reason: 'folded away');
      await _tapKey(tester, const Key('profile-tab-plan'));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.text('STUDIO PRO · \$49/mo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('hovering the card opens a folded curtain at once, and the card stays flat', (tester) async {
      final studio = await openCard(tester);
      await _tapKey(tester, const Key('profile-tab-identity'));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.text('github.com/mfarazcodes'), findsNothing);

      final rect = tester.getRect(card);
      final name = find.text('Mohd Faraz');
      final rest = tester.getTopLeft(name);
      final mouse = await _mouse(tester);
      await mouse.moveTo(rect.centerLeft + const Offset(8, 0));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.text('github.com/mfarazcodes'), findsOneWidget, reason: 'hover opens the curtain');
      final topLeft = tester.getTopLeft(find.text('Mohd Faraz'));
      await mouse.moveTo(rect.centerRight - const Offset(8, 0));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      final bottomRight = tester.getTopLeft(find.text('Mohd Faraz'));
      expect(topLeft, bottomRight, reason: 'the card does not tilt toward the cursor');
      expect(rest.dx, topLeft.dx);

      await mouse.moveTo(const Offset(2, 790));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.text('github.com/mfarazcodes'), findsNothing, reason: 'folds again when the pointer leaves');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('it lays out in one column on a narrow window', (tester) async {
      final studio = await openCard(tester, size: const Size(390, 844));
      expect(card, findsOneWidget);
      for (final tab in ProfileTab.values) {
        await _tapKey(tester, Key(tab.keyName));
        await _pumpFor(tester, const Duration(milliseconds: 500));
      }
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });
  });

  group('Card deck carousel', () {
    final deck = find.byKey(const Key('card-deck-carousel'));
    final top = find.byKey(const Key('deck-top-card'));

    Future<StudioController> openDeck(WidgetTester tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      await _tapKey(tester, const Key('sidebar-view-deck'));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      return studio;
    }

    String counter(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('deck-counter'))).data!;

    /// A project's name inside the deck (the sidebar list shows it too).
    Finder inDeck(String name) => find.descendant(of: deck, matching: find.text(name));

    testWidgets('the studio opens on the viewport with the list; STACK DECK opens the deck on the centre stage', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(studio.deckView, isFalse, reason: 'the studio opens on the live viewport');
      expect(deck, findsNothing);
      expect(find.text('LIST VIEW'), findsOneWidget);
      expect(find.text('STACK DECK'), findsOneWidget);
      expect(find.byKey(const Key('project-gold_atelier_bsdf')), findsOneWidget);

      await _tapKey(tester, const Key('sidebar-view-deck'));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(studio.deckView, isTrue);
      expect(deck, findsOneWidget);

      // The list stays where it was, filter and search included.
      for (final k in ['project-gold_atelier_bsdf', 'project-filter-all', 'project-filter-dynamic', 'project-search']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      // The deck is in the middle of the viewport stage, not in the sidebar.
      final sidebar = tester.getRect(find.byType(ProjectsSidebar));
      final stage = tester.getRect(find.byKey(const Key('deck-stage-scrim')));
      final deckRect = tester.getRect(deck);
      expect(deckRect.left, greaterThan(sidebar.right));
      expect(stage.inflate(1).contains(deckRect.center), isTrue);
      expect((deckRect.center.dx - stage.center.dx).abs(), lessThan(40), reason: 'centred horizontally');
      expect(stage.width, greaterThan(deckRect.width));

      await _tapKey(tester, const Key('sidebar-view-list'));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(deck, findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the DECK segment and BACK TO VIEWPORT toggle it too', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      await _tapKey(tester, const Key('workspace-deck'));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(studio.deckView, isTrue);
      expect(deck, findsOneWidget);
      expect(find.text('BACK TO VIEWPORT'), findsOneWidget);
      await _tapKey(tester, const Key('deck-close-btn'));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(studio.deckView, isFalse);
      expect(deck, findsNothing);
      await _tapKey(tester, const Key('workspace-deck'));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      await _tapKey(tester, const Key('workspace-deck'));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(deck, findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('on the centre stage the prints are large, and each sits on its own layer', (tester) async {
      final studio = await openDeck(tester);
      final size = tester.getSize(top);
      // Up to 520px wide, and no bigger than the stage's height allows.
      expect(size.width, inInclusiveRange(220, 520), reason: 'cards scale to the stage');
      expect(size.height, closeTo(size.width * 0.64, 0.5));
      expect(size.width, greaterThan(190), reason: 'bigger than the old sidebar deck');

      // The print is wrapped in its own RepaintBoundary, exactly its size.
      final boundary = find.ancestor(of: inDeck('CAUSTIC_STUDY_04'), matching: find.byType(RepaintBoundary)).first;
      expect(tester.getSize(boundary), size);
      for (final name in ['GOLD_ATELIER_BSDF', 'VOLUMETRIC_PRISM', 'ACRYLIC_LENS_ARRAY']) {
        final b = find.ancestor(of: inDeck(name), matching: find.byType(RepaintBoundary)).first;
        expect(tester.getSize(b), size, reason: name);
      }
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the deck fits a short stage and a narrow window', (tester) async {
      final short = await _pumpStudio(tester, const Size(1000, 600));
      short.setDeckView(true);
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(deck, findsOneWidget);
      final stage = tester.getRect(find.byKey(const Key('deck-stage-scrim')));
      expect(stage.inflate(2).contains(tester.getRect(deck).topLeft), isTrue);
      expect(tester.takeException(), isNull);
      await _teardown(tester, short);

      final narrow = await _pumpStudio(tester, const Size(390, 844));
      narrow.setDeckView(true);
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(deck, findsOneWidget);
      expect(tester.getSize(top).width, lessThanOrEqualTo(390));
      expect(tester.takeException(), isNull);
      await _teardown(tester, narrow);
    });

    testWidgets('dragging a print never orbits the camera behind the deck', (tester) async {
      final studio = await openDeck(tester);
      final before = studio.orbit.value;
      // Drag on the scrim, clear of the prints.
      final stage = tester.getRect(find.byKey(const Key('deck-stage-scrim')));
      final gesture = await tester.startGesture(stage.topLeft + const Offset(30, 60));
      await gesture.moveBy(const Offset(60, 40));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(studio.orbit.value, before);
      await _teardown(tester, studio);
    });

    testWidgets('the pile shows the active project on top and three more beneath', (tester) async {
      final studio = await openDeck(tester);
      expect(counter(tester), '01 / 05');
      for (final n in ['CAUSTIC_STUDY_04', 'GOLD_ATELIER_BSDF', 'VOLUMETRIC_PRISM', 'ACRYLIC_LENS_ARRAY']) {
        expect(inDeck(n), findsOneWidget, reason: n);
      }
      expect(inDeck('KERR_PHOTON_RING'), findsNothing, reason: 'the fifth print is not in the visible four');

      // A 3D fan, one perspective transform per print: Z tilts -4.2, +3.2,
      // -2.2 degrees; offsets 14, 28, 40 px; scales .93, .86, .79; and a pitch
      // that leans the pile back, growing with depth.
      Matrix4 poseOf(String name) {
        final slot = find.byKey(ValueKey('deck-slot-${name.toLowerCase()}'));
        return tester.widgetList<Transform>(find.descendant(of: slot, matching: find.byType(Transform))).first.transform;
      }

      final expected = {
        'gold_atelier_bsdf': (-4.2, 14.0, 0.93, 0.05),
        'volumetric_prism': (3.2, 28.0, 0.86, 0.08),
        'acrylic_lens_array': (-2.2, 40.0, 0.79, 0.11),
      };
      for (final entry in expected.entries) {
        final m = poseOf(entry.key);
        final (tilt, dy, scale, pitch) = entry.value;
        expect(m.entry(3, 2), closeTo(0.0015, 1e-5), reason: '${entry.key}: real perspective (0.0015, a hair less once pitched)');
        expect(m.getTranslation().y, closeTo(dy, 0.01), reason: entry.key);
        // The upper-left 2x2 holds rotateX(pitch) * rotateZ(tilt) * scale.
        final e10 = m.entry(1, 0) / math.cos(pitch);
        expect(math.atan2(e10, m.entry(0, 0)) * 180 / math.pi, closeTo(tilt, 0.01), reason: entry.key);
        expect(math.sqrt(m.entry(0, 0) * m.entry(0, 0) + e10 * e10), closeTo(scale, 0.001), reason: entry.key);
        expect(m.entry(2, 0), closeTo(math.sin(pitch) * math.sin(tilt * math.pi / 180) * scale, 1e-6), reason: '${entry.key}: pitched about X');
      }
      expect(poseOf('caustic_study_04').getTranslation().y, 0);
      expect(poseOf('caustic_study_04').entry(0, 0), closeTo(1, 1e-9));
      expect(studio.activeProjectId, 'caustic_study_04');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('NEXT and PREV cycle the active project', (tester) async {
      final studio = await openDeck(tester);
      await _tapKey(tester, const Key('deck-next-btn'));
      await _pumpFor(tester, const Duration(milliseconds: 800));
      expect(studio.activeProjectId, 'gold_atelier_bsdf');
      expect(counter(tester), '02 / 05');
      await _tapKey(tester, const Key('deck-next-btn'));
      await _pumpFor(tester, const Duration(milliseconds: 800));
      expect(studio.activeProjectId, 'volumetric_prism');

      await _tapKey(tester, const Key('deck-prev-btn'));
      await _pumpFor(tester, const Duration(milliseconds: 800));
      expect(studio.activeProjectId, 'gold_atelier_bsdf');
      await _tapKey(tester, const Key('deck-prev-btn'));
      await _pumpFor(tester, const Duration(milliseconds: 800));
      await _tapKey(tester, const Key('deck-prev-btn'));
      await _pumpFor(tester, const Duration(milliseconds: 800));
      expect(studio.activeProjectId, 'kerr_photon_ring', reason: 'PREV wraps round to the last');
      expect(counter(tester), '05 / 05');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('flicking the top card throws it off and activates the next project', (tester) async {
      final studio = await openDeck(tester);
      await tester.fling(top, const Offset(-320, -40), 2200);
      await tester.pump();
      // The next project is active at once; the thrown card is still in the air.
      expect(studio.activeProjectId, 'gold_atelier_bsdf');
      await tester.pump(const Duration(milliseconds: 120));
      final airborne = tester.getCenter(inDeck('CAUSTIC_STUDY_04'));
      expect(airborne.dx, lessThan(tester.getCenter(inDeck('GOLD_ATELIER_BSDF')).dx), reason: 'flying off to the left');
      await _pumpFor(tester, const Duration(milliseconds: 900));
      expect(counter(tester), '02 / 05');
      expect(inDeck('CAUSTIC_STUDY_04'), findsNothing, reason: 'back at the bottom of the pile, out of the visible four');
      expect(inDeck('KERR_PHOTON_RING'), findsOneWidget, reason: 'the next print has moved up into the visible four');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('a slow short drag tilts the card with its motion and springs back', (tester) async {
      final studio = await openDeck(tester);
      final gesture = await tester.startGesture(tester.getCenter(top));
      // The first stretch is the pan slop: the drag counts from where it wins.
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(30, 0));
      await _pumpFor(tester, const Duration(milliseconds: 400));
      await gesture.moveBy(const Offset(10, 0));
      await _pumpFor(tester, const Duration(milliseconds: 400));

      // One perspective transform carries the whole drag: translate, then
      // bank (Z), yaw (Y) and pitch (X) with the motion.
      final m = tester.widgetList<Transform>(find.ancestor(of: top, matching: find.byType(Transform))).first.transform;
      final dx = m.getTranslation().x;
      expect(dx, greaterThan(20));
      expect(m.entry(3, 2), closeTo(0.0015, 1e-5), reason: 'in perspective');
      expect(math.asin(m.entry(1, 0)), closeTo(dx * 0.0018, 1e-4), reason: 'bank follows horizontal motion: rotateZ(dx * 0.0018)');
      expect(math.asin(m.entry(0, 2)), closeTo(dx * 0.0014, 1e-4), reason: 'yaw follows it too: rotateY(dx * 0.0014)');
      expect(m.getTranslation().y.abs(), lessThan(1e-9));

      await gesture.up();
      await _pumpFor(tester, const Duration(milliseconds: 800));
      expect(studio.activeProjectId, 'caustic_study_04', reason: 'under the throw threshold');
      final settled = tester.widgetList<Transform>(find.ancestor(of: top, matching: find.byType(Transform))).first.transform;
      expect(settled.getTranslation().x.abs(), lessThan(0.5), reason: 'sprung back');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('a long slow drag past 90px is thrown on release', (tester) async {
      final studio = await openDeck(tester);
      final gesture = await tester.startGesture(tester.getCenter(top));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 120));
      }
      await _pumpFor(tester, const Duration(milliseconds: 300));
      await gesture.up();
      await _pumpFor(tester, const Duration(milliseconds: 900));
      expect(studio.activeProjectId, 'gold_atelier_bsdf', reason: 'omnidirectional: dragged downward');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('Left and Right arrows step the deck while it has focus', (tester) async {
      final studio = await openDeck(tester);
      tester.widget<Focus>(find.descendant(of: deck, matching: find.byType(Focus)).first).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _pumpFor(tester, const Duration(milliseconds: 800));
      expect(studio.activeProjectId, 'gold_atelier_bsdf');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _pumpFor(tester, const Duration(milliseconds: 800));
      expect(studio.activeProjectId, 'caustic_study_04');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('AUTOPLAY steps on a timer until switched off', (tester) async {
      final studio = await openDeck(tester);
      await _tapKey(tester, const Key('deck-autoplay-btn'));
      await tester.pump();
      expect(find.text('AUTOPLAY · ON'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 3300));
      await _pumpFor(tester, const Duration(milliseconds: 800));
      expect(studio.activeProjectId, 'gold_atelier_bsdf');

      await _tapKey(tester, const Key('deck-autoplay-btn'));
      await tester.pump();
      expect(find.text('AUTOPLAY'), findsOneWidget);
      await _pumpFor(tester, const Duration(seconds: 4));
      expect(studio.activeProjectId, 'gold_atelier_bsdf', reason: 'stopped');
      await _teardown(tester, studio);
    });

    testWidgets('a tap on the top card opens that project full screen', (tester) async {
      final studio = await openDeck(tester);
      expect(studio.deckView, isTrue);
      expect(studio.maximizedPanel, isNull);
      studio.toast.value = null;
      await tester.tap(top);
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(studio.activeProjectId, 'caustic_study_04');
      expect(studio.toast.value, 'PROJECT LOADED · CAUSTIC_STUDY_04');
      expect(studio.deckView, isFalse, reason: 'the deck closes');
      expect(studio.maximizedPanel, 'viewport', reason: 'and the viewport takes the whole window');
      expect(top, findsNothing);
      expect(find.text('SCENE_VIEWPORT.rt'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the top print says how to use it, and only the top one', (tester) async {
      final studio = await openDeck(tester);
      final hint = find.byKey(const Key('deck-open-hint'));
      expect(hint, findsOneWidget);
      expect(find.text('TAP TO OPEN FULLSCREEN · SWIPE TO CYCLE'), findsOneWidget);
      expect(tester.getRect(hint).overlaps(tester.getRect(top)), isTrue, reason: 'on the print itself');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('swiping throws the top print in an arc and the next surfaces with a spring pop', (tester) async {
      final studio = await openDeck(tester);
      final gold = find.byKey(const ValueKey('deck-slot-gold_atelier_bsdf'));
      double goldScale() =>
          tester.widgetList<Transform>(find.descendant(of: gold, matching: find.byType(Transform))).first.transform.entry(0, 0).abs();
      expect(goldScale(), closeTo(0.93, 0.01), reason: 'waiting at depth 1');

      // While it is dragged the print below climbs toward the front: lift = drag / 110.
      final gesture = await tester.startGesture(tester.getCenter(top));
      // The first stretch is the pan slop; the drag counts from where it wins.
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.moveBy(const Offset(40, 0));
      await _pumpFor(tester, const Duration(milliseconds: 250));
      expect(goldScale(), greaterThan(0.95), reason: 'rising toward scale 1.0 with the drag');
      expect(goldScale(), lessThan(1.0));
      await gesture.up();
      await _pumpFor(tester, const Duration(milliseconds: 900));
      expect(studio.activeProjectId, 'caustic_study_04', reason: 'under the throw threshold: it springs home');
      expect(goldScale(), closeTo(0.93, 0.01), reason: 'and the print below drops back');

      // NEXT throws it with nothing dragged first, so the next project has
      // the whole climb to make: it surfaces to the front with an overshoot.
      await _tapKey(tester, const Key('deck-next-btn'));
      await tester.pump();
      expect(studio.activeProjectId, 'gold_atelier_bsdf');
      var peak = 0.0;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        peak = math.max(peak, goldScale());
      }
      expect(peak, greaterThan(1.001), reason: 'easeOutBack pops past full size');
      await _pumpFor(tester, const Duration(milliseconds: 800));
      expect(goldScale(), closeTo(1, 0.001), reason: 'and settles on top');
      final arrived = tester.widgetList<Transform>(find.ancestor(of: top, matching: find.byType(Transform))).first.transform;
      expect(arrived.getTranslation().x.abs(), lessThan(0.5), reason: 'in the pile, not where the last print was let go');
      expect(arrived.getTranslation().y.abs(), lessThan(0.5));
      expect(counter(tester), '02 / 05');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('a thrown print flies on a lifted, yawing arc and tucks behind the pile', (tester) async {
      final studio = await openDeck(tester);
      await tester.fling(top, const Offset(320, 0), 2200);
      await tester.pump();
      final flier = find.byKey(const ValueKey('deck-flier'));
      var highest = 0.0, yaw = 0.0, farthest = 0.0, perspective = 0.0;
      for (var i = 0; i < 40 && flier.evaluate().isNotEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (flier.evaluate().isEmpty) break;
        final m = tester.widgetList<Transform>(find.descendant(of: flier, matching: find.byType(Transform))).first.transform;
        highest = math.min(highest, m.getTranslation().y);
        yaw = math.max(yaw, m.entry(0, 2).abs());
        farthest = math.max(farthest, m.getTranslation().x);
        perspective = math.max(perspective, m.entry(3, 2));
      }
      expect(perspective, greaterThan(0.001), reason: '3D: a perspective divide');
      expect(farthest, greaterThan(100), reason: 'off to the right');
      expect(highest, lessThan(-5), reason: 'lifted on the arc');
      expect(yaw, greaterThan(0.05), reason: 'yawing away: rotateY');
      await _pumpFor(tester, const Duration(milliseconds: 900));
      expect(flier, findsNothing, reason: 'tucked back');
      expect(counter(tester), '02 / 05');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('a press-and-hold drag still drops a print on the viewport', (tester) async {
      final studio = await openDeck(tester);
      studio.toast.value = null;
      final gesture = await tester.startGesture(tester.getCenter(top));
      await _pumpFor(tester, const Duration(milliseconds: 700));
      await gesture.moveTo(tester.getCenter(find.text('SCENE_VIEWPORT.rt')) + const Offset(0, 150));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(studio.toast.value, 'PROJECT LOADED · CAUSTIC_STUDY_04');
      expect(studio.activeProjectId, 'caustic_study_04');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the deck follows project changes made elsewhere', (tester) async {
      final studio = await openDeck(tester);
      studio.selectProject('kerr_photon_ring');
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(counter(tester), '05 / 05');
      expect(inDeck('KERR_PHOTON_RING'), findsOneWidget);
      expect(inDeck('CAUSTIC_STUDY_04'), findsOneWidget, reason: 'the deck wraps round');
      expect(inDeck('ACRYLIC_LENS_ARRAY'), findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('a print showing under the top one selects its project on one click', (tester) async {
      final studio = await openDeck(tester);
      // Only the lower edge of the second print shows below the top one.
      final peek = find.byKey(const ValueKey('deck-peek-gold_atelier_bsdf'));
      // (The slot is a pitched, tilted 3D pose, so ask for where its bottom
      // corners really are on screen and tap just above their midpoint.)
      final edge = Offset.lerp(tester.getBottomLeft(peek), tester.getBottomRight(peek), 0.5)! - const Offset(0, 1);
      await tester.tapAt(edge);
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(studio.activeProjectId, 'gold_atelier_bsdf');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('a released print springs home with a small overshoot', (tester) async {
      final studio = await openDeck(tester);
      final gesture = await tester.startGesture(tester.getCenter(top));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 300));
      double dx() => tester
          .widgetList<Transform>(find.ancestor(of: top, matching: find.byType(Transform)))
          .first
          .transform
          .getTranslation()
          .x;
      final start = dx();
      expect(start, greaterThan(20));

      await gesture.up();
      var lowest = start;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        lowest = math.min(lowest, dx());
      }
      expect(lowest, lessThan(-0.2), reason: 'damped spring: it passes through home once');
      expect(lowest, greaterThan(-start * 0.2), reason: 'but only a little');
      expect(dx().abs(), lessThan(0.3), reason: 'and settles');
      expect(studio.activeProjectId, 'caustic_study_04');
      await _teardown(tester, studio);
    });
  });

  group('performance architecture', () {
    test('upload ticks move only the progress notifiers, not the workspace', () {
      final studio = StudioController(autoConnect: false, animateShader: false);
      addTearDown(studio.dispose);
      studio.startFileUpload('CHRONOS_WATCH.usd', sizeMb: 112.4);
      var workspace = 0, progress = 0, phase = 0;
      studio.addListener(() => workspace++);
      studio.uploadProgressNotifier.addListener(() => progress++);
      studio.uploadPhaseNotifier.addListener(() => phase++);

      for (var i = 0; i < 12; i++) {
        studio.debugTick();
      }
      expect(studio.uploadProgress, greaterThan(0.25));
      expect(progress, 12, reason: 'the loader hears every tick');
      expect(phase, greaterThanOrEqualTo(1), reason: 'and a phase change');
      expect(workspace, 0, reason: 'the workspace hears none of them');

      studio.advanceUploadForTest(1.0);
      expect(workspace, greaterThanOrEqualTo(1), reason: 'finishing adds a project, so it does notify');
      expect(studio.uploadProgressNotifier.value, 1.0);
      expect(studio.uploadPhaseNotifier.value, 3);
    });

    testWidgets('the loader advances without rebuilding the workspace', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.startFileUpload('CHRONOS_WATCH.usd', sizeMb: 112.4);
      await tester.pump();
      var rebuilds = 0;
      studio.addListener(() => rebuilds++);
      studio.advanceUploadForTest(0.3);
      await tester.pump();
      expect(find.text('30%'), findsOneWidget);
      studio.advanceUploadForTest(0.6);
      await tester.pump();
      expect(find.text('60%'), findsOneWidget);
      expect(rebuilds, 0);
      studio.advanceUploadForTest(1.0);
      await _pumpFor(tester, const Duration(milliseconds: 300));
      await _teardown(tester, studio);
    });

    testWidgets('each window repaints on its own layer', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      for (final type in [TopTelemetryBar, ProjectsSidebar, MacWindowViewport, OpticsInspectorDeck, CommandDock]) {
        final nearest = find.ancestor(of: find.byType(type), matching: find.byType(RepaintBoundary)).first;
        expect(tester.widget<RepaintBoundary>(nearest).child.runtimeType, type, reason: '$type');
      }
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    test('the Monte Carlo speckle is built once per sample step and size', () {
      const size = Size(800, 500);
      final a = MonteCarloNoisePainter.pointsFor(5, size);
      final b = MonteCarloNoisePainter.pointsFor(5, size);
      expect(identical(a.$1, b.$1), isTrue, reason: 'same step: the cached arrays are reused');
      expect(identical(a.$2, b.$2), isTrue);
      expect(a.$1, hasLength(4));
      expect(a.$1.first.length, (800 * 500 / 90).round().clamp(0, 6000) ~/ 4 * 2);

      final next = MonteCarloNoisePainter.pointsFor(6, size);
      expect(identical(a.$1, next.$1), isFalse, reason: 'a new step re-rolls');
      expect(next.$1.first, isNot(a.$1.first));
      final resized = MonteCarloNoisePainter.pointsFor(6, const Size(400, 300));
      expect(identical(next.$1, resized.$1), isFalse, reason: 'a new size rebuilds');
      // Deterministic: the same step always rolls the same points.
      final again = MonteCarloNoisePainter.pointsFor(5, size);
      expect(again.$1.first, a.$1.first);
    });

    testWidgets('the live scene stops its clock under a modal and resumes after it', (tester) async {
      final studio = StudioController(autoConnect: false);
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      studio.setProbeVisible(true); // the ring only exists, and turns, while the probe is on
      await tester.pump();
      ValueListenable<double> clock() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<ProceduralScenePainter>()
          // The A/B wipe draws the scene on both sides; they share one clock.
          .first
          .time;

      final t0 = clock().value;
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(clock().value, greaterThan(t0), reason: 'running');

      studio.setAccountModalOpen(true);
      await _pumpFor(tester, const Duration(milliseconds: 100));
      final paused = clock().value;
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(clock().value, paused, reason: 'held still while the modal is up');

      studio.setAccountModalOpen(false);
      await _pumpFor(tester, const Duration(milliseconds: 100));
      final resumed = clock().value;
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(clock().value, greaterThan(resumed), reason: 'and running again');

      studio.setCommandPaletteOpen(true);
      await _pumpFor(tester, const Duration(milliseconds: 100));
      final palette = clock().value;
      await _pumpFor(tester, const Duration(milliseconds: 400));
      expect(clock().value, palette, reason: 'the palette pauses it too');
      await _teardown(tester, studio);
    });

    testWidgets('the scenes draw with no blur filters in the hot path', (tester) async {
      // Paint every scene into a recorder; any MaskFilter would show up as a
      // saveLayer-free blur pass, so assert on the source instead.
      final source = File('lib/widgets/procedural_scene_canvas.dart').readAsStringSync();
      expect(RegExp(r'maskFilter\s*[:=]|\.\.maskFilter').hasMatch(source), isFalse, reason: 'no per-frame blur passes in the procedural scenes');
      expect(source.contains('MaskFilter.blur'), isFalse);
      for (final kind in ProceduralSceneKind.values) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final painter = ProceduralScenePainter(
          kind: kind,
          time: ValueNotifier(3.7),
          orbit: ValueNotifier(Offset.zero),
          zoom: ValueNotifier(1),
          focus: ValueNotifier(const Offset(0.5, 0.5)),
          ior: 1.8,
          aperture: 2.0,
          focalDistance: 2,
          causticsEnergy: 1,
          bounces: 32,
          wavelengthNm: 540,
        );
        painter.paint(canvas, const Size(1000, 620));
        recorder.endRecording().dispose();
      }
    });

    testWidgets('the landing page and project previews are decoded ahead of use', (tester) async {
      final studio = StudioController(autoConnect: false, startInLandingPage: true);
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      final cache = PaintingBinding.instance.imageCache;
      final tracked = await tester.runAsync(() async {
        final out = <String, bool>{};
        for (final provider in LaunchHeroPortal.frameProviders) {
          final key = await provider.obtainKey(ImageConfiguration.empty);
          out['hero ${(key as dynamic).hashCode}'] = cache.statusForKey(key).tracked;
        }
        for (final p in studio.projects) {
          for (final image in <ImageProvider>[
            AssetImage(p.previewAsset),
            ResizeImage(AssetImage(p.previewAsset), width: 96),
            ResizeImage(AssetImage(p.previewAsset), width: CardDeckCarousel.imageWidth),
          ]) {
            final key = await image.obtainKey(ImageConfiguration.empty);
            out['${p.id} ${(key as dynamic).hashCode}'] = cache.statusForKey(key).tracked;
          }
        }
        return out;
      });
      expect(tracked!.values, isNotEmpty);
      expect(tracked.values.every((v) => v), isTrue, reason: tracked.entries.where((e) => !e.value).map((e) => e.key).join(', '));
      await _teardown(tester, studio);
    });

    test('the sidebar is 210px wide', () {
      expect(ProjectsSidebar.width, 210);
    });

    test('font styles are resolved once per weight, then only copied', () {
      final type = PhotonType(PhotonPalette.grading);
      // Warm every weight the studio's scale uses.
      void touch() {
        type
          ..headlineMd
          ..headlineSm
          ..bodyLg
          ..bodyMd
          ..bodySm
          ..buttonLabel
          ..telemetryLg
          ..telemetryMd
          ..telemetrySm
          ..labelCaps;
        type.ui(weight: FontWeight.w700);
        type.mono(weight: FontWeight.w700);
      }

      touch();
      final resolved = PhotonType.resolvedBaseStyles;
      expect(resolved, greaterThanOrEqualTo(4));
      for (var i = 0; i < 400; i++) {
        touch();
        type.ui(size: 10 + i % 7, color: Colors.red);
        type.mono(size: 9 + i % 5);
      }
      expect(PhotonType.resolvedBaseStyles, resolved, reason: 'no font resolution after the first use');

      // The copies still carry what each call asked for.
      final ui = type.ui(size: 15, weight: FontWeight.w500, height: 1.3, tracking: -0.01, color: Colors.red);
      expect(ui.fontSize, 15);
      expect(ui.fontWeight, FontWeight.w500);
      expect(ui.height, 1.3);
      expect(ui.letterSpacing, closeTo(-0.15, 1e-9));
      expect(ui.color, Colors.red);
      expect(type.ui().color, PhotonPalette.grading.carbon);
      final mono = type.mono(size: 10);
      expect(mono.fontFeatures, contains(const FontFeature.tabularFigures()), reason: 'numbers stay tabular');
      expect(PhotonType(PhotonPalette.daylight).labelCaps.color, PhotonPalette.daylight.textMuted);
      expect(type.mono().fontFamily, isNot(type.ui().fontFamily));
    });

    testWidgets('a theme change is one rebuild: no animated interpolation of the tree', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeAnimationDuration, Duration.zero);
      Color canvas() => Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor;
      expect(canvas(), PhotonPalette.grading.canvas);

      studio.setDarkGrading(false);
      await tester.pump();
      expect(canvas(), PhotonPalette.daylight.canvas, reason: 'one frame, not 200ms of in-between themes');
      studio.setDarkGrading(true);
      await tester.pump();
      expect(canvas(), PhotonPalette.grading.canvas);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the theme switch animates only while it moves, in 220ms', (tester) async {
      expect(ShaderThemeSwitch.duration, const Duration(milliseconds: 220));
      expect([ShaderThemeSwitch.width, ShaderThemeSwitch.height], [28, 28]);
      // On its own: the rest of the studio has pips that legitimately pulse.
      final dark = ValueNotifier<bool>(true);
      addTearDown(dark.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ValueListenableBuilder<bool>(
                valueListenable: dark,
                builder: (context, isDark, _) => ShaderThemeSwitch(dark: isDark, onChanged: (v) => dark.value = v),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'idle: nothing is scheduled');

      dark.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'moving');
      await _pumpFor(tester, const Duration(milliseconds: 260));
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'settled after 220ms');

      dark.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await _pumpFor(tester, const Duration(milliseconds: 260));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    test('the app opens with the project stack deck up; a bare controller still starts on the list', () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(source, contains('startInDeckView: true'));
      expect(source, contains('themeAnimationDuration: Duration.zero'));
      final studio = StudioController(autoConnect: false, animateShader: false);
      addTearDown(studio.dispose);
      expect(studio.deckView, isFalse, reason: 'tests and embedders choose their own');
      final app = StudioController(autoConnect: false, animateShader: false, startInDeckView: true);
      addTearDown(app.dispose);
      expect(app.deckView, isTrue);
    });

  });

  group('Photon mark', () {
    Future<ByteData> render(WidgetTester tester, {double size = 200}) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox.square(dimension: size, child: PhotonLogoMark(size: size)),
            ),
          ),
        ),
      );
      await _logoReady(tester);
      return _capture(tester, key);
    }

    double luma(Color c) => 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

    testWidgets('draws at the studio sizes and the icon sizes without fuss', (tester) async {
      for (final size in [16.0, 22.0, 24.0, 40.0, 256.0]) {
        await render(tester, size: size);
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });

    test('the mark takes no theme input at all', () {
      final source = File('lib/widgets/photon_primitives.dart').readAsStringSync();
      final start = source.indexOf('class PhotonLogoMark');
      final end = source.indexOf('/// Double-tap detection');
      final logo = source.substring(start, end);
      for (final themed in ['isDark', 'Theme.of', 'brightness', 'context.photon']) {
        expect(logo.contains(themed), isFalse, reason: 'the logo reads no $themed');
      }
    });

    test('the artwork is the supplied transparent PNG, registered as an asset', () {
      final bytes = File(PhotonLogo.asset).readAsBytesSync();
      expect(bytes.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final h = ByteData.sublistView(bytes);
      expect([h.getUint32(16), h.getUint32(20)], [1024, 1024]);
      expect(bytes[25], 6, reason: 'RGBA: it keeps its transparency');
      expect(File('pubspec.yaml').readAsStringSync(), contains(PhotonLogo.asset));
    });

    testWidgets('a dark navy squircle with its corner clear, contrasting the pastel artwork', (tester) async {
      final d = await render(tester);
      expect(_pixel(d, 200, 0, 0).a, 0, reason: 'the corner is outside the squircle');
      // Just inside the top-left of the tile, clear of the artwork.
      final bg = _pixel(d, 200, 20, 20);
      expect(bg.a, 1.0);
      expect(luma(bg), lessThan(35), reason: 'deep navy: $bg');
      expect(_channel(bg.b), greaterThan(_channel(bg.r)), reason: 'navy, not grey or black');
      // The artwork is far lighter than that: the prism, the beam and the ribbon.
      final prism = _pixel(d, 200, 100, 100);
      expect(luma(prism), greaterThan(luma(bg) + 90), reason: 'the prism stands out of the tile: $prism');
    });

    testWidgets('the prism, the pale beam and the coral ribbon are all there', (tester) async {
      final d = await render(tester);
      Color at(int x, int y) => _pixel(d, 200, x, y);
      // The prism: frosted blue.
      final prism = at(100, 104);
      expect(_channel(prism.b), greaterThan(_channel(prism.r) + 25), reason: 'blue prism: $prism');
      // The beam entering from the left: pale blue.
      final beam = at(32, 96);
      expect(_channel(beam.b), greaterThan(190), reason: 'the pale beam: $beam');
      expect(_channel(beam.b), greaterThan(_channel(beam.r)));
      // The ribbon leaving to the right: coral to amber.
      final ribbon = at(176, 109);
      expect(_channel(ribbon.r), greaterThan(200), reason: 'the warm ribbon: $ribbon');
      expect(_channel(ribbon.r), greaterThan(_channel(ribbon.b) + 60));
    });

    testWidgets('it holds at 16, 22, 24 and 40px: the prism is a clear light shape on the dark tile', (tester) async {
      for (final size in [16, 22, 24, 40]) {
        final d = await render(tester, size: size.toDouble());
        final corner = _pixel(d, size, (0.1 * size).round(), (0.1 * size).round());
        final centre = _pixel(d, size, size ~/ 2, (0.53 * size).round());
        expect(luma(centre), greaterThan(luma(corner) + 70), reason: '$size px: the prism against the tile');
        expect(_channel(centre.b), greaterThan(_channel(centre.r)), reason: '$size px: blue');
        expect(tester.takeException(), isNull);
      }
    });

    test('the old drawn mark is gone: no hand-drawn prism, rays or P in the painter code', () {
      final source = File('lib/widgets/photon_primitives.dart').readAsStringSync();
      for (final gone in ['PhotonLogoPainter', '_star(', '_hit(', 'wedge', 'fanTop', 'collimated', 'Doppler', '_ringStart', 'bowl', 'final stem', 'exit =']) {
        expect(source.contains(gone), isFalse, reason: gone);
      }
    });

    test('every place the mark appears uses this one widget', () {
      for (final f in ['launch_hero_portal.dart', 'top_telemetry_bar.dart', 'command_dock.dart']) {
        expect(File('lib/widgets/$f').readAsStringSync(), contains('PhotonLogoMark('), reason: f);
      }
    });
  });

  group('app icon', () {
    final file = File('windows/runner/resources/app_icon.ico');

    test('is a PNG-compressed ICO with 16, 32, 48 and 256px frames', () {
      final bytes = file.readAsBytesSync();
      final h = ByteData.sublistView(bytes);
      expect([h.getUint16(0, Endian.little), h.getUint16(2, Endian.little)], [0, 1], reason: 'reserved, type = icon');
      final count = h.getUint16(4, Endian.little);
      expect(count, 4);
      final sizes = <int>[];
      for (var i = 0; i < count; i++) {
        final e = 6 + 16 * i;
        final w = bytes[e] == 0 ? 256 : bytes[e];
        final ht = bytes[e + 1] == 0 ? 256 : bytes[e + 1];
        expect(w, ht);
        sizes.add(w);
        expect(h.getUint16(e + 6, Endian.little), 32, reason: '32 bits per pixel');
        final length = h.getUint32(e + 8, Endian.little), offset = h.getUint32(e + 12, Endian.little);
        expect(offset + length, lessThanOrEqualTo(bytes.length));
        expect(bytes.sublist(offset, offset + 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], reason: 'a PNG at $w');
        final png = ByteData.sublistView(bytes, offset);
        expect([png.getUint32(16), png.getUint32(20)], [w, w], reason: 'the PNG is $w x $w');
      }
      expect(sizes, [16, 32, 48, 256]);
    });

    testWidgets('its 256px frame is the app logo: the same PhotonLogo drawing, and the same picture as the widget', (tester) async {
      final bytes = file.readAsBytesSync();
      final h = ByteData.sublistView(bytes);
      final e = 6 + 16 * 3;
      final png = Uint8List.sublistView(bytes, h.getUint32(e + 12, Endian.little), h.getUint32(e + 12, Endian.little) + h.getUint32(e + 8, Endian.little));
      Future<Uint8List> rgba(ui.Image i) async => (await i.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      final result = await tester.runAsync(() async {
        final fromIcon = await rgba((await (await ui.instantiateImageCodec(png)).getNextFrame()).image);
        final art = (await (await ui.instantiateImageCodec(File(PhotonLogo.asset).readAsBytesSync())).getNextFrame()).image;
        final recorder = ui.PictureRecorder();
        PhotonLogo.paint(Canvas(recorder), const Size.square(256), art);
        final fromPainter = await rgba(await recorder.endRecording().toImage(256, 256));
        return (fromIcon, fromPainter);
      });
      final (icon, painter) = result!;
      expect(icon.length, painter.length);
      var differing = 0;
      for (var i = 0; i < icon.length; i++) {
        if ((icon[i] - painter[i]).abs() > 2) differing++;
      }
      expect(differing, lessThan(icon.length ~/ 200), reason: 'the icon is PhotonLogo.paint, rasterised');

      int px(Uint8List data, int x, int y, int channel) => data[(y * 256 + x) * 4 + channel];
      expect(px(icon, 0, 0, 3), 0, reason: 'a squircle with transparent corners');
      // The dark navy ground, and the pale prism standing out of it.
      final ground = [px(icon, 26, 26, 0), px(icon, 26, 26, 1), px(icon, 26, 26, 2)];
      expect(ground.every((v) => v < 45), isTrue, reason: 'navy ground: $ground');
      expect(ground[2], greaterThan(ground[0]));
      expect(px(icon, 128, 136, 2), greaterThan(180), reason: 'the blue prism');

      // And it is the picture the app shows: the widget's own render of the logo.
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: RepaintBoundary(key: key, child: const PhotonLogoMark(size: 256))),
        ),
      );
      await _logoReady(tester);
      final widget = (await _capture(tester, key)).buffer.asUint8List();
      var far = 0;
      for (var i = 0; i < icon.length; i += 4) {
        final d = (icon[i] - widget[i]).abs() + (icon[i + 1] - widget[i + 1]).abs() + (icon[i + 2] - widget[i + 2]).abs();
        if (d > 60) far++;
      }
      expect(far, lessThan(256 * 256 ~/ 40), reason: 'the widget and the icon show the same logo (under 2.5% of pixels differ visibly)');
    });

    test('the generator that writes it lives in tool/ and draws with PhotonLogo', () {
      final source = File('tool/gen_app_icon_test.dart').readAsStringSync();
      expect(source, contains('PhotonLogo.paint'));
      expect(source, contains('PhotonLogo.asset'));
    });
  });

  group('local file and URL ingest', () {
    StudioController make({RenderSocket? socket, bool autoConnect = false}) {
      final s = StudioController(socket: socket, autoConnect: autoConnect, animateShader: false);
      addTearDown(s.dispose);
      return s;
    }

    void finish(StudioController s) {
      for (var i = 0; i < 400 && s.isUploading; i++) {
        s.debugTick();
      }
    }

    const invalid = 'INVALID URL · USE HTTP/HTTPS/WS';

    test('a project can carry a local file, a URL and bytes, and copyWith keeps them', () {
      final p = kDefaultProjects.first;
      expect([p.localFilePath, p.externalUrl, p.customBytes], [null, null, null]);
      final q = p.copyWith(localFilePath: 'C:/a.png', externalUrl: 'https://x/a.png', customBytes: _tinyPng);
      expect(q.localFilePath, 'C:/a.png');
      expect(q.externalUrl, 'https://x/a.png');
      expect(identical(q.customBytes, _tinyPng), isTrue);
      final r = q.copyWith(name: 'RENAMED');
      expect([r.localFilePath, r.externalUrl], ['C:/a.png', 'https://x/a.png']);
      expect(identical(r.customBytes, _tinyPng), isTrue);
      expect(StudioController.imageExtensions, {'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'});
    });

    test('a local image runs the loader, then shows as a still with its path and bytes', () {
      final s = make();
      final before = s.projects.length;
      s.startLocalFileIngest(filePath: r'C:\Users\me\Pictures\hero shot.PNG', bytes: _tinyPng);
      expect(s.isUploading, isTrue);
      expect(s.uploadingFileName, 'hero shot.PNG');
      expect(s.uploadSizeMb, closeTo(_tinyPng.length / (1024 * 1024), 1e-9));
      finish(s);

      expect(s.projects.length, before + 1);
      final p = s.activeProject!;
      expect(p.name, 'HERO SHOT');
      expect(p.localFilePath, r'C:\Users\me\Pictures\hero shot.PNG');
      expect(identical(p.customBytes, _tinyPng), isTrue);
      expect(p.isDynamic, isFalse, reason: 'an image is shown as itself');
      expect(s.liveShaderEnabled, isFalse);
      expect(p.sceneType, 'Local Image');
      expect(p.externalUrl, isNull);
      expect(s.toast.value, 'ASSET INGESTED · hero shot.PNG');
    });

    test('every image extension is a still; a scene file keeps its path and stays a simulation', () {
      final s = make();
      for (final ext in ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif']) {
        s.startLocalFileIngest(filePath: '/home/me/shot.$ext', bytes: _tinyPng, sizeMb: 0.1);
        finish(s);
        expect(s.activeProject!.isDynamic, isFalse, reason: ext);
      }
      s.startLocalFileIngest(filePath: '/home/me/watch.usd', sizeMb: 12);
      finish(s);
      final usd = s.activeProject!;
      expect(usd.name, 'WATCH');
      expect(usd.localFilePath, '/home/me/watch.usd');
      expect(usd.customBytes, isNull);
      expect(usd.isDynamic, isTrue);
      expect(usd.sceneType, 'USD Scene Graph');
      expect(usd.subtitle, '.usd · 12.0 MB');
    });

    test('the size comes from the caller, the bytes, or the file itself', () {
      final s = make();
      s.startLocalFileIngest(filePath: '/a/b.exr', bytes: _tinyPng, sizeMb: 7.5);
      expect(s.uploadSizeMb, 7.5, reason: 'an explicit size wins');
      finish(s);

      final dir = Directory.systemTemp.createTempSync('photon_ingest_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}scene.obj')..writeAsBytesSync(List.filled(4096, 7));
      s.startLocalFileIngest(filePath: file.path);
      expect(s.uploadSizeMb, closeTo(4096 / (1024 * 1024), 1e-12), reason: 'read from the file');
      finish(s);

      s.startLocalFileIngest(filePath: '/not/on/this/disk.obj');
      expect(s.uploadSizeMb, 1.0, reason: 'a nominal size when it cannot be found');
    });

    test('a blank path is refused, and one ingest at a time keeps its own file', () {
      final s = make();
      s.startLocalFileIngest(filePath: '   ');
      expect(s.isUploading, isFalse);
      expect(s.toast.value, 'CHOOSE A FILE FIRST');

      final other = Uint8List.fromList([1, 2, 3]);
      s.startLocalFileIngest(filePath: '/x/first.png', bytes: _tinyPng);
      s.startLocalFileIngest(filePath: '/x/second.png', bytes: other);
      expect(s.toast.value, 'INGEST IN PROGRESS · first.png');
      finish(s);
      expect(identical(s.activeProject!.customBytes, _tinyPng), isTrue, reason: 'the second did not overwrite the first');
      expect(s.activeProject!.localFilePath, '/x/first.png');

      s.startLocalFileIngest(filePath: '/x/third.usd');
      finish(s);
      expect(s.activeProject!.customBytes, isNull, reason: 'nothing left over from the earlier files');
      expect(s.activeProject!.localFilePath, '/x/third.usd');
    });

    test('only http, https, ws and wss URLs with a host are accepted', () {
      final s = make();
      final before = s.projects.length;
      for (final bad in ['', '   ', 'nope', 'ftp://host/a.png', 'https://', 'http:///x.png', '//example.com/a.png', 'file:///C:/a.png', 'javascript:alert(1)']) {
        s.toast.value = null;
        s.startUrlIngest(bad);
        expect(s.toast.value, invalid, reason: '"$bad"');
        expect(s.isUploading, isFalse, reason: bad);
      }
      expect(s.projects.length, before);
    });

    test('an http URL runs the loader and becomes a still that loads from that address', () {
      final s = make();
      s.startUrlIngest('  https://cdn.example.com/renders/prism.png?sig=1  ');
      expect(s.isUploading, isTrue);
      expect(s.uploadingFileName, 'prism.png');
      finish(s);
      var p = s.activeProject!;
      expect(p.name, 'PRISM');
      expect(p.externalUrl, 'https://cdn.example.com/renders/prism.png?sig=1');
      expect(p.isDynamic, isFalse);
      expect(s.liveShaderEnabled, isFalse);
      expect(p.sceneType, 'Remote Image');
      expect(p.subtitle, '.png · cdn.example.com');
      expect(p.localFilePath, isNull);
      expect(p.customBytes, isNull);

      s.startUrlIngest('http://host.test/a/scene.exr');
      finish(s);
      p = s.activeProject!;
      expect(p.sceneType, 'Remote Asset', reason: 'not an image');
      expect(p.isDynamic, isFalse);

      s.startUrlIngest('https://example.com');
      expect(s.uploadingFileName, 'example_com.url', reason: 'no file name: the host stands in');
      finish(s);
      expect(s.activeProject!.name, 'EXAMPLE_COM');
    });

    test('a ws or wss URL links the engine stream instead of making a project', () {
      final socket = _RecordingSocket();
      final s = make(socket: socket);
      final before = s.projects.length;
      s.startUrlIngest(' ws://10.0.0.5:9000/stream ');
      expect(s.toast.value, 'STREAM LINKED · ws://10.0.0.5:9000/stream');
      expect(socket.uri, Uri.parse('ws://10.0.0.5:9000/stream'));
      expect(s.isUploading, isFalse);
      expect(s.projects.length, before);
      expect(socket.connects, 0, reason: 'a studio built not to connect only stages the address');

      s.startUrlIngest('wss://engine.test/live');
      expect(socket.uri.scheme, 'wss');
      expect(s.toast.value, 'STREAM LINKED · wss://engine.test/live');

      final live = _RecordingSocket();
      final connected = make(socket: live, autoConnect: true);
      expect(live.connects, 1);
      connected.startUrlIngest('ws://127.0.0.1:9001');
      expect(live.connects, 2, reason: 'a connected studio moves to the new stream');
    });

    test('the socket can be re-aimed, connecting only when asked', () {
      final socket = _FakeSocket();
      addTearDown(socket.dispose);
      socket.retarget(Uri.parse('ws://a:1'), reconnect: false);
      expect(socket.uri, Uri.parse('ws://a:1'));
      expect(socket.connects, 0);
      socket.retarget(Uri.parse('ws://b:2'));
      expect(socket.uri, Uri.parse('ws://b:2'));
      expect(socket.connects, 1);
    });

    test('the native file dialog never opens under test, and the picker can be replaced', () async {
      expect(await pickLocalFileNative(), isNull);
      expect(kIngestFileFilter, contains('*.png'));
      expect(kIngestFileFilter, contains('*.usd'));
      final s = make();
      expect(await s.pickLocalFile(), isNull);
      s.filePickerOverride = () async => '/picked/file.png';
      expect(await s.pickLocalFile(), '/picked/file.png');
    });

    Finder memoryImage(Uint8List bytes) =>
        find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage && identical((w.image as MemoryImage).bytes, bytes));

    testWidgets('the viewport shows an uploaded image from its bytes', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(memoryImage(_tinyPng), findsNothing);
      studio.startLocalFileIngest(filePath: r'C:\x\shot.png', bytes: _tinyPng, sizeMb: 0.1);
      studio.advanceUploadForTest(1.0);
      await tester.pump();
      expect(memoryImage(_tinyPng), findsWidgets);
      expect(find.byType(ProceduralSceneCanvas), findsNothing, reason: 'a still, not the simulation');
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('with no bytes it reads the file from disk, and falls back to the bundled still if it is gone', (tester) async {
      final dir = Directory.systemTemp.createTempSync('photon_view_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}shot.png')..writeAsBytesSync(_tinyPng);
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      Finder fileImage() =>
          find.byWidgetPredicate((w) => w is Image && w.image is FileImage && (w.image as FileImage).file.path == file.path);

      studio.startLocalFileIngest(filePath: file.path);
      studio.advanceUploadForTest(1.0);
      await tester.pump();
      expect(fileImage(), findsWidgets);

      file.deleteSync();
      studio.setWavelengthNm(500);
      await tester.pump();
      expect(fileImage(), findsNothing);
      final preview = studio.activeProject!.previewAsset;
      expect(
        find.byWidgetPredicate((w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == preview),
        findsWidgets,
        reason: 'the project\'s bundled render stands in',
      );
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('an embedded URL is loaded as a network image', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      const url = 'https://cdn.example.com/a/scene.png';
      studio.startUrlIngest(url);
      studio.advanceUploadForTest(1.0);
      await tester.pump();
      expect(
        find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage && (w.image as NetworkImage).url == url),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    group('the ingest sheet', () {
      final sheet = find.byKey(const Key('file-ingest-sheet'));

      Future<StudioController> openSheet(WidgetTester tester, {Size size = const Size(1280, 800)}) async {
        final studio = await _pumpStudio(tester, size);
        studio.setIngestSheetOpen(true);
        await tester.pump();
        return studio;
      }

      Future<File> tempImage() async {
        final dir = Directory.systemTemp.createTempSync('photon_sheet_');
        addTearDown(() => dir.deleteSync(recursive: true));
        return File('${dir.path}${Platform.pathSeparator}pasted shot.png')..writeAsBytesSync(_tinyPng);
      }

      testWidgets('it offers local upload, URL embed and the curated samples, in a 480px window', (tester) async {
        final studio = await openSheet(tester);
        expect(tester.getSize(sheet).width, lessThanOrEqualTo(480));
        expect(tester.getSize(sheet).width, greaterThan(440), reason: 'widened from 440');
        for (final k in [
          'ingest-local-file-btn',
          'ingest-local-path-input',
          'ingest-local-path-submit',
          'ingest-url-input',
          'ingest-url-submit-btn',
        ]) {
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        for (final text in [
          'LOCAL FILE UPLOAD',
          'UPLOAD LOCAL FILE (.PNG, .JPG, .USD, .EXR, .OBJ)',
          'BROWSE DISK...',
          'DIRECT URL EMBED',
          'EMBED URL',
          'CURATED ASSETS',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        expect(tester.widget<TextField>(find.byKey(const Key('ingest-url-input'))).decoration!.hintText, 'https://.../scene.png, .exr, .usd or ws://...');
        // The curated samples are still here, above nothing and below both.
        for (final p in kIngestPresets) {
          expect(find.text(p.fileName), findsOneWidget);
        }
        final curated = tester.getTopLeft(find.text('CURATED ASSETS')).dy;
        expect(tester.getTopLeft(find.text('LOCAL FILE UPLOAD')).dy, lessThan(curated));
        expect(tester.getTopLeft(find.text('DIRECT URL EMBED')).dy, lessThan(curated));
        expect(tester.takeException(), isNull);
        await _teardown(tester, studio);
      });

      testWidgets('BROWSE DISK uses the picker and ingests the file it returns, bytes and all', (tester) async {
        final file = await tempImage();
        final studio = await openSheet(tester);
        studio.filePickerOverride = () async => file.path;
        await _tapKey(tester, const Key('ingest-local-file-btn'));
        await tester.pump();
        await tester.pump();
        expect(studio.isUploading, isTrue);
        expect(studio.uploadingFileName, 'pasted shot.png');
        expect(studio.ingestSheetOpen, isFalse, reason: 'the sheet closes as the loader starts');
        studio.advanceUploadForTest(1.0);
        await tester.pump();
        expect(studio.activeProject!.localFilePath, file.path);
        expect(studio.activeProject!.customBytes, _tinyPng);
        await _pumpFor(tester, const Duration(milliseconds: 1600));
        await _teardown(tester, studio);
      });

      testWidgets('a cancelled dialog falls back to the path field', (tester) async {
        final studio = await openSheet(tester);
        studio.filePickerOverride = () async => null;
        await _tapKey(tester, const Key('ingest-local-file-btn'));
        await tester.pump();
        await tester.pump();
        expect(studio.isUploading, isFalse);
        expect(find.text('NO FILE CHOSEN · TYPE OR PASTE A PATH BELOW'), findsOneWidget);
        expect(tester.widget<TextField>(find.byKey(const Key('ingest-local-path-input'))).focusNode!.hasFocus, isTrue);
        await _teardown(tester, studio);
      });

      testWidgets('a typed path ingests the file; quotes are stripped; the button and Enter both work', (tester) async {
        final file = await tempImage();
        final studio = await openSheet(tester);
        await tester.enterText(find.byKey(const Key('ingest-local-path-input')), '"${file.path}"');
        await _tapKey(tester, const Key('ingest-local-path-submit'));
        await tester.pump();
        expect(studio.isUploading, isTrue);
        expect(studio.uploadingFileName, 'pasted shot.png');
        studio.advanceUploadForTest(1.0);
        await tester.pump();
        expect(studio.activeProject!.localFilePath, file.path, reason: 'without the quotes');
        await _pumpFor(tester, const Duration(milliseconds: 1600));

        studio.setIngestSheetOpen(true);
        await tester.pump();
        await tester.enterText(find.byKey(const Key('ingest-local-path-input')), file.path);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(studio.isUploading, isTrue, reason: 'Enter submits too');
        studio.advanceUploadForTest(1.0);
        await _pumpFor(tester, const Duration(milliseconds: 1600));
        await _teardown(tester, studio);
      });

      testWidgets('a missing or empty path is reported, and nothing starts', (tester) async {
        final studio = await openSheet(tester);
        await _tapKey(tester, const Key('ingest-local-path-submit'));
        await tester.pump();
        expect(find.text('TYPE OR PASTE A FILE PATH'), findsOneWidget);

        await tester.enterText(find.byKey(const Key('ingest-local-path-input')), r'C:\nowhere\ghost.png');
        await _tapKey(tester, const Key('ingest-local-path-submit'));
        await tester.pump();
        expect(studio.isUploading, isFalse);
        expect(studio.toast.value, r'FILE NOT FOUND · C:\nowhere\ghost.png');
        expect(find.text('FILE NOT FOUND · CHECK THE PATH'), findsOneWidget);
        expect(studio.ingestSheetOpen, isTrue);
        await _teardown(tester, studio);
      });

      testWidgets('EMBED URL starts the loader; a bad URL is reported and the sheet stays open', (tester) async {
        final studio = await openSheet(tester);
        await tester.enterText(find.byKey(const Key('ingest-url-input')), 'not a url');
        await _tapKey(tester, const Key('ingest-url-submit-btn'));
        await tester.pump();
        expect(studio.toast.value, invalid);
        expect(studio.ingestSheetOpen, isTrue);
        expect(studio.isUploading, isFalse);

        await tester.enterText(find.byKey(const Key('ingest-url-input')), 'https://cdn.example.com/hero.jpg');
        await _tapKey(tester, const Key('ingest-url-submit-btn'));
        await tester.pump();
        expect(studio.isUploading, isTrue);
        expect(studio.uploadingFileName, 'hero.jpg');
        expect(studio.ingestSheetOpen, isFalse);
        studio.advanceUploadForTest(1.0);
        await tester.pump();
        expect(studio.activeProject!.externalUrl, 'https://cdn.example.com/hero.jpg');
        await _pumpFor(tester, const Duration(milliseconds: 1600));
        await _teardown(tester, studio);
      });

      testWidgets('Enter in the URL field embeds it, and a ws URL links the stream', (tester) async {
        final socket = _RecordingSocket();
        final studio = StudioController(socket: socket, autoConnect: false, animateShader: false);
        await _pumpStudio(tester, const Size(1280, 800), controller: studio);
        studio.setIngestSheetOpen(true);
        await tester.pump();
        await tester.enterText(find.byKey(const Key('ingest-url-input')), 'ws://127.0.0.1:9100');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(studio.toast.value, 'STREAM LINKED · ws://127.0.0.1:9100');
        expect(socket.uri, Uri.parse('ws://127.0.0.1:9100'));
        expect(studio.ingestSheetOpen, isFalse);
        expect(studio.isUploading, isFalse);
        await _teardown(tester, studio);
      });

      testWidgets('the curated samples still start the loader', (tester) async {
        final studio = await openSheet(tester);
        await _tapKey(tester, const Key('ingest-file-CAUSTIC_POOL.exr'));
        await tester.pump();
        expect(studio.uploadingFileName, 'CAUSTIC_POOL.exr');
        await _teardown(tester, studio);
      });

      testWidgets('it fits a narrow window and a short one', (tester) async {
        var studio = await openSheet(tester, size: const Size(390, 844));
        expect(tester.takeException(), isNull);
        expect(tester.getSize(sheet).width, lessThanOrEqualTo(390));
        await _teardown(tester, studio);
        studio = await openSheet(tester, size: const Size(1000, 480));
        expect(tester.takeException(), isNull);
        expect(tester.getSize(sheet).height, lessThanOrEqualTo(480), reason: 'it scrolls inside the window');
        await tester.ensureVisible(find.text('CURATED ASSETS'));
        await tester.pump();
        await _teardown(tester, studio);
      });
    });
  });

  group('Photon model tiers', () {
    final popover = find.byKey(const Key('photon-model-popover'));
    final chip = find.byKey(const Key('photon-model-btn'));

    test('PHOTON LUMEN-1 has three tiers with these presets', () {
      expect(PhotonModelTier.values, [PhotonModelTier.lite, PhotonModelTier.quick, PhotonModelTier.pro]);
      const lite = PhotonModelTier.lite, quick = PhotonModelTier.quick, pro = PhotonModelTier.pro;
      expect([lite.name, lite.shortTag, lite.spec], ['PHOTON LUMEN · LITE', 'LITE', 'Neural Draft · 64 SPP · 4 Bounces']);
      expect([quick.name, quick.shortTag, quick.spec], ['PHOTON LUMEN · QUICK', 'QUICK', 'ReSTIR Interactive · 256 SPP · 12 Bounces']);
      expect([pro.name, pro.shortTag, pro.spec], ['PHOTON LUMEN · PRO', 'PRO', 'Full Spectral BiDir + SPPM · 1024 SPP · 24 Bounces']);
      expect([lite.defaultSpp, lite.defaultBounces, lite.defaultIntegrator], [64, 4, IntegratorMode.unidirectional]);
      expect([quick.defaultSpp, quick.defaultBounces, quick.defaultIntegrator], [256, 12, IntegratorMode.restir]);
      expect([pro.defaultSpp, pro.defaultBounces, pro.defaultIntegrator], [1024, 24, IntegratorMode.sppm]);
      expect([lite.accent, quick.accent, pro.accent], [const Color(0xFF22D3EE), const Color(0xFF1A2FFB), const Color(0xFFFF4C41)]);
      expect([lite.id, quick.id, pro.id], ['lite', 'quick', 'pro'], reason: 'the stable id the enum name shadows');
      expect(PhotonModelTier.modelId, 'photon_lumen_1');
    });

    test('a tier applies its preset, tells the engine, restarts convergence and can be undone', () {
      final socket = _RecordingSocket();
      final s = StudioController(socket: socket, autoConnect: false, animateShader: false);
      addTearDown(s.dispose);
      expect(s.modelTier, PhotonModelTier.quick, reason: 'Quick is the default');
      final initial = (s.targetSamples, s.maxBounces, s.integrator);
      for (var i = 0; i < 30; i++) {
        s.debugTick();
      }
      expect(s.samples.value, greaterThan(0));

      s.setModelTier(PhotonModelTier.lite);
      expect(s.modelTier, PhotonModelTier.lite);
      expect(s.targetSamples, 64);
      expect(s.maxBounces, 4);
      expect(s.integrator, IntegratorMode.unidirectional);
      expect(s.samples.value, 0, reason: 'convergence restarts');
      expect(s.toast.value, 'MODEL · PHOTON LUMEN · LITE');
      // (Maps are not value-equal, so say `equals` for list.contains to compare deeply.)
      expect(socket.sent, contains(equals({'model': 'photon_lumen_1', 'tier': 'lite'})));
      expect(socket.sent, contains(equals({'param': 'samples_per_pixel', 'value': 64.0})));
      expect(socket.sent, contains(equals({'param': 'max_bounces', 'value': 4.0})));

      s.setModelTier(PhotonModelTier.pro);
      expect([s.targetSamples, s.maxBounces, s.integrator], [1024, 24, IntegratorMode.sppm]);
      expect(socket.sent, contains(equals({'integrator': 'sppm'})));
      expect(socket.sent.last, {'model': 'photon_lumen_1', 'tier': 'pro'});

      // Undo steps back one preset at a time, and the tier follows the optics
      // it set (the badge must not say PRO over LITE's sample count).
      socket.sent.clear();
      s.undo();
      expect([s.modelTier, s.targetSamples, s.maxBounces, s.integrator], [PhotonModelTier.lite, 64, 4, IntegratorMode.unidirectional]);
      expect(socket.sent.last, {'model': 'photon_lumen_1', 'tier': 'lite'}, reason: 'the engine follows too');
      s.undo();
      expect(s.modelTier, PhotonModelTier.quick);
      expect((s.targetSamples, s.maxBounces, s.integrator), initial);
      s.redo();
      s.redo();
      expect([s.modelTier, s.targetSamples, s.maxBounces, s.integrator], [PhotonModelTier.pro, 1024, 24, IntegratorMode.sppm]);

      // The project remembers the preset across a switch.
      s.selectProject('volumetric_prism');
      s.selectProject('caustic_study_04');
      expect(s.targetSamples, 1024);
    });

    test('with the engine offline a tier still applies', () {
      final s = StudioController(socket: _RecordingSocket()..online = false, autoConnect: false, animateShader: false);
      addTearDown(s.dispose);
      s.setModelTier(PhotonModelTier.pro);
      expect(s.targetSamples, 1024);
      expect(s.modelTier, PhotonModelTier.pro);
    });

    testWidgets('the processor chip is still 40x40, with a tier badge and the link pip', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(tester.getSize(find.byKey(const ValueKey('proximity-link'))), const Size(40, 40));
      expect(tester.getSize(chip), const Size(40, 40));
      expect(find.descendant(of: chip, matching: find.byIcon(Icons.memory)), findsOneWidget);
      expect(find.descendant(of: chip, matching: find.text('QUICK')), findsOneWidget);
      expect(find.byKey(const Key('model-tier-badge')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('clicking it opens the selector over the dock with the engine and three tier cards', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(popover, findsNothing);
      await _tapKey(tester, const Key('photon-model-btn'));
      await _pumpFor(tester, const Duration(milliseconds: 200));
      expect(studio.modelPopoverOpen, isTrue);
      expect(popover, findsOneWidget);
      expect(find.text('PHOTON LUMEN-1 · NEURAL RAY KERNEL'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('model-engine-uri'))).data, 'ws://127.0.0.1:8765');
      expect(find.text('RECONNECT'), findsOneWidget);
      for (final (id, title, detail) in [
        ('lite', 'LUMEN LITE', '64 SPP · 4 Bounces · Sub-8ms Viewport'),
        ('quick', 'LUMEN QUICK', '256 SPP · 12 Bounces · Real-Time OIDN'),
        ('pro', 'LUMEN PRO', '1024 SPP · 24 Bounces · Spectral Cauchy'),
      ]) {
        final card = find.byKey(Key('model-tier-$id'));
        expect(card, findsOneWidget, reason: id);
        expect(find.descendant(of: card, matching: find.text(title)), findsOneWidget, reason: title);
        expect(find.descendant(of: card, matching: find.text(detail)), findsOneWidget, reason: detail);
      }
      // Above the dock, not over it.
      expect(tester.getRect(popover).bottom, lessThan(tester.getRect(find.byKey(const ValueKey('dock-surface'))).top + 1));
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('picking a tier applies it, closes the popover and updates the badge', (tester) async {
      final socket = _RecordingSocket();
      final studio = StudioController(socket: socket, autoConnect: false, animateShader: false);
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      await _tapKey(tester, const Key('photon-model-btn'));
      await _pumpFor(tester, const Duration(milliseconds: 200));
      await _tapKey(tester, const Key('model-tier-pro'));
      await _pumpFor(tester, const Duration(milliseconds: 200));
      expect(studio.modelTier, PhotonModelTier.pro);
      expect(studio.targetSamples, 1024);
      expect(studio.maxBounces, 24);
      expect(studio.integrator, IntegratorMode.sppm);
      expect(popover, findsNothing);
      expect(find.descendant(of: chip, matching: find.text('PRO')), findsOneWidget);
      expect(find.text('Vulkan RT • 1024 SPP'), findsOneWidget, reason: 'the header follows');
      expect(socket.sent, contains(equals({'model': 'photon_lumen_1', 'tier': 'pro'})));

      await _tapKey(tester, const Key('photon-model-btn'));
      await _pumpFor(tester, const Duration(milliseconds: 200));
      await _tapKey(tester, const Key('model-tier-lite'));
      await _pumpFor(tester, const Duration(milliseconds: 200));
      expect(find.descendant(of: chip, matching: find.text('LITE')), findsOneWidget);
      expect(studio.targetSamples, 64);
      await _teardown(tester, studio);
    });

    testWidgets('RECONNECT reports the address; Escape and a click outside dismiss', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setModelPopoverOpen(true);
      await tester.pump();
      await _tapKey(tester, const Key('model-reconnect-btn'));
      await tester.pump();
      expect(studio.toast.value, 'RECONNECTING · ws://127.0.0.1:8765');
      expect(popover, findsOneWidget, reason: 'reconnecting leaves it open');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(popover, findsNothing);

      studio.setModelPopoverOpen(true);
      await tester.pump();
      await tester.tapAt(const Offset(20, 300));
      await tester.pump();
      expect(popover, findsNothing);
      await _teardown(tester, studio);
    });

    testWidgets('a connected studio really reconnects', (tester) async {
      final socket = _RecordingSocket();
      final studio = StudioController(socket: socket, autoConnect: true, animateShader: false);
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      expect([socket.connects, socket.disconnects], [1, 0]);
      studio.reconnectEngine();
      expect([socket.connects, socket.disconnects], [2, 1]);
      await _teardown(tester, studio);
    });

    testWidgets('the chip is reachable in the companion layout too, and nothing overflows', (tester) async {
      final studio = await _pumpStudio(tester, const Size(390, 844));
      await _tapKey(tester, const Key('photon-model-btn'));
      await _pumpFor(tester, const Duration(milliseconds: 200));
      expect(popover, findsOneWidget);
      await _tapKey(tester, const Key('model-tier-lite'));
      await _pumpFor(tester, const Duration(milliseconds: 200));
      expect(studio.modelTier, PhotonModelTier.lite);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the palette can open the selector', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setCommandPaletteOpen(true);
      await tester.pump();
      await _tapKey(tester, const Key('palette-action-model'));
      await tester.pump();
      expect(studio.modelPopoverOpen, isTrue);
      expect(studio.commandPaletteOpen, isFalse);
      await _teardown(tester, studio);
    });
  });

  group('optical probe', () {
    final pill = find.byKey(const Key('hud-wavelength-pill'));

    test('the probe is off by default, and on only when asked for', () {
      final s = StudioController(autoConnect: false, animateShader: false);
      addTearDown(s.dispose);
      expect(s.probeVisible, isFalse);
      s.setProbeVisible(true);
      expect(s.probeVisible, isTrue);
      s.setProbeVisible(false);
      expect(s.probeVisible, isFalse);
      s.toggleProbeVisible();
      expect(s.probeVisible, isTrue);
      var heard = 0;
      s.addListener(() => heard++);
      s.setProbeVisible(true);
      expect(heard, 0, reason: 'no change, no notification');
    });

    testWidgets('a fresh studio draws no probe: no ring, no readout, nothing spinning for it', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      expect(studio.probeVisible, isFalse);
      expect(pill, findsNothing);
      expect(_probeRing, findsNothing);
      expect(find.text('PROBE'), findsOneWidget, reason: 'the tool to turn it on is there');
      await _teardown(tester, studio);
    });

    testWidgets('the PROBE toggle sits with the other tools and shows, then hides, the green circle', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      for (final label in ['A/B WIPE', 'LOUPE', 'FALSE COLOR', 'LIVE SHADER', 'BVH / RAYS', 'PROBE']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      final probe = find.byKey(const Key('toggle-focus-probe'));
      expect(probe, findsOneWidget);
      // It follows BVH / RAYS in the strip.
      expect(tester.getTopLeft(probe).dx, greaterThan(tester.getTopLeft(find.byKey(const Key('toggle-bvh-rays'))).dx));

      await _tapKey(tester, const Key('toggle-focus-probe'));
      await tester.pump();
      expect(studio.probeVisible, isTrue);
      expect(pill, findsOneWidget);
      expect(_probeRing, findsOneWidget, reason: 'the ring');

      await _tapKey(tester, const Key('toggle-focus-probe'));
      await tester.pump();
      expect(studio.probeVisible, isFalse);
      expect(pill, findsNothing);
      expect(_probeRing, findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the × on the readout removes it at once, with a toast', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setProbeVisible(true);
      await tester.pump();
      expect(find.descendant(of: pill, matching: find.byKey(const Key('dismiss-probe-crosshair'))), findsOneWidget);
      await tester.tap(find.byKey(const Key('dismiss-probe-crosshair')));
      await tester.pump();
      expect(studio.probeVisible, isFalse);
      expect(studio.toast.value, 'OPTICAL PROBE HIDDEN');
      expect(pill, findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('tapping the readout still steps the wavelength; the × does not', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setProbeVisible(true);
      await tester.pump();
      final nm = studio.wavelengthNm;
      await tester.tapAt(tester.getTopLeft(pill) + const Offset(10, 8));
      await tester.pump();
      expect(studio.wavelengthNm, isNot(nm));
      expect(studio.probeVisible, isTrue);
      await _teardown(tester, studio);
    });

    testWidgets('the palette toggles it', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setCommandPaletteOpen(true);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('palette-action-probe')));
      expect(find.text('Toggle Optical Focus Probe'), findsOneWidget);
      await _tapKey(tester, const Key('palette-action-probe'));
      await tester.pump();
      expect(studio.probeVisible, isTrue);
      await _teardown(tester, studio);
    });

    testWidgets('a hidden probe does not spin: the ring stops with it', (tester) async {
      final studio = StudioController(autoConnect: false);
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      expect(_probeRing, findsNothing, reason: 'off by default: nothing is turning');
      studio.setProbeVisible(true);
      await tester.pump();
      double turns() => tester.widget<RotationTransition>(_probeRing).turns.value;
      final t0 = turns();
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(turns(), isNot(t0), reason: 'turning while it is shown');

      studio.setProbeVisible(false);
      await _pumpFor(tester, const Duration(milliseconds: 200));
      expect(_probeRing, findsNothing);
      studio.setProbeVisible(true);
      await _pumpFor(tester, const Duration(milliseconds: 200));
      expect(_probeRing, findsOneWidget);
      await _teardown(tester, studio);
    });
  });

  group('export pipeline', () {
    final modal = find.byKey(const Key('export-project-modal'));

    Directory tempDir() {
      final dir = Directory.systemTemp.createTempSync('photon_export_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      return dir;
    }

    Map<String, dynamic> decode(String json) => jsonDecode(json) as Map<String, dynamic>;

    test('EXPORT EXR offline stages the manifest, opens the sheet and says what is ready', () {
      final socket = _RecordingSocket()..online = false;
      final s = StudioController(socket: socket, autoConnect: false, animateShader: false, now: () => DateTime.utc(2026, 11, 5, 9, 30));
      addTearDown(s.dispose);
      expect(s.exportModalOpen, isFalse);
      expect(s.stagedManifest, isNull);

      s.exportExr();
      expect(s.exportModalOpen, isTrue);
      expect(s.toast.value, 'EXPORT READY · CAUSTIC_STUDY_04.exr');
      expect(socket.sent, isEmpty);
      final m = decode(s.stagedManifest!);
      expect(m['schema'], 'photon.scene/1');
      expect(m['exported_at'], '2026-11-05T09:30:00.000Z');
      expect((m['project'] as Map)['id'], 'caustic_study_04');
      expect((m['project'] as Map)['name'], 'CAUSTIC_STUDY_04');
      expect((m['model'] as Map)['tier'], 'quick');
      expect((m['model'] as Map)['name'], 'PHOTON LUMEN · QUICK');
      expect(m['integrator'], 'unidirectional');
      expect((m['optics'] as Map).keys, kOpticsParams.map((p) => p.id), reason: 'all six parameters');
      expect((m['optics'] as Map)['ior'], 2.253);
      expect((m['probe'] as Map)['wavelength_nm'], 540.0);
      expect((m['camera'] as Map)['zoom'], 1.0);
      expect(((m['camera'] as Map)['focus'] as Map).keys, ['x', 'y']);
      expect(m['snapshots'], isEmpty);
    });

    test('with the engine up it also sends the export request, and the manifest follows the studio', () {
      final socket = _RecordingSocket();
      final s = StudioController(socket: socket, autoConnect: false, animateShader: false);
      addTearDown(s.dispose);
      s.setModelTier(PhotonModelTier.pro);
      s.setParam('aperture', 2.8);
      s.setWavelengthNm(470);
      s.setCameraZoom(2);
      s.captureSnapshot();
      s.selectProject('volumetric_prism');
      socket.sent.clear();

      s.exportExr();
      expect(s.toast.value, 'EXR EXPORT REQUESTED · STUDIO MANIFEST READY');
      expect(socket.sent, hasLength(1));
      final request = socket.sent.single;
      expect(request['action'], 'export_exr');
      expect(request['project'], 'volumetric_prism');
      expect(request['model_tier'], 'pro');
      expect((request['params'] as Map)['ior'], 1.78);

      final m = decode(s.stagedManifest!);
      expect((m['project'] as Map)['id'], 'volumetric_prism');
      expect((m['model'] as Map)['tier'], 'pro');
      expect(m['integrator'], 'sppm');
      expect((m['probe'] as Map)['wavelength_nm'], 470.0);
      expect((m['camera'] as Map)['zoom'], 2.0);
      final takes = m['snapshots'] as List;
      expect(takes, hasLength(1));
      expect((takes.single as Map)['label'], 'TAKE 01');
      expect(((takes.single as Map)['params'] as Map)['aperture'], 2.8);
    });

    test('overlays are one at a time', () {
      final s = StudioController(autoConnect: false, animateShader: false);
      addTearDown(s.dispose);
      s.setAccountModalOpen(true);
      s.exportExr();
      expect(s.accountModalOpen, isFalse);
      expect(s.exportModalOpen, isTrue);
      s.setModelPopoverOpen(true);
      expect(s.exportModalOpen, isFalse);
      s.setIngestSheetOpen(true);
      expect(s.modelPopoverOpen, isFalse);
      s.setCommandPaletteOpen(true);
      expect(s.ingestSheetOpen, isFalse);
      s.setExportModalOpen(true);
      expect(s.commandPaletteOpen, isFalse);
      s.setExportModalOpen(false);
      expect(s.sceneAnimationPaused, isFalse);
    });

    testWidgets('the header button opens the sheet; it shows the project, tier and manifest', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      await _tapText(tester, 'EXPORT EXR');
      await tester.pump();
      expect(modal, findsOneWidget);
      expect(studio.exportModalOpen, isTrue);
      expect(find.text('EXPORT RENDER & SCENE'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('export-project-name'))).data, 'CAUSTIC_STUDY_04');
      expect(tester.widget<Text>(find.byKey(const Key('export-summary'))).data, 'PHOTON LUMEN · QUICK · UNIDIRECTIONAL PT · 256 SPP');
      expect(tester.widget<Text>(find.byKey(const Key('export-manifest-preview'))).data, contains('"schema": "photon.scene/1"'));
      expect(find.text('EXPORT .EXR / .PNG FRAME'), findsOneWidget);
      expect(find.text('EXPORT .PHT SCENE JSON'), findsOneWidget);
      expect(find.byKey(const Key('export-frame-btn')), findsOneWidget);
      expect(find.byKey(const Key('export-pht-btn')), findsOneWidget);
      expect(studio.toast.value, 'EXPORT READY · CAUSTIC_STUDY_04.exr');
      expect(tester.takeException(), isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(modal, findsNothing);
      studio.exportExr();
      await tester.pump();
      await tester.tapAt(const Offset(10, 400));
      await tester.pump();
      expect(modal, findsNothing, reason: 'a click outside closes it');
      studio.exportExr();
      await tester.pump();
      await tester.tap(find.byKey(const Key('export-close')));
      await tester.pump();
      expect(modal, findsNothing);
      await _teardown(tester, studio);
    });

    testWidgets('EXPORT .PHT SCENE JSON writes the manifest to disk and copies it', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final dir = tempDir();
      final studio = StudioController(autoConnect: false, animateShader: false, now: () => DateTime.utc(2026, 11, 5));
      studio.exportDirectoryOverride = dir;
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      studio.exportExr();
      await tester.pump();

      final path = await tester.runAsync(studio.exportSceneManifest);
      await tester.pump();
      expect(path, '${dir.path}${Platform.pathSeparator}CAUSTIC_STUDY_04.pht.json');
      final onDisk = File(path!).readAsStringSync();
      expect(decode(onDisk)['schema'], 'photon.scene/1');
      expect((decode(onDisk)['project'] as Map)['name'], 'CAUSTIC_STUDY_04');
      expect(copied, onDisk, reason: 'the clipboard holds the same manifest');
      expect(studio.toast.value, 'SCENE MANIFEST COPIED & SAVED');
      expect(studio.lastExportSummary, path);
      expect(tester.widget<Text>(find.byKey(const Key('export-saved-path'))).data, 'SAVED · $path');
      await _teardown(tester, studio);
    });

    testWidgets('a clipboard failure still saves the manifest', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') throw PlatformException(code: 'denied');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final studio = StudioController(autoConnect: false, animateShader: false)..exportDirectoryOverride = tempDir();
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      final path = await tester.runAsync(studio.exportSceneManifest);
      expect(File(path!).existsSync(), isTrue);
      expect(studio.toast.value, 'MANIFEST SAVED · CLIPBOARD UNAVAILABLE');
      await _teardown(tester, studio);
    });

    testWidgets('EXPORT .EXR / .PNG FRAME captures the live viewport at up to 4K', (tester) async {
      final dir = tempDir();
      final studio = StudioController(autoConnect: false, animateShader: false)..exportDirectoryOverride = dir;
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      final stage = tester.getSize(find.byKey(studio.viewportCaptureKey));

      final path = await tester.runAsync(studio.exportFrame);
      expect(path, '${dir.path}${Platform.pathSeparator}CAUSTIC_STUDY_04_4K_ACEScg.png');
      final bytes = File(path!).readAsBytesSync();
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: 'a PNG');
      final header = ByteData.sublistView(bytes);
      final width = header.getUint32(16), height = header.getUint32(20);
      expect(width, greaterThan(stage.width * 2), reason: 'rendered up, toward 3840 wide');
      expect(width, lessThanOrEqualTo(stage.width * 4 + 1));
      expect(width / height, closeTo(stage.width / stage.height, 0.02), reason: 'the stage\'s own proportions');
      expect(studio.toast.value, 'EXPORTED · CAUSTIC_STUDY_04_4K_ACEScg.png');
      expect(studio.lastExportSummary, path);
      await _teardown(tester, studio);
    });

    testWidgets('with no stage on screen the frame is the project\'s own image as a PNG', (tester) async {
      final dir = tempDir();
      final studio = StudioController(autoConnect: false, animateShader: false)..exportDirectoryOverride = dir;
      await tester.pumpWidget(const SizedBox.shrink());
      final path = await tester.runAsync(studio.exportFrame);
      final bytes = File(path!).readAsBytesSync();
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: 'the bundled JPEG, re-encoded');
      expect(ByteData.sublistView(bytes).getUint32(16), greaterThan(100));

      studio.startLocalFileIngest(filePath: '/x/tiny.png', bytes: _tinyPng, sizeMb: 0.1);
      studio.advanceUploadForTest(1.0);
      final tiny = await tester.runAsync(studio.exportFrame);
      expect(tiny, endsWith('TINY_4K_ACEScg.png'));
      expect(ByteData.sublistView(File(tiny!).readAsBytesSync()).getUint32(16), 1, reason: 'the uploaded image itself');
      studio.dispose();
    });

    testWidgets('the sheet\'s buttons write the frame and the manifest and report where', (tester) async {
      final dir = tempDir();
      final studio = StudioController(autoConnect: false, animateShader: false)..exportDirectoryOverride = dir;
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      studio.exportExr();
      await tester.pump();

      await _tapKey(tester, const Key('export-pht-btn'));
      for (var i = 0; i < 40 && studio.lastExportSummary == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
      await tester.pump();
      expect(File('${dir.path}${Platform.pathSeparator}CAUSTIC_STUDY_04.pht.json').existsSync(), isTrue);
      expect(find.byKey(const Key('export-saved-path')), findsOneWidget);

      studio.toast.value = null;
      await _tapKey(tester, const Key('export-frame-btn'));
      for (var i = 0; i < 100 && studio.toast.value != 'EXPORTED · CAUSTIC_STUDY_04_4K_ACEScg.png'; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
      await tester.pump();
      expect(File('${dir.path}${Platform.pathSeparator}CAUSTIC_STUDY_04_4K_ACEScg.png').existsSync(), isTrue);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('an unwritable folder is reported, not thrown', (tester) async {
      final studio = StudioController(autoConnect: false, animateShader: false)
        ..exportDirectoryOverride = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}photon_missing_${DateTime.now().microsecondsSinceEpoch}');
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      expect(await tester.runAsync(studio.exportSceneManifest), isNull);
      expect(studio.toast.value, startsWith('EXPORT FAILED'));
      expect(await tester.runAsync(studio.exportFrame), isNull);
      expect(studio.toast.value, startsWith('EXPORT FAILED'));
      await _teardown(tester, studio);
    });

    testWidgets('the palette exports too, and the sheet fits a narrow window', (tester) async {
      final studio = await _pumpStudio(tester, const Size(390, 844));
      studio.setCommandPaletteOpen(true);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('palette-action-export')));
      await _tapKey(tester, const Key('palette-action-export'));
      await tester.pump();
      expect(modal, findsOneWidget);
      expect(studio.commandPaletteOpen, isFalse);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });
  });

  group('idle, ticker and stutter audit', () {
    test('the theme switch has no repeating animation of any kind', () {
      final source = File('lib/widgets/shader_theme_switch.dart').readAsStringSync();
      expect(source.contains('_twinkle'), isFalse);
      expect(source.contains('.repeat('), isFalse);
      expect(source.contains('Timer'), isFalse);
      expect(source.contains('createTicker'), isFalse);
    });

    test('the only repeating animations are the ones that stop with their reason', () {
      // Every .repeat( in the app, and the guard that stops it.
      final repeats = <String, int>{};
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final n = RegExp(r'\.repeat\(').allMatches(f.readAsStringSync()).length;
        if (n > 0) repeats[f.uri.pathSegments.last] = n;
      }
      expect(repeats.keys.toSet(), {
        'photon_primitives.dart', // the pulsing pip: only while something is converging
        'progressive_flux_loader.dart', // the shimmer: only while a transfer shows
        'command_dock.dart', // the focus beam: only while the prompt has focus
        'mac_window_viewport.dart', // the probe ring: only while shown and uncovered
      });
      // A pulsing pip never rides on the engine link alone.
      final dock = File('lib/widgets/command_dock.dart').readAsStringSync();
      expect(dock.contains('FlashingPip'), isFalse, reason: 'the connected chip is steady');
      expect(File('lib/widgets/mac_window_viewport.dart').readAsStringSync().contains('FlashingPip'), isFalse);
    });

    testWidgets('a converged, idle studio schedules no frames and no timers', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      for (var i = 0; i < 500 && studio.tickerActive; i++) {
        studio.debugTick();
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(studio.converged, isTrue);
      expect(studio.tickerActive, isFalse, reason: 'the convergence timer is gone');
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'and nothing is asking for a frame');
      await _teardown(tester, studio);
    });

    testWidgets('an open account console is a still image, with the pointer on it or off', (tester) async {
      final studio = StudioController(autoConnect: false);
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      for (var i = 0; i < 500 && studio.tickerActive; i++) {
        studio.debugTick();
      }
      studio.setAccountModalOpen(true);
      await _pumpFor(tester, const Duration(milliseconds: 600));
      expect(studio.sceneAnimationPaused, isTrue);
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'no aurora, no scene, no ring while it is just open');

      final mouse = await _mouse(tester);
      await mouse.moveTo(tester.getCenter(find.byKey(const Key('animated-profile-card'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'and nothing moves while you are on it');
      await mouse.moveTo(const Offset(2, 2));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'or when you leave');
      await _teardown(tester, studio);
    });

    testWidgets('every overlay holds the live scene and the probe ring still, and releases them on close', (tester) async {
      final studio = StudioController(autoConnect: false);
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      studio.setProbeVisible(true); // the ring only exists, and turns, while the probe is on
      await tester.pump();
      ValueListenable<double> clock() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<ProceduralScenePainter>()
          .first
          .time;
      double ring() => tester.widget<RotationTransition>(_probeRing).turns.value;

      final opens = <String, (void Function(), void Function())>{
        'account': (() => studio.setAccountModalOpen(true), () => studio.setAccountModalOpen(false)),
        'palette': (() => studio.setCommandPaletteOpen(true), () => studio.setCommandPaletteOpen(false)),
        'ingest': (() => studio.setIngestSheetOpen(true), () => studio.setIngestSheetOpen(false)),
        'export': (() => studio.setExportModalOpen(true), () => studio.setExportModalOpen(false)),
        'model': (() => studio.setModelPopoverOpen(true), () => studio.setModelPopoverOpen(false)),
      };
      for (final entry in opens.entries) {
        final (open, close) = entry.value;
        open();
        await _pumpFor(tester, const Duration(milliseconds: 100));
        expect(studio.sceneAnimationPaused, isTrue, reason: entry.key);
        final held = clock().value, turned = ring();
        await _pumpFor(tester, const Duration(milliseconds: 400));
        expect(clock().value, held, reason: '${entry.key}: the scene holds');
        expect(ring(), turned, reason: '${entry.key}: the ring holds');

        close();
        await _pumpFor(tester, const Duration(milliseconds: 100));
        final resumed = clock().value;
        await _pumpFor(tester, const Duration(milliseconds: 400));
        expect(clock().value, greaterThan(resumed), reason: '${entry.key}: running again');
      }
      await _teardown(tester, studio);
    });

    testWidgets('the landing page stops its ticker the instant the studio is entered, by any route', (tester) async {
      final studio = StudioController(autoConnect: false, startInLandingPage: true);
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      double filmScale() => tester
          .widget<Transform>(find.descendant(of: find.byKey(const ValueKey('film-frame-0')), matching: find.byType(Transform)).first)
          .transform
          .entry(0, 0);
      final s0 = filmScale();
      await tester.pump(const Duration(milliseconds: 500));
      expect(filmScale(), greaterThan(s0), reason: 'the film pushes in while the page is up');

      studio.enterPhotonStudio();
      await tester.pump();
      final stopped = filmScale();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(filmScale(), stopped, reason: 'frozen for the 260ms it takes to fade, not creeping on');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('launch-hero-portal')), findsNothing);
      await _teardown(tester, studio);
    });

    testWidgets('dragging a deck print rebuilds the stage only, not the controls beside it', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setDeckView(true);
      await _pumpFor(tester, const Duration(milliseconds: 400));
      final counter = find.byKey(const Key('deck-counter'));
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('deck-top-card'))));
      await gesture.moveBy(const Offset(50, 0));
      // The pan's start rebuilds the deck once (the print lifts); every move
      // after that goes to the stage's notifier alone.
      await tester.pump(const Duration(milliseconds: 16));
      final before = tester.widget<Text>(counter);
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(6, 2));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(identical(tester.widget<Text>(counter), before), isTrue, reason: 'the counter was not rebuilt by the drag');
      await gesture.up();
      await _pumpFor(tester, const Duration(milliseconds: 900));
      await _teardown(tester, studio);
    });

    testWidgets('every deck print is its own layer and stays put while another is dragged', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setDeckView(true);
      await _pumpFor(tester, const Duration(milliseconds: 400));
      final deck = find.byKey(const Key('card-deck-carousel'));
      final boundaries = find.descendant(of: deck, matching: find.byType(RepaintBoundary));
      expect(boundaries.evaluate().length, greaterThanOrEqualTo(4), reason: 'one per visible print');
      await _teardown(tester, studio);
    });

    testWidgets('a studio at rest with the engine offline and every overlay closed is quiet at any size', (tester) async {
      for (final size in [const Size(1280, 800), const Size(390, 844), const Size(1000, 600)]) {
        final studio = await _pumpStudio(tester, size);
        for (var i = 0; i < 500 && studio.tickerActive; i++) {
          studio.debugTick();
        }
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.binding.hasScheduledFrame, isFalse, reason: '$size');
        expect(tester.takeException(), isNull, reason: '$size');
        await _teardown(tester, studio);
      }
    });
  });

  group('new project popup', () {
    final modal = find.byKey(const Key('new-project-modal'));
    final name = find.byKey(const Key('new-project-name'));
    final details = find.byKey(const Key('new-project-details'));
    final image = find.byKey(const Key('new-project-image'));
    final note = find.byKey(const Key('new-project-note'));

    Future<StudioController> openSheet(WidgetTester tester, {Size size = const Size(1280, 800)}) async {
      final studio = await _pumpStudio(tester, size);
      studio.setNewProjectSheetOpen(true);
      await tester.pump();
      return studio;
    }

    File tempImage(String fileName) {
      final dir = Directory.systemTemp.createTempSync('photon_new_');
      addTearDown(() => dir.deleteSync(recursive: true));
      return File('${dir.path}${Platform.pathSeparator}$fileName')..writeAsBytesSync(_tinyPng);
    }

    String noteText(WidgetTester tester) => tester.widget<Text>(note).data!;

    testWidgets('it asks for a name, details and an optional image, and starts empty', (tester) async {
      final studio = await openSheet(tester);
      expect(modal, findsOneWidget);
      expect(find.text('NEW PROJECT'), findsOneWidget);
      for (final label in ['PROJECT NAME', 'DETAILS (OPTIONAL)', 'IMAGE (OPTIONAL)', 'CREATE PROJECT', 'CANCEL', 'BROWSE...']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final field in [name, details, image]) {
        expect(tester.widget<TextField>(field).controller!.text, isEmpty, reason: 'nothing pre-filled');
      }
      expect(tester.widget<TextField>(name).focusNode!.hasFocus, isTrue, reason: 'ready to type the name');
      expect(noteText(tester), contains('NO IMAGE IS ADDED UNLESS YOU CHOOSE ONE'));
      // No picture of any kind inside the popup.
      expect(find.descendant(of: modal, matching: find.byType(Image)), findsNothing);
      expect(tester.getSize(modal).width, lessThanOrEqualTo(460));
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('a project needs a name: without one nothing is created', (tester) async {
      final studio = await openSheet(tester);
      await tester.enterText(details, 'Just some details');
      await _tapKey(tester, const Key('new-project-create'));
      await tester.pump();
      expect(noteText(tester), 'NAME YOUR PROJECT');
      expect(studio.projects, hasLength(5));
      expect(modal, findsOneWidget);

      await tester.enterText(name, '   ');
      await _tapKey(tester, const Key('new-project-create'));
      await tester.pump();
      expect(noteText(tester), 'NAME YOUR PROJECT', reason: 'spaces are not a name');
      expect(studio.projects, hasLength(5));

      await tester.enterText(name, 'A');
      await tester.pump();
      expect(noteText(tester), contains('STARTS BLANK'), reason: 'typing clears the complaint');
      await _teardown(tester, studio);
    });

    testWidgets('name and details alone make a blank project: no image in the list, the viewport or the deck', (tester) async {
      final studio = await openSheet(tester);
      await tester.enterText(name, 'Chronos Watch');
      await tester.enterText(details, 'A steel watch under a softbox.');
      await _tapKey(tester, const Key('new-project-create'));
      await tester.pump();

      final p = studio.activeProject!;
      expect(p.name, 'Chronos Watch');
      expect(p.description, 'A steel watch under a softbox.');
      expect(p.hasImage, isFalse);
      expect(studio.projects.first.id, p.id);
      expect(modal, findsNothing, reason: 'the popup closes');

      // The list card: a placeholder, not somebody else's picture.
      final card = find.byKey(ValueKey('project-${p.id}'));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.byType(Image)), findsNothing);
      expect(find.descendant(of: card, matching: find.byIcon(Icons.add_photo_alternate_outlined)), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('A steel watch under a softbox.')), findsOneWidget);

      // The viewport says so, and offers to fix it.
      await _pumpFor(tester, const Duration(milliseconds: 300));
      // (The A/B wipe draws the stage twice, so there are two of each.)
      expect(find.byKey(const Key('blank-project-stage')), findsWidgets);
      expect(find.text('NO IMAGE YET'), findsWidgets);
      expect(tester.widget<Text>(find.byKey(const Key('blank-project-about')).first).data, 'A steel watch under a softbox.');
      expect(find.byKey(const Key('blank-project-add-image')), findsWidgets);
      expect(find.byType(ProceduralSceneCanvas), findsNothing, reason: 'no simulation either');

      // And the deck.
      studio.setDeckView(true);
      await _pumpFor(tester, const Duration(milliseconds: 400));
      final top = find.byKey(const Key('deck-top-card'));
      expect(find.descendant(of: top, matching: find.byIcon(Icons.add_photo_alternate_outlined)), findsOneWidget);
      expect(find.descendant(of: top, matching: find.byType(Image)), findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the image the user picks is the only image: BROWSE fills the field, CREATE loads the file', (tester) async {
      final file = tempImage('hero shot.png');
      final studio = await openSheet(tester);
      studio.filePickerOverride = () async => file.path;
      await tester.enterText(name, 'Hero');
      await _tapKey(tester, const Key('new-project-browse'));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<TextField>(image).controller!.text, file.path);

      await _tapKey(tester, const Key('new-project-create'));
      await tester.pump();
      final p = studio.activeProject!;
      expect(p.hasImage, isTrue);
      expect(p.localFilePath, file.path);
      expect(p.customBytes, _tinyPng, reason: 'read from the chosen file');
      expect(p.previewAsset, kNoPreview);
      expect(p.sceneType, 'Local Image');
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.byKey(const Key('blank-project-stage')), findsNothing);
      expect(find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage && identical((w.image as MemoryImage).bytes, p.customBytes)), findsWidgets);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('a cancelled dialog changes nothing and leaves the field to type in', (tester) async {
      final studio = await openSheet(tester);
      studio.filePickerOverride = () async => null;
      await _tapKey(tester, const Key('new-project-browse'));
      await tester.pump();
      await tester.pump();
      expect(noteText(tester), 'NO FILE CHOSEN \u00b7 TYPE OR PASTE A PATH OR LINK');
      expect(tester.widget<TextField>(image).controller!.text, isEmpty);
      expect(tester.widget<TextField>(image).focusNode!.hasFocus, isTrue);
      await _teardown(tester, studio);
    });

    testWidgets('a typed path (quoted or not) or a link works; a bad one is reported and nothing is created', (tester) async {
      final file = tempImage('typed.PNG');
      final studio = await openSheet(tester);
      await tester.enterText(name, 'Typed');

      await tester.enterText(image, r'C:\nowhere\ghost.png');
      await _tapKey(tester, const Key('new-project-create'));
      await tester.pump();
      expect(noteText(tester), 'IMAGE NOT FOUND \u00b7 CHECK THE PATH OR LINK');
      expect(studio.projects, hasLength(5));

      final scene = tempImage('watch.usd');
      await tester.enterText(image, scene.path);
      await _tapKey(tester, const Key('new-project-create'));
      await tester.pump();
      expect(noteText(tester), 'NOT AN IMAGE \u00b7 USE .PNG .JPG .WEBP .BMP OR .GIF');
      expect(studio.projects, hasLength(5));

      await tester.enterText(image, '"${file.path}"');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(studio.projects, hasLength(6), reason: 'Enter in the image field creates too');
      expect(studio.activeProject!.localFilePath, file.path, reason: 'without the quotes');
      expect(studio.activeProject!.customBytes, _tinyPng);

      studio.setNewProjectSheetOpen(true);
      await tester.pump();
      await tester.enterText(name, 'Linked');
      await tester.enterText(image, '  https://cdn.example.com/shots/one.jpg  ');
      await _tapKey(tester, const Key('new-project-create'));
      await tester.pump();
      expect(studio.activeProject!.externalUrl, 'https://cdn.example.com/shots/one.jpg');
      expect(studio.activeProject!.customBytes, isNull);
      expect(studio.activeProject!.sceneType, 'Remote Image');
      await _teardown(tester, studio);
    });

    testWidgets('CANCEL, the close button, Escape and a click outside all leave without creating', (tester) async {
      final studio = await openSheet(tester);
      await tester.enterText(name, 'Never made');
      for (final close in [
        () => _tapKey(tester, const Key('new-project-cancel')),
        () => _tapKey(tester, const Key('new-project-close')),
        () => tester.sendKeyEvent(LogicalKeyboardKey.escape),
        () => tester.tapAt(const Offset(10, 400)),
      ]) {
        expect(modal, findsOneWidget);
        await close();
        await tester.pump();
        expect(modal, findsNothing);
        expect(studio.projects, hasLength(5));
        studio.setNewProjectSheetOpen(true);
        await tester.pump();
      }
      expect(tester.widget<TextField>(name).controller!.text, isEmpty, reason: 'a fresh form each time');
      await _teardown(tester, studio);
    });

    testWidgets('CHOOSE IMAGE on the empty viewport gives that project its picture', (tester) async {
      final file = tempImage('later.png');
      final studio = await openSheet(tester);
      await tester.enterText(name, 'Later');
      await _tapKey(tester, const Key('new-project-create'));
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.byKey(const Key('blank-project-stage')), findsWidgets);

      studio.filePickerOverride = () async => file.path;
      // (The A/B wipe's curtain and HUD sit over the stage, so press the button
      // by its own handler rather than by pointer.)
      tester.widget<GestureDetector>(find.byKey(const Key('blank-project-add-image')).last).onTap!();
      for (var i = 0; i < 20 && !studio.activeProject!.hasImage; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      }
      await tester.pump();
      expect(studio.activeProject!.hasImage, isTrue);
      expect(studio.activeProject!.customBytes, _tinyPng);
      expect(studio.toast.value, 'IMAGE ADDED \u00b7 Later');
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.byKey(const Key('blank-project-stage')), findsNothing);

      // A file that is not an image is refused, with a reason.
      studio.createNewProject('Second');
      await _pumpFor(tester, const Duration(milliseconds: 300));
      final scene = tempImage('watch.usd');
      studio.filePickerOverride = () async => scene.path;
      expect(await tester.runAsync(studio.chooseImageForActiveProject), isFalse);
      expect(studio.toast.value, 'CHOOSE AN IMAGE (.PNG, .JPG, .WEBP, .BMP, .GIF)');
      expect(studio.activeProject!.hasImage, isFalse);
      studio.filePickerOverride = () async => null;
      expect(await tester.runAsync(studio.chooseImageForActiveProject), isFalse);
      expect(tester.takeException(), isNull);
      await _teardown(tester, studio);
    });

    testWidgets('the popup fits a narrow window and a short one', (tester) async {
      var studio = await openSheet(tester, size: const Size(390, 844));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(modal).width, lessThanOrEqualTo(390));
      await _teardown(tester, studio);
      studio = await openSheet(tester, size: const Size(1000, 460));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(modal).height, lessThanOrEqualTo(460));
      await tester.ensureVisible(find.byKey(const Key('new-project-create')));
      await _teardown(tester, studio);
    });
  });

  group('workspace switching', () {
    Finder segment(String label) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label && w.properties.button == true);
    bool selected(WidgetTester tester, String label) => tester.widget<Semantics>(segment(label).first).properties.selected == true;

    test('selectWorkspaceLayout sets the panel and leaves the deck in one notification', () {
      final s = StudioController(autoConnect: false, animateShader: false, startInDeckView: true);
      addTearDown(s.dispose);
      var heard = 0;
      s.addListener(() => heard++);
      s.selectWorkspaceLayout('viewport');
      expect([s.deckView, s.maximizedPanel], [false, 'viewport']);
      expect(heard, 1, reason: 'one frame, one notification');
      s.setDeckView(true);
      s.selectWorkspaceLayout(null);
      expect([s.deckView, s.maximizedPanel], [false, null]);
      s.setDeckView(true);
      s.selectWorkspaceLayout('optics');
      expect([s.deckView, s.maximizedPanel], [false, 'optics']);
      s.setDeckView(true);
      s.selectWorkspaceLayout('account');
      expect(s.accountModalOpen, isTrue, reason: 'the account has one home');
      expect(s.deckView, isTrue, reason: 'opening the console is not a layout switch');
    });

    for (final entry in {'SPLIT': null, 'VIEWPORT': 'viewport', 'OPTICS': 'optics'}.entries) {
      testWidgets('clicking ${entry.key} while the deck is open leaves the deck', (tester) async {
        final studio = await _pumpStudio(tester, const Size(1280, 800));
        studio.setDeckView(true);
        await _pumpFor(tester, const Duration(milliseconds: 400));
        expect(find.byKey(const Key('deck-top-card')), findsOneWidget);
        expect(selected(tester, 'DECK'), isTrue);

        await tester.tap(find.byWidgetPredicate((w) => w is Text && w.data == entry.key).first);
        await tester.pump();
        expect(studio.deckView, isFalse, reason: 'never stuck behind the deck scrim');
        expect(studio.maximizedPanel, entry.value);
        expect(selected(tester, 'DECK'), isFalse);
        expect(selected(tester, entry.key), isTrue, reason: 'the layout highlights in the same frame');
        await _pumpFor(tester, const Duration(milliseconds: 300));
        expect(find.byKey(const Key('deck-top-card')), findsNothing);
        expect(tester.takeException(), isNull);
        await _teardown(tester, studio);
      });
    }

    testWidgets('opening a print from the deck de-selects DECK and highlights VIEWPORT in one frame', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      studio.setDeckView(true);
      await _pumpFor(tester, const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('deck-top-card')));
      await tester.pump();
      expect(selected(tester, 'DECK'), isFalse);
      expect(selected(tester, 'VIEWPORT'), isTrue);
      expect(selected(tester, 'SPLIT'), isFalse);
      await _teardown(tester, studio);
    });
  });

  group('Lusion colour harmonisation', () {
    test('no pre-Lusion purple or rose is left in the widgets', () {
      final legacy = ['0xFF8A2BE2', '0xFFB57BFF', '0xFFFF2D78', '0xFFDCB8FF', '0xFFEFDBFF', '0xFF0E0E10'];
      // The procedural scenes keep their own spectral artwork palette.
      const artwork = {'procedural_scene_canvas.dart'};
      for (final f in Directory('lib/widgets').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        if (artwork.contains(f.uri.pathSegments.last)) continue;
        final source = f.readAsStringSync();
        for (final hex in legacy) {
          expect(source.contains(hex), isFalse, reason: '$hex in ${f.uri.pathSegments.last}');
        }
      }
    });

    test('the flux loader, rays and loupe clip use Lusion tokens', () {
      expect(ProgressiveFluxLoader.fluxColors, [const Color(0xFF1A2FFB), const Color(0xFF6878FF), const Color(0xFFFF4C41), const Color(0xFF22D3EE)]);
      expect(IreScale.clip, const Color(0xFFFF4C41));
    });

    testWidgets('the account avatar is Electric Blue to Hot Coral, in both themes', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      List<Color> avatar() => tester
          .widgetList<Container>(find.descendant(of: find.byKey(const Key('profile-card-trigger')), matching: find.byType(Container)))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.gradient)
          .whereType<LinearGradient>()
          .first
          .colors;
      expect(avatar(), [const Color(0xFF1A2FFB), const Color(0xFFFF4C41)]);
      await _setTheme(tester, dark: false);
      await tester.pump();
      expect(avatar(), [const Color(0xFF1A2FFB), const Color(0xFFFF4C41)]);
      await _teardown(tester, studio);
    });

    testWidgets('the QUICK badge lifts to periwinkle on the dark dock and stays Electric Blue on the light one', (tester) async {
      final studio = await _pumpStudio(tester, const Size(1280, 800));
      Color badge() => tester.widget<Text>(find.descendant(of: find.byKey(const Key('model-tier-badge')), matching: find.byType(Text))).style!.color!;
      expect(studio.modelTier, PhotonModelTier.quick);
      expect(badge(), const Color(0xFF6878FF));
      await _setTheme(tester, dark: false);
      await tester.pump();
      expect(badge(), const Color(0xFF1A2FFB));
      studio.setModelTier(PhotonModelTier.pro);
      await tester.pump();
      expect(badge(), const Color(0xFFFF4C41));
      await _teardown(tester, studio);
    });

    testWidgets('the launch button glows Electric Blue; the beam is blue, cyan, white and coral', (tester) async {
      final studio = StudioController(autoConnect: false, animateShader: false, startInLandingPage: true);
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      final glow = tester
          .widgetList<AnimatedContainer>(find.descendant(of: find.byKey(const Key('take-me-to-photon-btn')), matching: find.byType(AnimatedContainer)))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .expand((d) => d.boxShadow ?? const <BoxShadow>[])
          .first;
      expect(glow.color.toARGB32() & 0xFFFFFF, 0x1A2FFB);
      final source = File('lib/widgets/launch_hero_portal.dart').readAsStringSync();
      for (final hex in ['0xFF6878FF', '0xFF22D3EE', '0xFFFF4C41']) {
        expect(source, contains(hex), reason: hex);
      }
      await _teardown(tester, studio);
    });

    testWidgets('the portal hands over to the studio on an eased lens pull', (tester) async {
      final studio = StudioController(autoConnect: false, animateShader: false, startInLandingPage: true);
      await _pumpStudio(tester, const Size(1280, 800), controller: studio);
      final switcher = tester.widget<AnimatedSwitcher>(find.byWidgetPredicate((w) => w is AnimatedSwitcher && w.duration == const Duration(milliseconds: 260)));
      expect(switcher.switchInCurve, Curves.easeOutCubic);
      expect(switcher.switchOutCurve, Curves.easeInOutCubic);
      studio.enterPhotonStudio();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('launch-hero-portal')), findsNothing, reason: 'still gone within the same 260ms');
      await _teardown(tester, studio);
    });
  });
}
