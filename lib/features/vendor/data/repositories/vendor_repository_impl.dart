import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../../../core/config/supabase_config.dart';
import '../../../../core/constants/order_status.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/services/logger_service.dart';
import '../../../../core/utils/result.dart';
import '../../../customer/data/models/product_model.dart';
import '../../../customer/domain/entities/product_entity.dart';
import '../../domain/entities/vendor_customer_entity.dart';
import '../../domain/entities/vendor_entity.dart';
import '../../domain/entities/vendor_order_entity.dart';
import '../../domain/entities/vendor_rider_entity.dart';
import '../../domain/entities/vendor_stats_entity.dart';
import '../../domain/entities/rider_location_entity.dart';
import '../../domain/repositories/vendor_repository.dart';
import '../models/vendor_model.dart';
import '../models/vendor_customer_model.dart';
import '../models/vendor_order_model.dart';
import '../models/vendor_rider_model.dart';

const _vendorOrderSelectQuery =
    '*, profiles!orders_customer_profile_id_fkey(full_name, phone), '
    'riders(profiles(full_name)), addresses(full_address, lat, lng), order_items(*, products(name, image_url))';

class VendorRepositoryImpl implements VendorRepository {
  final sb.SupabaseClient _client;
  VendorRepositoryImpl({sb.SupabaseClient? client}) : _client = client ?? SupabaseConfig.client;

  String? get _userId => _client.auth.currentUser?.id;

  @override
  Future<Result<VendorEntity>> getMyVendorProfile() async {
    try {
      final userId = _userId;
      if (userId == null) {
        return const Error(AuthFailure('You must be signed in.'));
      }
      final row = await _client
          .from(SupabaseConfig.vendors)
          .select()
          .eq('profile_id', userId)
          .single();
      return Success(VendorModel.fromJson(row));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> updateVendorProfile({
    required String businessName,
    String? address,
    double? latitude,
    double? longitude,
    double? deliveryRadiusKm,
  }) async {
    try {
      final userId = _userId;
      if (userId == null) {
        return const Error(AuthFailure('You must be signed in.'));
      }
      final updates = <String, dynamic>{
        'business_name': businessName,
        if (address != null) 'address': address,
        if (latitude != null) 'lat': latitude,
        if (longitude != null) 'lng': longitude,
        if (deliveryRadiusKm != null) 'delivery_radius_km': deliveryRadiusKm,
      };
      await _client.from(SupabaseConfig.vendors).update(updates).eq('profile_id', userId);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<VendorStatsEntity>> getStats(String vendorId) async {
    try {
      final todayStart = DateTime.now().toUtc().copyWith(hour: 0, minute: 0, second: 0, microsecond: 0, millisecond: 0);

      // None of these five queries depend on each other's results, so they
      // run concurrently instead of as a sequential waterfall of round trips
      // — same data, same error behavior (the first failure still surfaces
      // to the outer catch below), just less wall-clock time to load the
      // dashboard.
      final results = await Future.wait([
        _client
            .from(SupabaseConfig.orders)
            .select('id, status, total_amount, payment_method')
            .eq('vendor_id', vendorId)
            .gte('created_at', todayStart.toIso8601String()),
        _client
            .from(SupabaseConfig.orders)
            .select('id')
            .eq('vendor_id', vendorId)
            .eq('status', 'pending'),
        // Orders terminate at 'delivered' (rider drop-off) and optionally
        // roll up to 'completed' after COD settlement, so both count as
        // successfully completed for the vendor's stats.
        _client
            .from(SupabaseConfig.orders)
            .select('id')
            .eq('vendor_id', vendorId)
            .inFilter('status', ['delivered', 'completed']),
        _client
            .from(SupabaseConfig.products)
            .select('id, stock_quantity')
            .eq('vendor_id', vendorId),
        _client
            .from(SupabaseConfig.riders)
            .select('id')
            .eq('vendor_id', vendorId),
      ]);
      final ordersToday = results[0];
      final pendingOrders = results[1];
      final completedOrders = results[2];
      final products = results[3];
      final riders = results[4];

      final todaysRows = ordersToday as List;
      // Revenue = sum of verified COD settlements today + non-COD
      // delivered/completed orders. This replaces the old logic that
      // counted all delivered order totals as revenue immediately.
      final nonCodRevenue = todaysRows.where((row) {
        final status = row['status'] as String?;
        final payment = row['payment_method'] as String?;
        return (status == 'delivered' || status == 'completed') && payment != 'cod';
      }).fold<double>(
          0, (sum, row) => sum + ((row['total_amount'] as num?)?.toDouble() ?? 0));

      // Verified COD settlements for today
      double codRevenue = 0;
      try {
        final codRows = await _client
            .from(SupabaseConfig.codSettlements)
            .select('amount')
            .eq('vendor_id', vendorId)
            .eq('status', 'verified')
            .gte('verified_at', todayStart.toIso8601String());
        codRevenue = (codRows as List).fold<double>(
            0, (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0));
      } catch (e) {
        // Falls back to 0 — a genuinely empty result set looks the same as a
        // query error here, but logging at least surfaces the latter.
        AppLogger.warning('Failed to load today\'s COD revenue for vendor $vendorId', e);
      }

      final todaysRevenue = nonCodRevenue + codRevenue;

      // Today's sales = sum of total_amount for today's delivered/completed
      // orders. This is the actual sales figure (what was sold), regardless
      // of whether the cash has been settled or not.
      final todaysSales = todaysRows.where((row) {
        final status = row['status'] as String?;
        return status == 'delivered' || status == 'completed';
      }).fold<int>(
          0, (sum, row) => sum + ((row['total_amount'] as num?)?.round() ?? 0));

      // Pending settlement = unsettled active cash payments (riders haven't
      // handed over yet). Falls back to 0 if payment_transactions has no rows.
      // Refund rows are always settled = false (only 'full'/'partial'/'over'
      // rows ever get flipped to settled), so they must be subtracted here
      // explicitly or refunded/reallocated cash keeps counting as unsettled
      // forever — refunds no longer mutate the original row's amount
      // (see migration 0027), so this can't rely on that anymore.
      int pendingSettlement = 0;
      try {
        final unsettledRows = await _client
            .from('payment_transactions')
            .select('amount, payment_type')
            .eq('vendor_id', vendorId)
            .eq('status', 'active')
            .eq('settled', false)
            .inFilter('payment_type', ['full', 'partial', 'over', 'refund']);
        pendingSettlement = (unsettledRows as List).fold<int>(0, (sum, row) {
          final amount = (row['amount'] as num?)?.round() ?? 0;
          return row['payment_type'] == 'refund' ? sum - amount : sum + amount;
        });
        if (pendingSettlement < 0) pendingSettlement = 0;
      } catch (e) {
        AppLogger.warning('Failed to load pending settlement for vendor $vendorId', e);
      }

      final productsRows = products as List;
      final lowStockCount = productsRows
          .where((row) => ((row['stock_quantity'] as num?)?.toInt() ?? 0) < 20)
          .length;

      return Success(VendorStatsEntity(
        todaysOrders: todaysRows.length,
        pendingOrders: (pendingOrders as List).length,
        completedOrders: (completedOrders as List).length,
        todaysRevenue: todaysRevenue,
        todaysSales: todaysSales,
        pendingSettlement: pendingSettlement,
        totalProducts: productsRows.length,
        lowStockProducts: lowStockCount,
        totalRiders: (riders as List).length,
      ));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<ProductEntity>>> getMyProducts(String vendorId) async {
    try {
      final rows = await _client
          .from(SupabaseConfig.products)
          .select('*, vendors(business_name, rating)')
          .eq('vendor_id', vendorId)
          .order('created_at', ascending: false);
      final products = (rows as List)
          .map((row) => ProductModel.fromJson(row as Map<String, dynamic>))
          .toList();
      return Success(products);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> createProduct({
    required String vendorId,
    String? categoryId,
    required String name,
    String? brand,
    required double sizeLiters,
    String? description,
    String? imageUrl,
    required double price,
    required double depositAmount,
    double discountPercent = 0,
    required int stockQuantity,
  }) async {
    try {
      await _client.from(SupabaseConfig.products).insert({
        'vendor_id': vendorId,
        'category_id': categoryId,
        'name': name,
        'brand': brand,
        'size_liters': sizeLiters,
        'description': description,
        'image_url': imageUrl,
        'price': price,
        'deposit_amount': depositAmount,
        'discount_percent': discountPercent,
        'stock_quantity': stockQuantity,
        'is_available': true,
      });
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> updateProduct(ProductEntity product) async {
    try {
      await _client.from(SupabaseConfig.products).update({
        'name': product.name,
        'brand': product.brand,
        'size_liters': product.sizeLiters,
        'description': product.description,
        'image_url': product.imageUrl,
        'price': product.price,
        'deposit_amount': product.depositAmount,
        'discount_percent': product.discountPercent,
        'stock_quantity': product.stockQuantity,
        'category_id': product.categoryId,
        'is_available': product.isAvailable,
      }).eq('id', product.id);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> deleteProduct(String productId) async {
    try {
      await _client.from(SupabaseConfig.products).delete().eq('id', productId);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> toggleProductAvailability(String productId, bool isAvailable) async {
    try {
      await _client
          .from(SupabaseConfig.products)
          .update({'is_available': isAvailable}).eq('id', productId);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> updateStock(String productId, int newQuantity) async {
    try {
      await _client
          .from(SupabaseConfig.products)
          .update({'stock_quantity': newQuantity}).eq('id', productId);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<VendorOrderEntity>>> getOrders(String vendorId, {OrderStatus? statusFilter}) async {
    try {
      var query = _client
          .from(SupabaseConfig.orders)
          .select(_vendorOrderSelectQuery)
          .eq('vendor_id', vendorId);

      if (statusFilter != null) {
        query = query.eq('status', statusFilter.dbValue);
      }

      final rows = await query.order('created_at', ascending: false);
      final orders = (rows as List)
          .map((row) => VendorOrderModel.fromJson(row as Map<String, dynamic>))
          .toList();
      return Success(orders);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> acceptOrder(String orderId) async {
    try {
      await _client.from(SupabaseConfig.orders).update({'status': 'accepted'}).eq('id', orderId);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> rejectOrder(String orderId, String reason) async {
    try {
      await _client.from(SupabaseConfig.orders).update({
        'status': 'rejected',
        'cancelled_reason': reason,
      }).eq('id', orderId);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> assignRider(String orderId, String riderId) async {
    try {
      await _client.from(SupabaseConfig.orders).update({
        'rider_id': riderId,
        'status': 'assigned',
      }).eq('id', orderId);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<VendorRiderEntity>>> getMyRiders(String vendorId) async {
    try {
      final rows = await _client
          .from(SupabaseConfig.riders)
          .select('*, profiles(full_name, phone, is_active)')
          .eq('vendor_id', vendorId)
          .order('created_at', ascending: false);
      final riders = (rows as List)
          .map((row) => VendorRiderModel.fromJson(row as Map<String, dynamic>))
          .toList();
      return Success(riders);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> linkRiderByPhone(String phone) async {
    try {
      await _client.rpc('link_rider_to_vendor', params: {'p_rider_phone': phone});
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> approveRider(String riderId) async {
    try {
      await _client.rpc('approve_rider', params: {'p_rider_id': riderId});
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> rejectRider(String riderId) async {
    try {
      await _client.rpc('reject_rider', params: {'p_rider_id': riderId});
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> unlinkRider(String riderId) async {
    try {
      // Goes through a SECURITY DEFINER RPC (migration 0022): a plain
      // UPDATE setting vendor_id = null is rejected by RLS because the
      // riders update policy re-checks owns_vendor() against the NEW
      // (now-null) vendor_id.
      await _client.rpc('unlink_rider', params: {'p_rider_id': riderId});
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<VendorCustomerEntity>>> getMyCustomers(String vendorId) async {
    try {
      final rows = await _client.rpc('get_vendor_customers', params: {
        'p_vendor_id': vendorId,
      });
      final customers = (rows as List)
          .map((row) => VendorCustomerModel.fromJson(row as Map<String, dynamic>))
          .toList();
      return Success(customers);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Stream<List<RiderLocationEntity>> watchRiderLocations() {
    // Deliberately unfiltered: `realtime_locations_visible_to_vendor`
    // (migration 0012) already restricts every row this query can
    // possibly return to this vendor's own linked riders, so there's
    // no need to fight the realtime stream API's limited filter
    // support (it only supports a single `.eq()`, not an `IN` list).
    return _client
        .from(SupabaseConfig.realtimeLocations)
        .stream(primaryKey: ['rider_id'])
        .map((rows) => rows.map((row) => RiderLocationEntity.fromJson(row)).toList());
  }

  @override
  Future<Result<List<VendorCustomerEntity>>> getRiderPendingCustomers(String riderId) async {
    try {
      final rows = await _client.rpc('get_rider_pending_customers', params: {
        'p_rider_id': riderId,
      });
      final customers = (rows as List)
          .map((row) => VendorCustomerModel.fromJson(_asMap(row)))
          .toList();
      return Success(customers);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  /// Supabase RPC returns dynamic JSON; normalise to a String-keyed map.
  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException('Unexpected RPC response shape');
  }
}
