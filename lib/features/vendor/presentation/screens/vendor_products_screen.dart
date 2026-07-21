import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../../customer/domain/entities/product_entity.dart';
import '../providers/vendor_providers.dart';

class VendorProductsScreen extends ConsumerWidget {
  const VendorProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(vendorProductsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Products')),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: AppShadows.brand(color: AppColors.roleVendor, opacity: 0.35),
        ),
        child: FloatingActionButton.extended(
          onPressed: () => context.pushNamed(RouteNames.vendorAddProduct),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Product'),
          backgroundColor: AppColors.roleVendor,
          elevation: 0,
        ),
      ),
      body: productsAsync.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: 4,
          itemBuilder: (_, __) => const Padding(padding: EdgeInsets.only(bottom: 12), child: ListTileSkeleton()),
        ),
        error: (error, _) => ErrorStateView(message: error.toString(), onRetry: () => ref.invalidate(vendorProductsProvider)),
        data: (products) {
          if (products.isEmpty) {
            return const EmptyStateView(
              title: 'No products yet',
              message: 'Add your first water product to start receiving orders.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(vendorProductsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _VendorProductTile(product: products[index]),
            ),
          );
        },
      ),
    );
  }
}

class _VendorProductTile extends ConsumerWidget {
  final ProductEntity product;
  const _VendorProductTile({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLowStock = product.stockQuantity < 20;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 64,
              height: 64,
              child: product.imageUrl != null
                  ? CachedNetworkImage(imageUrl: product.imageUrl!, fit: BoxFit.cover)
                  : Container(
                      color: AppColors.surfaceMuted,
                      child: const Icon(Icons.water_drop_outlined,
                          color: AppColors.textTertiary, size: 28),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text('${product.sizeLiters}L · ${product.discountedPrice.toCurrency}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 13, color: isLowStock ? AppColors.error : AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Text('${product.stockQuantity} in stock',
                        style: TextStyle(fontSize: 12, color: isLowStock ? AppColors.error : AppColors.textTertiary)),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              Switch(
                value: product.isAvailable,
                onChanged: (value) =>
                    ref.read(vendorProductsProvider.notifier).toggleAvailability(product.id, value),
                activeTrackColor: AppColors.roleVendor,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.textTertiary),
                onSelected: (value) {
                  if (value == 'edit') {
                    context.pushNamed(
                      RouteNames.vendorEditProduct,
                      pathParameters: {'productId': product.id},
                      extra: product,
                    );
                  } else if (value == 'delete') {
                    _confirmDelete(context, ref);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete this product?'),
        content: Text('"${product.name}" will be permanently removed from your catalog.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(vendorProductsProvider.notifier).deleteProduct(product.id);
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
