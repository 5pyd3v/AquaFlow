import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../../rider/presentation/providers/rider_providers.dart';
import '../providers/settlement_providers.dart';
import '../widgets/settlement_history_tile.dart';

class RiderCodWalletScreen extends ConsumerWidget {
  const RiderCodWalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riderAsync = ref.watch(myRiderProvider);
    final settlementsAsync = ref.watch(riderSettlementsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(riderSettlementsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _WalletHeader(),
              const SizedBox(height: 20),
              riderAsync.when(
                loading: () => const _BalanceSkeleton(),
                error: (e, _) => ErrorStateView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(myRiderProvider),
                ),
                data: (rider) {
                  if (rider.vendorId == null) {
                    return _NoVendorCard();
                  }
                  return _BalanceSection(
                    riderId: rider.id,
                    vendorId: rider.vendorId!,
                    vendorName: rider.vendorName ?? 'Vendor',
                  );
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: _SectionLabel(label: 'Settlement History')),
                  TextButton.icon(
                    onPressed: () =>
                        context.pushNamed(RouteNames.riderSettlementHistory),
                    icon: const Text('View all'),
                    label: const Icon(Icons.arrow_forward_rounded, size: 16),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Pending Payments Collection CTA
              riderAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (e, _) => const SizedBox.shrink(),
                data: (rider) {
                  if (rider.vendorId == null) return const SizedBox.shrink();
                  return InkWell(
                    onTap: () =>
                        context.pushNamed(RouteNames.riderPendingPayments),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFFFE0B2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF8F00).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.payments_rounded,
                                color: Color(0xFFE65100), size: 24),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Collect Pending Payments',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Collect debt from customers on your assigned orders',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_rounded,
                              color: AppColors.textTertiary, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              settlementsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => ErrorStateView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(riderSettlementsProvider),
                ),
                data: (settlements) {
                  if (settlements.isEmpty) {
                    return const _EmptyHistory();
                  }
                  return Column(
                    children: settlements
                        .map((s) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: SettlementHistoryTile(settlement: s),
                            ))
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF8F00), Color(0xFFE65100)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.account_balance_wallet_rounded,
              color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'COD Wallet',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
              ),
              Text(
                'Manage cash-on-delivery settlements',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BalanceSection extends ConsumerWidget {
  final String riderId;
  final String vendorId;
  final String vendorName;

  const _BalanceSection({
    required this.riderId,
    required this.vendorId,
    required this.vendorName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(riderCodBalanceProvider(vendorId));

    return balanceAsync.when(
      loading: () => const _BalanceSkeleton(),
      error: (e, _) => ErrorStateView(
        message: e.toString(),
        onRetry: () => ref.invalidate(riderCodBalanceProvider(vendorId)),
      ),
      data: (balance) => Column(
        children: [
          _OutstandingBalanceCard(
            outstanding: balance.outstanding,
            pending: balance.pending,
            vendorName: vendorName,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Total Collected',
                  value: balance.totalCollected.toCurrency,
                  icon: Icons.download_rounded,
                  color: const Color(0xFF2196F3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'Total Settled',
                  value: balance.totalVerified.toCurrency,
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: balance.outstanding > 0
                  ? () => _showSubmitSheet(context, ref, balance.outstanding)
                  : null,
              icon: const Icon(Icons.send_rounded, size: 20),
              label: const Text('Submit Cash'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSubmitSheet(BuildContext context, WidgetRef ref, double maxAmount) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GenerateSettlementSheet(
        riderId: riderId,
        vendorId: vendorId,
        vendorName: vendorName,
        maxAmount: maxAmount,
        ref: ref,
      ),
    );
  }
}

class _OutstandingBalanceCard extends StatelessWidget {
  final double outstanding;
  final double pending;
  final String vendorName;

  const _OutstandingBalanceCard({
    required this.outstanding,
    required this.pending,
    required this.vendorName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8F00), Color(0xFFE65100)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.brand(color: const Color(0xFFE65100), opacity: 0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storefront_rounded,
                  color: Colors.white.withValues(alpha: 0.85), size: 16),
              const SizedBox(width: 6),
              Text(
                vendorName,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Outstanding Balance',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            outstanding.toCurrency,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          if (pending > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${pending.toCurrency} pending verification',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoVendorCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.link_off_rounded, size: 48, color: AppColors.textTertiary),
          SizedBox(height: 12),
          Text(
            'Not linked to a vendor',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Ask your vendor to link your account to start managing COD settlements.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.receipt_long_rounded, size: 48, color: AppColors.textTertiary.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          const Text(
            'No settlements yet',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'When you submit cash to your vendor, records will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _BalanceSkeleton extends StatelessWidget {
  const _BalanceSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generate settlement bottom sheet
// ---------------------------------------------------------------------------
class _GenerateSettlementSheet extends ConsumerStatefulWidget {
  final String riderId;
  final String vendorId;
  final String vendorName;
  final double maxAmount;
  final WidgetRef ref;

  const _GenerateSettlementSheet({
    required this.riderId,
    required this.vendorId,
    required this.vendorName,
    required this.maxAmount,
    required this.ref,
  });

  @override
  ConsumerState<_GenerateSettlementSheet> createState() =>
      _GenerateSettlementSheetState();
}

class _GenerateSettlementSheetState
    extends ConsumerState<_GenerateSettlementSheet> {
  final _amountController = TextEditingController();
  String? _generatedCode;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    if (amount > widget.maxAmount) {
      setState(() => _error = 'Amount exceeds outstanding balance');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await ref.read(settlementControllerProvider.notifier).generate(
          riderId: widget.riderId,
          vendorId: widget.vendorId,
          amount: amount,
        );

    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _isLoading = false;
        _error = failure.message;
      }),
      (data) => setState(() {
        _isLoading = false;
        _generatedCode = data.code;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: _generatedCode != null
          ? _CodeDisplay(code: _generatedCode!, amount: double.parse(_amountController.text))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Submit Cash to ${widget.vendorName}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Max: ${widget.maxAmount.toCurrency}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Amount (PKR)',
                    prefixText: 'PKR ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _QuickAmountChip(
                      label: 'All',
                      onTap: () => _amountController.text =
                          widget.maxAmount.toStringAsFixed(0),
                    ),
                    _QuickAmountChip(
                      label: '½',
                      onTap: () => _amountController.text =
                          (widget.maxAmount / 2).toStringAsFixed(0),
                    ),
                    _QuickAmountChip(
                      label: '1000',
                      onTap: () => _amountController.text = '1000',
                    ),
                    _QuickAmountChip(
                      label: '500',
                      onTap: () => _amountController.text = '500',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _isLoading ? null : _generate,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Generate Code',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                ),
              ],
            ),
    );
  }
}

class _QuickAmountChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickAmountChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: AppColors.surfaceMuted,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    );
  }
}

class _CodeDisplay extends StatelessWidget {
  final String code;
  final double amount;
  const _CodeDisplay({required this.code, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded,
              color: Color(0xFF10B981), size: 40),
        ),
        const SizedBox(height: 16),
        const Text(
          'Tell this code to your vendor',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Code copied!'), duration: Duration(seconds: 2)),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.copy_rounded, size: 20, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Amount: ${amount.toCurrency}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Code expires in 24 hours',
          style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}
