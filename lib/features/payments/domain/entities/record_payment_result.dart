import 'package:equatable/equatable.dart';

/// Result returned by `complete_delivery_with_payment` — enough for the
/// UI to show the rider exactly what happened (applied vs. credited).
class RecordPaymentResult extends Equatable {
  final String transactionId;
  final String orderId;
  final int amount;
  final int applied;
  final int excessCredit;
  final int outstandingAfter;
  final int creditAfter;
  final String paymentType;

  const RecordPaymentResult({
    required this.transactionId,
    required this.orderId,
    required this.amount,
    required this.applied,
    required this.excessCredit,
    required this.outstandingAfter,
    required this.creditAfter,
    required this.paymentType,
  });

  factory RecordPaymentResult.fromJson(Map<String, dynamic> json) {
    return RecordPaymentResult(
      transactionId: json['transaction_id'] as String,
      orderId: json['order_id'] as String,
      amount: (json['amount'] as num?)?.round() ?? 0,
      applied: (json['applied'] as num?)?.round() ?? 0,
      excessCredit: (json['excess_credit'] as num?)?.round() ?? 0,
      outstandingAfter: (json['outstanding_after'] as num?)?.round() ?? 0,
      creditAfter: (json['credit_after'] as num?)?.round() ?? 0,
      paymentType: json['payment_type'] as String? ?? 'full',
    );
  }

  @override
  List<Object?> get props =>
      [transactionId, orderId, amount, applied, excessCredit, outstandingAfter, creditAfter, paymentType];
}
