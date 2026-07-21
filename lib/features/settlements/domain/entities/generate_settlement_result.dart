import 'package:equatable/equatable.dart';

class GenerateSettlementResult extends Equatable {
  final String id;
  final String code;
  final double amount;
  final double outstandingAfter;

  const GenerateSettlementResult({
    required this.id,
    required this.code,
    required this.amount,
    required this.outstandingAfter,
  });

  @override
  List<Object?> get props => [id, code, amount, outstandingAfter];
}
