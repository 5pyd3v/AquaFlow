import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../domain/entities/settlement_entity.dart';
import '../providers/settlement_providers.dart';
import '../widgets/settlement_history_tile.dart';

class VendorSettlementHistoryScreen extends ConsumerStatefulWidget {
  const VendorSettlementHistoryScreen({super.key});

  @override
  ConsumerState<VendorSettlementHistoryScreen> createState() =>
      _VendorSettlementHistoryScreenState();
}

class _VendorSettlementHistoryScreenState
    extends ConsumerState<VendorSettlementHistoryScreen> {
  String _search = '';
  SettlementStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final settlementsAsync = ref.watch(vendorSettlementsProvider);
    final summaryAsync = ref.watch(vendorCodSummaryProvider);

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
          'Settlement History',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(vendorSettlementsProvider);
          ref.invalidate(vendorCodSummaryProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            summaryAsync.when(
              loading: () => Container(
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (summary) => _SummaryCards(
                todaysVerified: summary.todaysVerified,
                totalVerified: summary.totalVerified,
                pendingCount: summary.pendingCount,
                pendingAmount: summary.pendingAmount,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search by amount or code',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _statusChips(),
            const SizedBox(height: 12),
            settlementsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => ErrorStateView(
                message: e.toString(),
                onRetry: () => ref.invalidate(vendorSettlementsProvider),
              ),
              data: (all) {
                final settlements = _applyFilters(all);
                if (settlements.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_rounded,
                            size: 48,
                            color: AppColors.textTertiary.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        const Text(
                          'No settlements found',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: settlements
                      .map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _VendorSettlementTile(settlement: s),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<SettlementEntity> _applyFilters(List<SettlementEntity> all) {
    return all.where((s) {
      if (_statusFilter != null && s.status != _statusFilter) return false;
      if (_search.isNotEmpty) {
        final hay = '${s.amount} ${s.code}'.toLowerCase();
        if (!hay.contains(_search.toLowerCase())) return false;
      }
      return true;
    }).toList();
  }

  Widget _statusChips() {
    final options = <(String, SettlementStatus?)>[
      ('All', null),
      ('Pending', SettlementStatus.pending),
      ('Verified', SettlementStatus.verified),
      ('Expired', SettlementStatus.expired),
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (label, status) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: _statusFilter == status,
                onSelected: (_) => setState(() => _statusFilter = status),
              ),
            ),
        ],
      ),
    );
  }
}

/// Vendor settlement tile — reuses the base tile but adds a masked/visible
/// OTP row (visible only within the 24h window, per the OTP rule).
class _VendorSettlementTile extends StatelessWidget {
  final SettlementEntity settlement;
  const _VendorSettlementTile({required this.settlement});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettlementHistoryTile(settlement: settlement),
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                settlement.isOtpVisible ? Icons.vpn_key_rounded : Icons.lock_outline_rounded,
                size: 15,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 8),
              Text(
                settlement.isOtpVisible ? 'OTP' : 'OTP Expired',
                style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
              const Spacer(),
              Text(
                settlement.isOtpVisible ? settlement.code : '••••••',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryCards extends StatelessWidget {
  final double todaysVerified;
  final double totalVerified;
  final int pendingCount;
  final double pendingAmount;

  const _SummaryCards({
    required this.todaysVerified,
    required this.totalVerified,
    required this.pendingCount,
    required this.pendingAmount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: "Today's COD",
                value: todaysVerified.toCurrency,
                icon: Icons.today_rounded,
                color: const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SummaryCard(
                label: 'Total Received',
                value: totalVerified.toCurrency,
                icon: Icons.account_balance_rounded,
                color: const Color(0xFF2196F3),
              ),
            ),
          ],
        ),
        if (pendingCount > 0) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFE0B2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.hourglass_top_rounded,
                    color: Color(0xFFFF8F00), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$pendingCount pending (${pendingAmount.toCurrency})',
                    style: const TextStyle(
                      color: Color(0xFFE65100),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
