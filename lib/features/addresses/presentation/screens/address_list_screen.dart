import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../domain/entities/address_entity.dart';
import '../providers/address_providers.dart';

/// Address book, used both from Account settings and — when
/// [selectionMode] is true — from checkout to pick a delivery address.
class AddressListScreen extends ConsumerWidget {
  final bool selectionMode;
  const AddressListScreen({super.key, this.selectionMode = false});

  IconData _iconFor(AddressLabel label) => switch (label) {
        AddressLabel.home => Icons.home_rounded,
        AddressLabel.office => Icons.business_rounded,
        AddressLabel.other => Icons.location_on_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(addressListProvider);
    final selectedId = ref.watch(selectedAddressIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text(selectionMode ? 'Select Delivery Address' : 'My Addresses')),
      body: addressesAsync.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: 4,
          itemBuilder: (_, __) => const ListTileSkeleton(),
        ),
        error: (error, _) => ErrorStateView(
          message: error.toString(),
          onRetry: () => ref.invalidate(addressListProvider),
        ),
        data: (addresses) {
          if (addresses.isEmpty) {
            return EmptyStateView(
              title: 'No addresses yet',
              message: 'Add a delivery address to start ordering water.',
              actionLabel: 'Add Address',
              onAction: () => _openAddAddress(context),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: addresses.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final address = addresses[index];
              final isSelected = selectionMode &&
                  (selectedId == address.id || (selectedId == null && address.isDefault));
              return _AddressCard(
                address: address,
                icon: _iconFor(address.label),
                isSelected: isSelected,
                selectionMode: selectionMode,
                onTap: selectionMode
                    ? () {
                        ref.read(selectedAddressIdProvider.notifier).state = address.id;
                        context.pop(address);
                      }
                    : null,
                onSetDefault: () => ref.read(addressListProvider.notifier).setDefault(address.id),
                onDelete: () => ref.read(addressListProvider.notifier).deleteAddress(address.id),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: PrimaryButton(
            label: 'Add New Address',
            icon: Icons.add_location_alt_rounded,
            outlined: true,
            onPressed: () => _openAddAddress(context),
          ),
        ),
      ),
    );
  }

  Future<void> _openAddAddress(BuildContext context) async {
    await context.pushNamed(RouteNames.addAddress);
  }
}

class _AddressCard extends StatelessWidget {
  final AddressEntity address;
  final IconData icon;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback? onTap;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  const _AddressCard({
    required this.address,
    required this.icon,
    required this.isSelected,
    required this.selectionMode,
    required this.onTap,
    required this.onSetDefault,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.6 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(address.label.display, style: Theme.of(context).textTheme.titleMedium),
                      if (address.isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.successBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Default',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.success)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(address.fullAddress,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                  if (address.landmark != null) ...[
                    const SizedBox(height: 2),
                    Text('Landmark: ${address.landmark}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
                  ],
                ],
              ),
            ),
            if (!selectionMode)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.textTertiary),
                onSelected: (value) {
                  if (value == 'default') onSetDefault();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  if (!address.isDefault)
                    const PopupMenuItem(value: 'default', child: Text('Set as default')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
