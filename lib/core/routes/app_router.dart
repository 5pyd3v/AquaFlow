import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/addresses/presentation/screens/add_address_screen.dart';
import '../../features/addresses/presentation/screens/address_list_screen.dart';
import '../../features/admin/presentation/screens/admin_home_screen.dart';
import '../../features/authentication/presentation/providers/auth_providers.dart';
import '../constants/user_role.dart';
import '../../features/authentication/presentation/screens/complete_profile_screen.dart';
import '../../features/authentication/presentation/screens/email_sign_in_screen.dart';
import '../../features/authentication/presentation/screens/email_sign_up_screen.dart';
import '../../features/authentication/presentation/screens/forgot_password_screen.dart';
import '../../features/authentication/presentation/screens/login_screen.dart';
import '../../features/authentication/presentation/screens/pending_approval_screen.dart';
import '../../features/authentication/presentation/screens/pin_login_screen.dart';
import '../../features/authentication/presentation/screens/reset_password_screen.dart';
import '../../features/cart/presentation/screens/cart_screen.dart';
import '../../features/customer/domain/entities/product_entity.dart';
import '../../features/customer/presentation/screens/customer_shell_screen.dart';
import '../../features/customer/presentation/screens/product_detail_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/orders/presentation/screens/checkout_screen.dart';
import '../../features/orders/presentation/screens/order_history_screen.dart';
import '../../features/orders/presentation/screens/order_tracking_screen.dart';
import '../../features/rider/presentation/screens/rider_account_screen.dart';
import '../../features/rider/presentation/screens/rider_active_deliveries_screen.dart';
import '../../features/rider/presentation/screens/rider_history_screen.dart';
import '../../features/rider/presentation/screens/rider_shell_screen.dart';
import '../../features/payments/presentation/screens/vendor_customer_finances_screen.dart';
import '../../features/payments/presentation/screens/vendor_finance_dashboard_screen.dart';
import '../../features/payments/presentation/screens/vendor_payment_approvals_screen.dart';
import '../../features/settlements/presentation/screens/rider_cod_wallet_screen.dart';
import '../../features/settlements/presentation/screens/rider_settlement_history_screen.dart';
import '../../features/settlements/presentation/screens/vendor_receive_cod_screen.dart';
import '../../features/settlements/presentation/screens/vendor_rider_financials_screen.dart';
import '../../features/settlements/presentation/screens/vendor_settlement_history_screen.dart';
import '../../features/splash/presentation/screens/splash_screen.dart';
import '../../features/vendor/presentation/screens/add_edit_product_screen.dart';
import '../../features/vendor/presentation/screens/vendor_account_screen.dart';
import '../../features/vendor/presentation/screens/vendor_create_customer_screen.dart';
import '../../features/vendor/presentation/screens/vendor_customers_screen.dart';
import '../../features/vendor/presentation/screens/vendor_live_map_screen.dart';
import '../../features/vendor/presentation/screens/vendor_orders_screen.dart';
import '../../features/vendor/presentation/screens/vendor_products_screen.dart';
import '../../features/vendor/presentation/screens/vendor_riders_screen.dart';
import '../../features/vendor/presentation/screens/vendor_shell_screen.dart';
import '../services/storage_service.dart';
import 'go_router_refresh_stream.dart';
import 'route_names.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = ref.watch(routerRefreshProvider);

  return GoRouter(
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: false,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final loggedInProfile = authState.valueOrNull;
      final location = state.matchedLocation;
      final hasSeenOnboarding = StorageService.instance.hasSeenOnboarding;
      final isRecovery = ref.read(authRepositoryProvider).isInPasswordRecovery;

      final isSplash = location == RoutePaths.splash;
      final isOnboarding = location == RoutePaths.onboarding;
      final isAuthRoute = location.startsWith('/login');
      final isCompleteProfile = location == RoutePaths.completeProfile;
      final isPendingApproval = location == RoutePaths.pendingApproval;
      final isResetPassword = location == RoutePaths.resetPassword;

      // Auth stream hasn't produced its first value yet — hold on the
      // branded splash instead of guessing at logged-out. This makes
      // the splash the single owner of the initial transition, so
      // there's no double-navigation race with the screen's own code.
      if (authState.isLoading && !authState.hasValue) {
        return isSplash ? null : RoutePaths.splash;
      }

      // Password recovery beats everything else: the user opened the
      // reset-password email link, which installed a temporary session.
      // Send them to the in-app reset screen no matter what role their
      // profile says — they haven't proven ownership yet, only recovery.
      if (isRecovery) {
        return isResetPassword ? null : RoutePaths.resetPassword;
      }

      // ---- Signed in ---------------------------------------------------
      // A logged-in user must NEVER be sent to onboarding — that check
      // lives only in the logged-out branch below. This is the fix for
      // "press back and land on onboarding again": onboarding is a
      // first-run-only, logged-out-only screen.
      if (loggedInProfile != null) {
        final needsProfileCompletion =
            !loggedInProfile.isVerified || loggedInProfile.fullName.isEmpty;
        if (needsProfileCompletion) {
          return isCompleteProfile ? null : RoutePaths.completeProfile;
        }
        // Vendors/riders in pending state (is_active = false) →
        // pending approval screen instead of their dashboard.
        if (!loggedInProfile.isActive &&
            (loggedInProfile.role == UserRole.vendor ||
             loggedInProfile.role == UserRole.rider)) {
          return isPendingApproval ? null : RoutePaths.pendingApproval;
        }
        // Profile complete: bounce out of the pre-app screens to home,
        // otherwise allow the requested in-app route.
        if (isSplash || isOnboarding || isAuthRoute || isCompleteProfile || isPendingApproval) {
          return _homePathForRole(loggedInProfile.role.dbValue);
        }
        return null;
      }

      // ---- Not signed in ----------------------------------------------
      if (!hasSeenOnboarding) {
        return isOnboarding ? null : RoutePaths.onboarding;
      }
      // Onboarding already seen: only auth routes are valid.
      if (!isAuthRoute) return RoutePaths.login;
      return null;
    },
    routes: [
      // On web, a fresh load or page refresh lands at `/` — which has
      // no matching GoRoute of its own, so without this it hits
      // errorBuilder ("Page not found: /") before the redirect logic
      // above or `initialLocation` ever gets a chance to run. This
      // makes `/` always bounce to splash, which then runs the normal
      // onboarding/auth/role redirect chain.
      GoRoute(
        path: '/',
        redirect: (context, state) => RoutePaths.splash,
      ),
      GoRoute(
        path: RoutePaths.splash,
        name: RouteNames.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RoutePaths.onboarding,
        name: RouteNames.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: RoutePaths.login,
        name: RouteNames.login,
        builder: (context, state) => const LoginScreen(),
        routes: [
          GoRoute(
            path: 'pin',
            name: RouteNames.pinLogin,
            builder: (context, state) => const PinLoginScreen(),
          ),
          GoRoute(
            path: 'email',
            name: RouteNames.emailSignIn,
            builder: (context, state) => const EmailSignInScreen(),
            routes: [
              GoRoute(
                path: 'sign-up',
                name: RouteNames.emailSignUp,
                builder: (context, state) => const EmailSignUpScreen(),
              ),
              GoRoute(
                path: 'forgot-password',
                name: RouteNames.forgotPassword,
                builder: (context, state) => const ForgotPasswordScreen(),
              ),
            ],
          ),
          // Landing route for Supabase's password-recovery deep link
          // (io.aquaflow.app://login-callback/reset-password). Kept as
          // a sibling of /login/email so the redirect guard below can
          // send the user here regardless of what they were browsing
          // when the recovery email finally arrived.
          GoRoute(
            path: 'reset-password',
            name: RouteNames.resetPassword,
            builder: (context, state) => const ResetPasswordScreen(),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.completeProfile,
        name: RouteNames.completeProfile,
        builder: (context, state) => const CompleteProfileScreen(),
      ),
      GoRoute(
        path: RoutePaths.pendingApproval,
        name: RouteNames.pendingApproval,
        builder: (context, state) => const PendingApprovalScreen(),
      ),

      // ---------------------------------------------------------------
      // Customer — the shell owns its own bottom-nav tab state
      // (IndexedStack), while every screen reachable *from* a tab has
      // its own real nested route below, so the URL bar and browser
      // back/forward button track navigation correctly on web.
      // ---------------------------------------------------------------
      GoRoute(
        path: RoutePaths.customerHome,
        name: RouteNames.customerHome,
        builder: (context, state) => const CustomerShellScreen(),
        routes: [
          GoRoute(
            path: 'product/:productId',
            name: RouteNames.productDetail,
            builder: (context, state) => ProductDetailScreen(
              productId: state.pathParameters['productId']!,
            ),
          ),
          GoRoute(
            path: 'cart',
            name: RouteNames.cart,
            builder: (context, state) => const CartScreen(),
          ),
          GoRoute(
            path: 'checkout',
            name: RouteNames.checkout,
            builder: (context, state) => const CheckoutScreen(),
          ),
          GoRoute(
            path: 'orders',
            name: RouteNames.orderHistory,
            builder: (context, state) => const OrderHistoryScreen(),
          ),
          GoRoute(
            path: 'orders/:orderId',
            name: RouteNames.orderTracking,
            builder: (context, state) => OrderTrackingScreen(
              orderId: state.pathParameters['orderId']!,
            ),
          ),
          GoRoute(
            path: 'addresses',
            name: RouteNames.addressList,
            builder: (context, state) => const AddressListScreen(),
          ),
          GoRoute(
            path: 'addresses/select',
            name: RouteNames.addressSelect,
            builder: (context, state) => const AddressListScreen(selectionMode: true),
          ),
          GoRoute(
            path: 'addresses/add',
            name: RouteNames.addAddress,
            builder: (context, state) => const AddAddressScreen(),
          ),
        ],
      ),

      // ---------------------------------------------------------------
      // Vendor — same pattern: shell + real nested routes per screen.
      // ---------------------------------------------------------------
      GoRoute(
        path: RoutePaths.vendorHome,
        name: RouteNames.vendorHome,
        builder: (context, state) => const VendorShellScreen(),
        routes: [
          GoRoute(
            path: 'orders',
            name: RouteNames.vendorOrders,
            builder: (context, state) => const VendorOrdersScreen(),
          ),
          GoRoute(
            path: 'products',
            name: RouteNames.vendorProducts,
            builder: (context, state) => const VendorProductsScreen(),
          ),
          GoRoute(
            path: 'products/add',
            name: RouteNames.vendorAddProduct,
            builder: (context, state) => const AddEditProductScreen(),
          ),
          GoRoute(
            path: 'products/edit/:productId',
            name: RouteNames.vendorEditProduct,
            builder: (context, state) => AddEditProductScreen(
              existingProduct: state.extra as ProductEntity?,
            ),
          ),
          GoRoute(
            path: 'riders',
            name: RouteNames.vendorRiders,
            builder: (context, state) => const VendorRidersScreen(),
          ),
          GoRoute(
            path: 'create-customer',
            name: RouteNames.vendorCreateCustomer,
            builder: (context, state) => const VendorCreateCustomerScreen(),
          ),
          GoRoute(
            path: 'customers',
            name: RouteNames.vendorCustomers,
            builder: (context, state) => const VendorCustomersScreen(),
          ),
          GoRoute(
            path: 'live-map',
            name: RouteNames.vendorLiveMap,
            builder: (context, state) => const VendorLiveMapScreen(),
          ),
          GoRoute(
            path: 'account',
            name: RouteNames.vendorAccount,
            builder: (context, state) => const VendorAccountScreen(),
          ),
          GoRoute(
            path: 'receive-cod',
            name: RouteNames.vendorReceiveCod,
            builder: (context, state) => const VendorReceiveCodScreen(),
          ),
          GoRoute(
            path: 'settlements',
            name: RouteNames.vendorSettlements,
            builder: (context, state) => const VendorSettlementHistoryScreen(),
          ),
          GoRoute(
            path: 'rider-finances',
            name: RouteNames.vendorRiderFinances,
            builder: (context, state) => const VendorRiderFinancialsScreen(),
          ),
          GoRoute(
            path: 'finances',
            name: RouteNames.vendorFinanceDashboard,
            builder: (context, state) => const VendorFinanceDashboardScreen(),
            routes: [
              GoRoute(
                path: 'approvals',
                name: RouteNames.vendorPaymentApprovals,
                builder: (context, state) => const VendorPaymentApprovalsScreen(),
              ),
              GoRoute(
                path: 'customer/:customerId',
                name: RouteNames.vendorCustomerFinances,
                builder: (context, state) => VendorCustomerFinancesScreen(
                  customerProfileId: state.pathParameters['customerId']!,
                  customerName: state.extra as String? ?? 'Customer',
                ),
              ),
            ],
          ),
        ],
      ),

      GoRoute(
        path: RoutePaths.riderHome,
        name: RouteNames.riderHome,
        builder: (context, state) => const RiderShellScreen(),
        routes: [
          GoRoute(
            path: 'deliveries',
            name: RouteNames.riderActiveDeliveries,
            builder: (context, state) => const RiderActiveDeliveriesScreen(),
          ),
          GoRoute(
            path: 'history',
            name: RouteNames.riderHistory,
            builder: (context, state) => const RiderHistoryScreen(),
          ),
          GoRoute(
            path: 'account',
            name: RouteNames.riderAccount,
            builder: (context, state) => const RiderAccountScreen(),
          ),
          GoRoute(
            path: 'wallet',
            name: RouteNames.riderWallet,
            builder: (context, state) => const RiderCodWalletScreen(),
            routes: [
              GoRoute(
                path: 'history',
                name: RouteNames.riderSettlementHistory,
                builder: (context, state) => const RiderSettlementHistoryScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.adminHome,
        name: RouteNames.adminHome,
        builder: (context, state) => const AdminHomeScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text('Page not found: ${state.uri}', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(RoutePaths.splash),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});

String _homePathForRole(String role) {
  switch (role) {
    case 'vendor':
      return RoutePaths.vendorHome;
    case 'rider':
      return RoutePaths.riderHome;
    case 'admin':
    case 'super_admin':
      return RoutePaths.adminHome;
    default:
      return RoutePaths.customerHome;
  }
}
