import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/misc/app_nav_shell.dart';
import '../../../settlements/presentation/screens/rider_cod_wallet_screen.dart';
import 'rider_account_screen.dart';
import 'rider_active_deliveries_screen.dart';
import 'rider_dashboard_screen.dart';
import 'rider_history_screen.dart';

class RiderShellScreen extends StatelessWidget {
  const RiderShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppNavShell(
      indicatorColor: AppColors.roleRider.withValues(alpha: 0.12),
      tabs: const [
        RiderDashboardScreen(),
        RiderActiveDeliveriesScreen(),
        RiderCodWalletScreen(),
        RiderHistoryScreen(),
        RiderAccountScreen(),
      ],
      destinations: const [
        AppNavDestination(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard_rounded, label: 'Dashboard'),
        AppNavDestination(icon: Icons.local_shipping_outlined, selectedIcon: Icons.local_shipping_rounded, label: 'Deliveries'),
        AppNavDestination(icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet_rounded, label: 'Wallet'),
        AppNavDestination(icon: Icons.history_rounded, selectedIcon: Icons.history_rounded, label: 'History'),
        AppNavDestination(icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: 'Account'),
      ],
    );
  }
}
