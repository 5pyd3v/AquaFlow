import '../../domain/entities/cod_balance_entity.dart';

class CodBalanceModel extends CodBalanceEntity {
  const CodBalanceModel({
    required super.outstanding,
    required super.pending,
    required super.totalSubmitted,
    required super.totalVerified,
    required super.totalCollected,
  });

  factory CodBalanceModel.fromJson(Map<String, dynamic> json) {
    return CodBalanceModel(
      outstanding: (json['outstanding'] as num?)?.toDouble() ?? 0,
      pending: (json['pending'] as num?)?.toDouble() ?? 0,
      totalSubmitted: (json['total_submitted'] as num?)?.toDouble() ?? 0,
      totalVerified: (json['total_verified'] as num?)?.toDouble() ?? 0,
      totalCollected: (json['total_collected'] as num?)?.toDouble() ?? 0,
    );
  }
}
