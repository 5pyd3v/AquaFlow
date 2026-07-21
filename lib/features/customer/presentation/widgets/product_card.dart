import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../domain/entities/product_entity.dart';
import '../providers/catalog_providers.dart';

/// The core commerce card — large image, brand, rating, price with
/// strike-through on discount, deposit note, stock badge, favorite
/// toggle, and a +/- quantity stepper once it's in the cart. This is
/// what gets reused in the grid, search results, and favorites list.
class ProductCard extends ConsumerWidget {
  final ProductEntity product;
  final VoidCallback onTap;

  const ProductCard({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final quantityInCart = ref.watch(cartProvider.notifier).quantityOf(product.id);
    final isFavorite = ref.watch(favoriteProductIdsProvider).contains(product.id);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  child: AspectRatio(
                    aspectRatio: 1.15,
                    child: product.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: product.imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: AppColors.surfaceMuted),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.surfaceMuted,
                              child: const Icon(Icons.water_drop_outlined, color: AppColors.textTertiary, size: 40),
                            ),
                          )
                        : Container(
                            color: AppColors.surfaceMuted,
                            child: const Icon(Icons.water_drop_outlined, color: AppColors.textTertiary, size: 40),
                          ),
                  ),
                ),
                if (product.hasDiscount)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${product.discountPercent.toStringAsFixed(0)}% OFF',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton(
                    onPressed: () => ref
                        .read(catalogRepositoryProvider)
                        .toggleFavoriteProduct(product.id, !isFavorite)
                        .then((_) => ref.invalidate(favoriteProductsProvider)),
                    icon: Icon(
                      isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: isFavorite ? AppColors.error : Colors.white,
                      size: 20,
                      shadows: const [Shadow(color: Colors.black38, blurRadius: 4)],
                    ),
                  ),
                ),
                if (!product.inStock)
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                      ),
                      alignment: Alignment.center,
                      child: const Text('Out of Stock',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text('${product.brand ?? product.vendorName} · ${product.sizeLiters}L',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 14, color: AppColors.secondary),
                            const SizedBox(width: 2),
                            Text(product.rating.toStringAsFixed(1),
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(width: 8),
                            const Icon(Icons.schedule_rounded, size: 13, color: AppColors.textTertiary),
                            const SizedBox(width: 2),
                            Text('${product.averageDeliveryMinutes}m',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(product.discountedPrice.toCurrency,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                              if (product.hasDiscount)
                                Text(product.price.toCurrency,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppColors.textTertiary, decoration: TextDecoration.lineThrough)),
                            ],
                          ),
                        ),
                        quantityInCart > 0
                            ? _QuantityStepper(product: product, quantity: quantityInCart)
                            : _AddButton(product: product, cartVendorId: cart.vendorId),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends ConsumerWidget {
  final ProductEntity product;
  final String? cartVendorId;
  const _AddButton({required this.product, required this.cartVendorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: !product.inStock
          ? null
          : () {
              final added = ref.read(cartProvider.notifier).addProduct(product);
              if (!added) {
                showDialog(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    title: const Text('Start a new cart?'),
                    content: const Text(
                        'Your cart has items from another vendor. Adding this will clear your current cart.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          ref.read(cartProvider.notifier).clearAndAdd(product);
                          Navigator.of(dialogContext).pop();
                        },
                        child: const Text('Clear & Add'),
                      ),
                    ],
                  ),
                );
              }
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: product.inStock ? AppColors.primary : AppColors.textTertiary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('ADD', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _QuantityStepper extends ConsumerWidget {
  final ProductEntity product;
  final int quantity;
  const _QuantityStepper({required this.product, required this.quantity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => ref.read(cartProvider.notifier).updateQuantity(product.id, quantity - 1),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.remove_rounded, size: 16, color: Colors.white),
            ),
          ),
          Text('$quantity', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          InkWell(
            onTap: () => ref.read(cartProvider.notifier).updateQuantity(product.id, quantity + 1),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.add_rounded, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
