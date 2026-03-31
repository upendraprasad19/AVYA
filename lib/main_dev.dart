import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/constants/app_environment.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/razorpay_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'app.dart';

/// DEV entry point — local Supabase + Razorpay test key + QA badge.
/// Run with: flutter run --flavor dev -t lib/main_dev.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mark as dev flavor — shows QA badge on logo.
  kIsDevFlavor = true;

  // Load dev environment (local Supabase + Razorpay test key).
  await dotenv.load(fileName: '.env.dev');

  await HiveService.instance.init();
  await SeedService.instance.seedIfNeeded();
  await UsageCounterService.instance.checkAndResetCounters();
  await SupabaseService.instance.initialize();
  RazorpayService.instance.initialize();

  runApp(
    const ProviderScope(
      child: ICanBeFitterApp(),
    ),
  );
}
