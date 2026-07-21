import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/cod_balance_entity.dart';
import '../../domain/entities/generate_settlement_result.dart';
import '../../domain/entities/settlement_entity.dart';
import '../../domain/entities/vendor_cod_summary_entity.dart';
import '../../domain/entities/verify_settlement_result.dart';
import '../../domain/repositories/settlement_repository.dart';
import '../models/cod_balance_model.dart';
import '../models/settlement_model.dart';
import '../models/vendor_cod_summary_model.dart';

class SettlementRepositoryImpl implements SettlementRepository {
  final SupabaseClient _client;

  SettlementRepositoryImpl({SupabaseClient? client})
      : _client = client ?? SupabaseConfig.client;

  @override
  Future<Result<GenerateSettlementResult>> generateSettlement({
    required String riderId,
    required String vendorId,
    required double amount,
  }) async {
    try {
      final response = await _client.rpc('generate_cod_settlement', params: {
        'p_rider_id': riderId,
        'p_vendor_id': vendorId,
        'p_amount': amount,
      });
      final data = response as Map<String, dynamic>;
      return Success(GenerateSettlementResult(
        id: data['id'] as String,
        code: data['code'] as String,
        amount: (data['amount'] as num).toDouble(),
        outstandingAfter: (data['outstanding_after'] as num).toDouble(),
      ));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<VerifySettlementResult>> verifySettlement({
    required String code,
    required String vendorId,
  }) async {
    try {
      final response = await _client.rpc('verify_cod_settlement', params: {
        'p_code': code,
        'p_vendor_id': vendorId,
      });
      final data = response as Map<String, dynamic>;
      return Success(VerifySettlementResult(
        settlementId: data['settlement_id'] as String,
        riderName: data['rider_name'] as String? ?? 'Unknown Rider',
        amount: (data['amount'] as num).toDouble(),
        createdAt: DateTime.parse(data['created_at'] as String),
        outstandingBefore: (data['outstanding_before'] as num).toDouble(),
        outstandingAfter: (data['outstanding_after'] as num).toDouble(),
      ));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<CodBalanceEntity>> getRiderCodBalance({
    required String riderId,
    required String vendorId,
  }) async {
    try {
      final response = await _client.rpc('get_rider_cod_balance', params: {
        'p_rider_id': riderId,
        'p_vendor_id': vendorId,
      });
      final data = response as Map<String, dynamic>;
      return Success(CodBalanceModel.fromJson(data));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<VendorCodSummaryEntity>> getVendorCodSummary({
    required String vendorId,
  }) async {
    try {
      final response = await _client.rpc('get_vendor_cod_summary', params: {
        'p_vendor_id': vendorId,
      });
      final data = response as Map<String, dynamic>;
      return Success(VendorCodSummaryModel.fromJson(data));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<SettlementEntity>>> getRiderSettlements({
    required String riderId,
  }) async {
    try {
      final rows = await _client
          .from(SupabaseConfig.codSettlements)
          .select()
          .eq('rider_id', riderId)
          .order('created_at', ascending: false);
      final settlements = (rows as List)
          .map((row) => SettlementModel.fromJson(row as Map<String, dynamic>))
          .toList();
      return Success(settlements);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<SettlementEntity>>> getVendorSettlements({
    required String vendorId,
  }) async {
    try {
      final rows = await _client
          .from(SupabaseConfig.codSettlements)
          .select()
          .eq('vendor_id', vendorId)
          .order('created_at', ascending: false);
      final settlements = (rows as List)
          .map((row) => SettlementModel.fromJson(row as Map<String, dynamic>))
          .toList();
      return Success(settlements);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }
}
