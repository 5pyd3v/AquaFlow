import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/order_status.dart';
import '../../../../core/utils/result.dart';
import '../../../customer/domain/entities/product_entity.dart';
import '../../data/repositories/vendor_repository_impl.dart';
import '../../domain/entities/rider_location_entity.dart';
import '../../domain/entities/vendor_customer_entity.dart';
import '../../domain/entities/vendor_entity.dart';
import '../../domain/entities/vendor_order_entity.dart';
import '../../domain/entities/vendor_rider_entity.dart';
import '../../domain/entities/vendor_stats_entity.dart';
import '../../domain/repositories/vendor_repository.dart';

final vendorRepositoryProvider = Provider<VendorRepository>((ref) => VendorRepositoryImpl());

/// The signed-in vendor's own business row — nearly every other vendor
/// provider depends on `vendor.id`, so this is the root of the tree.
final myVendorProvider = FutureProvider.autoDispose<VendorEntity>((ref) async {
  final result = await ref.read(vendorRepositoryProvider).getMyVendorProfile();
  return result.fold((failure) => throw failure, (data) => data);
});

final vendorStatsProvider = FutureProvider.autoDispose<VendorStatsEntity>((ref) async {
  final vendor = await ref.watch(myVendorProvider.future);
  final result = await ref.read(vendorRepositoryProvider).getStats(vendor.id);
  return result.fold((failure) => throw failure, (data) => data);
});

final vendorProductsProvider =
    AsyncNotifierProvider.autoDispose<VendorProductsController, List<ProductEntity>>(
        VendorProductsController.new);

class VendorProductsController extends AutoDisposeAsyncNotifier<List<ProductEntity>> {
  @override
  Future<List<ProductEntity>> build() async {
    final vendor = await ref.watch(myVendorProvider.future);
    final result = await ref.read(vendorRepositoryProvider).getMyProducts(vendor.id);
    return result.fold((failure) => throw failure, (data) => data);
  }

  Future<Result<void>> deleteProduct(String productId) async {
    final result = await ref.read(vendorRepositoryProvider).deleteProduct(productId);
    result.fold((_) {}, (_) => ref.invalidateSelf());
    return result;
  }

  Future<Result<void>> toggleAvailability(String productId, bool isAvailable) async {
    final result =
        await ref.read(vendorRepositoryProvider).toggleProductAvailability(productId, isAvailable);
    result.fold((_) {}, (_) => ref.invalidateSelf());
    return result;
  }

  Future<Result<void>> updateStock(String productId, int quantity) async {
    final result = await ref.read(vendorRepositoryProvider).updateStock(productId, quantity);
    result.fold((_) {}, (_) => ref.invalidateSelf());
    return result;
  }
}

final vendorOrderStatusFilterProvider = StateProvider.autoDispose<OrderStatus?>((ref) => null);

final vendorOrdersProvider =
    AsyncNotifierProvider.autoDispose<VendorOrdersController, List<VendorOrderEntity>>(
        VendorOrdersController.new);

class VendorOrdersController extends AutoDisposeAsyncNotifier<List<VendorOrderEntity>> {
  @override
  Future<List<VendorOrderEntity>> build() async {
    final statusFilter = ref.watch(vendorOrderStatusFilterProvider);
    final vendor = await ref.watch(myVendorProvider.future);
    final result = await ref.read(vendorRepositoryProvider).getOrders(vendor.id, statusFilter: statusFilter);
    return result.fold((failure) => throw failure, (data) => data);
  }

  Future<Result<void>> accept(String orderId) async {
    final result = await ref.read(vendorRepositoryProvider).acceptOrder(orderId);
    result.fold((_) {}, (_) => ref.invalidateSelf());
    return result;
  }

  Future<Result<void>> reject(String orderId, String reason) async {
    final result = await ref.read(vendorRepositoryProvider).rejectOrder(orderId, reason);
    result.fold((_) {}, (_) => ref.invalidateSelf());
    return result;
  }

  Future<Result<void>> assignRider(String orderId, String riderId) async {
    final result = await ref.read(vendorRepositoryProvider).assignRider(orderId, riderId);
    result.fold((_) {}, (_) => ref.invalidateSelf());
    return result;
  }
}

final vendorRidersProvider =
    AsyncNotifierProvider.autoDispose<VendorRidersController, List<VendorRiderEntity>>(
        VendorRidersController.new);

class VendorRidersController extends AutoDisposeAsyncNotifier<List<VendorRiderEntity>> {
  @override
  Future<List<VendorRiderEntity>> build() async {
    final vendor = await ref.watch(myVendorProvider.future);
    final result = await ref.read(vendorRepositoryProvider).getMyRiders(vendor.id);
    return result.fold((failure) => throw failure, (data) => data);
  }

  Future<Result<void>> linkByPhone(String phone) async {
    final result = await ref.read(vendorRepositoryProvider).linkRiderByPhone(phone);
    result.fold((_) {}, (_) => ref.invalidateSelf());
    return result;
  }

  Future<Result<void>> approve(String riderId) async {
    final result = await ref.read(vendorRepositoryProvider).approveRider(riderId);
    result.fold((_) {}, (_) => ref.invalidateSelf());
    return result;
  }

  Future<Result<void>> reject(String riderId) async {
    final result = await ref.read(vendorRepositoryProvider).rejectRider(riderId);
    result.fold((_) {}, (_) => ref.invalidateSelf());
    return result;
  }

  Future<Result<void>> unlink(String riderId) async {
    final result = await ref.read(vendorRepositoryProvider).unlinkRider(riderId);
    result.fold((_) {}, (_) => ref.invalidateSelf());
    return result;
  }
}

/// Vendor's customers list — fetched via SECURITY DEFINER RPC so it
/// bypasses the per-customer RLS (customers can only read their own row).
final vendorCustomersProvider =
    FutureProvider.autoDispose<List<VendorCustomerEntity>>((ref) async {
  final vendor = await ref.watch(myVendorProvider.future);
  final result = await ref.read(vendorRepositoryProvider).getMyCustomers(vendor.id);
  return result.fold((failure) => throw failure, (data) => data);
});

/// Live location for every rider this vendor is authorized to see
/// (scoped server-side by RLS — migration 0012). Feeds both the Live
/// Riders map and the nearest-rider sort in the assignment sheet.
final riderLocationsStreamProvider = StreamProvider.autoDispose<List<RiderLocationEntity>>((ref) {
  return ref.watch(vendorRepositoryProvider).watchRiderLocations();
});
