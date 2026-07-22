import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../../cart/domain/cart_item_entity.dart';
import '../../domain/entities/order_entity.dart';
import '../../domain/repositories/order_repository.dart';
import '../models/order_model.dart';

const _orderSelectQuery =
    '*, vendors(business_name), riders(profile_id, profiles(full_name, phone)), '
    'addresses(full_address), order_items(*, products(name, image_url))';

class OrderRepositoryImpl implements OrderRepository {
  final sb.SupabaseClient _client;
  OrderRepositoryImpl({sb.SupabaseClient? client}) : _client = client ?? SupabaseConfig.client;

  @override
  Future<Result<OrderEntity>> placeOrder({
    required String addressId,
    required String vendorId,
    required List<CartItemEntity> items,
    required String paymentMethod,
    bool isEmergency = false,
    bool includeDeposit = false,
    String? couponId,
    double discountAmount = 0,
    double deliveryFee = 0,
  }) async {
    try {
      final itemsPayload = items
          .map((item) => {
                'product_id': item.product.id,
                'quantity': item.quantity,
                'unit_price': item.product.discountedPrice,
                'unit_deposit': includeDeposit ? item.product.depositAmount : 0.0,
              })
          .toList();

      final orderRow = await _client.rpc('place_order', params: {
        'p_address_id': addressId,
        'p_vendor_id': vendorId,
        'p_items': itemsPayload,
        'p_payment_method': paymentMethod,
        'p_is_emergency': isEmergency,
        'p_coupon_id': couponId,
        'p_discount_amount': discountAmount,
        'p_delivery_fee': deliveryFee,
      });

      final orderId = (orderRow as Map<String, dynamic>)['id'] as String;
      return getOrderById(orderId);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<List<OrderEntity>>> getOrderHistory({int page = 0, int pageSize = 20}) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return const Success([]);

      final from = page * pageSize;
      final to = from + pageSize - 1;

      final rows = await _client
          .from(SupabaseConfig.orders)
          .select(_orderSelectQuery)
          .eq('customer_profile_id', userId)
          .order('created_at', ascending: false)
          .range(from, to);

      final orders =
          (rows as List).map((row) => OrderModel.fromJson(row as Map<String, dynamic>)).toList();
      return Success(orders);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Stream<List<OrderEntity>> watchOrderHistory({int limit = 100}) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return Stream.value(const []);

    // Same "stream as change signal, then re-fetch the joined rows"
    // approach as watchOrder — raw realtime rows have no joins, and this
    // way a brand-new (still-pending) order or any status change made by
    // the vendor/rider shows up immediately without a manual pull-to-refresh.
    return _client
        .from(SupabaseConfig.orders)
        .stream(primaryKey: ['id'])
        .eq('customer_profile_id', userId)
        .order('created_at', ascending: false)
        .limit(limit)
        .asyncMap((_) async {
      final result = await getOrderHistory(pageSize: limit);
      return result.fold((failure) => throw failure, (data) => data);
    });
  }

  @override
  Future<Result<OrderEntity>> getOrderById(String orderId) async {
    try {
      final row = await _client
          .from(SupabaseConfig.orders)
          .select(_orderSelectQuery)
          .eq('id', orderId)
          .single();
      return Success(OrderModel.fromJson(row));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Stream<OrderEntity> watchOrder(String orderId) {
    // Supabase realtime streams return raw table rows (no joins), so
    // we use the stream purely as a change signal and re-fetch the
    // fully joined order whenever it fires — simpler and more robust
    // than trying to keep a hand-joined stream in sync.
    return _client
        .from(SupabaseConfig.orders)
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .asyncMap((_) async {
      final result = await getOrderById(orderId);
      return result.fold((failure) => throw failure, (data) => data);
    });
  }

  @override
  Future<Result<void>> cancelOrder(String orderId, String reason) async {
    try {
      final order = await _client
          .from(SupabaseConfig.orders)
          .select('status')
          .eq('id', orderId)
          .single();
      final currentStatus = order['status'] as String;
      if (currentStatus != 'pending' && currentStatus != 'accepted') {
        return const Error(
            ValidationFailure('This order can no longer be cancelled — it is already being prepared for delivery.'));
      }
      await _client.from(SupabaseConfig.orders).update({
        'status': 'cancelled',
        'cancelled_reason': reason,
      }).eq('id', orderId);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }
}
