import '../constants/user_role.dart';

/// Static, non-secret application configuration.
class AppConfig {
  AppConfig._();

  static const String appName = 'AquaFlow';
  static const String appTagline = 'Pure Water, Delivered Fast';
  static const String appVersion = '1.0.0';

  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 50;

  // Timeouts
  static const Duration apiConnectTimeout = Duration(seconds: 15);
  static const Duration apiReceiveTimeout = Duration(seconds: 20);
  static const Duration otpResendCooldown = Duration(seconds: 60);
  static const Duration otpExpiry = Duration(minutes: 5);

  // Location
  static const double defaultDeliveryRadiusKm = 8.0;
  static const double riderLocationUpdateIntervalMeters = 25.0;
  static const Duration riderLocationUpdateInterval = Duration(seconds: 8);

  // Business rules
  static const double minOrderAmount = 100.0;
  static const double emergencyDeliverySurcharge = 150.0;
  static const int maxAddressesPerCustomer = 6;
  static const int vendorResponseTimeoutSeconds = 90;

  // Cache
  static const Duration cacheValidDuration = Duration(hours: 6);
  static const String hiveOrdersBox = 'orders_cache_box';
  static const String hiveProductsBox = 'products_cache_box';
  static const String hiveUserBox = 'user_box';

  // Support
  static const String supportPhone = '+92-300-0000000';
  static const String supportEmail = 'support@aquaflow.app';

  // Deep-link callback used for Supabase magic links (email
  // verification, password reset, Google OAuth). Must match the
  // <data android:scheme=... android:host=...> in AndroidManifest.xml
  // and be added to Supabase → Authentication → URL Configuration →
  // Additional Redirect URLs. `path` is what the router matches on to
  // pick the right screen (see app_router.dart).
  static const String deepLinkScheme = 'io.aquaflow.app';
  static const String deepLinkHost = 'login-callback';
  static const String authCallbackUrl =
      '$deepLinkScheme://$deepLinkHost/';
  static const String passwordRecoveryUrl =
      '$deepLinkScheme://$deepLinkHost/reset-password';

  // App flavor / fixed role
  //
  // Each build of the app (customer / vendor / rider) is compiled with
  // this set so screens like EmailSignUpScreen know which role they're
  // for without an in-app picker.
  //
  // Run with e.g.:
  //   flutter run --dart-define=FLAVOR=customer
  //   flutter run --dart-define=FLAVOR=vendor
  //   flutter run --dart-define=FLAVOR=rider
  static const String _flavorString =
      String.fromEnvironment('FLAVOR', defaultValue: 'vendor');

  static UserRole get fixedRole {
    switch (_flavorString) {
      case 'vendor':
        return UserRole.vendor;
      case 'rider':
        return UserRole.rider;
      case 'customer':
      default:
        return UserRole.customer;
    }
  }
}