import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/dialogs/confirm_sign_out_dialog.dart';
import '../../../../shared/widgets/misc/gradient_hero_header.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GradientHeroHeader(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  child: Text(
                    (profile?.fullName.isNotEmpty == true ? profile!.fullName[0] : '?').toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile?.fullName ?? 'AquaFlow User',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                      const SizedBox(height: 4),
                      Text(profile?.phone ?? profile?.email ?? '',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              children: [
                _MenuTile(
                  icon: Icons.location_on_outlined,
                  label: 'My Addresses',
                  onTap: () => context.pushNamed(RouteNames.addressList),
                ),
                const _TileDivider(),
                _MenuTile(
                  icon: Icons.receipt_long_outlined,
                  label: 'Order History',
                  onTap: () => context.pushNamed(RouteNames.orderHistory),
                ),
                const _TileDivider(),
                _MenuTile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Wallet',
                  onTap: () => context.pushNamed(RouteNames.customerWallet),
                ),
                const _TileDivider(),
                const _MenuTile(icon: Icons.local_offer_outlined, label: 'Coupons', isComingSoon: true),
                const _TileDivider(),
                const _MenuTile(icon: Icons.support_agent_outlined, label: 'Help & Support', isComingSoon: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: _MenuTile(
              icon: Icons.logout_rounded,
              label: 'Sign Out',
              iconColor: AppColors.error,
              textColor: AppColors.error,
              onTap: () => _confirmSignOut(context, ref),
            ),
          ),
          const SizedBox(height: 20),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? AppConfig.appVersion;
              return Center(
                child: Text('${AppConfig.appName} v$version',
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
              );
            },
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showSignOutConfirmDialog(
      context,
      message: 'You can sign back in anytime with the same phone number or email.',
      onConfirm: () => ref.read(authControllerProvider.notifier).signOut(),
    );
  }
}

class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 56, endIndent: 12, color: AppColors.border);
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? textColor;
  final bool isComingSoon;

  const _MenuTile({
    required this.icon,
    required this.label,
    this.onTap,
    this.iconColor,
    this.textColor,
    this.isComingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (iconColor ?? AppColors.primary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor ?? AppColors.primary, size: 20),
      ),
      title: Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
      trailing: isComingSoon
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(20)),
              child: const Text('Soon', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
            )
          : const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
      onTap: isComingSoon ? null : onTap,
    );
  }
}
