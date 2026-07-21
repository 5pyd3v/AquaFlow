import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../domain/entities/product_entity.dart';
import '../providers/catalog_providers.dart';

final _productByIdProvider =
    FutureProvider.family<ProductEntity, String>((ref, productId) async {
  final result = await ref.read(catalogRepositoryProvider).getProductById(productId);
  return result.fold((failure) => throw failure, (data) => data);
});

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(_productByIdProvider(widget.productId));

    return Scaffold(
      body: productAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorStateView(
          message: error.toString(),
          onRetry: () => ref.invalidate(_productByIdProvider(widget.productId)),
        ),
        data: (product) => _buildContent(context, product),
      ),
      bottomNavigationBar: productAsync.maybeWhen(
        data: (product) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: PrimaryButton(
              label: 'Add to Cart · ${(product.discountedPrice * _quantity).toCurrency}',
              icon: Icons.shopping_cart_rounded,
              onPressed: !product.inStock
                  ? null
                  : () => _handleAddToCart(context, product),
            ),
          ),
        ),
        orElse: () => null,
      ),
    );
  }

  void _handleAddToCart(BuildContext context, ProductEntity product) {
    final added = ref.read(cartProvider.notifier).addProduct(product, quantity: _quantity);
    if (added) {
      context.pushNamed(RouteNames.cart);
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Start a new cart?'),
        content: const Text(
            'Your cart has items from another vendor. Adding this will clear your current cart.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(cartProvider.notifier).clearAndAdd(product, quantity: _quantity);
              Navigator.of(dialogContext).pop();
              context.pushNamed(RouteNames.cart);
            },
            child: const Text('Clear & Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, ProductEntity product) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          flexibleSpace: FlexibleSpaceBar(
            background: product.imageUrl != null
                ? CachedNetworkImage(imageUrl: product.imageUrl!, fit: BoxFit.cover)
                : Container(
                    color: AppColors.surfaceMuted,
                    child: const Icon(Icons.water_drop_outlined, size: 80, color: AppColors.textTertiary),
                  ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(product.name, style: Theme.of(context).textTheme.headlineSmall)),
                    if (!product.inStock)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(20)),
                        child: const Text('Out of Stock',
                            style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('${product.brand ?? ''} · ${product.sizeLiters}L · Sold by ${product.vendorName}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: AppColors.secondary, size: 18),
                    const SizedBox(width: 4),
                    Text('${product.rating.toStringAsFixed(1)} rating',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(width: 16),
                    const Icon(Icons.schedule_rounded, color: AppColors.textTertiary, size: 16),
                    const SizedBox(width: 4),
                    Text('${product.averageDeliveryMinutes} min delivery',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
                const Divider(height: 32),
                Row(
                  children: [
                    Text(product.discountedPrice.toCurrency,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    if (product.hasDiscount) ...[
                      const SizedBox(width: 10),
                      Text(product.price.toCurrency,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.textTertiary, decoration: TextDecoration.lineThrough)),
                    ],
                  ],
                ),
                if (product.depositAmount > 0) ...[
                  const SizedBox(height: 6),
                  Text('+ ${product.depositAmount.toCurrency} refundable bottle deposit',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 20),
                if (product.description != null) ...[
                  Text('About this product', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(product.description!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 20),
                ],
                Text('Quantity', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _StepperButton(
                      icon: Icons.remove_rounded,
                      onTap: () => setState(() => _quantity = (_quantity - 1).clamp(1, 99)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text('$_quantity', style: Theme.of(context).textTheme.titleMedium),
                    ),
                    _StepperButton(
                      icon: Icons.add_rounded,
                      onTap: () => setState(() => _quantity = (_quantity + 1).clamp(1, 99)),
                    ),
                  ],
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}
