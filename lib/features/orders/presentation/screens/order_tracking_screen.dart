import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/order_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/datetime_extensions.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../../../shared/widgets/misc/gradient_hero_header.dart';
import '../../../payments/domain/entities/payment_transaction_entity.dart';
import '../../../payments/presentation/providers/payment_providers.dart';
import '../../domain/entities/order_entity.dart';
import '../providers/order_providers.dart';
import '../providers/rating_providers.dart';
import '../widgets/rating_sheet.dart';

/// Live order timeline. Backed by [orderTrackingProvider], a realtime
/// Supabase stream — the moment the vendor/rider updates `orders.status`
/// in Postgres, this screen updates with no polling, no manual refresh.
class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  bool _ratingShown = false;

  /// Auto-open the rating sheet the first time we see a delivered/
  /// completed order the customer hasn't rated yet.
  Future<void> _maybePromptRating(OrderEntity order) async {
    if (_ratingShown) return;
    final ratable = order.status == OrderStatus.delivered ||
        order.status == OrderStatus.completed ||
        order.status == OrderStatus.returned;
    if (!ratable) return;

    final alreadyRated = await ref.read(hasRatedOrderProvider(order.id).future);
    if (!mounted || _ratingShown || alreadyRated) return;

    _ratingShown = true;
    // Let the current frame settle before pushing the sheet.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    final rated = await showRatingSheet(context, order);
    if (rated == true) ref.invalidate(hasRatedOrderProvider(order.id));
  }

  @override
  Widget build(BuildContext context) {
    final orderId = widget.orderId;
    ref.listen(orderTrackingProvider(orderId), (_, next) {
      final order = next.valueOrNull;
      if (order != null) _maybePromptRating(order);
    });
    final orderAsync = ref.watch(orderTrackingProvider(orderId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Track Order'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: orderAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.primary),
        ),
        error: (error, _) => ErrorStateView(
          message: error.toString(),
          onRetry: () => ref.invalidate(orderTrackingProvider(orderId)),
        ),
        data: (order) => _TrackingContent(order: order),
      ),
    );
  }
}

class _TrackingContent extends ConsumerWidget {
  final OrderEntity order;
  const _TrackingContent({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCancelledOrRejected =
        order.status == OrderStatus.cancelled || order.status == OrderStatus.rejected;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        GradientHeroHeader(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #${order.orderNumber}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                    const SizedBox(height: 4),
                    Text(order.createdAt.friendlyLabel, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(order.vendorName, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                child: Text(order.status.label,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (isCancelledOrRejected)
          AppCard(
            color: AppColors.errorBg,
            border: Border.all(color: Colors.transparent),
            shadow: const [],
            child: Row(
              children: [
                const Icon(Icons.cancel_rounded, color: AppColors.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('This order was ${order.status.label.toLowerCase()}.',
                      style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          )
        else
          AppCard(child: _StatusTimeline(currentStatus: order.status)),
        const SizedBox(height: 20),
        if (order.riderId != null) ...[
          if (order.deliveryCode != null &&
              (order.status == OrderStatus.assigned ||
                  order.status == OrderStatus.pickedUp ||
                  order.status == OrderStatus.onTheWay)) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppShadows.brand(color: AppColors.secondary, opacity: 0.22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Your Delivery Code',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    order.deliveryCode!,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Share this code with your rider only once your order arrives — it confirms the handoff.',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          const _SectionLabel('Your Rider'),
          const SizedBox(height: 10),
          AppCard(
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.roleRider,
                  child: Icon(Icons.two_wheeler_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.riderName ?? 'Rider', style: Theme.of(context).textTheme.titleSmall),
                      const Text('On the way to you', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                if (order.riderPhone != null)
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.successBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: () => launchUrl(Uri.parse('tel:${order.riderPhone}')),
                      icon: const Icon(Icons.call_rounded, color: AppColors.success),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        const _SectionLabel('Delivery Address'),
        const SizedBox(height: 10),
        AppCard(
          child: Row(
            children: [
              const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(order.deliveryAddress,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _SectionLabel('Order Summary'),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              ...order.items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${item.quantity}x',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.primary)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(item.productName)),
                        Text(item.lineTotal.toCurrency, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Order Total', style: Theme.of(context).textTheme.titleMedium),
                  Text(order.totalAmount.toCurrency,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 10),
              _PaymentSummaryRow(
                label: 'Amount Paid',
                value: order.amountPaid.toCurrency,
                color: AppColors.success,
              ),
              if (order.creditApplied > 0)
                _PaymentSummaryRow(
                  label: 'Wallet Credit Applied',
                  value: order.creditApplied.toCurrency,
                  color: AppColors.info,
                ),
              if (order.outstandingAmount > 0)
                _PaymentSummaryRow(
                  label: 'Outstanding',
                  value: order.outstandingAmount.toCurrency,
                  color: AppColors.warning,
                ),
              if (order.isRefunded)
                const _PaymentSummaryRow(
                  label: 'Status',
                  value: 'Refunded',
                  color: AppColors.error,
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _SectionLabel('Payment History'),
        const SizedBox(height: 10),
        _OrderPaymentHistory(orderId: order.id),
        const SizedBox(height: 24),
        if (order.status == OrderStatus.pending || order.status == OrderStatus.accepted)
          PrimaryButton(
            label: 'Cancel Order',
            outlined: true,
            onPressed: () => _confirmCancel(context, ref),
          ),
        if (order.status == OrderStatus.delivered ||
            order.status == OrderStatus.completed ||
            order.status == OrderStatus.returned)
          Consumer(
            builder: (context, ref, _) {
              final rated = ref.watch(hasRatedOrderProvider(order.id)).valueOrNull ?? false;
              if (rated) {
                return AppCard(
                  color: AppColors.successBg,
                  border: Border.all(color: Colors.transparent),
                  shadow: const [],
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                      SizedBox(width: 8),
                      Text('Thanks for rating this order',
                          style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              }
              return PrimaryButton(
                label: 'Rate this order',
                icon: Icons.star_rounded,
                onPressed: () async {
                  final result = await showRatingSheet(context, order);
                  if (result == true) ref.invalidate(hasRatedOrderProvider(order.id));
                },
              );
            },
          ),
      ],
    );
  }

  void _confirmCancel(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Cancel this order?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('No, keep it')),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final result =
                  await ref.read(orderRepositoryProvider).cancelOrder(order.id, 'Cancelled by customer');
              if (!context.mounted) return;
              result.fold(
                (failure) => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
                ),
                (_) => ref.invalidate(orderTrackingProvider(order.id)),
              );
            },
            child: const Text('Yes, cancel', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleSmall);
  }
}

class _StatusTimeline extends StatelessWidget {
  final OrderStatus currentStatus;
  const _StatusTimeline({required this.currentStatus});

  @override
  Widget build(BuildContext context) {
    final steps = OrderStatus.timelineOrder;
    final currentIndex = steps.indexOf(currentStatus).clamp(0, steps.length - 1);

    return Column(
      children: List.generate(steps.length, (index) {
        final step = steps[index];
        final isDone = index <= currentIndex;
        final isLast = index == steps.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: isDone ? step.color : AppColors.surfaceMuted,
                      shape: BoxShape.circle,
                      border: Border.all(color: isDone ? step.color : AppColors.border, width: 2),
                    ),
                    child: isDone ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: index < currentIndex ? step.color : AppColors.border,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: Text(
                    step.label,
                    style: TextStyle(
                      fontWeight: isDone ? FontWeight.w700 : FontWeight.w500,
                      color: isDone ? AppColors.textPrimary : AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _PaymentSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _PaymentSummaryRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// Every payment / partial-payment / refund event recorded against this
/// specific order — so a customer who was charged in installments, or who
/// had part of a payment redirected to cover an older debt, can see exactly
/// what happened instead of just a single opaque "paid" status.
class _OrderPaymentHistory extends ConsumerWidget {
  final String orderId;
  const _OrderPaymentHistory({required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderPaymentsProvider(orderId));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (payments) {
        if (payments.isEmpty) {
          return AppCard(
            child: Text(
              'No payment activity recorded yet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          );
        }
        return Column(
          children: payments
              .map((txn) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PaymentEventTile(txn: txn),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _PaymentEventTile extends StatelessWidget {
  final PaymentTransactionEntity txn;
  const _PaymentEventTile({required this.txn});

  (Color, IconData, String) get _typeMeta => switch (txn.type) {
        PaymentType.full => (AppColors.success, Icons.check_circle_rounded, 'Full payment'),
        PaymentType.partial => (AppColors.warning, Icons.pie_chart_rounded, 'Partial payment'),
        PaymentType.over => (AppColors.info, Icons.account_balance_wallet_rounded, 'Overpayment'),
        PaymentType.credit => (const Color(0xFF7C3AED), Icons.card_giftcard_rounded, 'Wallet credit applied'),
        PaymentType.refund => (AppColors.error, Icons.reply_rounded, 'Refund'),
        PaymentType.adjustment => (AppColors.textSecondary, Icons.tune_rounded, 'Adjustment'),
      };

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = _typeMeta;
    final deleted = txn.status == PaymentTxnStatus.deleted;

    return AppCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    if (deleted)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Reversed',
                            style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
                Text(
                  txn.createdAt.friendlyLabel,
                  style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                ),
                if (txn.notes != null && txn.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(txn.notes!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ),
              ],
            ),
          ),
          Text(
            txn.amount.toCurrency,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: deleted ? AppColors.textTertiary : color,
              decoration: deleted ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }
}
