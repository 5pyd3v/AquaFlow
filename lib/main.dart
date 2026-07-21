import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/config/env_config.dart';
import 'core/config/supabase_config.dart';
import 'core/routes/app_router.dart';
import 'core/services/logger_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/storage_service.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load `.env` before anything else touches EnvConfig.
  await dotenv.load(fileName: '.env');
  EnvConfig.validate();

  await StorageService.instance.init();
  await SupabaseConfig.initialize();

  // Firebase Cloud Messaging is mobile-only in this build. Web push
  // needs its own setup (a `firebase-messaging-sw.js` service worker,
  // a VAPID key, and browser notification-permission UX) that's a
  // deliberately separate piece of work — attempting FCM init on web
  // without it throws in the browser console on every hot reload, so
  // we skip it outright on web rather than half-support it.
  if (!kIsWeb) {
    try {
      if (EnvConfig.firebaseApiKey.isNotEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: EnvConfig.firebaseApiKey,
            appId: EnvConfig.firebaseAppId,
            messagingSenderId: EnvConfig.firebaseSenderId,
            projectId: EnvConfig.firebaseProjectId,
            storageBucket: EnvConfig.firebaseStorageBucket,
          ),
        );
        await NotificationService.instance.initialize();
      } else {
        AppLogger.warning('Firebase keys not set in .env — push notifications disabled.');
      }
    } catch (e, st) {
      AppLogger.error('Firebase initialization failed', e, st);
    }
  }

  runApp(const ProviderScope(child: AquaFlowApp()));
}

class AquaFlowApp extends ConsumerWidget {
  const AquaFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
