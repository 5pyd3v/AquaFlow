import '../../domain/entities/settlement_entity.dart';

class SettlementModel extends SettlementEntity {
  const SettlementModel({
    required super.id,
    required super.riderId,
    required super.vendorId,
    required super.amount,
    required super.code,
    required super.status,
    required super.createdAt,
    super.verifiedAt,
    required super.expiresAt,
    super.riderName,
    super.riderPhone,
    super.vendorName,
  });

  factory SettlementModel.fromJson(Map<String, dynamic> json) {
    final riders = json['riders'] as Map<String, dynamic>?;
    final profiles = riders?['profiles'] as Map<String, dynamic>?;

    return SettlementModel(
      id: json['id'] as String,
      riderId: json['rider_id'] as String,
      vendorId: json['vendor_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      code: json['code'] as String? ?? '',
      status: _parseStatus(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      verifiedAt: json['verified_at'] != null
          ? DateTime.parse(json['verified_at'] as String)
          : null,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      riderName: json['rider_name'] as String? ?? profiles?['full_name'] as String?,
      riderPhone: json['rider_phone'] as String? ?? profiles?['phone'] as String?,
      vendorName: json['vendor_name'] as String?,
    );
  }

  static SettlementStatus _parseStatus(String? status) {
    return switch (status) {
      'verified' => SettlementStatus.verified,
      'expired' => SettlementStatus.expired,
      _ => SettlementStatus.pending,
    };
  }
}
