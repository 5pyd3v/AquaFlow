import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../domain/entities/vendor_customer_entity.dart';
import '../providers/vendor_providers.dart';

class VendorCustomersScreen extends ConsumerStatefulWidget {
  const VendorCustomersScreen({super.key});

  @override
  ConsumerState<VendorCustomersScreen> createState() =>
      _VendorCustomersScreenState();
}

class _VendorCustomersScreenState extends ConsumerState<VendorCustomersScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<VendorCustomerEntity> _filtered(List<VendorCustomerEntity> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((c) {
      return c.fullName.toLowerCase().contains(q) ||
          c.phone.contains(q) ||
          (c.email?.toLowerCase().contains(q) ?? false) ||
          (c.pin?.contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(vendorCustomersProvider);
    final vendorId = ref.watch(myVendorProvider).valueOrNull?.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Customers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded),
            tooltip: 'Add Customer',
            onPressed: () => context.pushNamed(RouteNames.vendorCreateCustomer),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search by name, phone, email, or PIN...',
                prefixIcon:
                    const Icon(Icons.search_rounded, color: AppColors.textTertiary),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),
          Expanded(
            child: customersAsync.when(
              loading: () => ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: 5,
                itemBuilder: (_, __) => const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: ListTileSkeleton(),
                ),
              ),
              error: (error, _) => ErrorStateView(
                message: error.toString(),
                onRetry: () => ref.invalidate(vendorCustomersProvider),
              ),
              data: (customers) {
                final filtered = _filtered(customers);
                if (customers.isEmpty) {
                  return EmptyStateView(
                    title: 'No customers yet',
                    message:
                        'Create a customer account from "Add Customer" to get started.',
                    actionLabel: 'Add Customer',
                    onAction: () =>
                        context.pushNamed(RouteNames.vendorCreateCustomer),
                  );
                }
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48, color: AppColors.textTertiary.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        Text(
                          'No customers match "$_query"',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(vendorCustomersProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _CustomerCard(
                      customer: filtered[index],
                      vendorId: vendorId,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends ConsumerWidget {
  final VendorCustomerEntity customer;
  final String? vendorId;
  const _CustomerCard({required this.customer, required this.vendorId});

  bool get _hasRealEmail =>
      customer.email != null &&
      customer.email!.isNotEmpty &&
      !customer.email!.contains('@pin.aquaflow.app');

  Future<void> _confirmResetPin(BuildContext context, WidgetRef ref) async {
    final vId = vendorId;
    if (vId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset PIN?'),
        content: Text(
          "This generates a new login PIN for ${customer.fullName}. "
          'Their current PIN will stop working immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset PIN'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref.read(authControllerProvider.notifier).resetCustomerPin(
          vendorId: vId,
          customerProfileId: customer.profileId,
        );
    if (!context.mounted) return;

    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
      ),
      (newPin) {
        ref.invalidate(vendorCustomersProvider);
        _showNewPinDialog(context, newPin);
      },
    );
  }

  void _showNewPinDialog(BuildContext context, String pin) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('PIN reset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share this new login PIN with ${customer.fullName}.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Center(
                child: Text(
                  pin,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 10,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: pin));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PIN copied')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy PIN'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.pushNamed(
        RouteNames.vendorCustomerFinances,
        pathParameters: {'customerId': customer.profileId},
        extra: customer.fullName,
      ),
      child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: Text(
                    customer.fullName.isNotEmpty
                        ? customer.fullName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.phone_rounded,
                            size: 12, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          customer.phone.isNotEmpty ? customer.phone : 'No phone',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${customer.totalOrders}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const Text(
                    'orders',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (customer.address != null && customer.address!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_rounded,
                    size: 13, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    customer.address!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
              ],
            ),
          ],
          if (_hasRealEmail) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.alternate_email_rounded,
                    size: 13, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    customer.email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
              ],
            ),
          ],
          if (customer.outstanding > 0 || customer.availableCredit > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (customer.outstanding > 0)
                  _FinanceBadge(
                    label: 'Owes ${customer.outstanding.toCurrency}',
                    icon: Icons.error_outline_rounded,
                    color: AppColors.error,
                  ),
                if (customer.outstanding > 0 && customer.availableCredit > 0)
                  const SizedBox(width: 8),
                if (customer.availableCredit > 0)
                  _FinanceBadge(
                    label: 'Credit ${customer.availableCredit.toCurrency}',
                    icon: Icons.account_balance_wallet_rounded,
                    color: const Color(0xFF10B981),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Text(
                  'PIN',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    customer.pin ?? 'Not set',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: customer.pin != null
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
                if (customer.pin != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: customer.pin!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PIN copied')),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.copy_rounded,
                          size: 16, color: AppColors.primary),
                    ),
                  ),
                Tooltip(
                  message: 'Reset PIN',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: vendorId == null ? null : () => _confirmResetPin(context, ref),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.lock_reset_rounded,
                          size: 18, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _FinanceBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _FinanceBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
