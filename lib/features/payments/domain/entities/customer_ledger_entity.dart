import 'package:equatable/equatable.dart';
import 'payment_transaction_entity.dart';

/// Accounting-style ledger for a single customer (vendor-scoped view).
/// The [entries] are the chronological payment/credit rows; the summary
/// figures are pre-aggregated server-side so the UI does no math.
class CustomerLedgerEntity extends Equatable {
  final int totalPurchases;
  final int totalPaid;
  final int outstanding;
  final int availableCredit;
  final DateTime? lastPaymentAt;
  final List<PaymentTransactionEntity> entries;

  const CustomerLedgerEntity({
    required this.totalPurchases,
    required this.totalPaid,
    required this.outstanding,
    required this.availableCredit,
    this.lastPaymentAt,
    this.entries = const [],
  });

  @override
  List<Object?> get props =>
      [totalPurchases, totalPaid, outstanding, availableCredit, lastPaymentAt, entries];
}
