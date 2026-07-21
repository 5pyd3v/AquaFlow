import 'package:supabase_flutter/supabase_flutter.dart';
import 'env_config.dart';

/// Wraps Supabase initialisation so `main.dart` stays declarative.
class SupabaseConfig {
  SupabaseConfig._();

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      anonKey: EnvConfig.supabaseAnonKey,
      debug: EnvConfig.isDevelopment,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        eventsPerSecond: 10,
      ),
    );
  }

  /// Table name constants — keeps repositories typo-proof and gives us
  /// a single place to update if the schema is ever renamed.
  static const String profiles = 'profiles';
  static const String vendors = 'vendors';
  static const String riders = 'riders';
  static const String customers = 'customers';
  static const String products = 'products';
  static const String categories = 'categories';
  static const String inventory = 'inventory';
  static const String orders = 'orders';
  static const String orderItems = 'order_items';
  static const String addresses = 'addresses';
  static const String transactions = 'transactions';
  static const String ratings = 'ratings';
  static const String coupons = 'coupons';
  static const String settings = 'settings';
  static const String auditLogs = 'audit_logs';
  static const String trackingLogs = 'tracking_logs';
  static const String realtimeLocations = 'realtime_locations';
  static const String wallets = 'wallets';
  static const String walletTransactions = 'wallet_transactions';
  static const String favorites = 'favorites';
  static const String codSettlements = 'cod_settlements';

  // Storage buckets
  static const String bucketAvatars = 'avatars';
  static const String bucketProducts = 'products';
  static const String bucketProofs = 'delivery-proofs';
  static const String bucketDocuments = 'vendor-documents';
}
