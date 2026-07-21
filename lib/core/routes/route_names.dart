/// Central registry of route paths + names. Screens navigate via
/// `context.goNamed(RouteNames.login)` / `context.pushNamed(...)`
/// rather than hardcoded path strings, so renaming a path never
/// breaks a `push` call somewhere deep in a feature folder.
///
/// Every screen a user can land on directly — including ones reached
/// via a button tap deep inside a tab, like product detail or order
/// tracking — has a real GoRouter route here rather than a bare
/// `Navigator.push(MaterialPageRoute(...))`. That matters most on
/// web: it's what makes the browser's address bar, back/forward
/// buttons, and page-refresh all do the right thing instead of
/// dumping the user back to the shell root.
class RouteNames {
  RouteNames._();

  static const splash = 'splash';
  static const onboarding = 'onboarding';

  static const login = 'login';
  static const pinLogin = 'pin-login';
  static const emailSignIn = 'email-sign-in';
  static const emailSignUp = 'email-sign-up';
  static const forgotPassword = 'forgot-password';
  static const resetPassword = 'reset-password';
  static const completeProfile = 'complete-profile';
  static const pendingApproval = 'pending-approval';
  static const roleSelection = 'role-selection';

  // Role home shells
  static const customerHome = 'customer-home';
  static const vendorHome = 'vendor-home';
  static const riderHome = 'rider-home';
  static const adminHome = 'admin-home';

  // Customer feature routes
  static const productDetail = 'product-detail';
  static const cart = 'cart';
  static const checkout = 'checkout';
  static const orderHistory = 'order-history';
  static const orderTracking = 'order-tracking';
  static const addressList = 'address-list';
  static const addressSelect = 'address-select';
  static const addAddress = 'add-address';
  static const customerWallet = 'customer-wallet';

  // Vendor feature routes
  static const vendorOrders = 'vendor-orders';
  static const vendorProducts = 'vendor-products';
  static const vendorAddProduct = 'vendor-add-product';
  static const vendorEditProduct = 'vendor-edit-product';
  static const vendorRiders = 'vendor-riders';
  static const vendorAccount = 'vendor-account';
  static const vendorLiveMap = 'vendor-live-map';
  static const vendorCreateCustomer = 'vendor-create-customer';
  static const vendorCustomers = 'vendor-customers';

  // Rider feature routes
  static const riderActiveDeliveries = 'rider-active-deliveries';
  static const riderHistory = 'rider-history';
  static const riderAccount = 'rider-account';
  static const riderWallet = 'rider-wallet';
  static const riderSettlementHistory = 'rider-settlement-history';
  static const riderOrderDetail = 'rider-order-detail';
  static const riderRefund = 'rider-refund';
  static const paymentCollection = 'payment-collection';
  static const receiptViewer = 'receipt-viewer';

  // Settlement routes
  static const vendorReceiveCod = 'vendor-receive-cod';
  static const vendorSettlements = 'vendor-settlements';
  static const vendorRiderFinances = 'vendor-rider-finances';

  // Vendor finance routes
  static const vendorFinanceDashboard = 'vendor-finance-dashboard';
  static const vendorCustomerFinances = 'vendor-customer-finances';
  static const vendorPaymentApprovals = 'vendor-payment-approvals';
}

class RoutePaths {
  RoutePaths._();

  static const splash = '/splash';
  static const onboarding = '/onboarding';

  static const login = '/login';
  static const pinLogin = '/login/pin';
  static const emailSignIn = '/login/email';
  static const emailSignUp = '/login/email/sign-up';
  static const forgotPassword = '/login/email/forgot-password';
  static const resetPassword = '/login/reset-password';
  static const completeProfile = '/complete-profile';
  static const pendingApproval = '/pending-approval';
  static const roleSelection = '/role-selection';

  static const customerHome = '/customer';
  static const vendorHome = '/vendor';
  static const riderHome = '/rider';
  static const adminHome = '/admin';

  // Customer — nested under /customer so back navigation returns to the shell
  static const productDetail = '/customer/product/:productId';
  static const cart = '/customer/cart';
  static const checkout = '/customer/checkout';
  static const orderHistory = '/customer/orders';
  static const orderTracking = '/customer/orders/:orderId';
  static const addressList = '/customer/addresses';
  static const addressSelect = '/customer/addresses/select';
  static const addAddress = '/customer/addresses/add';
  static const customerWallet = '/customer/wallet';

  // Vendor
  static const vendorOrders = '/vendor/orders';
  static const vendorProducts = '/vendor/products';
  static const vendorAddProduct = '/vendor/products/add';
  static const vendorEditProduct = '/vendor/products/edit/:productId';
  static const vendorRiders = '/vendor/riders';
  static const vendorAccount = '/vendor/account';
  static const vendorLiveMap = '/vendor/live-map';
  static const vendorCreateCustomer = '/vendor/create-customer';
  static const vendorCustomers = '/vendor/customers';

  // Rider
  static const riderActiveDeliveries = '/rider/deliveries';
  static const riderHistory = '/rider/history';
  static const riderAccount = '/rider/account';
  static const riderWallet = '/rider/wallet';
  static const riderSettlementHistory = '/rider/wallet/history';
  static const riderOrderDetail = '/rider/history/:orderId';
  static const riderRefund = '/rider/refund';
  static const paymentCollection = '/rider/deliveries/payment';
  static const receiptViewer = '/rider/receipt';

  // Settlements
  static const vendorReceiveCod = '/vendor/receive-cod';
  static const vendorSettlements = '/vendor/settlements';
  static const vendorRiderFinances = '/vendor/rider-finances';

  // Vendor finance
  static const vendorFinanceDashboard = '/vendor/finances';
  static const vendorCustomerFinances = '/vendor/finances/customer/:customerId';
  static const vendorPaymentApprovals = '/vendor/finances/approvals';

  static String productDetailOf(String productId) => '/customer/product/$productId';
  static String orderTrackingOf(String orderId) => '/customer/orders/$orderId';
  static String vendorEditProductOf(String productId) => '/vendor/products/edit/$productId';
  static String vendorCustomerFinancesOf(String customerId) => '/vendor/finances/customer/$customerId';
  static String riderOrderDetailOf(String orderId) => '/rider/history/$orderId';
}
