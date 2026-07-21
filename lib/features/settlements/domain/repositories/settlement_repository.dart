import '../../../../core/utils/result.dart';
import '../entities/cod_balance_entity.dart';
import '../entities/generate_settlement_result.dart';
import '../entities/settlement_entity.dart';
import '../entities/vendor_cod_summary_entity.dart';
import '../entities/verify_settlement_result.dart';

abstract class SettlementRepository {
  Future<Result<GenerateSettlementResult>> generateSettlement({
    required String riderId,
    required String vendorId,
    required double amount,
  });

  Future<Result<VerifySettlementResult>> verifySettlement({
    required String code,
    required String vendorId,
  });

  Future<Result<CodBalanceEntity>> getRiderCodBalance({
    required String riderId,
    required String vendorId,
  });

  Future<Result<VendorCodSummaryEntity>> getVendorCodSummary({
    required String vendorId,
  });

  Future<Result<List<SettlementEntity>>> getRiderSettlements({
    required String riderId,
  });

  Future<Result<List<SettlementEntity>>> getVendorSettlements({
    required String vendorId,
  });
}
