import '../../../../core/constants/order_status.dart';
import '../../../../core/utils/result.dart';
import '../entities/rider_delivery_entity.dart';
import '../entities/rider_profile_entity.dart';
import '../entities/rider_stats_entity.dart';

abstract class RiderRepository {
  Future<Result<RiderProfileEntity>> getMyRiderProfile();

  Future<Result<void>> updateVehicleInfo({
    required String vehicleType,
    required String vehiclePlate,
  });

  Future<Result<void>> setShiftStatus(bool isOnShift);

  Future<Result<RiderStatsEntity>> getStats(String riderId);

  /// Deliveries currently in flight for this rider (assigned, picked
  /// up, or on the way) — what the "Active Deliveries" tab shows.
  Future<Result<List<RiderDeliveryEntity>>> getActiveDeliveries(String riderId);

  /// Completed/cancelled deliveries — the "History" tab.
  Future<Result<List<RiderDeliveryEntity>>> getDeliveryHistory(String riderId);

  Future<Result<void>> updateDeliveryStatus(String orderId, OrderStatus newStatus);

  /// Verifies the customer-provided handoff code server-side (via the
  /// `verify_delivery_otp` RPC) and marks the order delivered on
  /// success — the correct code is never read by this client.
  Future<Result<void>> completeDelivery(String orderId, String enteredOtp);

  /// Upserts this rider's current lat/lng into `realtime_locations`,
  /// which the customer's tracking screen (and future admin heat map)
  /// reads from.
  Future<Result<void>> broadcastLocation({
    required double latitude,
    required double longitude,
    double? headingDegrees,
    double? speedKmh,
  });
}
