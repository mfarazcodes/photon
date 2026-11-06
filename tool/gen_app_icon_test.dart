// Regenerates windows/runner/resources/app_icon.ico from the exact drawing the
// app uses (PhotonLogoPainter), so the taskbar and titlebar icon always match
// the in-app mark.
//
//     flutter test tool/gen_app_icon_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photon/widgets/photon_primitives.dart';

/// The frames in the .ico, smallest first.
const List<int> kIconSizes = [16, 32, 48, 256];

Future<Uint8List> _png(int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const PhotonLogoPainter().paint(canvas, Size.square(size.toDouble()));
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Packs PNG frames into an ICO container (PNG-compressed entries).
Uint8List buildIco(Map<int, Uint8List> frames) {
  final sizes = frames.keys.toList()..sort();
  final headerLength = 6 + 16 * sizes.length;
  final total = headerLength + frames.values.fold<int>(0, (sum, f) => sum + f.length);
  final out = ByteData(total);
  out.setUint16(0, 0, Endian.little); // reserved
  out.setUint16(2, 1, Endian.little); // type: icon
  out.setUint16(4, sizes.length, Endian.little);
  var offset = headerLength;
  for (var i = 0; i < sizes.length; i++) {
    final size = sizes[i];
    final png = frames[size]!;
    final entry = 6 + 16 * i;
    out.setUint8(entry, size >= 256 ? 0 : size); // 0 means 256
    out.setUint8(entry + 1, size >= 256 ? 0 : size);
    out.setUint8(entry + 2, 0); // palette colours
    out.setUint8(entry + 3, 0);
    out.setUint16(entry + 4, 1, Endian.little); // colour planes
    out.setUint16(entry + 6, 32, Endian.little); // bits per pixel
    out.setUint32(entry + 8, png.length, Endian.little);
    out.setUint32(entry + 12, offset, Endian.little);
    offset += png.length;
  }
  final bytes = out.buffer.asUint8List();
  offset = headerLength;
  for (final size in sizes) {
    final png = frames[size]!;
    bytes.setRange(offset, offset + png.length, png);
    offset += png.length;
  }
  return bytes;
}

void main() {
  testWidgets('writes windows/runner/resources/app_icon.ico', (tester) async {
    final ico = await tester.runAsync(() async {
      final frames = <int, Uint8List>{for (final size in kIconSizes) size: await _png(size)};
      return buildIco(frames);
    });
    File('windows/runner/resources/app_icon.ico').writeAsBytesSync(ico!);
    expect(ico.length, greaterThan(1000));

    // A 256px preview, and a 16px one scaled up, for a quick look (build/ is
    // not committed).
    final previews = await tester.runAsync(() async => {'logo': await _png(256), 'logo_16': await _png(16)});
    Directory('build').createSync(recursive: true);
    previews!.forEach((name, png) => File('build/$name.png').writeAsBytesSync(png));
  });
}
