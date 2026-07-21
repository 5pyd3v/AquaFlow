/// Centralised environment configuration.
///
/// Values are loaded from `.env` at startup via `flutter_dotenv`.
/// Never hardcode secrets — this class only reads what dotenv exposes.
library;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  EnvConfig._();

  static String get supabaseUrl => dotenv.get('SUPABASE_URL', fallback: '');
  static String get supabaseAnonKey =>
      dotenv.get('SUPABASE_ANON_KEY', fallback: '');

  static String get googleMapsApiKeyAndroid =>
      dotenv.get('GOOGLE_MAPS_API_KEY_ANDROID', fallback: '');

  static String get firebaseApiKey => dotenv.get('FIREBASE_API_KEY', fallback: '');
  static String get firebaseAppId => dotenv.get('FIREBASE_APP_ID', fallback: '');
  static String get firebaseSenderId =>
      dotenv.get('FIREBASE_SENDER_ID', fallback: '');
  static String get firebaseProjectId =>
      dotenv.get('FIREBASE_PROJECT_ID', fallback: '');
  static String get firebaseStorageBucket =>
      dotenv.get('FIREBASE_STORAGE_BUCKET', fallback: '');

  static String get stripePublishableKey =>
      dotenv.get('STRIPE_PUBLISHABLE_KEY', fallback: '');

  static String get razorpayKey => dotenv.get('RAZORPAY_KEY', fallback: '');

  static String get easypaisaMerchantId =>
      dotenv.get('EASYPAISA_MERCHANT_ID', fallback: '');

  static String get jazzcashMerchantId =>
      dotenv.get('JAZZCASH_MERCHANT_ID', fallback: '');

  static String get environment =>
      dotenv.get('APP_ENV', fallback: 'development');

  static bool get isProduction => environment == 'production';
  static bool get isDevelopment => environment == 'development';

  /// Validates that all mandatory keys are present. Called once at
  /// startup in `main.dart` — fails fast instead of crashing deep
  /// inside a repository call later.
  static void validate() {
    final missing = <String>[];
    if (supabaseUrl.isEmpty) missing.add('SUPABASE_URL');
    if (supabaseAnonKey.isEmpty) missing.add('SUPABASE_ANON_KEY');

    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required .env keys: ${missing.join(', ')}. '
        'Copy .env.example to .env and fill in the values.',
      );
    }
  }
}
