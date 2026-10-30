import 'package:flutter/material.dart';

/// Photon studio palette. Every surface in the app pulls from here.
class PC {
  PC._();

  // Flat, faintly warm grey sampled from the reference desktop.
  static const canvasTop = Color(0xFFEDEBEC);
  static const canvasBottom = Color(0xFFEDEBEC);
  static const ink = Color(0xFF0A0A0A);
  static const inkSoft = Color(0xFF3A3A3A);
  static const muted = Color(0xFF7A7A7A);
  static const hairline = Color(0xFFE0E0E0);
  static const window = Color(0xFFF8F8F8);
  static const white = Color(0xFFFFFFFF);
  static const blue = Color(0xFF2563EB);
  static const blueSoft = Color(0xFFDBE6FD);
  static const dock = Color(0xFF0A0A0A);
  static const dockRaised = Color(0xFF181818);
  static const archive = Color(0xFF050505);
  static const archiveMuted = Color(0xFF666666);

  static const red = Color(0xFFE5564A);
  static const amber = Color(0xFFF0B43C);
  static const green = Color(0xFF35C15A);

  static const indigo = Color(0xFF312E81);
  static const violet = Color(0xFF5B21B6);
  static const purple = Color(0xFF7C3AED);
  static const magenta = Color(0xFFD946EF);
  static const cyan = Color(0xFF22D3EE);
  static const pink = Color(0xFFFF6FB5);
  static const orange = Color(0xFFFF5A1F);

  static const List<BoxShadow> floatShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> windowShadow = [
    BoxShadow(color: Color(0x22000000), blurRadius: 60, offset: Offset(0, 24)),
    BoxShadow(color: Color(0x10000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
}

/// Photon type ramp: tracked-out uppercase sans for chrome, mono for data.
class PT {
  PT._();

  static const sansFamily = 'Segoe UI';
  static const monoFamily = 'Consolas';
  static const _monoFallback = ['Cascadia Mono', 'Courier New', 'monospace'];

  static TextStyle label({
    double size = 15,
    Color color = PC.ink,
    FontWeight weight = FontWeight.w500,
    double spacing = 0.2,
    double height = 1.2,
  }) =>
      TextStyle(
        fontFamily: sansFamily,
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: spacing,
        height: height,
      );

  static TextStyle mono({
    double size = 13,
    Color color = PC.ink,
    FontWeight weight = FontWeight.w500,
    double spacing = 0.4,
  }) =>
      TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: _monoFallback,
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: spacing,
        height: 1.25,
      );

  static TextStyle display({
    double size = 56,
    Color color = PC.ink,
    FontWeight weight = FontWeight.w800,
  }) =>
      TextStyle(
        fontFamily: sansFamily,
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: -size * 0.035,
        height: 0.98,
      );

  static TextStyle body({double size = 16, Color color = PC.muted}) =>
      TextStyle(
        fontFamily: sansFamily,
        fontSize: size,
        color: color,
        height: 1.45,
        fontWeight: FontWeight.w400,
      );
}

ThemeData photonTheme() {
  return ThemeData(
    useMaterial3: true,
    fontFamily: PT.sansFamily,
    scaffoldBackgroundColor: PC.canvasTop,
    colorScheme: ColorScheme.fromSeed(
      seedColor: PC.blue,
      brightness: Brightness.light,
      primary: PC.blue,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: PC.blue,
      selectionColor: Color(0x332563EB),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(4),
      radius: const Radius.circular(4),
      thumbColor: WidgetStateProperty.all(const Color(0x33000000)),
    ),
  );
}
