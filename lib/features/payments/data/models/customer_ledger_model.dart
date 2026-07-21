import '../../domain/entities/customer_ledger_entity.dart';
import 'payment_transaction_model.dart';

class CustomerLedgerModel extends CustomerLedgerEntity {
  const CustomerLedgerModel({
    required super.totalPurchases,
    required super.totalPaid,
    required super.outstanding,
    required super.availableCredit,
    super.lastPaymentAt,
    super.entries,
  });

  factory CustomerLedgerModel.fromJson(Map<String, dynamic> json) {
    int i(String k) => (json[k] as num?)?.round() ?? 0;
    final entries = (json['entries'] as List?)
            ?.map((e) => PaymentTransactionModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    return CustomerLedgerModel(
      totalPurchases: i('total_purchases'),
      totalPaid: i('total_paid'),
      outstanding: i('outstanding'),
      availableCredit: i('available_credit'),
      lastPaymentAt: json['last_payment_at'] != null
          ? DateTime.tryParse(json['last_payment_at'] as String)
          : null,
      entries: entries,
    );
  }
}
