import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/user_role.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/result.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/user_profile_entity.dart';
import '../../domain/repositories/auth_repository.dart';

// Re-export so screens can import the outcome type without depending
// on the repository interface directly.
export '../../domain/repositories/auth_repository.dart' show SignUpOutcome;

/// Concrete repository singleton. Swappable in tests via
/// `ProviderScope(overrides: [authRepositoryProvider.overrideWithValue(fake)])`.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repo = AuthRepositoryImpl();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Live auth/profile stream the whole app listens to for routing
/// decisions (see `app_router.dart` refreshListenable).
final authStateProvider = StreamProvider<UserProfileEntity?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges;
});

/// Live "user is inside a password-recovery session" flag. Set to true
/// the instant Supabase emits the `passwordRecovery` auth event (which
/// fires when a customer opens the reset-password email link), and
/// stays true until they either successfully update their password or
/// sign out. The router uses this to redirect an otherwise valid
/// session straight to the reset-password screen instead of the role
/// home.
final passwordRecoveryProvider = StreamProvider<bool>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.passwordRecoveryChanges;
});

/// Convenience derived providers used by guards/UI.
final currentRoleProvider = Provider<UserRole?>((ref) {
  return ref.watch(authStateProvider).valueOrNull?.role;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).valueOrNull != null;
});

/// Async action controller for every auth screen (phone OTP flow,
/// email/password, Google, sign-out). Exposes a `Result`-shaped
/// AsyncValue so screens can pattern-match failures without duplicating
/// try/catch per button.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);

class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<Result<UserProfileEntity>> signInWithPin({
    required String pin,
  }) async {
    state = const AsyncLoading();
    final result = await _repo.signInWithPin(pin: pin);
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      (_) => const AsyncData(null),
    );
    return result;
  }

  Future<Result<SignUpOutcome>> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required UserRole role,
    String? vendorId,
    String? businessName,
  }) async {
    state = const AsyncLoading();

    // Prevent duplicate phone numbers — check before calling Supabase.
    final phoneCheck = await _repo.isPhoneRegistered(phone);
    final phoneTaken = phoneCheck.fold((_) => false, (taken) => taken);
    if (phoneTaken) {
      const failure = AuthFailure('This phone number is already registered to another account.');
      state = AsyncError(failure, StackTrace.current);
      return const Error(failure);
    }

    final result = await _repo.signUpWithEmail(
      email: email,
      password: password,
      fullName: fullName,
      phone: phone,
      role: role,
      vendorId: vendorId,
      businessName: businessName,
    );
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      (_) => const AsyncData(null),
    );
    return result;
  }

  Future<Result<UserProfileEntity>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    final result = await _repo.signInWithEmail(email: email, password: password);
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      (_) => const AsyncData(null),
    );
    return result;
  }

  Future<Result<UserProfileEntity>> signInWithGoogle() async {
    state = const AsyncLoading();
    final result = await _repo.signInWithGoogle();
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      (_) => const AsyncData(null),
    );
    return result;
  }

  Future<Result<void>> completeProfile({
    required String fullName,
    required UserRole role,
    String? email,
    String? phone,
    String? vendorId,
  }) async {
    state = const AsyncLoading();
    final result = await _repo.completeProfile(
      fullName: fullName,
      role: role,
      email: email,
      phone: phone,
      vendorId: vendorId,
    );
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      (_) => const AsyncData(null),
    );
    return result;
  }

  Future<Result<void>> resetPassword(String email) async {
    state = const AsyncLoading();
    final result = await _repo.resetPasswordForEmail(email);
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      (_) => const AsyncData(null),
    );
    return result;
  }

  Future<Result<void>> updatePassword(String newPassword) async {
    state = const AsyncLoading();
    final result = await _repo.updatePassword(newPassword);
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      (_) => const AsyncData(null),
    );
    return result;
  }

  Future<Result<String>> createCustomerAccount({
    required String phone,
    required String fullName,
    required String vendorId,
  }) async {
    state = const AsyncLoading();
    final result = await _repo.createCustomerAccount(
      phone: phone,
      fullName: fullName,
      vendorId: vendorId,
    );
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      (_) => const AsyncData(null),
    );
    return result;
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    final result = await _repo.signOut();
    state = result.fold(
      (failure) => AsyncError(failure, StackTrace.current),
      (_) => const AsyncData(null),
    );
  }
}
