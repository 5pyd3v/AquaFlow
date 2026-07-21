import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/authentication/domain/entities/user_profile_entity.dart';
import '../../features/authentication/presentation/providers/auth_providers.dart';

/// A `Listenable` that GoRouter watches via `refreshListenable` so it
/// re-runs its redirect logic whenever auth state changes.
///
/// Deliberately implemented as a `ref.listen` on the *Riverpod-managed*
/// `authStateProvider` rather than the raw Supabase stream. The raw
/// broadcast stream has two independent listeners (GoRouter's refresh
/// AND Riverpod's StreamProvider), and broadcast delivery order is
/// subscription-order — the refresh used to fire *before* the
/// StreamProvider had updated, so `ref.read(authStateProvider)` inside
/// the redirect saw the *previous* value. That caused "sign out
/// requires two taps" and "sign up bounces back before the new session
/// is visible": the router redirect ran on stale state.
///
/// By wiring the notifier to Riverpod's `ref.listen`, the notification
/// fires only *after* `authStateProvider` has committed the new value,
/// so the redirect always reads fresh state.
final routerRefreshProvider = Provider<Listenable>((ref) {
  final notifier = ValueNotifier<int>(0);
  ref.onDispose(notifier.dispose);
  ref.listen<AsyncValue<UserProfileEntity?>>(
    authStateProvider,
    (previous, next) => notifier.value++,
    fireImmediately: true,
  );
  // Also refresh on password-recovery events so tapping the reset
  // email link re-runs the router redirect immediately (rather than
  // waiting for the next auth event to bump the value).
  ref.listen<AsyncValue<bool>>(
    passwordRecoveryProvider,
    (previous, next) => notifier.value++,
    fireImmediately: true,
  );
  return notifier;
});
