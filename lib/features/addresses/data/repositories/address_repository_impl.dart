import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../../../core/config/app_config.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/address_entity.dart';
import '../../domain/repositories/address_repository.dart';
import '../models/address_model.dart';

class AddressRepositoryImpl implements AddressRepository {
  final sb.SupabaseClient _client;
  AddressRepositoryImpl({sb.SupabaseClient? client}) : _client = client ?? SupabaseConfig.client;

  String? get _userId => _client.auth.currentUser?.id;

  @override
  Future<Result<List<AddressEntity>>> getAddresses() async {
    try {
      final userId = _userId;
      if (userId == null) return const Success([]);
      final rows = await _client
          .from(SupabaseConfig.addresses)
          .select()
          .eq('customer_profile_id', userId)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);
      final addresses = (rows as List)
          .map((row) => AddressModel.fromJson(row as Map<String, dynamic>))
          .toList();
      return Success(addresses);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<AddressEntity>> addAddress({
    required AddressLabel label,
    required String fullAddress,
    required double latitude,
    required double longitude,
    String? landmark,
    bool setAsDefault = false,
  }) async {
    try {
      final userId = _userId;
      if (userId == null) {
        return const Error(AuthFailure('You must be signed in to add an address.'));
      }

      final existingRows = await _client
          .from(SupabaseConfig.addresses)
          .select('id')
          .eq('customer_profile_id', userId);
      final existingCount = (existingRows as List).length;
      if (existingCount >= AppConfig.maxAddressesPerCustomer) {
        return const Error(ValidationFailure(
            'You can save up to ${AppConfig.maxAddressesPerCustomer} addresses. Delete one to add a new one.'));
      }

      if (setAsDefault || existingCount == 0) {
        await _client
            .from(SupabaseConfig.addresses)
            .update({'is_default': false}).eq('customer_profile_id', userId);
      }

      final inserted = await _client
          .from(SupabaseConfig.addresses)
          .insert({
            'customer_profile_id': userId,
            'label': label.dbValue,
            'full_address': fullAddress,
            'lat': latitude,
            'lng': longitude,
            'landmark': landmark,
            'is_default': setAsDefault || existingCount == 0,
          })
          .select()
          .single();

      return Success(AddressModel.fromJson(inserted));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> updateAddress(AddressEntity address) async {
    try {
      await _client.from(SupabaseConfig.addresses).update({
        'label': address.label.dbValue,
        'full_address': address.fullAddress,
        'lat': address.latitude,
        'lng': address.longitude,
        'landmark': address.landmark,
      }).eq('id', address.id);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> deleteAddress(String addressId) async {
    try {
      await _client.from(SupabaseConfig.addresses).delete().eq('id', addressId);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> setDefaultAddress(String addressId) async {
    try {
      final userId = _userId;
      if (userId == null) {
        return const Error(AuthFailure('You must be signed in.'));
      }
      await _client
          .from(SupabaseConfig.addresses)
          .update({'is_default': false}).eq('customer_profile_id', userId);
      await _client
          .from(SupabaseConfig.addresses)
          .update({'is_default': true}).eq('id', addressId);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }
}
