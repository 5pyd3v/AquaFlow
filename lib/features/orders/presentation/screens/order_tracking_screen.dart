import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/order_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/datetime_extensions.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
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
      appBar: AppBar(title: const Text('Track Order')),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #${order.orderNumber}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(order.createdAt.friendlyLabel, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
        const SizedBox(height: 24),
        if (isCancelledOrRejected)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(16)),
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
          _StatusTimeline(currentStatus: order.status),
        const SizedBox(height: 24),
        if (order.riderId != null) ...[
          if (order.deliveryCode != null &&
              (order.status == OrderStatus.assigned ||
                  order.status == OrderStatus.pickedUp ||
                  order.status == OrderStatus.onTheWay)) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.secondaryDark),
                      const SizedBox(width: 8),
                      Text('Your Delivery Code',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: AppColors.secondaryDark)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    order.deliveryCode!,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                      color: AppColors.secondaryDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Share this code with your rider only once your order arrives — it confirms the handoff.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          Text('Your Rider', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
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
                  IconButton(
                    onPressed: () => launchUrl(Uri.parse('tel:${order.riderPhone}')),
                    icon: const Icon(Icons.call_rounded, color: AppColors.success),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        Text('Delivery Address', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(order.deliveryAddress, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        Text('Order Summary', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        ...order.items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text('${item.quantity}x ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Expanded(child: Text(item.productName)),
                  Text(item.lineTotal.toCurrency),
                ],
              ),
            )),
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total Paid', style: Theme.of(context).textTheme.titleMedium),
            Text(order.totalAmount.toCurrency,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primary)),
          ],
        ),
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
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.successBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
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
