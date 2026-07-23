import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// The bordered, rounded-square back-arrow button shared by every auth
/// screen's top bar. Only the tap callback varies per screen (some pop
/// via `Navigator.maybePop`, others via go_router's `context.pop()`),
/// so that's the one thing left as a parameter.
class BackIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  const BackIconButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 20),
      ),
    );
  }
}
