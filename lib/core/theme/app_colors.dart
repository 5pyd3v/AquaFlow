import 'package:flutter/material.dart';

/// AquaFlow brand palette.
///
/// Primary is a deep aqua/teal (trust, water, cleanliness) paired with
/// a warm amber accent for CTAs — deliberately not another
/// green-delivery-app clone.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF0A6E8C);
  static const Color primaryDark = Color(0xFF054F66);
  static const Color primaryLight = Color(0xFF3E9CBB);
  static const Color secondary = Color(0xFFFFA531);
  static const Color secondaryDark = Color(0xFFE0870F);

  // Neutrals
  static const Color background = Color(0xFFF7FAFB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEFF4F6);
  static const Color border = Color(0xFFE2E9EC);
  static const Color divider = Color(0xFFEBEFF1);

  // Text
  static const Color textPrimary = Color(0xFF16232A);
  static const Color textSecondary = Color(0xFF5C6D74);
  static const Color textTertiary = Color(0xFF93A3A9);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Semantic
  static const Color success = Color(0xFF1FAA6D);
  static const Color successBg = Color(0xFFE5F7EE);
  static const Color warning = Color(0xFFF5A623);
  static const Color warningBg = Color(0xFFFDF2E1);
  static const Color error = Color(0xFFE5484D);
  static const Color errorBg = Color(0xFFFCEBEC);
  static const Color info = Color(0xFF3E9CBB);
  static const Color infoBg = Color(0xFFE7F5F9);

  // Order status timeline colours
  static const Color statusPreparing = Color(0xFF93A3A9);
  static const Color statusAccepted = Color(0xFF3E9CBB);
  static const Color statusAssigned = Color(0xFF0A6E8C);
  static const Color statusPickedUp = Color(0xFFFFA531);
  static const Color statusOnTheWay = Color(0xFFF5A623);
  static const Color statusDelivered = Color(0xFF1FAA6D);
  static const Color statusCancelled = Color(0xFFE5484D);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, primary],
  );

  /// Richer three-stop brand gradient for hero headers — reads as a
  /// premium teal wash rather than a flat two-tone fill.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF11809E), Color(0xFF0A6E8C), Color(0xFF054F66)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0A6E8C), Color(0xFF072E3B)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFB552), secondary],
  );

  static const LinearGradient shimmerGradient = LinearGradient(
    begin: Alignment(-1.0, -0.3),
    end: Alignment(1.0, 0.3),
    colors: [
      Color(0xFFEFF4F6),
      Color(0xFFE2E9EC),
      Color(0xFFEFF4F6),
    ],
  );

  // Role accent colors (used for role-badges / dashboard theming)
  static const Color roleCustomer = primary;
  static const Color roleVendor = Color(0xFF7C5CFF);
  static const Color roleRider = Color(0xFFFFA531);
  static const Color roleAdmin = Color(0xFF16232A);
}
