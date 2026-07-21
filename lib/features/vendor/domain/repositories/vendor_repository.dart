import '../../../../core/constants/order_status.dart';
import '../../../../core/utils/result.dart';
import '../../../customer/domain/entities/product_entity.dart';
import '../entities/rider_location_entity.dart';
import '../entities/vendor_entity.dart';
import '../entities/vendor_order_entity.dart';
import '../entities/vendor_rider_entity.dart';
import '../entities/vendor_customer_entity.dart';
import '../entities/vendor_stats_entity.dart';

abstract class VendorRepository {
  Future<Result<VendorEntity>> getMyVendorProfile();

  Future<Result<void>> updateVendorProfile({
    required String businessName,
    String? address,
    double? latitude,
    double? longitude,
    double? deliveryRadiusKm,
  });

  Future<Result<VendorStatsEntity>> getStats(String vendorId);

  Future<Result<List<ProductEntity>>> getMyProducts(String vendorId);

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
  });

  Future<Result<void>> updateProduct(ProductEntity product);

  Future<Result<void>> deleteProduct(String productId);

  Future<Result<void>> toggleProductAvailability(String productId, bool isAvailable);

  Future<Result<void>> updateStock(String productId, int newQuantity);

  Future<Result<List<VendorOrderEntity>>> getOrders(String vendorId, {OrderStatus? statusFilter});

  Future<Result<void>> acceptOrder(String orderId);

  Future<Result<void>> rejectOrder(String orderId, String reason);

  Future<Result<void>> assignRider(String orderId, String riderId);

  Future<Result<List<VendorRiderEntity>>> getMyRiders(String vendorId);

  Future<Result<void>> linkRiderByPhone(String phone);

  /// Approve a rider who self-registered under this vendor. Flips their
  /// account active so they can leave the pending-approval screen.
  Future<Result<void>> approveRider(String riderId);

  /// Reject a pending rider request — unlinks them from this vendor.
  Future<Result<void>> rejectRider(String riderId);

  Future<Result<void>> unlinkRider(String riderId);

  Future<Result<List<VendorCustomerEntity>>> getMyCustomers(String vendorId);

  /// Live stream of every rider location this vendor is authorized to
  /// see (enforced by RLS — see migration 0012 — rather than filtered
  /// client-side), for the "Live Riders" map.
  Stream<List<RiderLocationEntity>> watchRiderLocations();
}
