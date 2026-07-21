import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

/// Distinguishes "has a network interface" from "can actually reach
/// the internet" — connectivity_plus alone reports connected on a
/// captive Wi-Fi with no real internet, which breaks offline banners.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final InternetConnection _internetChecker = InternetConnection();

  StreamSubscription<InternetStatus>? _subscription;
  final StreamController<bool> _statusController =
      StreamController<bool>.broadcast();

  Stream<bool> get onStatusChange => _statusController.stream;

  Future<bool> get isConnected async {
    final results = await _connectivity.checkConnectivity();
    if (results.contains(ConnectivityResult.none)) return false;
    return _internetChecker.hasInternetAccess;
  }

  void startMonitoring() {
    _subscription = _internetChecker.onStatusChange.listen((status) {
      _statusController.add(status == InternetStatus.connected);
    });
  }

  void dispose() {
    _subscription?.cancel();
    _statusController.close();
  }
}
