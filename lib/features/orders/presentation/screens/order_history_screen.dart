import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/order_status.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/datetime_extensions.dart';
import '../../../../shared/extensions/num_extensions.dart';
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
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(orderHistoryProvider),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: GradientHeroHeader(
                    child: _HeaderContent(orders: ordersAsync.valueOrNull),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: _SegmentedFilter(
                    selected: filter,
                    onChanged: (f) => ref.read(_orderFilterProvider.notifier).state = f,
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
                  final sections = _groupByDate(filtered);
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    sliver: SliverList.builder(
                      itemCount: sections.fold<int>(0, (n, s) => n + s.orders.length + 1),
                      itemBuilder: (context, flatIndex) {
                        var i = flatIndex;
                        for (final section in sections) {
                          if (i == 0) {
                            return Padding(
                              padding: EdgeInsets.only(top: section == sections.first ? 0 : 20, bottom: 10, left: 4),
                              child: Text(
                                section.label,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textTertiary,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            );
                          }
                          i--;
                          if (i < section.orders.length) {
                            final order = section.orders[i];
                            final isLast = i == section.orders.length - 1;
                            return Padding(
                              padding: EdgeInsets.only(bottom: isLast ? 0 : 1),
                              child: _OrderRow(
                                order: order,
                                isFirst: i == 0,
                                isLast: isLast,
                              ),
                            );
                          }
                          i -= section.orders.length;
                        }
                        return const SizedBox.shrink();
                      },
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

  List<_DateSection> _groupByDate(List<OrderEntity> orders) {
    final sections = <_DateSection>[];
    for (final order in orders) {
      final label = order.createdAt.isToday
          ? 'Today'
          : order.createdAt.isYesterday
              ? 'Yesterday'
              : order.createdAt.toDayMonthYear;
      if (sections.isNotEmpty && sections.last.label == label) {
        sections.last.orders.add(order);
      } else {
        sections.add(_DateSection(label, [order]));
      }
    }
    return sections;
  }
}

class _DateSection {
  final String label;
  final List<OrderEntity> orders;
  _DateSection(this.label, this.orders);
}

class _HeaderContent extends StatelessWidget {
  final List<OrderEntity>? orders;
  const _HeaderContent({required this.orders});

  @override
  Widget build(BuildContext context) {
    final activeCount = orders?.where((o) => !o.status.isTerminal).length ?? 0;
    final total = orders?.length ?? 0;
    final totalSpend = orders
            ?.where((o) => o.status != OrderStatus.cancelled && o.status != OrderStatus.rejected)
            .fold<double>(0, (sum, o) => sum + o.amountPaid) ??
        0;

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
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.3)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: _statTile('$total', 'Orders')),
            _statDivider(),
            Expanded(child: _statTile('$activeCount', 'In progress')),
            _statDivider(),
            Expanded(child: _statTile(totalSpend.toCurrency, 'Total spent')),
          ],
        ),
      ],
    );
  }

  Widget _statDivider() => Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.18));

  Widget _statTile(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19, letterSpacing: -0.4)),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5)),
      ],
    );
  }
}

/// A single rounded track with an animated sliding highlight behind the
/// selected label — the transaction-filter pattern used by banking apps
/// (Revolut, Wise) rather than a row of separately-floating pill chips.
class _SegmentedFilter extends StatelessWidget {
  final _OrderFilter selected;
  final ValueChanged<_OrderFilter> onChanged;
  const _SegmentedFilter({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = _OrderFilter.values;
    final index = options.indexOf(selected);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / options.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: segmentWidth * index,
                width: segmentWidth,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppShadows.card,
                  ),
                ),
              ),
              Row(
                children: options.map((f) {
                  final isSelected = f == selected;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(f),
                      child: SizedBox(
                        height: 38,
                        child: Center(
                          child: Text(
                            f.label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? AppColors.primary : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Bank-statement-style transaction row: merchant initial, name +
/// status/time on two lines, amount emphasized on the right. Adjacent
/// rows within the same date section share one card with hairline
/// dividers, like a real statement, instead of each floating separately.
class _OrderRow extends StatelessWidget {
  final OrderEntity order;
  final bool isFirst;
  final bool isLast;
  const _OrderRow({required this.order, required this.isFirst, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.vertical(
      top: Radius.circular(isFirst ? 18 : 0),
      bottom: Radius.circular(isLast ? 18 : 0),
    );

    return Material(
      color: AppColors.surface,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: () => context.pushNamed(
          RouteNames.orderTracking,
          pathParameters: {'orderId': order.id},
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppColors.border),
            boxShadow: isFirst ? AppShadows.card : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: order.status.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_statusIcon(order.status), color: order.status.color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(order.vendorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                        ),
                        Text(order.createdAt.toTime,
                            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(color: order.status.color, shape: BoxShape.circle),
                        ),
                        Flexible(
                          child: Text(order.status.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: order.status.color, fontWeight: FontWeight.w600)),
                        ),
                        Text(' · #${order.orderNumber}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                      ],
                    ),
                    if (order.outstandingAmount > 0 || order.isRefunded) ...[
                      const SizedBox(height: 6),
                      _PaymentBadge(order: order),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(order.totalAmount.toCurrency,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textTertiary),
                ],
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(order.isRefunded ? Icons.reply_rounded : Icons.schedule_rounded, size: 11, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
