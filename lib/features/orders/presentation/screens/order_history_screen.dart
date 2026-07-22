import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/order_status.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/datetime_extensions.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../../../shared/widgets/misc/gradient_hero_header.dart';
import '../../domain/entities/order_entity.dart';
import '../providers/order_providers.dart';

enum _OrderFilter { all, active, completed, cancelled }

extension on _OrderFilter {
  String get label => switch (this) {
        _OrderFilter.all => 'All',
        _OrderFilter.active => 'Active',
        _OrderFilter.completed => 'Completed',
        _OrderFilter.cancelled => 'Cancelled',
      };

  bool matches(OrderStatus status) => switch (this) {
        _OrderFilter.all => true,
        _OrderFilter.active => !status.isTerminal,
        _OrderFilter.completed =>
          status == OrderStatus.completed || status == OrderStatus.delivered || status == OrderStatus.returned,
        _OrderFilter.cancelled => status == OrderStatus.cancelled || status == OrderStatus.rejected,
      };
}

final _orderFilterProvider = StateProvider.autoDispose<_OrderFilter>((ref) => _OrderFilter.all);

class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(orderHistoryProvider);
    final filter = ref.watch(_orderFilterProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(orderHistoryProvider),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: GradientHeroHeader(
                    child: _HeaderContent(orders: ordersAsync.valueOrNull),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    children: _OrderFilter.values
                        .map((f) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _FilterChip(
                                label: f.label,
                                isSelected: filter == f,
                                onTap: () => ref.read(_orderFilterProvider.notifier).state = f,
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
              ordersAsync.when(
                loading: () => SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverList.builder(
                    itemCount: 5,
                    itemBuilder: (_, __) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: ListTileSkeleton(),
                    ),
                  ),
                ),
                error: (error, _) => SliverFillRemaining(
                  child: ErrorStateView(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(orderHistoryProvider),
                  ),
                ),
                data: (orders) {
                  final filtered = orders.where((o) => filter.matches(o.status)).toList();
                  if (orders.isEmpty) {
                    return const SliverFillRemaining(
                      child: EmptyStateView(
                        title: 'No orders yet',
                        message: 'Your order history will show up here once you place your first order.',
                      ),
                    );
                  }
                  if (filtered.isEmpty) {
                    return SliverFillRemaining(
                      child: EmptyStateView(
                        title: 'Nothing here',
                        message: 'No ${filter.label.toLowerCase()} orders to show.',
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _OrderTile(order: filtered[index]),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderContent extends StatelessWidget {
  final List<OrderEntity>? orders;
  const _HeaderContent({required this.orders});

  @override
  Widget build(BuildContext context) {
    final activeCount = orders?.where((o) => !o.status.isTerminal).length ?? 0;
    final total = orders?.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('My Orders',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _statTile('$total', 'Total orders')),
            Container(width: 1, height: 32, color: Colors.white.withValues(alpha: 0.2)),
            Expanded(child: _statTile('$activeCount', 'In progress')),
          ],
        ),
      ],
    );
  }

  Widget _statTile(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
          boxShadow: isSelected ? AppShadows.brand(opacity: 0.22) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final OrderEntity order;
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 18,
      padding: const EdgeInsets.all(14),
      onTap: () => context.pushNamed(
        RouteNames.orderTracking,
        pathParameters: {'orderId': order.id},
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
                  color: order.status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_statusIcon(order.status), color: order.status.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('#${order.orderNumber}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(order.vendorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: order.status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(order.status.label,
                    style: TextStyle(color: order.status.color, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const Divider(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 13, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Text(order.createdAt.friendlyLabel,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
                  Text(' · ${order.items.length} item${order.items.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
                ],
              ),
              Text(order.totalAmount.toCurrency,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.primary)),
            ],
          ),
          if (order.outstandingAmount > 0 || order.isRefunded) ...[
            const SizedBox(height: 10),
            _PaymentBadge(order: order),
          ],
        ],
      ),
    );
  }

  IconData _statusIcon(OrderStatus status) => switch (status) {
        OrderStatus.pending => Icons.hourglass_top_rounded,
        OrderStatus.accepted => Icons.thumb_up_alt_rounded,
        OrderStatus.assigned => Icons.person_pin_circle_rounded,
        OrderStatus.pickedUp => Icons.inventory_2_rounded,
        OrderStatus.onTheWay => Icons.local_shipping_rounded,
        OrderStatus.delivered => Icons.check_circle_rounded,
        OrderStatus.returned => Icons.replay_rounded,
        OrderStatus.completed => Icons.task_alt_rounded,
        OrderStatus.cancelled => Icons.cancel_rounded,
        OrderStatus.rejected => Icons.block_rounded,
      };
}

class _PaymentBadge extends StatelessWidget {
  final OrderEntity order;
  const _PaymentBadge({required this.order});

  @override
  Widget build(BuildContext context) {
    final (color, text) = order.isRefunded
        ? (AppColors.error, 'Refunded')
        : (AppColors.warning, '${order.outstandingAmount.toCurrency} due');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(order.isRefunded ? Icons.reply_rounded : Icons.schedule_rounded, size: 13, color: color),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
