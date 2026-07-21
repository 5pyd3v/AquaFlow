import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/misc/app_nav_shell.dart';
import '../../../orders/presentation/screens/order_history_screen.dart';
import '../providers/catalog_providers.dart';
import 'account_screen.dart';
import 'customer_catalog_screen.dart';
import 'favorites_screen.dart';

/// Bottom-nav host for the four customer tabs. The shared [AppNavShell]
/// owns tab state (via IndexedStack) and the back-button behaviour.
class CustomerShellScreen extends ConsumerWidget {
  const CustomerShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppNavShell(
      indicatorColor: AppColors.primary.withValues(alpha: 0.12),
      onTabChanged: (index) {
        if (index == 0) {
          ref.read(productListProvider.notifier).refresh();
        }
      },
      tabs: const [
        CustomerCatalogScreen(),
        OrderHistoryScreen(),
        FavoritesScreen(),
        AccountScreen(),
      ],
      destinations: const [
        AppNavDestination(icon: Icons.storefront_outlined, selectedIcon: Icons.storefront_rounded, label: 'Shop'),
        AppNavDestination(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long_rounded, label: 'Orders'),
        AppNavDestination(icon: Icons.favorite_border_rounded, selectedIcon: Icons.favorite_rounded, label: 'Favorites'),
        AppNavDestination(icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: 'Account'),
      ],
    );
  }
}
