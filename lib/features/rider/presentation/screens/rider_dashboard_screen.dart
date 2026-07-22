import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../domain/entities/rider_profile_entity.dart';
import '../providers/rider_providers.dart';

class RiderDashboardScreen extends ConsumerWidget {
  const RiderDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riderAsync = ref.watch(myRiderProvider);
    final statsAsync = ref.watch(riderStatsProvider);
    final shiftState = ref.watch(shiftControllerProvider);
    final profile = ref.watch(authStateProvider).valueOrNull;

    ref.listen(myRiderProvider, (previous, next) {
      final broadcaster = ref.read(locationBroadcastProvider);
      final isOnShift = next.valueOrNull?.isOnShift ?? false;
      if (isOnShift && !broadcaster.isActive) {
        broadcaster.start();
      } else if (!isOnShift && broadcaster.isActive) {
        broadcaster.stop();
      }
    });

    // `ref.listen` only fires on changes — cover cold-open too.
    final currentRider = riderAsync.valueOrNull;
    if (currentRider != null) {
      final broadcaster = ref.read(locationBroadcastProvider);
      if (currentRider.isOnShift && !broadcaster.isActive) {
        broadcaster.start();
      } else if (!currentRider.isOnShift && broadcaster.isActive) {
        broadcaster.stop();
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myRiderProvider);
            ref.invalidate(riderStatsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              riderAsync.when(
                loading: () => Container(
                  height: 210,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                error: (e, _) => ErrorStateView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(myRiderProvider),
                ),
                data: (rider) => _RiderShiftHero(
                  rider: rider,
                  ownerName: profile?.fullName,
                  isToggling: shiftState.isLoading,
                  onToggle: (value) =>
                      ref.read(shiftControllerProvider.notifier).toggleShift(value),
                ),
              ),
              const SizedBox(height: 22),
              const _SectionHeader(
                icon: Icons.query_stats_rounded,
                label: 'Your Performance',
                subtitle: 'Deliveries, ratings & COD status',
              ),
              const SizedBox(height: 12),
              statsAsync.when(
                loading: () => _statsSkeleton(),
                error: (e, _) => ErrorStateView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(riderStatsProvider),
                ),
                data: (stats) => Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _StatTile(
                            icon: Icons.local_shipping_rounded,
                            label: 'Deliveries Today',
                            value: '${stats.todaysDeliveries}',
                            gradient: AppColors.primaryGradient,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatTile(
                            icon: Icons.workspace_premium_rounded,
                            label: 'Total Deliveries',
                            value: '${stats.totalDeliveries}',
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFB443), Color(0xFFFF7A00)],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _StatTile(
                            icon: Icons.star_rounded,
                            label: 'Rating',
                            value: stats.rating.toStringAsFixed(1),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF9F7BFF), Color(0xFF7C5CFF)],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatTile(
                            icon: Icons.account_balance_wallet_rounded,
                            label: 'COD Collected',
                            value: stats.totalCodCollected.toCurrency,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF64B5F6), Color(0xFF2196F3)],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _CodBalanceCard(
                      outstanding: stats.codOutstanding,
                      pendingVerification: stats.codPendingVerification,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _ActiveDeliveriesCTA(
                onTap: () => context.pushNamed(RouteNames.riderActiveDeliveries),
              ),
              const SizedBox(height: 12),
              _PendingPaymentsCTA(
                onTap: () => context.pushNamed(RouteNames.riderPendingPayments),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsSkeleton() {
    return Column(
      children: List.generate(
        2,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: List.generate(
              2,
              (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 0 ? 12 : 0),
                  child: Container(
                    height: 110,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RiderShiftHero extends StatelessWidget {
  final RiderProfileEntity rider;
  final String? ownerName;
  final bool isToggling;
  final ValueChanged<bool> onToggle;

  const _RiderShiftHero({
    required this.rider,
    required this.ownerName,
    required this.isToggling,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final linked = rider.vendorName != null;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFC96B),
            Color(0xFFFF9A2E),
            Color(0xFFF06E0F),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppShadows.brand(color: const Color(0xFFFF9A2E), opacity: 0.35),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Decorative rings.
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            right: 40,
            bottom: -30,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.two_wheeler_rounded,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ownerName?.isNotEmpty == true
                                ? 'Hey, ${ownerName!.split(' ').first}'
                                : 'Delivery Rider',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            linked
                                ? 'Delivering for ${rider.vendorName}'
                                : 'Not linked to a vendor yet',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: rider.isOnShift
                              ? const Color(0xFF6EE7A0)
                              : Colors.white.withValues(alpha: 0.55),
                          boxShadow: rider.isOnShift
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF6EE7A0)
                                        .withValues(alpha: 0.7),
                                    blurRadius: 8,
                                  )
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rider.isOnShift ? 'On Shift' : 'Off Shift',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              rider.isOnShift
                                  ? 'Broadcasting your live location'
                                  : linked
                                      ? 'Toggle on to start receiving deliveries'
                                      : 'Link with a vendor to go on shift',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      isToggling
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Switch(
                              value: rider.isOnShift,
                              onChanged: linked ? onToggle : null,
                              activeTrackColor: Colors.white,
                              activeThumbColor: const Color(0xFFF06E0F),
                              inactiveTrackColor:
                                  Colors.white.withValues(alpha: 0.25),
                              inactiveThumbColor: Colors.white,
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Gradient gradient;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.roleRider.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColors.roleRider, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveDeliveriesCTA extends StatelessWidget {
  final VoidCallback onTap;
  const _ActiveDeliveriesCTA({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppShadows.brand(opacity: 0.32),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.route_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active Deliveries',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Navigate, confirm pickup, complete drop-offs',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _CodBalanceCard extends StatelessWidget {
  final double outstanding;
  final double pendingVerification;
  const _CodBalanceCard({required this.outstanding, required this.pendingVerification});

  @override
  Widget build(BuildContext context) {
    final hasOutstanding = outstanding > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasOutstanding ? const Color(0xFFFFF7ED) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasOutstanding ? const Color(0xFFFFE0B2) : const Color(0xFFA5D6A7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (hasOutstanding ? const Color(0xFFFF8F00) : const Color(0xFF43A047))
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  hasOutstanding ? Icons.account_balance_wallet_rounded : Icons.check_circle_rounded,
                  color: hasOutstanding ? const Color(0xFFFF8F00) : const Color(0xFF43A047),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasOutstanding ? 'COD Outstanding' : 'All Settled',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: hasOutstanding ? const Color(0xFFE65100) : const Color(0xFF2E7D32),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      outstanding.toCurrency,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: hasOutstanding ? const Color(0xFFE65100) : const Color(0xFF2E7D32),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (pendingVerification > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded, size: 16, color: Color(0xFFFF8F00)),
                  const SizedBox(width: 8),
                  Text(
                    'Pending verification: ${pendingVerification.toCurrency}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF8F00),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingPaymentsCTA extends StatelessWidget {
  final VoidCallback onTap;
  const _PendingPaymentsCTA({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFC96B), Color(0xFFFF9A2E), Color(0xFFF06E0F)],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppShadows.brand(opacity: 0.32),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.payments_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Collect Pending Payments',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Collect debt from customers on your orders',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
