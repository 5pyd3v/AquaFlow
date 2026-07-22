import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/order_status.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/utils/result.dart';
import '../../data/repositories/rider_repository_impl.dart';
import '../../domain/entities/rider_delivery_entity.dart';
import '../../domain/entities/rider_profile_entity.dart';
import '../../domain/entities/rider_stats_entity.dart';
import '../../domain/repositories/rider_repository.dart';

final riderRepositoryProvider = Provider<RiderRepository>((ref) => RiderRepositoryImpl());

final myRiderProvider = FutureProvider.autoDispose<RiderProfileEntity>((ref) async {
  final result = await ref.read(riderRepositoryProvider).getMyRiderProfile();
  return result.fold((failure) => throw failure, (data) => data);
});

final riderStatsProvider = FutureProvider.autoDispose<RiderStatsEntity>((ref) async {
  final rider = await ref.watch(myRiderProvider.future);
  final result = await ref.read(riderRepositoryProvider).getStats(rider.id);
  return result.fold((failure) => throw failure, (data) => data);
});

final activeDeliveriesProvider =
    AsyncNotifierProvider.autoDispose<ActiveDeliveriesController, List<RiderDeliveryEntity>>(
        ActiveDeliveriesController.new);

class ActiveDeliveriesController extends AutoDisposeAsyncNotifier<List<RiderDeliveryEntity>> {
  @override
  Future<List<RiderDeliveryEntity>> build() async {
    final rider = await ref.watch(myRiderProvider.future);
    final result = await ref.read(riderRepositoryProvider).getActiveDeliveries(rider.id);
    return result.fold((failure) => throw failure, (data) => data);
  }

  Future<Result<void>> updateStatus(String orderId, OrderStatus status) async {
    final result = await ref.read(riderRepositoryProvider).updateDeliveryStatus(orderId, status);
    result.fold((_) {}, (_) => ref.invalidateSelf());
    return result;
  }

  Future<Result<void>> completeDelivery(String orderId, String otp) async {
    final result = await ref.read(riderRepositoryProvider).completeDelivery(orderId, otp);
    result.fold((_) {}, (_) {
      ref.invalidateSelf();
      ref.invalidate(deliveryHistoryProvider);
      ref.invalidate(riderStatsProvider);
    });
    return result;
  }
}

final deliveryHistoryProvider = FutureProvider.autoDispose<List<RiderDeliveryEntity>>((ref) async {
  final rider = await ref.watch(myRiderProvider.future);
  final result = await ref.read(riderRepositoryProvider).getDeliveryHistory(rider.id);
  return result.fold((failure) => throw failure, (data) => data);
});

/// Check if a specific customer has outstanding payments on orders assigned to this rider.
/// Used to show "Defaulter" badge on order detail screen.
final customerOutstandingProvider =
    FutureProvider.autoDispose.family<int, CustomerOutstandingParams>((ref, params) async {
  final result = await ref.read(riderRepositoryProvider).getCustomerOutstanding(
        customerProfileId: params.customerProfileId,
        riderId: params.riderId,
      );
  return result.fold((failure) => 0, (data) => data);
});

/// Parameters for checking customer outstanding
class CustomerOutstandingParams {
  final String customerProfileId;
  final String riderId;
  CustomerOutstandingParams(this.customerProfileId, this.riderId);
}

/// Toggles the rider's shift (available/offline) and starts or stops
/// the live-location broadcast loop accordingly — going "on shift"
/// with no active delivery yet still updates the rider's own last-
/// known point so the vendor/admin dashboards can show it on a map.
final shiftControllerProvider = AsyncNotifierProvider.autoDispose<ShiftController, void>(ShiftController.new);

class ShiftController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<Result<void>> toggleShift(bool isOnShift) async {
    state = const AsyncLoading();
    final result = await ref.read(riderRepositoryProvider).setShiftStatus(isOnShift);
    state = result.fold((failure) => AsyncError(failure, StackTrace.current), (_) => const AsyncData(null));
    result.fold((_) {}, (_) => ref.invalidate(myRiderProvider));
    return result;
  }
}

/// Streams the device's live position and pushes it to
/// `realtime_locations` while the rider is on shift. Deliberately
/// NOT `autoDispose` — this needs to keep running for the whole
/// session based on shift status, not the lifetime of whichever
/// screen happens to be mounted. It's started/stopped explicitly by
/// listening to `myRiderProvider.isOnShift` (see
/// `rider_dashboard_screen.dart`), not by widget mount/unmount, so an
/// `autoDispose` provider — which tears itself down the instant
/// nothing calls `ref.watch` on it — would silently kill the stream
/// right after starting it.
final locationBroadcastProvider = Provider<LocationBroadcaster>((ref) {
  final broadcaster = LocationBroadcaster(ref);
  ref.onDispose(broadcaster.stop);
  return broadcaster;
});

class LocationBroadcaster {
  final Ref _ref;
  StreamSubscription? _subscription;

  LocationBroadcaster(this._ref);

  bool get isActive => _subscription != null;

  void start() {
    if (_subscription != null) return;
    _subscription = LocationService.instance.watchPosition().listen((position) {
      _ref.read(riderRepositoryProvider).broadcastLocation(
            latitude: position.latitude,
            longitude: position.longitude,
            headingDegrees: position.heading,
            speedKmh: position.speed * 3.6,
          );
    });
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }
}
