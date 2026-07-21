import 'package:flutter/material.dart';
import '../../../core/constants/user_role.dart';
import '../../../core/theme/app_colors.dart';

class RoleBadge extends StatelessWidget {
  final UserRole role;
  const RoleBadge({super.key, required this.role});

  Color get _color => switch (role) {
        UserRole.customer => AppColors.roleCustomer,
        UserRole.vendor => AppColors.roleVendor,
        UserRole.rider => AppColors.roleRider,
        UserRole.admin || UserRole.superAdmin => AppColors.roleAdmin,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        role.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}
