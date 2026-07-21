import '../../domain/entities/payment_amendment_entity.dart';

class PaymentAmendmentModel extends PaymentAmendmentEntity {
  const PaymentAmendmentModel({
    required super.id,
    required super.paymentTransactionId,
    super.riderId,
    super.riderName,
    required super.vendorId,
    required super.action,
    super.requestedAmount,
    super.currentAmount,
    super.orderNumber,
    required super.reason,
    required super.status,
    required super.createdAt,
    super.resolvedAt,
  });

  factory PaymentAmendmentModel.fromJson(Map<String, dynamic> json) {
    // Optional joins: payment_transactions(amount, orders(order_number)),
    // riders(profiles(full_name)).
    final txn = json['payment_transactions'] as Map<String, dynamic>?;
    final txnOrder = txn?['orders'] as Map<String, dynamic>?;
    final rider = json['riders'] as Map<String, dynamic>?;
    final riderProfile = rider?['profiles'] as Map<String, dynamic>?;
    return PaymentAmendmentModel(
      id: json['id'] as String,
      paymentTransactionId: json['payment_transaction_id'] as String,
      riderId: json['rider_id'] as String?,
      riderName: json['rider_name'] as String? ?? riderProfile?['full_name'] as String?,
      vendorId: json['vendor_id'] as String,
      action: (json['requested_action'] as String?) == 'delete'
          ? AmendmentAction.delete
          : AmendmentAction.edit,
      requestedAmount: (json['requested_amount'] as num?)?.round(),
      currentAmount: (json['current_amount'] as num?)?.round() ??
          (txn?['amount'] as num?)?.round() ??
          0,
      orderNumber: json['order_number'] as String? ?? txnOrder?['order_number'] as String?,
      reason: json['reason'] as String? ?? '',
      status: switch (json['status'] as String?) {
        'approved' => AmendmentStatus.approved,
        'rejected' => AmendmentStatus.rejected,
        _ => AmendmentStatus.pending,
      },
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.tryParse(json['resolved_at'] as String)
          : null,
    );
  }
}
