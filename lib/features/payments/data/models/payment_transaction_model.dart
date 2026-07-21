import '../../domain/entities/payment_transaction_entity.dart';

class PaymentTransactionModel extends PaymentTransactionEntity {
  const PaymentTransactionModel({
    required super.id,
    required super.orderId,
    super.orderNumber,
    required super.customerProfileId,
    super.customerName,
    super.riderId,
    super.riderName,
    required super.vendorId,
    required super.amount,
    required super.outstandingBefore,
    required super.outstandingAfter,
    required super.creditBefore,
    required super.creditAfter,
    required super.type,
    required super.status,
    required super.settled,
    super.settlementId,
    super.notes,
    super.receiptUrl,
    required super.createdAt,
  });

  factory PaymentTransactionModel.fromJson(Map<String, dynamic> json) {
    int i(String k) => (json[k] as num?)?.round() ?? 0;
    // Supports both a flat ledger-entry row and a full table row with
    // optional joined `orders`/`profiles`/`payment_receipts` relations.
    final order = json['orders'] as Map<String, dynamic>?;
    final receipts = json['payment_receipts'] as List?;
    return PaymentTransactionModel(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      orderNumber: json['order_number'] as String? ?? order?['order_number'] as String?,
      customerProfileId: json['customer_profile_id'] as String? ?? '',
      customerName: json['customer_name'] as String?,
      riderId: json['rider_id'] as String?,
      riderName: json['rider_name'] as String?,
      vendorId: json['vendor_id'] as String? ?? '',
      amount: i('amount'),
      outstandingBefore: i('outstanding_before'),
      outstandingAfter: i('outstanding_after'),
      creditBefore: i('credit_before'),
      creditAfter: i('credit_after'),
      type: _parseType(json['payment_type'] as String?),
      status: _parseStatus(json['status'] as String?),
      settled: json['settled'] as bool? ?? false,
      settlementId: json['settlement_id'] as String?,
      notes: json['notes'] as String?,
      receiptUrl: json['receipt_url'] as String? ??
          (receipts != null && receipts.isNotEmpty
              ? (receipts.first as Map<String, dynamic>)['receipt_url'] as String?
              : null),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  static PaymentType _parseType(String? t) => switch (t) {
        'full' => PaymentType.full,
        'partial' => PaymentType.partial,
        'over' => PaymentType.over,
        'credit' => PaymentType.credit,
        'refund' => PaymentType.refund,
        'adjustment' => PaymentType.adjustment,
        _ => PaymentType.partial,
      };

  static PaymentTxnStatus _parseStatus(String? s) => switch (s) {
        'edited' => PaymentTxnStatus.edited,
        'deleted' => PaymentTxnStatus.deleted,
        _ => PaymentTxnStatus.active,
      };
}
