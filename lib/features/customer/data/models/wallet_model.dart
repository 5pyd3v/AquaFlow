import '../../domain/entities/wallet_entity.dart';

class CustomerWalletSummaryModel extends CustomerWalletSummaryEntity {
  const CustomerWalletSummaryModel({
    required super.balance,
    required super.totalOutstanding,
    required super.pendingOrderCount,
    required super.transactions,
  });

  factory CustomerWalletSummaryModel.fromJson(Map<String, dynamic> json) {
    final txnList = json['transactions'] as List? ?? [];
    return CustomerWalletSummaryModel(
      balance: (json['balance'] as num?)?.round() ?? 0,
      totalOutstanding: (json['total_outstanding'] as num?)?.round() ?? 0,
      pendingOrderCount: (json['pending_order_count'] as num?)?.toInt() ?? 0,
      transactions: txnList
          .map((t) => _parseTxn(t as Map<String, dynamic>))
          .toList(),
    );
  }

  static WalletTransactionEntity _parseTxn(Map<String, dynamic> json) {
    return WalletTransactionEntity(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'credit',
      amount: (json['amount'] as num?)?.round() ?? 0,
      description: json['description'] as String?,
      orderId: json['order_id'] as String?,
      orderNumber: json['order_number'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
