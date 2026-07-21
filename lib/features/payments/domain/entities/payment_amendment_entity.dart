import 'package:equatable/equatable.dart';

enum AmendmentAction { edit, delete }

enum AmendmentStatus { pending, approved, rejected }

/// A rider's request to change or remove a payment that is already
/// locked by a verified settlement. The vendor approves or rejects it.
class PaymentAmendmentEntity extends Equatable {
  final String id;
  final String paymentTransactionId;
  final String? riderId;
  final String? riderName;
  final String vendorId;
  final AmendmentAction action;
  final int? requestedAmount;
  final int currentAmount;
  final String? orderNumber;
  final String reason;
  final AmendmentStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const PaymentAmendmentEntity({
    required this.id,
    required this.paymentTransactionId,
    this.riderId,
    this.riderName,
    required this.vendorId,
    required this.action,
    this.requestedAmount,
    this.currentAmount = 0,
    this.orderNumber,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
  });

  @override
  List<Object?> get props => [
        id,
        paymentTransactionId,
        riderId,
        vendorId,
        action,
        requestedAmount,
        status,
        createdAt,
        resolvedAt,
      ];
}
