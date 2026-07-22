import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/result.dart';
import '../../../cart/domain/cart_item_entity.dart';
import '../../data/repositories/order_repository_impl.dart';
import '../../domain/entities/order_entity.dart';
import '../../domain/repositories/order_repository.dart';

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepositoryImpl();
});

// Realtime stream, not a one-shot fetch: the Orders tab lives inside the
// customer shell's IndexedStack and is built once at app start, so a plain
// FutureProvider would only ever fetch that first snapshot. A freshly
// placed (still-pending) order — or any status change — needs to appear
// without the customer needing to leave and re-enter the tab.
final orderHistoryProvider = StreamProvider.autoDispose<List<OrderEntity>>((ref) {
  return ref.watch(orderRepositoryProvider).watchOrderHistory();
});

final orderTrackingProvider =
    StreamProvider.family.autoDispose<OrderEntity, String>((ref, orderId) {
  return ref.read(orderRepositoryProvider).watchOrder(orderId);
});

final placeOrderControllerProvider =
    AsyncNotifierProvider.autoDispose<PlaceOrderController, void>(PlaceOrderController.new);

class PlaceOrderController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

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
    state = const AsyncLoading();
    final result = await ref.read(orderRepositoryProvider).placeOrder(
          addressId: addressId,
          vendorId: vendorId,
          items: items,
          paymentMethod: paymentMethod,
          isEmergency: isEmergency,
          includeDeposit: includeDeposit,
          couponId: couponId,
          discountAmount: discountAmount,
          deliveryFee: deliveryFee,
        );
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      (_) => const AsyncData(null),
    );
    return result;
  }
}
