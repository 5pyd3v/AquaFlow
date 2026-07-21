import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../domain/entities/vendor_entity.dart';
import '../providers/vendor_providers.dart';

class VendorDashboardScreen extends ConsumerWidget {
  const VendorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorAsync = ref.watch(myVendorProvider);
    final statsAsync = ref.watch(vendorStatsProvider);
    final profile = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myVendorProvider);
            ref.invalidate(vendorStatsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
            children: [
              vendorAsync.when(
                loading: () => const _HeaderSkeleton(),
                error: (e, _) => ErrorStateView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(myVendorProvider),
                ),
                data: (vendor) => _VendorHero(
                  vendor: vendor,
                  ownerName: profile?.fullName,
                ),
              ),
              const SizedBox(height: 18),
              const _SectionHeader(
                icon: Icons.insights_rounded,
                label: "Today's Performance",
              ),
              const SizedBox(height: 10),
              statsAsync.when(
                loading: () => const _StatsSkeleton(),
                error: (e, _) => ErrorStateView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(vendorStatsProvider),
                ),
                data: (stats) => _StatsGrid(
                  tiles: [
                    _StatTileData(
                      icon: Icons.receipt_long_rounded,
                      label: 'Orders',
                      value: '${stats.todaysOrders}',
                      gradient: AppColors.primaryGradient,
                    ),
                    _StatTileData(
                      icon: Icons.payments_rounded,
                      label: 'Revenue',
                      value: stats.todaysRevenue.toCurrency,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF34D399), Color(0xFF10B981)],
                      ),
                    ),
                    _StatTileData(
                      icon: Icons.hourglass_top_rounded,
                      label: 'Pending',
                      value: '${stats.pendingOrders}',
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFB443), Color(0xFFFF7A00)],
                      ),
                      pulse: stats.pendingOrders > 0,
                    ),
                    _StatTileData(
                      icon: Icons.check_circle_rounded,
                      label: 'Completed',
                      value: '${stats.completedOrders}',
                      gradient: const LinearGradient(
                        colors: [Color(0xFF60A5FA), Color(0xFF3B82F6)],
                      ),
                    ),
                    _StatTileData(
                      icon: Icons.inventory_2_rounded,
                      label: 'Products',
                      value: '${stats.totalProducts}',
                      gradient: const LinearGradient(
                        colors: [Color(0xFF64B5F6), Color(0xFF2196F3)],
                      ),
                    ),
                    _StatTileData(
                      icon: Icons.warning_amber_rounded,
                      label: 'Low Stock',
                      value: '${stats.lowStockProducts}',
                      gradient: stats.lowStockProducts > 0
                          ? const LinearGradient(
                              colors: [Color(0xFFFF7B7B), Color(0xFFE53935)],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFFBDBDBD), Color(0xFF9E9E9E)],
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const _SectionHeader(
                icon: Icons.rocket_launch_rounded,
                label: 'Quick Actions',
              ),
              const SizedBox(height: 10),
              _QuickActionsGrid(
                actions: [
                  _QuickActionData(
                    icon: Icons.person_add_alt_1_rounded,
                    label: 'Add Customer',
                    subtitle: 'Register & generate PIN',
                    tint: const Color(0xFF7C5CFF),
                    onTap: () => context.pushNamed(RouteNames.vendorCreateCustomer),
                  ),
                  _QuickActionData(
                    icon: Icons.people_alt_rounded,
                    label: 'Customers',
                    subtitle: 'View & manage',
                    tint: const Color(0xFF26A69A),
                    onTap: () => context.pushNamed(RouteNames.vendorCustomers),
                  ),
                  _QuickActionData(
                    icon: Icons.two_wheeler_rounded,
                    label: 'My Riders',
                    subtitle: 'Link & manage riders',
                    tint: AppColors.roleRider,
                    onTap: () => context.pushNamed(RouteNames.vendorRiders),
                  ),
                  _QuickActionData(
                    icon: Icons.map_rounded,
                    label: 'Live Map',
                    subtitle: 'Real-time tracking',
                    tint: const Color(0xFF10B981),
                    onTap: () => context.pushNamed(RouteNames.vendorLiveMap),
                  ),
                  _QuickActionData(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Receive COD',
                    subtitle: 'Rider settlement code',
                    tint: const Color(0xFFE65100),
                    onTap: () => context.pushNamed(RouteNames.vendorReceiveCod),
                  ),
                  _QuickActionData(
                    icon: Icons.account_balance_rounded,
                    label: 'Finances',
                    subtitle: 'KPIs, ledgers & cash',
                    tint: const Color(0xFF2196F3),
                    onTap: () => context.pushNamed(RouteNames.vendorFinanceDashboard),
                  ),
                  _QuickActionData(
                    icon: Icons.receipt_long_rounded,
                    label: 'Settlements',
                    subtitle: 'COD settlement history',
                    tint: const Color(0xFF00897B),
                    onTap: () => context.pushNamed(RouteNames.vendorSettlements),
                  ),
                  _QuickActionData(
                    icon: Icons.inventory_rounded,
                    label: 'Products',
                    subtitle: 'Manage catalog',
                    tint: const Color(0xFFFF6B6B),
                    onTap: () => context.pushNamed(RouteNames.vendorProducts),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero — compact gradient header with vendor ID badge
// ---------------------------------------------------------------------------
class _VendorHero extends StatelessWidget {
  final VendorEntity vendor;
  final String? ownerName;
  const _VendorHero({required this.vendor, this.ownerName});

  @override
  Widget build(BuildContext context) {
    final isProfileIncomplete = vendor.businessName == null || vendor.businessName!.isEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF9E85FF),
            Color(0xFF7C5CFF),
            Color(0xFF5B3EDB),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.brand(color: const Color(0xFF7C5CFF), opacity: 0.35),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -24,
            top: -24,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isProfileIncomplete ? 'Complete your profile' : vendor.businessName!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ownerName != null && ownerName!.isNotEmpty
                              ? 'Managed by $ownerName'
                              : 'Business Account',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _StatusPill(status: vendor.status.label, color: _statusColor(vendor.status.label)),
                ],
              ),
              const SizedBox(height: 14),
              // Vendor ID badge — copyable
              _VendorIdBadge(vendorId: vendor.id),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    _MiniMetric(
                      icon: Icons.star_rounded,
                      value: vendor.rating.toStringAsFixed(1),
                      label: 'Rating',
                    ),
                    _VerticalDivider(),
                    _MiniMetric(
                      icon: Icons.local_shipping_rounded,
                      value: '${vendor.totalOrders}',
                      label: 'Orders',
                    ),
                    _VerticalDivider(),
                    _MiniMetric(
                      icon: Icons.location_on_rounded,
                      value: '${vendor.deliveryRadiusKm.toStringAsFixed(0)}km',
                      label: 'Radius',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('active') || lower.contains('approved')) return const Color(0xFF10B981);
    if (lower.contains('pending')) return const Color(0xFFFFB443);
    if (lower.contains('suspend') || lower.contains('reject')) return const Color(0xFFE53935);
    return Colors.white;
  }
}

// ---------------------------------------------------------------------------
// Vendor ID badge — tappable to copy
// ---------------------------------------------------------------------------
class _VendorIdBadge extends StatelessWidget {
  final String vendorId;
  const _VendorIdBadge({required this.vendorId});

  @override
  Widget build(BuildContext context) {
    final short = vendorId.length > 8 ? '${vendorId.substring(0, 8)}...' : vendorId;
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: vendorId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vendor ID copied to clipboard')),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge_rounded, color: Colors.white.withValues(alpha: 0.85), size: 14),
            const SizedBox(width: 6),
            Text(
              'Vendor ID: $short',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.copy_rounded, color: Colors.white.withValues(alpha: 0.7), size: 12),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  final Color color;
  const _StatusPill({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 9.5,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _MiniMetric({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 13),
              const SizedBox(width: 3),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      color: Colors.white.withValues(alpha: 0.18),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header — compact
// ---------------------------------------------------------------------------
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary, size: 15),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stats grid — compact 3-column layout
// ---------------------------------------------------------------------------
class _StatTileData {
  final IconData icon;
  final String label;
  final String value;
  final Gradient gradient;
  final bool pulse;
  const _StatTileData({
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
    this.pulse = false,
  });
}

class _StatsGrid extends StatelessWidget {
  final List<_StatTileData> tiles;
  const _StatsGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.95,
      children: tiles.map((t) => _StatTile(data: t)).toList(),
    );
  }
}

class _StatTile extends StatelessWidget {
  final _StatTileData data;
  const _StatTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: data.gradient,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(data.icon, color: Colors.white, size: 16),
              ),
              if (data.pulse) const _PulseDot(),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.value,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                data.label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final scale = 1.0 + _c.value * 0.6;
        final opacity = (1.0 - _c.value).clamp(0.0, 1.0);
        return SizedBox(
          width: 16,
          height: 16,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: opacity * 0.35),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: AppColors.warning, shape: BoxShape.circle),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions grid — compact 3-column
// ---------------------------------------------------------------------------
class _QuickActionData {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color tint;
  final VoidCallback onTap;
  const _QuickActionData({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.tint,
    required this.onTap,
  });
}

class _QuickActionsGrid extends StatelessWidget {
  final List<_QuickActionData> actions;
  const _QuickActionsGrid({required this.actions});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.85,
      children: actions.map((a) => _QuickActionTile(data: a)).toList(),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final _QuickActionData data;
  const _QuickActionTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.card,
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: data.tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(data.icon, color: data.tint, size: 18),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.label,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      data.subtitle,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeletons
// ---------------------------------------------------------------------------
class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.95,
      children: List.generate(
        6,
        (_) => Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
