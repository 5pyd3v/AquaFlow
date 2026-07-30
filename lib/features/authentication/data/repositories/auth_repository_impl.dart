import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../../../core/config/app_config.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/constants/user_role.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/services/logger_service.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entities/user_profile_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/user_profile_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  final sb.SupabaseClient _client;
  final _profileController = StreamController<UserProfileEntity?>.broadcast();
  final _recoveryController = StreamController<bool>.broadcast();
  UserProfileModel? _cachedProfile;

  /// True once Supabase has emitted `AuthChangeEvent.passwordRecovery`
  /// (i.e. the user just tapped the "Reset your password" email). The
  /// router uses this to send them to /login/reset-password instead of
  /// the role home for their (temporarily valid) recovery session.
  bool _inPasswordRecovery = false;

  AuthRepositoryImpl({sb.SupabaseClient? client})
      : _client = client ?? SupabaseConfig.client {
    _client.auth.onAuthStateChange.listen((data) async {
      // A recovery deep-link installs a session *and* fires the
      // passwordRecovery event. Flag it before pushing profile updates
      // so the router sees the flag on the same tick.
      if (data.event == sb.AuthChangeEvent.passwordRecovery) {
        _inPasswordRecovery = true;
        _recoveryController.add(true);
      } else if (data.event == sb.AuthChangeEvent.signedOut) {
        _inPasswordRecovery = false;
        _recoveryController.add(false);
      }

      final session = data.session;
      if (session == null) {
        _cachedProfile = null;
        _profileController.add(null);
        return;
      }
      final result = await refreshProfile();
      result.fold(
        (failure) {
          AppLogger.warning('Could not load profile after auth change', failure.message);
          _profileController.add(null);
        },
        (profile) => _profileController.add(profile),
      );
    });
  }

  @override
  Stream<UserProfileEntity?> get authStateChanges => _profileController.stream;

  @override
  Stream<bool> get passwordRecoveryChanges => _recoveryController.stream;

  @override
  bool get isInPasswordRecovery => _inPasswordRecovery;

  @override
  void clearPasswordRecovery() {
    _inPasswordRecovery = false;
    _recoveryController.add(false);
  }

  @override
  UserProfileEntity? get currentProfile => _cachedProfile;

  @override
  Future<Result<bool>> isPhoneRegistered(String phone) async {
    try {
      final rows = await _client
          .from(SupabaseConfig.profiles)
          .select('id')
          .eq('phone', phone)
          .limit(1);
      return Success((rows as List).isNotEmpty);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<SignUpOutcome>> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required UserRole role,
    String? vendorId,
    String? businessName,
  }) async {
    try {
      // Create the user directly via SECURITY DEFINER RPC — no email sent,
      // no rate limits. The RPC creates auth.users + identity + profile +
      // role sub-row all in one transaction with email pre-confirmed.
      final uid = await _client.rpc('create_email_user', params: {
        'p_email': email,
        'p_password': password,
        'p_full_name': fullName,
        'p_phone': phone,
        'p_role': role.dbValue,
        'p_business_name': businessName,
        'p_vendor_id': vendorId,
      });

      if (uid == null) {
        return const Error(AuthFailure(
          'An account with this email or phone number already exists. Please sign in instead.',
        ));
      }

      // Vendors/riders are created inactive (pending approval) — they
      // cannot use the app until an admin/vendor approves them. Attempt
      // an immediate sign-in so the router can show the pending-approval
      // screen, but if GoTrue rejects it (e.g. NULL token columns on
      // older Supabase instances cause "Database error querying schema")
      // that's fine: the account IS created, and the user just needs to
      // know it's pending.
      final needsApproval = role == UserRole.vendor || role == UserRole.rider;

      try {
        await _client.auth.signInWithPassword(email: email, password: password);
      } catch (signInError) {
        if (needsApproval) {
          // Account created successfully but sign-in failed (expected on
          // some Supabase versions). Return success so the UI shows the
          // "pending approval" dialog instead of a scary error.
          AppLogger.warning(
            'Post-signup sign-in failed for $role (expected if pending approval)',
            signInError.toString(),
          );
          return const Success(SignUpOutcome());
        }
        // For customer/admin roles the sign-in must succeed — propagate.
        rethrow;
      }

      final profile = await refreshProfile();
      return profile.fold(
        (failure) => Error(failure),
        (p) => Success(SignUpOutcome(profile: p)),
      );
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<UserProfileEntity>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth
          .signInWithPassword(email: email, password: password);
      final user = response.user;
      if (user == null) {
        return const Error(AuthFailure('Incorrect email or password.'));
      }
      final profile = await _fetchOrBootstrapProfile(user);
      return Success(profile);
    } on sb.AuthException catch (e) {
      // GoTrue "Database error querying schema" means the auth.users row
      // has NULL token columns (created by our RPC before migration 0030
      // fixed them). Check if a profile exists with pending-approval
      // status and give the user a helpful message instead.
      if (e.message.toLowerCase().contains('database error')) {
        try {
          final rows = await _client
              .from(SupabaseConfig.profiles)
              .select('role, is_active')
              .eq('email', email)
              .limit(1);
          if ((rows as List).isNotEmpty) {
            final row = rows.first;
            final role = row['role'] as String? ?? '';
            final isActive = row['is_active'] as bool? ?? true;
            if (!isActive && (role == 'vendor' || role == 'rider')) {
              return Error(AuthFailure(
                'Your ${role} account is pending approval. '
                'You will be able to log in once approved.',
              ));
            }
          }
        } catch (_) {
          // Profile lookup failed too — fall through to generic message.
        }
      }
      return Error(ErrorMapper.map(e));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<bool>> isEmailRegistered(String email) async {
    try {
      final rows = await _client
          .from(SupabaseConfig.profiles)
          .select('id')
          .eq('email', email)
          .limit(1);
      return Success((rows as List).isNotEmpty);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<bool>> isVendorIdValid(String vendorId) async {
    try {
      final rows = await _client
          .from(SupabaseConfig.vendors)
          .select('id')
          .eq('id', vendorId)
          .limit(1);
      return Success((rows as List).isNotEmpty);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  /// Deterministic synthetic email used to back a customer's phone+PIN
  /// login with Supabase's standard email/password auth. Customers never
  /// see or type this — they log in with phone + 6-digit PIN.
  String _syntheticEmail(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return '$digits@pin.aquaflow.app';
  }

  String _generatePin() {
    final rng = Random.secure();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  @override
  Future<Result<UserProfileEntity>> signInWithPin({
    required String pin,
  }) async {
    try {
      // Look up the customer's phone by PIN via RPC
      final response = await _client.rpc('resolve_pin_login', params: {
        'p_pin': pin,
      });
      final phone = response?['phone'] as String?;
      if (phone == null) {
        return const Error(AuthFailure('Invalid PIN. Please check and try again.'));
      }
      final authResponse = await _client.auth.signInWithPassword(
        email: _syntheticEmail(phone),
        password: pin,
      );
      final user = authResponse.user;
      if (user == null) {
        return const Error(AuthFailure('Invalid PIN.'));
      }
      final profile = await _fetchOrBootstrapProfile(user, phone: phone);
      return Success(profile);
    } on sb.AuthException {
      return const Error(AuthFailure('Invalid PIN. Please check and try again.'));
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<String>> createCustomerAccount({
    required String vendorId,
    required String phone,
    required String fullName,
  }) async {
    try {
      // Reject duplicate phone numbers up front.
      final existing = await _client
          .from(SupabaseConfig.profiles)
          .select('id')
          .eq('phone', phone)
          .limit(1);
      if ((existing as List).isNotEmpty) {
        return const Error(AuthFailure('This phone number is already registered.'));
      }

      // Also check if the synthetic email is already taken.
      final email = _syntheticEmail(phone);
      final emailCheck = await isEmailRegistered(email);
      if (emailCheck.fold((_) => false, (exists) => exists)) {
        return const Error(AuthFailure('An account with this phone number already exists.'));
      }

      final pin = _generatePin();

      // Single SECURITY DEFINER RPC that:
      //   1. Creates auth.users row with confirmed email
      //   2. Creates profile + customer sub-row
      //   3. Links to vendor, stores PIN
      // No temp client, no email sent, no session interference.
      final result = await _client.rpc('create_pin_customer', params: {
        'p_vendor_id': vendorId,
        'p_phone': phone,
        'p_full_name': fullName,
        'p_email': email,
        'p_pin': pin,
      });

      // RPC returns null if the email already existed in auth.users
      if (result == null || result == false) {
        return const Error(AuthFailure('Could not create customer account. Please try again.'));
      }

      return Success(pin);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<String>> resetCustomerPin({
    required String vendorId,
    required String customerProfileId,
  }) async {
    try {
      final newPin = _generatePin();
      final result = await _client.rpc('reset_customer_pin', params: {
        'p_vendor_id': vendorId,
        'p_customer_profile_id': customerProfileId,
        'p_new_pin': newPin,
      });

      if (result == null || result == false) {
        return const Error(AuthFailure('Could not reset PIN. Please try again.'));
      }

      return Success(newPin);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<UserProfileEntity>> signInWithGoogle() async {
    try {
      await _client.auth.signInWithOAuth(
        sb.OAuthProvider.google,
        // On web, Supabase performs a full-page redirect back to the
        // current origin by default when `redirectTo` is omitted —
        // passing a mobile deep-link scheme here would just open an
        // unhandled `io.aquaflow.app://` URL in the browser and strand
        // the sign-in. The custom scheme only makes sense on a real
        // device/emulator, where it re-opens this app.
        redirectTo: kIsWeb ? null : AppConfig.authCallbackUrl,
      );
      // The session arrives asynchronously through onAuthStateChange;
      // callers should await `authStateChanges` after this resolves.
      final user = _client.auth.currentUser;
      if (user == null) {
        return const Error(AuthFailure('Google sign-in was cancelled.'));
      }
      final profile = await _fetchOrBootstrapProfile(user);
      return Success(profile);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> completeProfile({
    required String fullName,
    required UserRole role,
    String? email,
    String? phone,
    String? vendorId,
  }) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        return const Error(AuthFailure('No active session found.'));
      }

      // Riders and customers must be tied to a vendor; vendors/admins are not.
      final needsVendor = role == UserRole.rider || role == UserRole.customer;
      final trimmedPhone = phone?.trim() ?? '';
      final trimmedVendorId = vendorId?.trim() ?? '';

      if (needsVendor) {
        if (trimmedPhone.isEmpty) {
          return const Error(ValidationFailure('Phone number is required.'));
        }
        if (trimmedVendorId.isEmpty) {
          return const Error(ValidationFailure('Vendor ID is required.'));
        }
        // The chosen vendor must actually exist.
        final vendorExists = await isVendorIdValid(trimmedVendorId);
        final invalidVendor = vendorExists.fold((_) => true, (exists) => !exists);
        if (invalidVendor) {
          return const Error(ValidationFailure('That Vendor ID does not exist.'));
        }
        // The phone must not already belong to another profile.
        final rows = await _client
            .from(SupabaseConfig.profiles)
            .select('id')
            .eq('phone', trimmedPhone)
            .neq('id', user.id)
            .limit(1);
        if ((rows as List).isNotEmpty) {
          return const Error(
            ValidationFailure('That phone number is already in use.'),
          );
        }
      }

      final needsApproval = role == UserRole.vendor || role == UserRole.rider;
      await _client.from(SupabaseConfig.profiles).upsert({
        'id': user.id,
        'full_name': fullName,
        'phone': needsVendor ? trimmedPhone : (user.phone ?? ''),
        'email': email ?? user.email,
        'role': role.dbValue,
        'is_verified': true,
        'is_active': !needsApproval,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // The `ensure_role_subrow` trigger (migration 0008) creates the
      // rider/customer row on role change, but without a vendor link.
      // Attach the chosen vendor now that the profile row is in place.
      if (needsVendor) {
        final table = role == UserRole.rider
            ? SupabaseConfig.riders
            : SupabaseConfig.customers;
        await _client
            .from(table)
            .update({'vendor_id': trimmedVendorId})
            .eq('profile_id', user.id);
      }

      await refreshProfile();
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> resetPasswordForEmail(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        // Deep-link back into the app so tapping the email opens the
        // in-app "set a new password" screen rather than the default
        // Supabase dashboard Site URL (localhost during setup).
        redirectTo: kIsWeb ? null : AppConfig.passwordRecoveryUrl,
      );
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(sb.UserAttributes(password: newPassword));
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await _client.auth.signOut();
      _cachedProfile = null;
      _inPasswordRecovery = false;
      _recoveryController.add(false);
      return const Success(null);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  @override
  Future<Result<UserProfileEntity>> refreshProfile() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        return const Error(AuthFailure('Not signed in.'));
      }
      final profile = await _fetchOrBootstrapProfile(user);
      // Also push the refreshed profile down the stream so anything
      // watching authStateChanges (Riverpod StreamProvider + the router
      // refresh) sees the freshly-verified profile without waiting for
      // the next Supabase auth event. This is what makes the "sign up
      // → land on vendor/rider home directly" flow work.
      _profileController.add(profile);
      return Success(profile);
    } catch (e) {
      return Error(ErrorMapper.map(e));
    }
  }

  /// Fetches the `profiles` row for the signed-in auth user. If it
  /// doesn't exist yet (first OTP login), creates a minimal row so
  /// downstream code always has a profile to read — the role-selection
  /// / complete-profile screen fills in the rest.
  Future<UserProfileModel> _fetchOrBootstrapProfile(
    sb.User user, {
    String? phone,
  }) async {
    final existing = await _client
        .from(SupabaseConfig.profiles)
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (existing != null) {
      // Auto-verify profiles that already have the required fields
      // filled in (from the sign-up metadata the trigger copied).
      // This fixes "email confirmation lands on complete-profile even
      // though the user already provided name/role during sign-up".
      //
      // BUT: don't auto-verify if the user still needs to provide a
      // phone number or vendor link (Google login gives us a name but
      // no phone/vendor, so we must hold them at complete-profile).
      final hasName = (existing['full_name'] as String?)?.isNotEmpty == true;
      final hasPhone = (existing['phone'] as String?)?.isNotEmpty == true;
      final role = existing['role'] as String? ?? 'customer';
      final needsVendorLink = role == 'customer' || role == 'rider';
      final isFullyComplete = hasName && (!needsVendorLink || hasPhone);

      final needsAutoVerify =
          existing['is_verified'] != true && isFullyComplete;
      if (needsAutoVerify) {
        await _client.from(SupabaseConfig.profiles).update({
          'is_verified': true,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', user.id);
        existing['is_verified'] = true;
      }
      final model = UserProfileModel.fromJson(existing);
      _cachedProfile = model;
      return model;
    }

    final bootstrapRole = user.userMetadata?['role'] ?? UserRole.customer.dbValue;
    final bootstrapNeedsApproval = bootstrapRole == 'vendor' || bootstrapRole == 'rider';
    final bootstrapped = {
      'id': user.id,
      'full_name': user.userMetadata?['full_name'] ?? '',
      'phone': phone ?? user.phone ?? '',
      'email': user.email,
      'role': bootstrapRole,
      'is_verified': false,
      'is_active': !bootstrapNeedsApproval,
      'created_at': DateTime.now().toIso8601String(),
    };

    try {
      await _client.from(SupabaseConfig.profiles).insert(bootstrapped);
    } on sb.PostgrestException catch (e) {
      // Row may already exist from a race with a DB trigger — ignore
      // unique-violation and re-fetch instead of failing the sign-in.
      if (e.code != '23505') rethrow;
    }

    final refetched = await _client
        .from(SupabaseConfig.profiles)
        .select()
        .eq('id', user.id)
        .single();

    final model = UserProfileModel.fromJson(refetched);
    _cachedProfile = model;
    return model;
  }

  void dispose() {
    _profileController.close();
    _recoveryController.close();
  }
}
