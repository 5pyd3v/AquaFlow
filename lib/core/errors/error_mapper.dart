import 'package:supabase_flutter/supabase_flutter.dart';
import 'exceptions.dart' hide AuthException;
import 'failures.dart';

/// Translates any exception thrown by the data layer into a typed
/// [Failure]. This is the single choke point that keeps
/// PostgrestException / AuthException / SocketException etc. from
/// leaking past the repository boundary.
///
/// Deliberately has zero `dart:io` dependency — this file runs on
/// every platform including web, where `dart:io` doesn't exist at
/// all and importing it is a hard compile error, not just a runtime
/// warning. Socket-level errors (native platforms only) are matched
/// by type name below instead of a static `SocketException` import.
class ErrorMapper {
  ErrorMapper._();

  static Failure map(Object error) {
    if (error is Failure) return error;

    if (error is AuthApiException) {
      return AuthFailure(_friendlyAuthMessage(error.message));
    }
    if (error is AuthException) {
      return AuthFailure(error.message);
    }
    if (error is PostgrestException) {
      return ServerFailure(_friendlyDbMessage(error), statusCode: int.tryParse(error.code ?? ''));
    }
    if (error is StorageException) {
      return ServerFailure(error.message, statusCode: error.statusCode != null ? int.tryParse(error.statusCode!) : null);
    }
    if (error is NetworkException) {
      return NetworkFailure(error.message);
    }
    // Matches `SocketException` (native platforms) and analogous
    // low-level connection errors by type name rather than a static
    // `dart:io` import, so this file compiles identically on web.
    if (error.runtimeType.toString() == 'SocketException') {
      return const NetworkFailure();
    }
    if (error is CacheException) {
      return CacheFailure(error.message);
    }
    if (error is ValidationException) {
      return ValidationFailure(error.message, fieldErrors: error.fieldErrors);
    }
    if (error is PermissionException) {
      return PermissionFailure(error.message);
    }
    if (error is LocationException) {
      return LocationFailure(error.message);
    }
    if (error is PaymentException) {
      return PaymentFailure(error.message);
    }
    if (error is ServerException) {
      return ServerFailure(error.message, statusCode: error.statusCode);
    }

    return UnknownFailure(error.toString());
  }

  static String _friendlyAuthMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return 'Incorrect phone/email or password.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Please verify your email before logging in.';
    }
    if (lower.contains('otp')) {
      return 'The verification code is invalid or has expired.';
    }
    if (lower.contains('already registered')) {
      return 'An account with this phone/email already exists.';
    }
    return raw;
  }

  static String _friendlyDbMessage(PostgrestException e) {
    if (e.code == '23505') return 'This record already exists.';
    if (e.code == '23503') return 'This action references data that no longer exists.';
    if (e.code == '42501') return 'You do not have permission to perform this action.';
    return e.message;
  }
}
