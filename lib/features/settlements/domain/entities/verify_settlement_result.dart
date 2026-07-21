import 'package:equatable/equatable.dart';

class VerifySettlementResult extends Equatable {
  final String settlementId;
  final String riderName;
  final double amount;
  final DateTime createdAt;
  final double outstandingBefore;
  final double outstandingAfter;

  const VerifySettlementResult({
    required this.settlementId,
    required this.riderName,
    required this.amount,
    required this.createdAt,
    required this.outstandingBefore,
    required this.outstandingAfter,
  });

  @override
  List<Object?> get props => [settlementId, riderName, amount, createdAt, outstandingBefore, outstandingAfter];
}
