import '../../domain/entities/rider_cash_position_entity.dart';

class RiderCashPositionModel extends RiderCashPositionEntity {
  const RiderCashPositionModel({
    required super.riderId,
    required super.riderName,
    required super.collected,
    required super.settled,
    required super.pendingSettlement,
  });

  factory RiderCashPositionModel.fromJson(Map<String, dynamic> json) {
    int i(String k) => (json[k] as num?)?.round() ?? 0;
    return RiderCashPositionModel(
      riderId: json['rider_id'] as String,
      riderName: (json['rider_name'] as String?)?.trim().isNotEmpty == true
          ? json['rider_name'] as String
          : 'Rider',
      collected: i('collected'),
      settled: i('settled'),
      pendingSettlement: i('pending_settlement'),
    );
  }
}
