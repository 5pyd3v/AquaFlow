import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../domain/entities/customer_ledger_entity.dart';
import '../../domain/entities/payment_transaction_entity.dart';
import '../providers/payment_providers.dart';
import '../widgets/payment_type_style.dart';
import 'receipt_viewer_screen.dart';

/// Per-customer financial detail: summary, accounting ledger and a
/// chronological payment timeline with tappable receipts.
class VendorCustomerFinancesScreen extends ConsumerWidget {
  final String customerProfileId;
  final String customerName;

  const VendorCustomerFinancesScreen({
    super.key,
    required this.customerProfileId,
    required this.customerName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customerLedgerProvider(customerProfileId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(customerName)),
      body: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: const [ShimmerBox(height: 120), SizedBox(height: 12), ShimmerBox(height: 200)],
        ),
        error: (e, _) => ErrorStateView(
          message: e.toString(),
          onRetry: () => ref.invalidate(customerLedgerProvider(customerProfileId)),
        ),
        data: (ledger) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(customerLedgerProvider(customerProfileId)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _summaryCard(context, ledger),
              const SizedBox(height: 20),
              Text('Payment Timeline', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (ledger.entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: EmptyStateView(
                    title: 'No payments yet',
                    message: 'Payments, credits and refunds for this customer will appear here.',
                  ),
                )
              else
                for (final e in ledger.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TimelineTile(txn: e),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(BuildContext context, CustomerLedgerEntity l) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _metric('Total Purchases', l.totalPurchases.toCurrency, AppColors.textPrimary)),
              Expanded(child: _metric('Total Paid', l.totalPaid.toCurrency, AppColors.success)),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(child: _metric('Outstanding', l.outstanding.toCurrency, AppColors.warning)),
              Expanded(child: _metric('Available Credit', l.availableCredit.toCurrency, AppColors.info)),
            ],
          ),
          if (l.lastPaymentAt != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last payment: ${l.lastPaymentAt!.toLocal().toString().split(' ').first}',
              style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.3)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final PaymentTransactionEntity txn;
  const _TimelineTile({required this.txn});

  String get _label => switch (txn.type) {
        PaymentType.full => 'Full payment',
        PaymentType.partial => 'Partial payment',
        PaymentType.over => 'Overpayment',
        PaymentType.credit => 'Credit applied',
        PaymentType.refund => 'Refund',
        PaymentType.adjustment => 'Adjustment',
      };

  @override
  Widget build(BuildContext context) {
    final color = txn.type.color;
    final icon = txn.type.icon;
    final label = _label;
    final deleted = txn.status == PaymentTxnStatus.deleted;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (deleted)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Deleted',
                                style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                    if (txn.orderNumber != null)
                      Text('Order #${txn.orderNumber}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                ),
              ),
              Text(
                txn.amount.toCurrency,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: deleted ? AppColors.textTertiary : AppColors.textPrimary,
                  decoration: deleted ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                txn.createdAt.toLocal().toString().split('.').first,
                style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
              ),
              const Spacer(),
              if (txn.settled)
                const Text('settled', style: TextStyle(fontSize: 11, color: AppColors.success)),
              if (txn.receiptUrl != null) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReceiptViewerScreen(
                        args: ReceiptViewerArgs(
                          receiptUrl: txn.receiptUrl!,
                          uploadedByName: txn.riderName,
                          uploadedAt: txn.createdAt,
                        ),
                      ),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.receipt_long_rounded, size: 16),
                  label: const Text('Receipt'),
                ),
              ],
            ],
          ),
          if (txn.notes != null && txn.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(txn.notes!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}
