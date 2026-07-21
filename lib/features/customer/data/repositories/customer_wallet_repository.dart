import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/wallet_entity.dart';
import '../models/wallet_model.dart';

class CustomerWalletRepository {
  final sb.SupabaseClient _client;

  CustomerWalletRepository({sb.SupabaseClient? client})
      : _client = client ?? SupabaseConfig.client;

  Future<Result<CustomerWalletSummaryEntity>> getWalletSummary() async {
    try {
      final result = await _client.rpc('get_customer_wallet_summary');
      final data = result as Map<String, dynamic>;
      return Success(CustomerWalletSummaryModel.fromJson(data));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }
}
