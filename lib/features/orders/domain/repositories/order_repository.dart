import '../../../../core/utils/result.dart';
import '../../../cart/domain/cart_item_entity.dart';
import '../entities/order_entity.dart';

abstract class OrderRepository {
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
  });

  Future<Result<List<OrderEntity>>> getOrderHistory({int page = 0, int pageSize = 20});

  /// Realtime stream of the customer's order list — fires immediately on
  /// a fresh order (even before the vendor accepts it) and again on every
  /// status change, so the Orders tab never shows a stale snapshot.
  Stream<List<OrderEntity>> watchOrderHistory({int limit = 100});

  Future<Result<OrderEntity>> getOrderById(String orderId);

  /// Realtime stream of a single order row — powers the live tracking
  /// screen without polling.
  Stream<OrderEntity> watchOrder(String orderId);

  Future<Result<void>> cancelOrder(String orderId, String reason);
}
