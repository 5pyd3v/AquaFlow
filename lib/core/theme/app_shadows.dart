import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Soft, layered shadows for the modern UI. Deliberately low-alpha and
/// tinted toward the brand ink (not pure black) so cards lift off the
/// background without the heavy grey drop-shadow that dates an app.
class AppShadows {
  AppShadows._();

  /// Resting elevation for cards and tiles.
  static List<BoxShadow> get card => [
        BoxShadow(
          color: const Color(0xFF0A2A36).withValues(alpha: 0.04),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: const Color(0xFF0A2A36).withValues(alpha: 0.03),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  /// Slightly lifted — used for primary CTAs / focused surfaces.
  static List<BoxShadow> get raised => [
        BoxShadow(
          color: const Color(0xFF0A2A36).withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ];

  /// Colored glow beneath brand-colored elements (hero header, FAB).
  /// Pass [color] to tint the glow toward a role-specific accent
  /// (e.g. vendor violet, rider amber); defaults to the primary teal.
  static List<BoxShadow> brand({Color? color, double opacity = 0.28}) => [
        BoxShadow(
          color: (color ?? AppColors.primary).withValues(alpha: opacity),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
      ];
}
