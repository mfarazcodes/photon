import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photon/main.dart';

Future<void> pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('Photon studio boots, toggles gravity and opens windows',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PhotonApp());
    await pumpFrames(tester, 5);

    expect(find.text('PHOTON VFX STUDIO®'), findsOneWidget);
    expect(find.text('PHOTON_ENGINE_V3.4'), findsOneWidget);
    expect(find.text('LIQUID_MORPH.vfx'), findsOneWidget);
    expect(find.text('EXPLORE'), findsOneWidget);

    // Gravity on: icons fall; gravity off: they spring back to the grid.
    await tester.tap(find.text('Gravity'));
    await pumpFrames(tester, 40);
    await tester.tap(find.text('Gravity'));
    await pumpFrames(tester, 150);

    // Clicking a shader node opens its viewport window.
    await tester.tap(find.text('CHROME_SHADER.frag'));
    await pumpFrames(tester, 30);
    expect(find.text('CHROME_SHADER.FRAG'), findsOneWidget);

    // The explore dock morphs into the menu.
    await tester.tap(find.text('EXPLORE'));
    await pumpFrames(tester, 40);
    expect(find.text('RECENT RENDERS'), findsOneWidget);
  });
}
