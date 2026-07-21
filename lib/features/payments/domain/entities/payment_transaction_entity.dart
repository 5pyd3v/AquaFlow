import 'package:equatable/equatable.dart';

/// How a payment was applied to the order.
/// - [full]: cleared the entire outstanding balance
/// - [partial]: paid less than outstanding; the rest stays owed
/// - [over]: paid more than outstanding; the excess became wallet credit
/// - [credit]: wallet credit consumed against a new order
/// - [refund] / [adjustment]: vendor-side corrections
enum PaymentType { full, partial, over, credit, refund, adjustment }

/// Lifecycle of a payment record. Financial rows are never hard-deleted;
/// they move to [edited] (superseded) or [deleted] (soft) and keep an
/// audit trail.
enum PaymentTxnStatus { active, edited, deleted }

class PaymentTransactionEntity extends Equatable {
  final String id;
  final String orderId;
  final String? orderNumber;
  final String customerProfileId;
  final String? customerName;
  final String? riderId;
  final String? riderName;
  final String vendorId;
  final int amount;
  final int outstandingBefore;
  final int outstandingAfter;
  final int creditBefore;
  final int creditAfter;
  final PaymentType type;
  final PaymentTxnStatus status;
  final bool settled;
  final String? settlementId;
  final String? notes;
  final String? receiptUrl;
  final DateTime createdAt;

  const PaymentTransactionEntity({
    required this.id,
    required this.orderId,
    this.orderNumber,
    required this.customerProfileId,
    this.customerName,
    this.riderId,
    this.riderName,
    required this.vendorId,
    required this.amount,
    required this.outstandingBefore,
    required this.outstandingAfter,
    required this.creditBefore,
    required this.creditAfter,
    required this.type,
    required this.status,
    required this.settled,
    this.settlementId,
    this.notes,
    this.receiptUrl,
    required this.createdAt,
  });

  /// A payment can be freely edited/deleted by the rider only while it
  /// is still active and its cash has not yet been rolled into a
  /// verified settlement. After that it needs a vendor-approved
  /// amendment request.
  bool get isEditable => status == PaymentTxnStatus.active && !settled;

  @override
  List<Object?> get props => [
        id,
        orderId,
        customerProfileId,
        riderId,
        vendorId,
        amount,
        outstandingBefore,
        outstandingAfter,
        creditBefore,
        creditAfter,
        type,
        status,
        settled,
        settlementId,
        createdAt,
      ];
}
