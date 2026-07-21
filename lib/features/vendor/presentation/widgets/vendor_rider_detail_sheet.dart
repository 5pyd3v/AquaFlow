import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../settlements/domain/entities/cod_balance_entity.dart';
import '../../../settlements/presentation/providers/settlement_providers.dart';
import '../../domain/entities/vendor_rider_entity.dart';

final _riderCodForVendorProvider = FutureProvider.autoDispose
    .family<CodBalanceEntity, ({String riderId, String vendorId})>((ref, args) async {
  final result = await ref.read(settlementRepositoryProvider).getRiderCodBalance(
        riderId: args.riderId,
        vendorId: args.vendorId,
      );
  return result.fold((failure) => throw failure, (data) => data);
});

class VendorRiderDetailSheet extends ConsumerWidget {
  final VendorRiderEntity rider;
  final String vendorId;

  const VendorRiderDetailSheet({
    super.key,
    required this.rider,
    required this.vendorId,
  });

  static void show(BuildContext context, VendorRiderEntity rider, String vendorId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VendorRiderDetailSheet(rider: rider, vendorId: vendorId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(
      _riderCodForVendorProvider((riderId: rider.id, vendorId: vendorId)),
    );

    final statusColor = switch (rider.status) {
      RiderStatus.available => const Color(0xFF10B981),
      RiderStatus.onDelivery => const Color(0xFF2196F3),
      RiderStatus.suspended => AppColors.error,
      RiderStatus.offline => AppColors.textTertiary,
    };

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Profile header
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.roleRider.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.person_rounded, color: AppColors.roleRider, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rider.fullName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            rider.status.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Personal details
            const _SectionTitle(label: 'Personal Details'),
            const SizedBox(height: 10),
            _DetailCard(children: [
              _DetailRow(icon: Icons.phone_rounded, label: 'Phone', value: rider.phone),
              _DetailRow(
                icon: Icons.star_rounded,
                label: 'Rating',
                value: rider.rating > 0 ? '${rider.rating.toStringAsFixed(1)} / 5.0' : 'No ratings yet',
                valueColor: rider.rating >= 4.0 ? const Color(0xFF10B981) : null,
              ),
              _DetailRow(
                icon: Icons.local_shipping_rounded,
                label: 'Total Deliveries',
                value: '${rider.totalDeliveries}',
              ),
            ]),
            const SizedBox(height: 20),

            // Vehicle info
            const _SectionTitle(label: 'Vehicle'),
            const SizedBox(height: 10),
            _DetailCard(children: [
              _DetailRow(
                icon: Icons.two_wheeler_rounded,
                label: 'Vehicle Type',
                value: rider.vehicleType ?? 'Not set',
              ),
            ]),
            const SizedBox(height: 20),

            // Financial section
            const _SectionTitle(label: 'COD Finances'),
            const SizedBox(height: 10),
            balanceAsync.when(
              loading: () => Container(
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Unable to load financial data',
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              ),
              data: (balance) => _FinanceCard(balance: balance),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  const _SectionTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final List<Widget> children;
  const _DetailCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) const Divider(height: 20),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textTertiary),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _FinanceCard extends StatelessWidget {
  final CodBalanceEntity balance;
  const _FinanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Outstanding — big highlight
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: balance.outstanding > 0
                  ? const Color(0xFFFFF3E0)
                  : const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  'Outstanding Balance',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: balance.outstanding > 0
                        ? const Color(0xFFE65100)
                        : const Color(0xFF2E7D32),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  balance.outstanding.toCurrency,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: balance.outstanding > 0
                        ? const Color(0xFFE65100)
                        : const Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _FinanceRow(
            label: 'Total COD Collected',
            value: balance.totalCollected.toCurrency,
            color: const Color(0xFF2196F3),
          ),
          const Divider(height: 16),
          _FinanceRow(
            label: 'Total Submitted (Verified)',
            value: balance.totalVerified.toCurrency,
            color: const Color(0xFF10B981),
          ),
          const Divider(height: 16),
          _FinanceRow(
            label: 'Pending Verification',
            value: balance.pending.toCurrency,
            color: const Color(0xFFFF8F00),
          ),
        ],
      ),
    );
  }
}

class _FinanceRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _FinanceRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
