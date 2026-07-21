import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../providers/cart_provider.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Cart'),
        actions: [
          if (!cart.isEmpty)
            TextButton(
              onPressed: () => ref.read(cartProvider.notifier).clear(),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: cart.isEmpty
          ? const EmptyStateView(
              title: 'Your cart is empty',
              message: 'Browse the catalog and add some water bottles to get started.',
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ...cart.items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 60,
                                height: 60,
                                child: item.product.imageUrl != null
                                    ? CachedNetworkImage(imageUrl: item.product.imageUrl!, fit: BoxFit.cover)
                                    : Container(
                                        color: AppColors.surfaceMuted,
                                        child: const Icon(Icons.water_drop_outlined, color: AppColors.textTertiary),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.product.name, style: Theme.of(context).textTheme.titleSmall),
                                  const SizedBox(height: 4),
                                  Text(item.product.discountedPrice.toCurrency,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_rounded, size: 16),
                                    onPressed: () => ref
                                        .read(cartProvider.notifier)
                                        .updateQuantity(item.product.id, item.quantity - 1),
                                  ),
                                  Text('${item.quantity}', style: Theme.of(context).textTheme.titleSmall),
                                  IconButton(
                                    icon: const Icon(Icons.add_rounded, size: 16),
                                    onPressed: () => ref
                                        .read(cartProvider.notifier)
                                        .updateQuantity(item.product.id, item.quantity + 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
                const SizedBox(height: 12),
                _SummaryRow(label: 'Subtotal', value: cart.subtotal),
                if (cart.depositTotal > 0)
                  _SummaryRow(label: 'Bottle Deposit (refundable)', value: cart.depositTotal),
                _SummaryRow(
                  label: 'Delivery Fee',
                  value: cart.subtotal >= AppConfig.minOrderAmount ? 0 : 50,
                ),
                const Divider(height: 28),
                _SummaryRow(
                  label: 'Total',
                  value: cart.subtotal +
                      cart.depositTotal +
                      (cart.subtotal >= AppConfig.minOrderAmount ? 0 : 50),
                  isBold: true,
                ),
              ],
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: PrimaryButton(
                  label: 'Proceed to Checkout',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () => context.pushNamed(RouteNames.checkout),
                ),
              ),
            ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final bool isBold;
  const _SummaryRow({required this.label, required this.value, this.isBold = false});

  @override
  Widget build(BuildContext context) {
    final style = isBold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value == 0 ? 'Free' : value.toCurrency, style: style),
        ],
      ),
    );
  }
}
