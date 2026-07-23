import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../shared/extensions/datetime_extensions.dart';
import '../../../../shared/extensions/num_extensions.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/loaders/shimmer_loader.dart';
import '../../../../shared/widgets/loaders/state_views.dart';
import '../../domain/entities/wallet_entity.dart';
import '../providers/wallet_providers.dart';

class CustomerWalletScreen extends ConsumerWidget {
  const CustomerWalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(customerWalletSummaryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Wallet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async => ref.invalidate(customerWalletSummaryProvider),
        child: walletAsync.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              ShimmerBox(height: 140),
              SizedBox(height: 16),
              ShimmerBox(height: 60),
              SizedBox(height: 16),
              ShimmerBox(height: 200),
            ],
          ),
          error: (e, _) => ErrorStateView(
            message: e.toString(),
            onRetry: () => ref.invalidate(customerWalletSummaryProvider),
          ),
          data: (wallet) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _BalanceCard(balance: wallet.balance),
              if (wallet.totalOutstanding > 0) ...[
                const SizedBox(height: 12),
                _OutstandingBanner(
                  amount: wallet.totalOutstanding,
                  orderCount: wallet.pendingOrderCount,
                ),
              ],
              const SizedBox(height: 22),
              const Text('Transaction History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
              const SizedBox(height: 12),
              if (wallet.transactions.isEmpty)
                _emptyTransactions()
              else
                ..._buildSections(wallet.transactions),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSections(List<WalletTransactionEntity> transactions) {
    final sections = <MapEntry<String, List<WalletTransactionEntity>>>[];
    for (final t in transactions) {
      final label = t.createdAt.isToday
          ? 'Today'
          : t.createdAt.isYesterday
              ? 'Yesterday'
              : t.createdAt.toDayMonthYear;
      if (sections.isNotEmpty && sections.last.key == label) {
        sections.last.value.add(t);
      } else {
        sections.add(MapEntry(label, [t]));
      }
    }

    final widgets = <Widget>[];
    for (var s = 0; s < sections.length; s++) {
      final section = sections[s];
      widgets.add(Padding(
        padding: EdgeInsets.only(top: s == 0 ? 0 : 18, bottom: 8, left: 4),
        child: Text(section.key,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textTertiary, letterSpacing: 0.2)),
      ));
      widgets.add(_LedgerCard(transactions: section.value));
    }
    return widgets;
  }

  Widget _emptyTransactions() {
    return const AppCard(
      padding: EdgeInsets.all(24),
      radius: 16,
      child: Column(
        children: [
          Icon(Icons.receipt_long_rounded, size: 40, color: AppColors.textTertiary),
          SizedBox(height: 12),
          Text(
            'No transactions yet',
            style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4),
          Text(
            'Credits from overpayments and refunds will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final int balance;
  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.brand(opacity: 0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Available Balance',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            balance.toCurrency,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            balance > 0
                ? 'Auto-applied on your next order'
                : 'Credits will appear here from overpayments or refunds',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _OutstandingBanner extends StatelessWidget {
  final int amount;
  final int orderCount;
  const _OutstandingBanner({required this.amount, required this.orderCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: Color(0xFFF57C00), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You have ${amount.toCurrency} pending',
                  style: const TextStyle(
                    color: Color(0xFFE65100),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Across $orderCount order${orderCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Color(0xFFF57C00),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One connected card per date section with hairline dividers between
/// entries — matches the statement-style ledger used on Order History /
/// Order Tracking, instead of each transaction floating in its own card.
class _LedgerCard extends StatelessWidget {
  final List<WalletTransactionEntity> transactions;
  const _LedgerCard({required this.transactions});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          for (var i = 0; i < transactions.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 58, color: AppColors.divider),
            _TransactionRow(transaction: transactions[i]),
          ],
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final WalletTransactionEntity transaction;
  const _TransactionRow({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.isCredit;
    final color = isCredit ? AppColors.success : AppColors.error;
    final icon = isCredit ? Icons.add_rounded : Icons.remove_rounded;
    final sign = isCredit ? '+' : '−';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description ?? (isCredit ? 'Credit received' : 'Credit used'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      transaction.createdAt.toTime,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
                    ),
                    if (transaction.orderNumber != null) ...[
                      const Text(' · ', style: TextStyle(color: AppColors.textTertiary, fontSize: 11.5)),
                      Text(
                        '#${transaction.orderNumber}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$sign${transaction.amount.toCurrency}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
