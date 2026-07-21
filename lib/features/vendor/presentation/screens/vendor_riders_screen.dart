import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/inputs/app_text_field.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../domain/entities/vendor_rider_entity.dart';
import '../providers/vendor_providers.dart';
import '../widgets/vendor_rider_detail_sheet.dart';

class VendorRidersScreen extends ConsumerWidget {
  const VendorRidersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ridersAsync = ref.watch(vendorRidersProvider);
    final vendorId = ref.watch(myVendorProvider).valueOrNull?.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Riders')),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: AppShadows.brand(color: AppColors.roleVendor, opacity: 0.35),
        ),
        child: FloatingActionButton.extended(
          onPressed: () => _showLinkRiderDialog(context, ref),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Link Rider'),
          backgroundColor: AppColors.roleVendor,
          elevation: 0,
        ),
      ),
      body: ridersAsync.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: 3,
          itemBuilder: (_, __) => const Padding(padding: EdgeInsets.only(bottom: 12), child: ListTileSkeleton()),
        ),
        error: (error, _) => ErrorStateView(message: error.toString(), onRetry: () => ref.invalidate(vendorRidersProvider)),
        data: (riders) {
          if (riders.isEmpty) {
            return EmptyStateView(
              title: 'No riders yet',
              message: 'Link a rider who has already signed up on AquaFlow using their phone number.',
              actionLabel: 'Link a Rider',
              onAction: () => _showLinkRiderDialog(context, ref),
            );
          }
          final pending = riders.where((r) => !r.isApproved).toList();
          final approved = riders.where((r) => r.isApproved).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(vendorRidersProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
              children: [
                if (pending.isNotEmpty) ...[
                  const _SectionHeader(
                    label: 'Pending Requests',
                    icon: Icons.pending_actions_rounded,
                  ),
                  const SizedBox(height: 12),
                  for (final rider in pending) ...[
                    _PendingRiderTile(rider: rider),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 12),
                ],
                if (approved.isNotEmpty) ...[
                  if (pending.isNotEmpty) ...[
                    const _SectionHeader(
                      label: 'Active Riders',
                      icon: Icons.verified_user_rounded,
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (final rider in approved) ...[
                    _RiderTile(rider: rider, vendorId: vendorId ?? ''),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showLinkRiderDialog(BuildContext context, WidgetRef ref) {
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Link a Rider'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The rider must already have an AquaFlow account (self-registered as a Delivery Rider).',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: phoneController,
                  label: 'Rider Phone Number',
                  hint: '+923001234567',
                  keyboardType: TextInputType.phone,
                  validator: Validators.phone,
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
                      final result = await ref
                          .read(vendorRidersProvider.notifier)
                          .linkByPhone(phoneController.text.trim());
                      if (!dialogContext.mounted) return;
                      setState(() => isLoading = false);
                      result.fold(
                        (failure) => ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text(failure.message), backgroundColor: AppColors.error),
                        ),
                        (_) => Navigator.of(dialogContext).pop(),
                      );
                    },
              child: isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Link'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

/// A rider who self-registered under this vendor and is waiting to be
/// approved. The vendor approves or rejects the request here — this is
/// the vendor-side replacement for admin approval.
class _PendingRiderTile extends ConsumerStatefulWidget {
  final VendorRiderEntity rider;
  const _PendingRiderTile({required this.rider});

  @override
  ConsumerState<_PendingRiderTile> createState() => _PendingRiderTileState();
}

class _PendingRiderTileState extends ConsumerState<_PendingRiderTile> {
  bool _busy = false;

  Future<void> _run(Future<Result<void>> Function() action, String errorPrefix) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$errorPrefix: ${failure.message}'), backgroundColor: AppColors.error),
      ),
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final rider = widget.rider;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.5)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFCB70), Color(0xFFFFA531)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppShadows.brand(color: AppColors.roleRider, opacity: 0.28),
                ),
                child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rider.fullName, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(rider.phone,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Awaiting approval',
                        style: TextStyle(fontSize: 11, color: AppColors.secondary, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(4),
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmReject(context),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _run(
                      () => ref.read(vendorRidersProvider.notifier).approve(rider.id),
                      'Could not approve',
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _confirmReject(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Reject this request?'),
        content: Text(
          '${widget.rider.fullName} will be unlinked from your business and won\'t be able to deliver for you.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _run(
                () => ref.read(vendorRidersProvider.notifier).reject(widget.rider.id),
                'Could not reject',
              );
            },
            child: const Text('Reject', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _RiderTile extends ConsumerWidget {
  final VendorRiderEntity rider;
  final String vendorId;
  const _RiderTile({required this.rider, required this.vendorId});

  Color get _statusColor => switch (rider.status) {
        RiderStatus.available => AppColors.success,
        RiderStatus.onDelivery => AppColors.primary,
        RiderStatus.offline => AppColors.textTertiary,
        RiderStatus.suspended => AppColors.error,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => VendorRiderDetailSheet.show(context, rider, vendorId),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFCB70), Color(0xFFFFA531)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow:
                    AppShadows.brand(color: AppColors.roleRider, opacity: 0.28),
              ),
              child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rider.fullName, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(rider.phone, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(rider.status.label, style: TextStyle(fontSize: 12, color: _statusColor, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      const Icon(Icons.star_rounded, size: 13, color: AppColors.secondary),
                      Text(rider.rating.toStringAsFixed(1), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.textTertiary),
              onSelected: (value) {
                if (value == 'unlink') _confirmUnlink(context, ref);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'unlink', child: Text('Unlink Rider')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmUnlink(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Unlink this rider?'),
        content: Text('${rider.fullName} will no longer receive delivery assignments from your business.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(vendorRidersProvider.notifier).unlink(rider.id);
            },
            child: const Text('Unlink', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
