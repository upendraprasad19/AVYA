import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/razorpay_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'app.dart';

/// PROD entry point — production Supabase + Razorpay live key + clean logo.
/// Run with: flutter run --dart-define-from-file=.env.prod --flavor prod -t lib/main_prod.dart
/// Build with: flutter build apk --dart-define-from-file=.env.prod --flavor prod -t lib/main_prod.dart
///
/// Heavy services (SeedService, Supabase, OneSignal) are deferred to
/// SplashScreen so the UI appears instantly — same pattern as main.dart.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Hive — registers adapters and opens all 10 boxes.
  //    Must complete before runApp() so Riverpod providers can read boxes.
  await HiveService.instance.init();

  // 2. Reset stale usage counters (daily/monthly) based on date.
  //    Fast local-only operation; safe to do before runApp().
  await UsageCounterService.instance.checkAndResetCounters();

  // 3. Initialize Razorpay checkout handler (no-op on web).
  RazorpayService.instance.initialize();

  // SeedService, Supabase, and OneSignal are deferred to SplashScreen
  // so the UI appears immediately instead of after a 30-50s black screen.

  runApp(
    const ProviderScope(
      child: ICanBeFitterApp(),
    ),
  );
}
