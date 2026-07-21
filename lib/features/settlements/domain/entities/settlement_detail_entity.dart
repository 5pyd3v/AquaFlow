import 'package:equatable/equatable.dart';

/// One payment covered by a settlement (for the audit detail view).
class SettlementIncludedPayment extends Equatable {
  final String id;
  final String orderId;
  final int amount;
  final String paymentType;
  final DateTime createdAt;

  const SettlementIncludedPayment({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.paymentType,
    required this.createdAt,
  });

  factory SettlementIncludedPayment.fromJson(Map<String, dynamic> json) {
    return SettlementIncludedPayment(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      amount: (json['amount'] as num?)?.round() ?? 0,
      paymentType: json['payment_type'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, orderId, amount, paymentType, createdAt];
}

/// Full audit detail for one settlement — cash reconciliation figures +
/// the list of payments it covered.
class SettlementDetailEntity extends Equatable {
  final String id;
  final String code;
  final String status;
  final int amount;
  final String riderName;
  final String vendorName;
  final String? verifiedBy;
  final int orderCount;
  final int transactionCount;
  final int? totalCashCollected;
  final int? totalCashSettled;
  final int? cashDifference;
  final int? outstandingRemaining;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? verifiedAt;
  final List<SettlementIncludedPayment> payments;

  const SettlementDetailEntity({
    required this.id,
    required this.code,
    required this.status,
    required this.amount,
    required this.riderName,
    required this.vendorName,
    this.verifiedBy,
    required this.orderCount,
    required this.transactionCount,
    this.totalCashCollected,
    this.totalCashSettled,
    this.cashDifference,
    this.outstandingRemaining,
    required this.createdAt,
    required this.expiresAt,
    this.verifiedAt,
    this.payments = const [],
  });

  factory SettlementDetailEntity.fromJson(Map<String, dynamic> json) {
    int? ni(String k) => (json[k] as num?)?.round();
    return SettlementDetailEntity(
      id: json['id'] as String,
      code: json['code'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      amount: (json['amount'] as num?)?.round() ?? 0,
      riderName: json['rider_name'] as String? ?? 'Unknown',
      vendorName: json['vendor_name'] as String? ?? 'Unknown',
      verifiedBy: json['verified_by'] as String?,
      orderCount: (json['order_count'] as num?)?.round() ?? 0,
      transactionCount: (json['transaction_count'] as num?)?.round() ?? 0,
      totalCashCollected: ni('total_cash_collected'),
      totalCashSettled: ni('total_cash_settled'),
      cashDifference: ni('cash_difference'),
      outstandingRemaining: ni('outstanding_remaining'),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? '') ?? DateTime.now(),
      verifiedAt: json['verified_at'] != null
          ? DateTime.tryParse(json['verified_at'] as String)
          : null,
      payments: (json['payments'] as List?)
              ?.map((e) => SettlementIncludedPayment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  @override
  List<Object?> get props => [id, code, status, amount, verifiedAt, payments];
}
