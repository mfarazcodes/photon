import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Spacing scale from DESIGN.md (4px baseline rhythm).
abstract final class PhotonSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

/// Radius language from DESIGN.md.
abstract final class PhotonRadius {
  /// Inputs, micro-buttons, scrubbers.
  static const double control = 4;

  /// Floating windows and sheets (0.5rem).
  static const double window = 8;

  /// HUD capsules and status badges.
  static const double pill = 9999;
}

/// Colour tokens. One instance per studio mode; read them through
/// `context.photon.colors`.
@immutable
class PhotonPalette {
  const PhotonPalette({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.substrate,
    required this.carbon,
    required this.onCarbon,
    required this.violet,
    required this.violetInk,
    required this.rose,
    required this.border,
    required this.textMuted,
    required this.ghost,
    required this.hoverFill,
    required this.dock,
    required this.onDock,
    required this.viewportMatte,
    required this.shadow,
  });

  final Brightness brightness;

  /// Cyclorama base: the master canvas behind every window.
  final Color canvas;
  final Color surface;

  /// Floating windows, inspector panels, HUD capsules.
  final Color substrate;

  /// Matte Carbon: primary ink and the primary action fill.
  final Color carbon;
  final Color onCarbon;

  /// Spectral Violet fills, tracks and borders.
  final Color violet;

  /// Spectral Violet when used as text; lifted in dark mode for contrast.
  final Color violetInk;

  /// Caustic Rose: clipping, ray-limit and thermal states.
  final Color rose;

  /// Border Structural: 1px hairlines.
  final Color border;
  final Color textMuted;

  /// Telemetry Ghost: inactive guides and slider tracks.
  final Color ghost;
  final Color hoverFill;

  /// Command dock background (Matte Carbon in daylight mode).
  final Color dock;
  final Color onDock;

  /// Neutral surround behind the render. Mid-gray in dark grading mode.
  final Color viewportMatte;
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  /// Primary ink as plain text colour.
  Color get ink => carbon;

  /// Daylight Cyclorama: the High-Key Daylight Laboratory aesthetic.
  static const PhotonPalette daylight = PhotonPalette(
    brightness: Brightness.light,
    canvas: Color(0xFFF3F3F5),
    surface: Color(0xFFF9F9FB),
    substrate: Color(0xFFFFFFFF),
    carbon: Color(0xFF0E0E10),
    onCarbon: Color(0xFFFFFFFF),
    violet: Color(0xFF8A2BE2),
    violetInk: Color(0xFF8A2BE2),
    rose: Color(0xFFFF2D78),
    border: Color(0xFFE2E2E6),
    textMuted: Color(0xFF6E6E76),
    ghost: Color(0xFFA5A5AE),
    hoverFill: Color(0xFFEAEAEF),
    dock: Color(0xFF0E0E10),
    onDock: Color(0xFFFFFFFF),
    viewportMatte: Color(0xFF0E0E10),
    shadow: Color(0xFF0E0E10),
  );

  /// Dark Studio (the default): charcoal canvas, architectural panels, and a
  /// neutral mid-gray matte around the render.
  static const PhotonPalette grading = PhotonPalette(
    brightness: Brightness.dark,
    canvas: Color(0xFF18191C),
    surface: Color(0xFF1E1F22),
    substrate: Color(0xFF141417),
    carbon: Color(0xFFF3F3F5),
    onCarbon: Color(0xFF0E0E10),
    violet: Color(0xFF8A2BE2),
    violetInk: Color(0xFFB57BFF),
    rose: Color(0xFFFF2D78),
    border: Color(0xFF2A2B30),
    textMuted: Color(0xFF9A9AA4),
    ghost: Color(0xFF55555E),
    hoverFill: Color(0xFF25262B),
    dock: Color(0xFF101012),
    onDock: Color(0xFFF3F3F5),
    viewportMatte: Color(0xFF767679),
    shadow: Color(0xFF000000),
  );
}

/// Typography tokens, bound to a palette so text colours follow the theme.
@immutable
class PhotonType {
  const PhotonType(this.colors);

  final PhotonPalette colors;

  static const _tabular = <FontFeature>[FontFeature.tabularFigures()];

  /// Geist for studio controls, headers and prose.
  TextStyle ui({
    double size = 12,
    FontWeight weight = FontWeight.w400,
    double height = 1.5,
    double tracking = 0,
    Color? color,
  }) => GoogleFonts.geist(
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: size * tracking,
    color: color ?? colors.carbon,
  );

  /// JetBrains Mono with tabular figures: every number in the studio goes
  /// through this so counters never jitter while converging.
  TextStyle mono({
    double size = 11,
    FontWeight weight = FontWeight.w400,
    double height = 1.4,
    double tracking = 0,
    Color? color,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: size * tracking,
    color: color ?? colors.carbon,
    fontFeatures: _tabular,
  );

  // Geist scale.
  TextStyle get headlineMd => ui(size: 20, weight: FontWeight.w500, height: 26 / 20, tracking: -0.02);
  TextStyle get headlineSm => ui(size: 15, weight: FontWeight.w500, height: 20 / 15, tracking: -0.01);
  TextStyle get bodyLg => ui(size: 14, height: 22 / 14, tracking: -0.01);
  TextStyle get bodyMd => ui(size: 12, height: 18 / 12, tracking: -0.005);
  TextStyle get bodySm => ui(size: 11, height: 16 / 11);
  TextStyle get buttonLabel => ui(size: 12, weight: FontWeight.w500, height: 1.2);

  // JetBrains Mono scale.
  TextStyle get telemetryLg => mono(size: 13, weight: FontWeight.w500, height: 18 / 13, tracking: -0.02);
  TextStyle get telemetryMd => mono(size: 11, height: 15 / 11, tracking: -0.01);
  TextStyle get telemetrySm => mono(size: 10, height: 13 / 10);
  TextStyle get labelCaps => mono(
    size: 9,
    weight: FontWeight.w600,
    height: 12 / 9,
    tracking: 0.08,
    color: colors.textMuted,
  );
}

/// Theme extension carrying the studio tokens.
@immutable
class PhotonTokens extends ThemeExtension<PhotonTokens> {
  PhotonTokens(this.colors) : text = PhotonType(colors);

  final PhotonPalette colors;
  final PhotonType text;

  /// Level 2: floating palettes and tool windows.
  List<BoxShadow> get level2 => [
    BoxShadow(
      color: colors.shadow.withValues(alpha: colors.isDark ? 0.35 : 0.04),
      blurRadius: 20,
      spreadRadius: -2,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: colors.shadow.withValues(alpha: colors.isDark ? 0.25 : 0.02),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];

  /// Caustic Active Glow: sharp violet micro-halo for selection and drops.
  List<BoxShadow> get causticGlow => [
    BoxShadow(color: colors.violet, spreadRadius: 1),
    BoxShadow(
      color: colors.violet.withValues(alpha: 0.35),
      blurRadius: 12,
      spreadRadius: -2,
    ),
  ];

  @override
  PhotonTokens copyWith({PhotonPalette? colors}) => PhotonTokens(colors ?? this.colors);

  @override
  PhotonTokens lerp(ThemeExtension<PhotonTokens>? other, double t) {
    if (other is! PhotonTokens) return this;
    return t < 0.5 ? this : other;
  }
}

extension PhotonThemeContext on BuildContext {
  PhotonTokens get photon => Theme.of(this).extension<PhotonTokens>()!;
}

/// Builds the Material [ThemeData] for a studio mode.
ThemeData buildPhotonTheme(PhotonPalette p) {
  final tokens = PhotonTokens(p);
  final base = ThemeData(
    brightness: p.brightness,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.violet,
      brightness: p.brightness,
    ).copyWith(
      primary: p.carbon,
      onPrimary: p.onCarbon,
      secondary: p.violet,
      tertiary: p.rose,
      surface: p.substrate,
      onSurface: p.carbon,
      outline: p.border,
    ),
    scaffoldBackgroundColor: p.canvas,
    canvasColor: p.canvas,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: p.hoverFill,
    dividerColor: p.border,
    extensions: [tokens],
  );
  final type = tokens.text;
  return base.copyWith(
    // Built from individual Geist styles: GoogleFonts.geistTextTheme returns a
    // material_ui TextTheme, which ThemeData.textTheme does not accept.
    textTheme: base.textTheme.copyWith(
      headlineMedium: type.headlineMd,
      titleMedium: type.headlineSm,
      titleSmall: type.bodyMd.copyWith(fontWeight: FontWeight.w500),
      bodyLarge: type.bodyLg,
      bodyMedium: type.bodyMd,
      bodySmall: type.bodySm,
      labelLarge: type.buttonLabel,
      labelMedium: type.labelCaps,
      labelSmall: type.labelCaps,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.carbon,
        borderRadius: BorderRadius.circular(PhotonRadius.control),
      ),
      textStyle: tokens.text.telemetrySm.copyWith(color: p.onCarbon),
      waitDuration: const Duration(milliseconds: 400),
    ),
  );
}
