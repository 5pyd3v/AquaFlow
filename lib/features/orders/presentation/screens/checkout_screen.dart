import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:collection/collection.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/services/logger_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../addresses/domain/entities/address_entity.dart';
import '../../../addresses/presentation/providers/address_providers.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../payments/presentation/providers/payment_providers.dart';
import '../providers/order_providers.dart';

enum _PaymentOption { cod, wallet, stripe, easypaisa, jazzcash }

extension on _PaymentOption {
  String get dbValue => switch (this) {
        _PaymentOption.cod => 'cod',
        _PaymentOption.wallet => 'wallet',
        _PaymentOption.stripe => 'stripe',
        _PaymentOption.easypaisa => 'easypaisa',
        _PaymentOption.jazzcash => 'jazzcash',
      };

  String get label => switch (this) {
        _PaymentOption.cod => 'Cash on Delivery',
        _PaymentOption.wallet => 'AquaFlow Wallet',
        _PaymentOption.stripe => 'Credit / Debit Card',
        _PaymentOption.easypaisa => 'EasyPaisa',
        _PaymentOption.jazzcash => 'JazzCash',
      };

  IconData get icon => switch (this) {
        _PaymentOption.cod => Icons.payments_outlined,
        _PaymentOption.wallet => Icons.account_balance_wallet_outlined,
        _PaymentOption.stripe => Icons.credit_card_rounded,
        _PaymentOption.easypaisa => Icons.phone_android_rounded,
        _PaymentOption.jazzcash => Icons.phone_android_rounded,
      };

  bool get isImplemented => this == _PaymentOption.cod;
}

/// Address selection, payment method, order summary, and emergency
/// delivery toggle — then a single tap invokes the `place_order` RPC
/// via [placeOrderControllerProvider]. Only Cash on Delivery is wired
/// to a live gateway right now; the other methods are shown (per the
/// "architecture-ready" requirement) but disabled with a clear note,
/// so nothing pretends to charge a card it can't actually charge.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  _PaymentOption _selectedPayment = _PaymentOption.cod;
  bool _isEmergency = false;
  bool _includeDeposit = false;

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final addressesAsync = ref.watch(addressListProvider);
    final selectedAddressId = ref.watch(selectedAddressIdProvider);
    final placingOrder = ref.watch(placeOrderControllerProvider).isLoading;

    final baseDeliveryFee = cart.subtotal >= AppConfig.minOrderAmount ? 0.0 : 50.0;
    final emergencyFee = _isEmergency ? AppConfig.emergencyDeliverySurcharge : 0.0;
    final deliveryFee = baseDeliveryFee + emergencyFee;
    final depositTotal = _includeDeposit ? cart.depositTotal : 0.0;
    final total = cart.subtotal + depositTotal + deliveryFee;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Delivery Address', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          addressesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Could not load addresses: $e'),
            data: (addresses) {
              final selected = addresses.where((a) => a.id == selectedAddressId).firstOrNull ??
                  addresses.where((a) => a.isDefault).firstOrNull ??
                  addresses.firstOrNull;
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  final picked = await context.pushNamed<AddressEntity>(RouteNames.addressSelect);
                  if (picked != null) {
                    ref.read(selectedAddressIdProvider.notifier).state = picked.id;
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: selected == null
                            ? const Text('Select a delivery address')
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(selected.label.display,
                                      style: Theme.of(context).textTheme.titleSmall),
                                  Text(selected.fullAddress,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: AppColors.textSecondary)),
                                ],
                              ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isEmergency,
            onChanged: (value) => setState(() => _isEmergency = value),
            activeTrackColor: AppColors.primary,
            title: const Text('Emergency Delivery', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Get it within 30 minutes for an extra ${AppConfig.emergencyDeliverySurcharge.toCurrency}'),
          ),
          if (cart.depositTotal > 0)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _includeDeposit,
              onChanged: (value) => setState(() => _includeDeposit = value),
              activeTrackColor: AppColors.primary,
              title: const Text('Include Bottle Deposit', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Refundable deposit of ${cart.depositTotal.toCurrency} for returnable bottles'),
            ),
          const SizedBox(height: 12),
          Text('Payment Method', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          ..._PaymentOption.values.map((option) => _PaymentTile(
                option: option,
                isSelected: _selectedPayment == option,
                onTap: option.isImplemented
                    ? () => setState(() => _selectedPayment = option)
                    : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('${option.label} is coming soon — the architecture already supports it.'),
                        )),
              )),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _SummaryLine('Subtotal', cart.subtotal),
                if (_includeDeposit && depositTotal > 0) _SummaryLine('Bottle Deposit (refundable)', depositTotal),
                if (emergencyFee > 0) _SummaryLine('Emergency Surcharge', emergencyFee),
                _SummaryLine('Delivery Fee', baseDeliveryFee),
                const Divider(height: 20),
                _SummaryLine('Total', total, isBold: true),
              ],
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: PrimaryButton(
            label: 'Place Order · ${total.toCurrency}',
            isLoading: placingOrder,
            onPressed: () => _placeOrder(context, addressesAsync.valueOrNull, deliveryFee),
          ),
        ),
      ),
    );
  }

  Future<void> _placeOrder(
    BuildContext context,
    List<AddressEntity>? addresses,
    double deliveryFee,
  ) async {
    final cart = ref.read(cartProvider);
    final selectedAddressId = ref.read(selectedAddressIdProvider);
    final address = addresses?.where((a) => a.id == selectedAddressId).firstOrNull ??
        addresses?.where((a) => a.isDefault).firstOrNull ??
        addresses?.firstOrNull;

    if (address == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a delivery address'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (cart.vendorId == null || cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your cart is empty'), backgroundColor: AppColors.error),
      );
      return;
    }

    final result = await ref.read(placeOrderControllerProvider.notifier).placeOrder(
          addressId: address.id,
          vendorId: cart.vendorId!,
          items: cart.items,
          paymentMethod: _selectedPayment.dbValue,
          isEmergency: _isEmergency,
          includeDeposit: _includeDeposit,
          deliveryFee: deliveryFee,
        );

    if (!context.mounted) return;

    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
      ),
      (order) async {
        ref.read(cartProvider.notifier).clear();
        // Auto-apply any available customer wallet credit to the fresh
        // order. Non-breaking: if the customer has no credit the RPC
        // applies 0 and the flow is identical to before. Failures here
        // must never block navigation to tracking.
        try {
          await ref.read(paymentRepositoryProvider).applyCustomerCredit(orderId: order.id);
        } catch (e) {
          AppLogger.warning('Failed to auto-apply wallet credit to order ${order.id}', e);
        }
        if (!context.mounted) return;
        context.pushReplacementNamed(
          RouteNames.orderTracking,
          pathParameters: {'orderId': order.id},
        );
      },
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final _PaymentOption option;
  final bool isSelected;
  final VoidCallback onTap;
  const _PaymentTile({required this.option, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 1.6 : 1),
          ),
          child: Row(
            children: [
              Icon(option.icon, color: option.isImplemented ? AppColors.primary : AppColors.textTertiary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  option.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: option.isImplemented ? AppColors.textPrimary : AppColors.textTertiary,
                  ),
                ),
              ),
              if (!option.isImplemented)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(20)),
                  child: const Text('Soon', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                )
              else
                Radio<bool>(value: true, groupValue: isSelected ? true : null, onChanged: (_) => onTap()),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final double value;
  final bool isBold;
  const _SummaryLine(this.label, this.value, {this.isBold = false});

  @override
  Widget build(BuildContext context) {
    final style = isBold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value <= 0 ? 'Free' : value.toCurrency, style: style),
        ],
      ),
    );
  }
}
