import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/misc/app_nav_shell.dart';
import 'vendor_account_screen.dart';
import 'vendor_dashboard_screen.dart';
import 'vendor_orders_screen.dart';
import 'vendor_products_screen.dart';

class VendorShellScreen extends StatelessWidget {
  const VendorShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppNavShell(
      indicatorColor: AppColors.roleVendor.withValues(alpha: 0.12),
      tabs: const [
        VendorDashboardScreen(),
        VendorOrdersScreen(),
        VendorProductsScreen(),
        VendorAccountScreen(),
      ],
      destinations: const [
        AppNavDestination(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard_rounded, label: 'Dashboard'),
        AppNavDestination(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long_rounded, label: 'Orders'),
        AppNavDestination(icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2_rounded, label: 'Products'),
        AppNavDestination(icon: Icons.storefront_outlined, selectedIcon: Icons.storefront_rounded, label: 'Account'),
      ],
    );
  }
}
