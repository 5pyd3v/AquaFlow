import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Shared "Sign out?" confirmation — identical chrome across the
/// customer/vendor/rider account screens, only the body message and
/// the sign-out action differ per role.
void showSignOutConfirmDialog(
  BuildContext context, {
  required String message,
  required VoidCallback onConfirm,
}) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Sign out?'),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onConfirm();
          },
          child: const Text('Sign Out', style: TextStyle(color: AppColors.error)),
        ),
      ],
    ),
  );
}
