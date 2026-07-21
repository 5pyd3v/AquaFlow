import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../domain/entities/payment_amendment_entity.dart';
import '../providers/payment_providers.dart';

/// Vendor reviews rider requests to edit/delete already-settled payments.
class VendorPaymentApprovalsScreen extends ConsumerWidget {
  const VendorPaymentApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(vendorAmendmentRequestsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Payment Approvals')),
      body: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: const [ShimmerBox(height: 120), SizedBox(height: 12), ShimmerBox(height: 120)],
        ),
        error: (e, _) => ErrorStateView(
          message: e.toString(),
          onRetry: () => ref.invalidate(vendorAmendmentRequestsProvider),
        ),
        data: (all) {
          final pending = all.where((a) => a.status == AmendmentStatus.pending).toList();
          final resolved = all.where((a) => a.status != AmendmentStatus.pending).toList();
          if (all.isEmpty) {
            return const EmptyStateView(
              title: 'No amendment requests',
              message: 'When a rider asks to change or remove a settled payment, it appears here for your approval.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(vendorAmendmentRequestsProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (pending.isNotEmpty) ...[
                  Text('Pending (${pending.length})', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  for (final a in pending)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _AmendmentCard(amendment: a, actionable: true),
                    ),
                ],
                if (resolved.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('History', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  for (final a in resolved)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _AmendmentCard(amendment: a, actionable: false),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AmendmentCard extends ConsumerStatefulWidget {
  final PaymentAmendmentEntity amendment;
  final bool actionable;
  const _AmendmentCard({required this.amendment, required this.actionable});

  @override
  ConsumerState<_AmendmentCard> createState() => _AmendmentCardState();
}

class _AmendmentCardState extends ConsumerState<_AmendmentCard> {
  bool _busy = false;

  (Color, String) get _statusMeta => switch (widget.amendment.status) {
        AmendmentStatus.approved => (AppColors.success, 'Approved'),
        AmendmentStatus.rejected => (AppColors.error, 'Rejected'),
        AmendmentStatus.pending => (AppColors.warning, 'Pending'),
      };

  Future<void> _resolve(bool approve) async {
    setState(() => _busy = true);
    final result = await ref.read(paymentControllerProvider.notifier).resolveAmendment(
          requestId: widget.amendment.id,
          approve: approve,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    result.fold(
      (f) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(f.message), backgroundColor: AppColors.error),
      ),
      (_) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Amendment approved' : 'Amendment rejected'),
          backgroundColor: approve ? AppColors.success : AppColors.textSecondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.amendment;
    final (color, label) = _statusMeta;
    final isDelete = a.action == AmendmentAction.delete;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isDelete ? Icons.delete_outline_rounded : Icons.edit_rounded,
                  size: 18, color: isDelete ? AppColors.error : AppColors.primary),
              const SizedBox(width: 8),
              Text(isDelete ? 'Delete payment' : 'Edit payment',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (a.orderNumber != null)
            _row('Order', '#${a.orderNumber}'),
          if (a.riderName != null) _row('Rider', a.riderName!),
          _row('Current amount', a.currentAmount.toCurrency),
          if (!isDelete && a.requestedAmount != null)
            _row('Requested amount', a.requestedAmount!.toCurrency),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('Reason: ${a.reason}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
          if (widget.actionable) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _resolve(false),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _resolve(true),
                    child: _busy
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
