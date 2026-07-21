import '../../../../core/constants/user_role.dart';
import '../../../../core/utils/result.dart';
import '../entities/user_profile_entity.dart';

/// Result of an email/password sign-up.
///
/// Contains the freshly-created profile so the caller can navigate
/// directly into the app. Email confirmation is handled automatically
/// via a SECURITY DEFINER RPC — the user never needs to check their
/// inbox.
class SignUpOutcome {
  final UserProfileEntity? profile;
  const SignUpOutcome({this.profile});
}

/// Contract the presentation layer depends on. The concrete
/// implementation talks to Supabase Auth + the `profiles` table; a
/// fake implementation can be swapped in for widget tests.
abstract class AuthRepository {
  Stream<UserProfileEntity?> get authStateChanges;

  /// Emits `true` when Supabase reports a `passwordRecovery` auth
  /// event (the user tapped the reset-password link), and `false`
  /// once they've either updated their password or signed out. The
  /// router listens to this so it can send the user to the in-app
  /// reset-password screen instead of a role home during recovery.
  Stream<bool> get passwordRecoveryChanges;
  bool get isInPasswordRecovery;
  void clearPasswordRecovery();

  UserProfileEntity? get currentProfile;

  /// Checks whether a phone number is already registered to another
  /// profile. Used during sign-up to prevent duplicate phone numbers.
  Future<Result<bool>> isPhoneRegistered(String phone);

  /// Checks whether an email is already registered.
  Future<Result<bool>> isEmailRegistered(String email);

  /// Validates that a vendor_id exists.
  Future<Result<bool>> isVendorIdValid(String vendorId);

  /// PIN-based login for customers (6-digit PIN only).
  Future<Result<UserProfileEntity>> signInWithPin({
    required String pin,
  });

  /// Vendor creates a customer account. Returns the generated 6-digit PIN.
  Future<Result<String>> createCustomerAccount({
    required String vendorId,
    required String phone,
    required String fullName,
  });

  /// Creates an account, auto-confirms it, and returns the profile.
  /// For vendor/rider roles the account is created but marked inactive
  /// pending admin approval.
  Future<Result<SignUpOutcome>> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required UserRole role,
    String? vendorId,
    String? businessName,
  });

  Future<Result<UserProfileEntity>> signInWithEmail({
    required String email,
    required String password,
  });

  Future<Result<UserProfileEntity>> signInWithGoogle();

  Future<Result<void>> completeProfile({
    required String fullName,
    required UserRole role,
    String? email,
    String? phone,
    String? vendorId,
  });

  Future<Result<void>> resetPasswordForEmail(String email);

  /// Updates the currently-signed-in user's password. Called from the
  /// reset-password screen after Supabase's recovery link puts a
  /// PasswordRecovery session in place.
  Future<Result<void>> updatePassword(String newPassword);

  Future<Result<void>> signOut();

  Future<Result<UserProfileEntity>> refreshProfile();
}
