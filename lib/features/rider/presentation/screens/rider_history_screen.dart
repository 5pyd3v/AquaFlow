import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/datetime_extensions.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../domain/entities/rider_delivery_entity.dart';
import '../providers/rider_providers.dart';

class RiderHistoryScreen extends ConsumerWidget {
  const RiderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(deliveryHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery History')),
      body: historyAsync.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: 5,
          itemBuilder: (_, __) => const Padding(padding: EdgeInsets.only(bottom: 12), child: ListTileSkeleton()),
        ),
        error: (error, _) =>
            ErrorStateView(message: error.toString(), onRetry: () => ref.invalidate(deliveryHistoryProvider)),
        data: (deliveries) {
          if (deliveries.isEmpty) {
            return const EmptyStateView(
              title: 'No deliveries yet',
              message: 'Completed deliveries will show up here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(deliveryHistoryProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: deliveries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _HistoryTile(delivery: deliveries[index]),
            ),
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final RiderDeliveryEntity delivery;
  const _HistoryTile({required this.delivery});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
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
                  color: delivery.status.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.done_all_rounded,
                    color: delivery.status.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('#${delivery.orderNumber}', style: Theme.of(context).textTheme.titleSmall)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: delivery.status.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(delivery.status.label,
                    style: TextStyle(color: delivery.status.color, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(delivery.customerName, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(delivery.deliveryAddress,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(delivery.createdAt.friendlyLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
              Text(delivery.totalAmount.toCurrency,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }
}
