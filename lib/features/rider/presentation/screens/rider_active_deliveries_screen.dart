import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/order_status.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../../payments/presentation/providers/payment_providers.dart';
import '../../../payments/presentation/screens/payment_collection_screen.dart';
import '../../domain/entities/rider_delivery_entity.dart';
import '../providers/rider_providers.dart';

/// The rider's working screen — one card per assigned delivery, with
/// a state-machine action button that walks it forward: Picked Up →
/// On the Way → Complete (which pops the OTP dialog). Also owns the
/// live-location broadcast: starts the moment there's at least one
/// active delivery, stops when the list is empty or this screen
/// closes.
class RiderActiveDeliveriesScreen extends ConsumerStatefulWidget {
  const RiderActiveDeliveriesScreen({super.key});

  @override
  ConsumerState<RiderActiveDeliveriesScreen> createState() => _RiderActiveDeliveriesScreenState();
}

class _RiderActiveDeliveriesScreenState extends ConsumerState<RiderActiveDeliveriesScreen> {
  @override
  Widget build(BuildContext context) {
    final deliveriesAsync = ref.watch(activeDeliveriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Active Deliveries')),
      body: deliveriesAsync.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: 3,
          itemBuilder: (_, __) => const Padding(padding: EdgeInsets.only(bottom: 12), child: ListTileSkeleton()),
        ),
        error: (error, _) =>
            ErrorStateView(message: error.toString(), onRetry: () => ref.invalidate(activeDeliveriesProvider)),
        data: (deliveries) {
          if (deliveries.isEmpty) {
            return const EmptyStateView(
              title: 'No active deliveries',
              message: "You're all caught up. New assignments will show up here the moment a vendor assigns you.",
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(activeDeliveriesProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: deliveries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) => _DeliveryCard(delivery: deliveries[index]),
            ),
          );
        },
      ),
    );
  }
}

class _DeliveryCard extends ConsumerWidget {
  final RiderDeliveryEntity delivery;
  const _DeliveryCard({required this.delivery});

  bool get _hasValidCoordinates =>
      delivery.deliveryLat != 0 || delivery.deliveryLng != 0;

  Future<void> _openNavigation(BuildContext context) async {
    if (!_hasValidCoordinates) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No delivery coordinates available for navigation'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${delivery.deliveryLat},${delivery.deliveryLng}&travelmode=driving',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: delivery.isEmergency ? AppColors.error : AppColors.border,
          width: delivery.isEmergency ? 1.4 : 1,
        ),
        boxShadow: delivery.isEmergency
            ? AppShadows.brand(color: AppColors.error, opacity: 0.18)
            : AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('#${delivery.orderNumber}', style: Theme.of(context).textTheme.titleSmall)),
              if (delivery.isEmergency)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(20)),
                  child: const Text('URGENT', style: TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: delivery.status.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(delivery.status.label, style: TextStyle(color: delivery.status.color, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoRow(icon: Icons.storefront_outlined, label: 'Pickup', value: delivery.vendorAddress ?? delivery.vendorName),
          const SizedBox(height: 6),
          _InfoRow(icon: Icons.location_on_outlined, label: 'Drop-off', value: delivery.deliveryAddress),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 16, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Expanded(child: Text(delivery.customerName, style: Theme.of(context).textTheme.bodyMedium)),
              if (delivery.customerPhone.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.call_rounded, size: 18, color: AppColors.success),
                  onPressed: () => launchUrl(Uri.parse('tel:${delivery.customerPhone}')),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                delivery.isCodPayment ? 'Collect ${delivery.totalAmount.toCurrency} (COD)' : 'Prepaid',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: delivery.isCodPayment ? AppColors.warning : AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Text(delivery.totalAmount.toCurrency, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 300;
              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: () => _openNavigation(context),
                        icon: const Icon(Icons.directions_rounded, size: 18),
                        label: const Text('Navigate'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 46,
                      child: _ActionButton(delivery: delivery),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: () => _openNavigation(context),
                        icon: const Icon(Icons.directions_rounded, size: 18),
                        label: const Text('Navigate'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 46,
                      child: _ActionButton(delivery: delivery),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              children: [
                TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends ConsumerWidget {
  final RiderDeliveryEntity delivery;
  const _ActionButton({required this.delivery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (delivery.status) {
      case OrderStatus.assigned:
        return ElevatedButton(
          onPressed: () =>
              ref.read(activeDeliveriesProvider.notifier).updateStatus(delivery.id, OrderStatus.pickedUp),
          child: const Text('Mark Picked Up'),
        );
      case OrderStatus.pickedUp:
        return ElevatedButton(
          onPressed: () =>
              ref.read(activeDeliveriesProvider.notifier).updateStatus(delivery.id, OrderStatus.onTheWay),
          child: const Text('Start Delivery'),
        );
      case OrderStatus.onTheWay:
        return ElevatedButton(
          onPressed: () => _showOtpDialog(context, ref),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
          child: const Text('Complete Delivery'),
        );
      default:
        return const SizedBox();
    }
  }

  void _showOtpDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Enter Delivery Code'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Ask the customer for their 4-digit delivery code to confirm the handoff.",
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: controller,
                  label: 'Delivery Code',
                  hint: '0000',
                  keyboardType: TextInputType.number,
                  validator: (v) => Validators.otp(v, length: 4),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => isLoading = true);
                      final otp = controller.text.trim();

                      if (delivery.isCodPayment) {
                        // Split flow: verify PIN only (no state change), then
                        // open the payment screen. The order is marked
                        // delivered ONLY after payment is committed there —
                        // no "delivered but unpaid" gap is possible.
                        final verify = await ref
                            .read(paymentControllerProvider.notifier)
                            .verifyPin(orderId: delivery.id, otp: otp);
                        if (!dialogContext.mounted) return;
                        setState(() => isLoading = false);
                        await verify.fold(
                          (failure) async => ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
                          ),
                          (_) async {
                            Navigator.of(dialogContext).pop();
                            final completed = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => PaymentCollectionScreen(
                                  args: PaymentCollectionArgs(
                                    orderId: delivery.id,
                                    orderNumber: delivery.orderNumber,
                                    otp: otp,
                                    vendorId: delivery.vendorId,
                                    outstanding: delivery.totalAmount.round(),
                                    isCod: true,
                                  ),
                                ),
                              ),
                            );
                            if (completed == true) {
                              ref.invalidate(activeDeliveriesProvider);
                              ref.invalidate(deliveryHistoryProvider);
                              ref.invalidate(riderStatsProvider);
                            }
                          },
                        );
                        return;
                      }

                      // Prepaid / non-COD: complete directly, no payment step.
                      final result = await ref
                          .read(activeDeliveriesProvider.notifier)
                          .completeDelivery(delivery.id, otp);
                      if (!dialogContext.mounted) return;
                      setState(() => isLoading = false);
                      result.fold(
                        (failure) => ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
                        ),
                        (_) {
                          Navigator.of(dialogContext).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Delivery completed 🎉'), backgroundColor: AppColors.success),
                          );
                        },
                      );
                    },
              child: isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }
}
