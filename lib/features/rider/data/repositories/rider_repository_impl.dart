import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../../../core/config/supabase_config.dart';
import '../../../../core/constants/order_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/rider_delivery_entity.dart';
import '../../domain/entities/rider_profile_entity.dart';
import '../../domain/entities/rider_stats_entity.dart';
import '../../domain/repositories/rider_repository.dart';
import '../models/rider_delivery_model.dart';
import '../models/rider_profile_model.dart';

const _riderDeliverySelectQuery =
    '*, vendors(business_name, address, lat, lng), '
    'profiles!orders_customer_profile_id_fkey(full_name, phone), '
    'addresses(full_address, lat, lng), order_items(*, products(name, image_url))';

class RiderRepositoryImpl implements RiderRepository {
  final sb.SupabaseClient _client;
  RiderRepositoryImpl({sb.SupabaseClient? client}) : _client = client ?? SupabaseConfig.client;

  String? get _userId => _client.auth.currentUser?.id;

  @override
  Future<Result<RiderProfileEntity>> getMyRiderProfile() async {
    try {
      final userId = _userId;
      if (userId == null) {
        return const Error(AuthFailure('You must be signed in.'));
      }
      final row = await _client
          .from(SupabaseConfig.riders)
          .select('*, vendors(business_name)')
          .eq('profile_id', userId)
          .single();
      return Success(RiderProfileModel.fromJson(row));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> updateVehicleInfo({
    required String vehicleType,
    required String vehiclePlate,
  }) async {
    try {
      final userId = _userId;
      if (userId == null) {
        return const Error(AuthFailure('You must be signed in.'));
      }
      await _client.from(SupabaseConfig.riders).update({
        'vehicle_type': vehicleType,
        'vehicle_plate': vehiclePlate,
      }).eq('profile_id', userId);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> setShiftStatus(bool isOnShift) async {
    try {
      final userId = _userId;
      if (userId == null) {
        return const Error(AuthFailure('You must be signed in.'));
      }
      await _client.from(SupabaseConfig.riders).update({
        'is_on_shift': isOnShift,
        'status': isOnShift ? 'available' : 'offline',
      }).eq('profile_id', userId);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<RiderStatsEntity>> getStats(String riderId) async {
    try {
      final riderRow = await _client
          .from(SupabaseConfig.riders)
          .select('rating, total_deliveries, vendor_id')
          .eq('id', riderId)
          .single();

      final todayStart =
          DateTime.now().toUtc().copyWith(hour: 0, minute: 0, second: 0, microsecond: 0, millisecond: 0);

      final todaysOrders = await _client
          .from(SupabaseConfig.orders)
          .select('id')
          .eq('rider_id', riderId)
          .eq('status', 'delivered')
          .gte('delivered_at', todayStart.toIso8601String());

      final todaysCount = (todaysOrders as List).length;

      // COD financials — get total collected from payment_transactions (actual cash collected)
      // This ensures partial payments are correctly tracked
      final paymentTransactions = await _client
          .from(SupabaseConfig.paymentTransactions)
          .select('amount')
          .eq('rider_id', riderId)
          .eq('status', 'active')
          .inFilter('payment_type', ['full', 'partial', 'over']);

      double totalCodCollected = 0;
      for (final txn in (paymentTransactions as List)) {
        totalCodCollected += (txn['amount'] as num?)?.toDouble() ?? 0;
      }

      // Get verified + pending from settlements
      final settlements = await _client
          .from(SupabaseConfig.codSettlements)
          .select('amount, status')
          .eq('rider_id', riderId);

      double totalVerified = 0;
      double totalPending = 0;
      for (final row in (settlements as List)) {
        final amount = (row['amount'] as num?)?.toDouble() ?? 0;
        if (row['status'] == 'verified') {
          totalVerified += amount;
        } else if (row['status'] == 'pending') {
          totalPending += amount;
        }
      }

      // Outstanding = what rider has collected but not yet handed to vendor
      // (collected from payment_transactions - verified settlements)
      final outstanding = (totalCodCollected - totalVerified).clamp(0.0, double.infinity);

      return Success(RiderStatsEntity(
        todaysDeliveries: todaysCount,
        totalDeliveries: (riderRow['total_deliveries'] as num?)?.toInt() ?? 0,
        rating: (riderRow['rating'] as num?)?.toDouble() ?? 5.0,
        totalCodCollected: totalCodCollected,
        codOutstanding: outstanding,
        codPendingVerification: totalPending,
      ));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<RiderDeliveryEntity>>> getActiveDeliveries(String riderId) async {
    try {
      final rows = await _client
          .from(SupabaseConfig.orders)
          .select(_riderDeliverySelectQuery)
          .eq('rider_id', riderId)
          .inFilter('status', ['assigned', 'picked_up', 'on_the_way']).order('is_emergency', ascending: false);

      final deliveries =
          (rows as List).map((row) => RiderDeliveryModel.fromJson(row as Map<String, dynamic>)).toList();
      return Success(deliveries);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<RiderDeliveryEntity>>> getDeliveryHistory(String riderId) async {
    try {
      final rows = await _client
          .from(SupabaseConfig.orders)
          .select(_riderDeliverySelectQuery)
          .eq('rider_id', riderId)
          .inFilter('status', ['delivered', 'completed', 'returned']).order('created_at', ascending: false);

      final deliveries =
          (rows as List).map((row) => RiderDeliveryModel.fromJson(row as Map<String, dynamic>)).toList();
      return Success(deliveries);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> updateDeliveryStatus(String orderId, OrderStatus newStatus) async {
    try {
      await _client.from(SupabaseConfig.orders).update({'status': newStatus.dbValue}).eq('id', orderId);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> completeDelivery(String orderId, String enteredOtp) async {
    try {
      await _client.rpc('verify_delivery_otp', params: {
        'p_order_id': orderId,
        'p_entered_otp': enteredOtp,
      });
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> broadcastLocation({
    required double latitude,
    required double longitude,
    double? headingDegrees,
    double? speedKmh,
  }) async {
    try {
      final userId = _userId;
      if (userId == null) {
        return const Error(AuthFailure('You must be signed in.'));
      }
      final riderRow =
          await _client.from(SupabaseConfig.riders).select('id').eq('profile_id', userId).single();
      final riderId = riderRow['id'] as String;

      await _client.from(SupabaseConfig.realtimeLocations).upsert({
        'rider_id': riderId,
        'lat': latitude,
        'lng': longitude,
        'heading': headingDegrees,
        'speed_kmh': speedKmh,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<int>> getCustomerOutstanding({
    required String customerProfileId,
    required String riderId,
  }) async {
    try {
      // Query orders for this customer assigned to this rider
      // Use outstanding_amount column which is already correctly maintained
      final rows = await _client
          .from(SupabaseConfig.orders)
          .select('outstanding_amount')
          .eq('customer_profile_id', customerProfileId)
          .eq('rider_id', riderId)
          .not('status', 'in', '("cancelled","rejected")');

      int totalOutstanding = 0;
      for (final row in (rows as List)) {
        totalOutstanding += (row['outstanding_amount'] as num?)?.toInt() ?? 0;
      }
      return Success(totalOutstanding);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }
}
