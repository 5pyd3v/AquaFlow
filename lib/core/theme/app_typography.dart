import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Centralised text theme built on Poppins. The font files are
/// bundled locally (`assets/fonts/`, declared in `pubspec.yaml`) —
/// deliberately not fetched via the `google_fonts` package, which
/// downloads font files over the network at runtime and would either
/// flash unstyled text or throw console errors on Chrome the moment
/// the network is slow, offline, or restricted (e.g. corporate/school
/// wifi blocking fonts.gstatic.com). Bundling means the exact same
/// font renders identically and instantly on every platform,
/// including a fresh `flutter run -d chrome` with no network calls.
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Poppins';

  static TextTheme get textTheme => TextTheme(
        displayLarge: _StylePresets.displayLarge,
        displayMedium: _StylePresets.displayMedium,
        displaySmall: _StylePresets.displaySmall,
        headlineLarge: _StylePresets.headlineLarge,
        headlineMedium: _StylePresets.headlineMedium,
        headlineSmall: _StylePresets.headlineSmall,
        titleLarge: _StylePresets.titleLarge,
        titleMedium: _StylePresets.titleMedium,
        titleSmall: _StylePresets.titleSmall,
        bodyLarge: _StylePresets.bodyLarge,
        bodyMedium: _StylePresets.bodyMedium,
        bodySmall: _StylePresets.bodySmall,
        labelLarge: _StylePresets.labelLarge,
        labelMedium: _StylePresets.labelMedium,
        labelSmall: _StylePresets.labelSmall,
      );
}

class _StylePresets {
  _StylePresets._();

  static const _base = TextStyle(
    fontFamily: AppTypography.fontFamily,
    color: AppColors.textPrimary,
  );

  static final displayLarge = _base.copyWith(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2);
  static final displayMedium = _base.copyWith(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2);
  static final displaySmall = _base.copyWith(fontSize: 21, fontWeight: FontWeight.w700, height: 1.25);
  static final headlineLarge = _base.copyWith(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3);
  static final headlineMedium = _base.copyWith(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3);
  static final headlineSmall = _base.copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.35);
  static final titleLarge = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4);
  static final titleMedium = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4);
  static final titleSmall = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w600, height: 1.4);
  static final bodyLarge = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w400, height: 1.5);
  static final bodyMedium = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400, height: 1.5);
  static final bodySmall = _base.copyWith(fontSize: 11.5, fontWeight: FontWeight.w400, height: 1.5);
  static final labelLarge = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3);
  static final labelMedium = _base.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.3);
  static final labelSmall = _base.copyWith(fontSize: 10.5, fontWeight: FontWeight.w500, height: 1.3);
}
