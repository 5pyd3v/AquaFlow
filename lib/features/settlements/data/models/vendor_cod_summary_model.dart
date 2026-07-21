import '../../domain/entities/vendor_cod_summary_entity.dart';

class VendorCodSummaryModel extends VendorCodSummaryEntity {
  const VendorCodSummaryModel({
    required super.todaysVerified,
    required super.totalVerified,
    required super.pendingCount,
    required super.pendingAmount,
  });

  factory VendorCodSummaryModel.fromJson(Map<String, dynamic> json) {
    return VendorCodSummaryModel(
      todaysVerified: (json['todays_verified'] as num?)?.toDouble() ?? 0,
      totalVerified: (json['total_verified'] as num?)?.toDouble() ?? 0,
      pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
      pendingAmount: (json['pending_amount'] as num?)?.toDouble() ?? 0,
    );
  }
}
