import 'package:equatable/equatable.dart';

class WalletTransactionEntity extends Equatable {
  final String id;
  final String type;
  final int amount;
  final String? description;
  final String? orderId;
  final String? orderNumber;
  final DateTime createdAt;

  const WalletTransactionEntity({
    required this.id,
    required this.type,
    required this.amount,
    this.description,
    this.orderId,
    this.orderNumber,
    required this.createdAt,
  });

  bool get isCredit => type == 'credit';

  @override
  List<Object?> get props => [id, type, amount, description, orderId, createdAt];
}

class CustomerWalletSummaryEntity extends Equatable {
  final int balance;
  final int totalOutstanding;
  final int pendingOrderCount;
  final List<WalletTransactionEntity> transactions;

  const CustomerWalletSummaryEntity({
    required this.balance,
    required this.totalOutstanding,
    required this.pendingOrderCount,
    required this.transactions,
  });

  @override
  List<Object?> get props => [balance, totalOutstanding, pendingOrderCount, transactions];
}
