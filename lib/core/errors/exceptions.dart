/// Low-level exceptions thrown by the data layer (repositories, data
/// sources). These get caught and translated into [Failure]s before
/// reaching the presentation layer — presentation code should never
/// catch a raw exception type directly. Each overrides `toString()`
/// with just the human message anyway, as a safety net for the rare
/// call site (e.g. a raw `try/catch` around a platform call like
/// Geolocator) that displays `e.toString()` directly.
class ServerException implements Exception {
  final String message;
  final int? statusCode;
  const ServerException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class NetworkException implements Exception {
  final String message;
  const NetworkException([this.message = 'No internet connection']);
  @override
  String toString() => message;
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

class CacheException implements Exception {
  final String message;
  const CacheException([this.message = 'Cache error']);
  @override
  String toString() => message;
}

class ValidationException implements Exception {
  final String message;
  final Map<String, String>? fieldErrors;
  const ValidationException(this.message, {this.fieldErrors});
  @override
  String toString() => message;
}

class PermissionException implements Exception {
  final String message;
  const PermissionException([this.message = 'Permission denied']);
  @override
  String toString() => message;
}

class LocationException implements Exception {
  final String message;
  const LocationException(this.message);
  @override
  String toString() => message;
}

class PaymentException implements Exception {
  final String message;
  final String? gatewayCode;
  const PaymentException(this.message, {this.gatewayCode});
  @override
  String toString() => message;
}
