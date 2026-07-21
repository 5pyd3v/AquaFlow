import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';

/// Premium brand header used at the top of primary screens. A rounded
/// gradient panel with soft floating "bubble" accents (a nod to water),
/// a colored glow beneath it, and a flexible content slot. This is the
/// piece that replaces the flat "username on a plain bar" look.
class GradientHeroHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final double borderRadius;

  const GradientHeroHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 22, 20, 24),
    this.gradient,
    this.borderRadius = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: AppShadows.brand(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient ?? AppColors.brandGradient,
          ),
          child: Stack(
            children: [
              // Decorative water "bubbles" — subtle, clipped to the panel.
              Positioned(
                top: -28,
                right: -18,
                child: _bubble(96, 0.10),
              ),
              Positioned(
                top: 34,
                right: 52,
                child: _bubble(20, 0.14),
              ),
              Positioned(
                bottom: -34,
                left: -20,
                child: _bubble(88, 0.07),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}
