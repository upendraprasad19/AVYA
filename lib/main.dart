import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/razorpay_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'features/ai_coach/repositories/ai_coach_repository.dart';
import 'app.dart';

/// Default entry point.
/// Run with: flutter run --dart-define-from-file=.env --flavor dev
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Environment variables are now injected at build time via
  // --dart-define-from-file=.env (never bundled in the APK).

  // 0. Firebase + Crashlytics — initialized FIRST so any subsequent
  //    crash during startup is captured. Guarded so unit tests and
  //    local dev without google-services.json don't blow up.
  try {
    await Firebase.initializeApp();
    // Route uncaught framework errors → Crashlytics fatal.
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    // Route uncaught async platform errors → Crashlytics fatal.
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    // Disable collection in debug to avoid spamming dashboard during dev.
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
  } catch (e) {
    debugPrint('[main] Firebase/Crashlytics init failed: $e');
  }

  // 1. Initialize Hive — registers adapters and opens all 10 boxes.
  //    Must complete before runApp() so Riverpod providers can read boxes.
  await HiveService.instance.init();

  // One-time backfill of coach_memory from legacy coaching_notes.
  // Safe to call on every launch — idempotent.
  await AiCoachRepository.instance.backfillCoachMemoryIfNeeded();

  // 1a. Atomic-logout recovery (F16). If a previous session was killed
  //     mid-logout, finish the wipe before anything else reads Hive.
  try {
    final flag =
        HiveService.instance.configBox.get('logout_in_progress') as bool?;
    if (flag == true) {
      debugPrint('[main] detected interrupted logout — completing clearAllData');
      await UserRepository.instance.clearAllData();
      // clearAllData also wipes configBox, so the flag is gone implicitly.
    }
  } catch (e) {
    debugPrint('[main] atomic-logout recovery failed: $e');
  }

  // 2. Reset stale usage counters (daily/monthly) based on date.
  //    Fast local-only operation; safe to do before runApp().
  await UsageCounterService.instance.checkAndResetCounters();

  // 3. Initialize Razorpay checkout handler (no-op on web).
  RazorpayService.instance.initialize();

  // 4. Register SyncQueue op executors. No-op unless
  //    sync_reliability_v1 feature flag is on. Must run AFTER Hive init
  //    (queue persists to syncBox). Queue drain is deferred to the
  //    splash screen, which waits for Supabase auth before firing.
  SyncService.instance.initQueue();

  // Supabase, SeedService, and OneSignal are deferred to SplashScreen
  // so the UI appears immediately instead of after a 30-50s black screen.

  runApp(
    const ProviderScope(
      child: ICanBeFitterApp(),
    ),
  );
}
