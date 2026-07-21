import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../../vendor/domain/entities/vendor_rider_entity.dart';
import '../../../vendor/presentation/providers/vendor_providers.dart';
import '../../domain/entities/cod_balance_entity.dart';
import '../providers/settlement_providers.dart';

final _riderFinanceProvider = FutureProvider.autoDispose
    .family<CodBalanceEntity, ({String riderId, String vendorId})>((ref, args) async {
  final result = await ref.read(settlementRepositoryProvider).getRiderCodBalance(
        riderId: args.riderId,
        vendorId: args.vendorId,
      );
  return result.fold((failure) => throw failure, (data) => data);
});

class VendorRiderFinancialsScreen extends ConsumerWidget {
  const VendorRiderFinancialsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ridersAsync = ref.watch(vendorRidersProvider);
    final vendorAsync = ref.watch(myVendorProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Rider Finances',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: ridersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorStateView(
          message: e.toString(),
          onRetry: () => ref.invalidate(vendorRidersProvider),
        ),
        data: (riders) {
          if (riders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_off_rounded,
                      size: 56, color: AppColors.textTertiary.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  const Text(
                    'No riders linked',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }
          final vendorId = vendorAsync.valueOrNull?.id;
          if (vendorId == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(vendorRidersProvider);
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: riders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _RiderFinanceCard(
                rider: riders[index],
                vendorId: vendorId,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RiderFinanceCard extends ConsumerWidget {
  final VendorRiderEntity rider;
  final String vendorId;

  const _RiderFinanceCard({required this.rider, required this.vendorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(
      _riderFinanceProvider((riderId: rider.id, vendorId: vendorId)),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.roleRider.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.two_wheeler_rounded,
                    color: AppColors.roleRider, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rider.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      rider.phone,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          balanceAsync.when(
            loading: () => Container(
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            error: (_, __) => const Text(
              'Unable to load balance',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
            data: (balance) => Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        label: 'Outstanding',
                        value: balance.outstanding.toCurrency,
                        color: balance.outstanding > 0
                            ? const Color(0xFFE65100)
                            : const Color(0xFF10B981),
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        label: 'Pending',
                        value: balance.pending.toCurrency,
                        color: const Color(0xFFFF8F00),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        label: 'Total Collected',
                        value: balance.totalCollected.toCurrency,
                        color: const Color(0xFF2196F3),
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        label: 'Total Settled',
                        value: balance.totalVerified.toCurrency,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Metric({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}
