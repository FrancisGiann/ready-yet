import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentInk,
    required this.sky,
    required this.lilac,
    required this.peach,
    required this.isDark,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent;
  final Color accentInk;
  final Color sky;
  final Color lilac;
  final Color peach;
  final bool isDark;

  @override
  AppColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? ink,
    Color? muted,
    Color? line,
    Color? accent,
    Color? accentInk,
    Color? sky,
    Color? lilac,
    Color? peach,
    bool? isDark,
  }) => AppColors(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    accent: accent ?? this.accent,
    accentInk: accentInk ?? this.accentInk,
    sky: sky ?? this.sky,
    lilac: lilac ?? this.lilac,
    peach: peach ?? this.peach,
    isDark: isDark ?? this.isDark,
  );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      sky: Color.lerp(sky, other.sky, t)!,
      lilac: Color.lerp(lilac, other.lilac, t)!,
      peach: Color.lerp(peach, other.peach, t)!,
      isDark: t < .5 ? isDark : other.isDark,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}

const _accentColors = <Color>[
  Color(0xFFD4F56A),
  Color(0xFFA9D8E8),
  Color(0xFFCAB9E7),
];

ThemeData createAppTheme({required bool dark, required int accentIndex}) {
  final accent = _accentColors[accentIndex.clamp(0, _accentColors.length - 1)];
  final colors = AppColors(
    canvas: dark ? const Color(0xFF101B18) : const Color(0xFFF6F5EF),
    surface: dark ? const Color(0xFF182521) : const Color(0xFFFFFFFF),
    surfaceRaised: dark ? const Color(0xFF202F29) : const Color(0xFFECEDE4),
    ink: dark ? const Color(0xFFF3F2E9) : const Color(0xFF172623),
    // Keep secondary copy readable on both the porcelain canvas and raised cards.
    muted: dark ? const Color(0xFFACB8B1) : const Color(0xFF5F6C66),
    line: dark ? const Color(0xFF33433C) : const Color(0xFFE1E4DA),
    accent: accent,
    accentInk: const Color(0xFF172623),
    sky: dark ? const Color(0xFF293D43) : const Color(0xFFDCEEF0),
    lilac: dark ? const Color(0xFF393347) : const Color(0xFFE8E1F1),
    peach: dark ? const Color(0xFF483A32) : const Color(0xFFF2E4D8),
    isDark: dark,
  );
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: dark ? Brightness.dark : Brightness.light,
    surface: colors.surface,
    primary: colors.ink,
    onPrimary: colors.surface,
    secondary: accent,
    onSecondary: colors.accentInk,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.canvas,
    extensions: <ThemeExtension<dynamic>>[colors],
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
    textTheme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light)
        .textTheme
        .apply(bodyColor: colors.ink, displayColor: colors.ink)
        .copyWith(
          headlineLarge: TextStyle(
            fontSize: 36,
            height: 1.02,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.8,
            color: colors.ink,
          ),
          headlineMedium: TextStyle(
            fontSize: 30,
            height: 1.08,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.1,
            color: colors.ink,
          ),
          titleLarge: TextStyle(
            fontSize: 19,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -.35,
            color: colors.ink,
          ),
          bodyLarge: TextStyle(fontSize: 16, height: 1.35, color: colors.ink),
          bodyMedium: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: colors.muted,
          ),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colors.ink,
          ),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.canvas,
      foregroundColor: colors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF2C3A34) : const Color(0xFF172623),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

Color accentSwatch(int index) =>
    _accentColors[index.clamp(0, _accentColors.length - 1)];
