import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../domain/entities/rider_cash_position_entity.dart';
import '../../domain/entities/vendor_finance_kpis_entity.dart';
import '../providers/payment_providers.dart';

/// The vendor's complete financial overview: headline KPIs, per-rider
/// cash reconciliation, and jump-off points to per-customer ledgers and
/// pending payment amendments.
class VendorFinanceDashboardScreen extends ConsumerWidget {
  const VendorFinanceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpisAsync = ref.watch(vendorFinanceKpisProvider);
    final ridersAsync = ref.watch(vendorRiderCashPositionsProvider);
    final amendmentsAsync = ref.watch(vendorAmendmentRequestsProvider);

    final pendingApprovals = amendmentsAsync.maybeWhen(
      data: (list) => list.where((a) => a.status.name == 'pending').length,
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Finances')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(vendorFinanceKpisProvider);
          ref.invalidate(vendorRiderCashPositionsProvider);
          ref.invalidate(vendorPaymentOverviewProvider);
          ref.invalidate(vendorAmendmentRequestsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _quickLinks(context, pendingApprovals),
            const SizedBox(height: 20),
            Text('Overview', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            kpisAsync.when(
              loading: () => const _KpiSkeleton(),
              error: (e, _) => ErrorStateView(
                message: e.toString(),
                onRetry: () => ref.invalidate(vendorFinanceKpisProvider),
              ),
              data: (kpis) => _KpiGrid(kpis: kpis),
            ),
            const SizedBox(height: 24),
            Text('Cash held by riders', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Collected minus settled = cash still on the road.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 12),
            ridersAsync.when(
              loading: () => const ShimmerBox(height: 90),
              error: (e, _) => ErrorStateView(
                message: e.toString(),
                onRetry: () => ref.invalidate(vendorRiderCashPositionsProvider),
              ),
              data: (riders) {
                if (riders.isEmpty) {
                  return const EmptyStateView(
                    title: 'No riders yet',
                    message: 'Cash positions appear once riders start collecting COD payments.',
                  );
                }
                return Column(
                  children: [
                    for (final r in riders)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RiderCashCard(position: r),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickLinks(BuildContext context, int pendingApprovals) {
    return Row(
      children: [
        Expanded(
          child: AppCard(
            onTap: () => context.pushNamed(RouteNames.vendorPaymentApprovals),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.rule_rounded, color: AppColors.primary),
                    const Spacer(),
                    if (pendingApprovals > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('$pendingApprovals',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('Payment Approvals', style: TextStyle(fontWeight: FontWeight.w700)),
                const Text('Review amendment requests',
                    style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final VendorFinanceKpisEntity kpis;
  const _KpiGrid({required this.kpis});

  @override
  Widget build(BuildContext context) {
    final items = <_KpiSpec>[
      _KpiSpec("Today's Collection", kpis.todaysCollection.toCurrency, Icons.today_rounded, AppColors.success),
      _KpiSpec('This Month', kpis.monthsCollection.toCurrency, Icons.calendar_month_rounded, AppColors.primary),
      _KpiSpec('Pending Collection', kpis.pendingCollection.toCurrency, Icons.schedule_rounded, AppColors.warning),
      _KpiSpec('Awaiting Settlement', kpis.awaitingSettlement.toCurrency, Icons.account_balance_wallet_rounded, const Color(0xFFE65100)),
      _KpiSpec('Outstanding Customers', '${kpis.outstandingCustomers}', Icons.people_alt_rounded, AppColors.info),
      _KpiSpec('Credits Issued', kpis.creditsIssued.toCurrency, Icons.card_giftcard_rounded, const Color(0xFF7C3AED)),
      _KpiSpec('Partial Payments', '${kpis.partialCount}', Icons.pie_chart_rounded, const Color(0xFF0EA5E9)),
      _KpiSpec('Refunds', kpis.refunds.toCurrency, Icons.reply_rounded, AppColors.error),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: [for (final s in items) _KpiTile(spec: s)],
    );
  }
}

class _KpiSpec {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _KpiSpec(this.label, this.value, this.icon, this.color);
}

class _KpiTile extends StatelessWidget {
  final _KpiSpec spec;
  const _KpiTile({required this.spec});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: spec.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(spec.icon, color: spec.color, size: 18),
          ),
          Text(spec.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          Text(spec.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _RiderCashCard extends StatelessWidget {
  final RiderCashPositionEntity position;
  const _RiderCashCard({required this.position});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  position.riderName.isNotEmpty ? position.riderName[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(position.riderName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              if (position.pendingSettlement > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${position.pendingSettlement.toCurrency} pending',
                      style: const TextStyle(color: Color(0xFFE65100), fontSize: 11, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('Collected', position.collected.toCurrency, AppColors.info),
              _stat('Settled', position.settled.toCurrency, AppColors.success),
              _stat('Pending', position.pendingSettlement.toCurrency, const Color(0xFFE65100)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 14)),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}

class _KpiSkeleton extends StatelessWidget {
  const _KpiSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: [for (var i = 0; i < 4; i++) const ShimmerBox(height: 90)],
    );
  }
}
