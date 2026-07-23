import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/order_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/datetime_extensions.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../domain/entities/vendor_order_entity.dart';
import '../providers/vendor_providers.dart';
import '../widgets/rider_assignment_sheet.dart';

class VendorOrdersScreen extends ConsumerStatefulWidget {
  const VendorOrdersScreen({super.key});

  @override
  ConsumerState<VendorOrdersScreen> createState() => _VendorOrdersScreenState();
}

class _VendorOrdersScreenState extends ConsumerState<VendorOrdersScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Orders'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Container(
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: AppShadows.brand(opacity: 0.24),
                ),
                dividerColor: Colors.transparent,
                splashBorderRadius: BorderRadius.circular(11),
                tabs: const [
                  Tab(text: 'Pending'),
                  Tab(text: 'Active'),
                  Tab(text: 'History'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _OrdersList(bucket: _OrderBucket.pending),
          _OrdersList(bucket: _OrderBucket.active),
          _OrdersList(bucket: _OrderBucket.history),
        ],
      ),
    );
  }
}

enum _OrderBucket { pending, active, history }

class _OrdersList extends ConsumerWidget {
  final _OrderBucket bucket;
  const _OrdersList({required this.bucket});

  bool _matchesBucket(OrderStatus status) {
    switch (bucket) {
      case _OrderBucket.pending:
        return status == OrderStatus.pending;
      case _OrderBucket.active:
        return [OrderStatus.accepted, OrderStatus.assigned, OrderStatus.pickedUp, OrderStatus.onTheWay]
            .contains(status);
      case _OrderBucket.history:
        return status.isTerminal || status == OrderStatus.delivered;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(vendorOrdersProvider);

    return ordersAsync.when(
      loading: () => ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: 4,
        itemBuilder: (_, __) => const Padding(padding: EdgeInsets.only(bottom: 12), child: ListTileSkeleton()),
      ),
      error: (error, _) => ErrorStateView(message: error.toString(), onRetry: () => ref.invalidate(vendorOrdersProvider)),
      data: (allOrders) {
        final orders = allOrders.where((o) => _matchesBucket(o.status)).toList();
        if (orders.isEmpty) {
          return const EmptyStateView(
            title: 'No orders here',
            message: 'Orders in this stage will show up here as they come in.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(vendorOrdersProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _VendorOrderCard(order: orders[index]),
          ),
        );
      },
    );
  }
}

class _VendorOrderCard extends ConsumerWidget {
  final VendorOrderEntity order;
  const _VendorOrderCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: order.isEmergency ? AppColors.error : AppColors.border,
          width: order.isEmergency ? 1.4 : 1,
        ),
        boxShadow: order.isEmergency
            ? AppShadows.brand(color: AppColors.error, opacity: 0.18)
            : AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: order.status.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.receipt_long_rounded,
                    color: order.status.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('#${order.orderNumber}', style: Theme.of(context).textTheme.titleSmall)),
              if (order.isEmergency)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(20)),
                  child: const Text('URGENT', style: TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: order.status.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(order.status.label, style: TextStyle(color: order.status.color, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 16, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Expanded(child: Text(order.customerName, style: Theme.of(context).textTheme.bodyMedium)),
              if (order.customerPhone.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.call_rounded, size: 18, color: AppColors.success),
                  onPressed: () => launchUrl(Uri.parse('tel:${order.customerPhone}')),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(order.deliveryAddress,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(order.createdAt.friendlyLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
              Text(order.totalAmount.toCurrency,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.primary)),
            ],
          ),
          if (order.riderName != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.two_wheeler_rounded, size: 16, color: AppColors.roleRider),
                const SizedBox(width: 6),
                Text('Rider: ${order.riderName}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
          if (order.status == OrderStatus.pending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _reject(context, ref),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      minimumSize: const Size.fromHeight(40),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => ref.read(vendorOrdersProvider.notifier).accept(order.id),
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ] else if (order.status == OrderStatus.accepted && order.riderId == null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openRiderAssignment(context, ref),
                icon: const Icon(Icons.two_wheeler_rounded, size: 18),
                label: const Text('Assign Rider'),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _reject(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Reject this order?'),
        content: const Text('The customer will be notified immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(vendorOrdersProvider.notifier).reject(order.id, 'Rejected by vendor');
            },
            child: const Text('Reject', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _openRiderAssignment(BuildContext context, WidgetRef ref) async {
    final riderId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => RiderAssignmentSheet(
        destinationLat: order.deliveryLat,
        destinationLng: order.deliveryLng,
      ),
    );
    if (riderId != null) {
      ref.read(vendorOrdersProvider.notifier).assignRider(order.id, riderId);
    }
  }
}
