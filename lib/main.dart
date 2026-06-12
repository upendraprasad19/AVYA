import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/razorpay_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  // Crashlytics has no web binding — a null-check inside the plugin crashed
  // boot on web (Obs#2, 2026-06-13: "[main] Firebase/Crashlytics init failed:
  // Null check operator used on a null value"). Guard the whole init by
  // platform; the Android/iOS path (init + FlutterError/PlatformDispatcher
  // fatal routing) is unchanged.
  if (!kIsWeb) {
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
  }

  // 1. Initialize Hive — registers adapters and opens all 10 boxes.
  //    Must complete before runApp() so Riverpod providers can read boxes.
  await HiveService.instance.init();

  // coach_memory backfill RELOCATED to restoring_screen (Obs#3, dc52a4 class):
  // it touches the user-scoped coachBox/userBox and MUST run AFTER
  // HiveUserSession.openForUser — here at boot it raced the session open and
  // threw "HiveUserSession not opened — cannot wrap user-scoped box coachBox"
  // every launch (silent fail). Now in restoring_screen._ensureOwnershipBeforeHome
  // + _healAfterRestoreInBackground, after openForUser.

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

  await runZonedGuarded(
    () async {
      runApp(
        const ProviderScope(
          child: ICanBeFitterApp(),
        ),
      );
    },
    (error, stack) async {
      if (error is HiveOwnershipException) {
        debugPrint('[main] HiveOwnershipException caught: $error');
        try {
          await Hive.box(HiveService.configBoxName).put(
            'session_expired_flag',
            DateTime.now().toIso8601String(),
          );
        } catch (e) {
          debugPrint('[main] write session_expired_flag failed: $e');
        }
        try {
          await UserRepository.instance.clearAllData();
        } catch (e) {
          debugPrint('[main] clearAllData on ownership-exception failed: $e');
        }
        try {
          await HiveUserSession.deleteAllFilesForCurrentUser();
        } catch (e) {
          debugPrint(
            '[main] deleteAllFilesForCurrentUser on ownership-exception failed: $e',
          );
        }
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (e) {
          debugPrint('[main] signOut on ownership-exception failed: $e');
        }
        // Router auth listener will redirect to /sign-in on signOut.
        // No need to push a route manually.
        return;
      }
      // Re-raise non-ownership errors.
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}
