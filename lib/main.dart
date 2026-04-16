import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/razorpay_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'app.dart';

/// Default entry point.
/// Run with: flutter run --dart-define-from-file=.env --flavor dev
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Environment variables are now injected at build time via
  // --dart-define-from-file=.env (never bundled in the APK).

  // 1. Initialize Hive — registers adapters and opens all 10 boxes.
  //    Must complete before runApp() so Riverpod providers can read boxes.
  await HiveService.instance.init();

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
