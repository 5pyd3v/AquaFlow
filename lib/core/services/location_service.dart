import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../config/app_config.dart';
import '../errors/exceptions.dart';

/// Wraps Geolocator with the permission-request flow the app needs
/// (customer address pinning, rider live tracking) so no screen has
/// to reimplement the "check → request → open settings" dance.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  StreamSubscription<Position>? _positionSubscription;

  Future<bool> ensurePermission() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
          'Location services are disabled. Please enable GPS.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationException('Location permission was denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
          'Location permission permanently denied. Enable it from app settings.');
    }

    return true;
  }

  Future<Position> getCurrentPosition() async {
    await ensurePermission();
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  /// Continuous stream used by the Rider app to broadcast location to
  /// `realtime_locations` while a delivery is active.
  Stream<Position> watchPosition() {
    final settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: AppConfig.riderLocationUpdateIntervalMeters.round(),
    );
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  double distanceInKm(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000;
  }

  Future<void> stopWatching() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }
}
