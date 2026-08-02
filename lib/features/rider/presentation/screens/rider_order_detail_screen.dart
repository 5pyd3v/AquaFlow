import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/datetime_extensions.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../payments/domain/entities/payment_transaction_entity.dart';
import '../../../payments/presentation/providers/payment_providers.dart';
import '../../domain/entities/rider_delivery_entity.dart';
import '../providers/rider_providers.dart';

class RiderOrderDetailScreen extends ConsumerWidget {
  final RiderDeliveryEntity delivery;
  const RiderOrderDetailScreen({super.key, required this.delivery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(orderPaymentsProvider(delivery.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Order #${delivery.orderNumber}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _orderInfoCard(context),
          const SizedBox(height: 16),
          _customerCard(context, ref),
          const SizedBox(height: 16),
          _itemsCard(context),
          const SizedBox(height: 16),
          Text('Payments', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          paymentsAsync.when(
            loading: () => const ShimmerBox(height: 80),
            error: (e, _) => const Text('Could not load payments',
                style: TextStyle(color: AppColors.error)),
            data: (payments) {
              if (payments.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text('No payments recorded',
                      style: TextStyle(color: AppColors.textTertiary)),
                );
              }
              return Column(
                children: payments
                    .map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _PaymentTile(
                            payment: p,
                            onRefund: p.isRefundable
                                ? () => _navigateToRefund(context, p)
                                : null,
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _navigateToRefund(BuildContext context, PaymentTransactionEntity payment) {
    context.pushNamed(
      RouteNames.riderRefund,
      extra: payment,
    );
  }

  Widget _orderInfoCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Order Info', style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const Divider(height: 20),
          _detailRow('Order Number', '#${delivery.orderNumber}'),
          _detailRow('Status', delivery.status.label),
          _detailRow('Payment Method', delivery.paymentMethod.toUpperCase()),
          _detailRow('Total Amount', delivery.totalAmount.toCurrency),
          _detailRow('Date', delivery.createdAt.friendlyLabel),
        ],
      ),
    );
  }

  Widget _customerCard(BuildContext context, WidgetRef ref) {
    // Check if customer has pending payments on their assigned orders
    AsyncValue<int> outstandingAsync = const AsyncData(0);
    if (delivery.customerProfileId != null) {
      // This requires the rider ID - we need to get it from myRiderProvider
      final rider = ref.watch(myRiderProvider).valueOrNull;
      if (rider != null) {
        outstandingAsync = ref.watch(customerOutstandingProvider(
            CustomerOutstandingParams(delivery.customerProfileId!, rider.id)));
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_rounded, size: 20, color: AppColors.info),
              const SizedBox(width: 8),
              Text('Customer', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              outstandingAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (e, _) => const SizedBox.shrink(),
                data: (outstanding) {
                  if (outstanding > 0) {
                    return Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFFFE0B2).withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_rounded,
                              size: 14, color: Color(0xFFE65100)),
                          SizedBox(width: 4),
                          Text(
                            'Defaulter',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFE65100)),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
          const Divider(height: 20),
          _detailRow('Name', delivery.customerName),
          _detailRow('Phone', delivery.customerPhone),
          _detailRow('Address', delivery.deliveryAddress),
        ],
      ),
    );
  }

  Widget _itemsCard(BuildContext context) {
    if (delivery.items.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_rounded, size: 20, color: AppColors.warning),
              const SizedBox(width: 8),
              Text('Items (${delivery.items.length})', style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const Divider(height: 20),
          for (final item in delivery.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${item.productName} x${item.quantity}',
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Text(item.lineTotal.toCurrency,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final PaymentTransactionEntity payment;
  final VoidCallback? onRefund;
  const _PaymentTile({required this.payment, this.onRefund});

  @override
  Widget build(BuildContext context) {
    final isRefund = payment.type == PaymentType.refund;
    final color = isRefund ? AppColors.error : AppColors.success;
    final icon = isRefund ? Icons.reply_rounded : Icons.payments_rounded;
    final sign = isRefund ? '-' : '+';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.type.name.toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                ),
                if (payment.notes != null && payment.notes!.isNotEmpty)
                  Text(payment.notes!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$sign${payment.amount.toCurrency}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 14)),
              Text(payment.createdAt.friendlyLabel,
                  style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
            ],
          ),
          if (onRefund != null) ...[
            const SizedBox(width: 8),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.reply_rounded, size: 18, color: AppColors.error),
              tooltip: 'Refund',
              onPressed: onRefund,
            ),
          ],
        ],
      ),
    );
  }
}
