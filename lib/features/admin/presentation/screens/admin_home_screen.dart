import 'package:flutter/material.dart';
import '../../../../core/constants/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/misc/dashboard_shell_scaffold.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DashboardShellScaffold(
      role: UserRole.admin,
      accent: AppColors.roleAdmin,
      modules: [
        DashboardModule(
          icon: Icons.query_stats_rounded,
          title: 'Company-Wide Analytics',
          subtitle: 'Revenue graphs, heat maps, live monitoring',
        ),
        DashboardModule(
          icon: Icons.storefront_outlined,
          title: 'Vendor Management',
          subtitle: 'Approve, suspend, and audit vendors',
        ),
        DashboardModule(
          icon: Icons.two_wheeler_outlined,
          title: 'Rider Management',
          subtitle: 'Onboard riders and monitor live locations',
        ),
        DashboardModule(
          icon: Icons.campaign_outlined,
          title: 'Broadcasts & CMS',
          subtitle: 'Announcements, offers, and content pages',
        ),
      ],
    );
  }
}
