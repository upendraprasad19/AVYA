import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'app.dart';

/// PROD entry point — production Supabase + Razorpay live key + clean logo.
/// Run with: flutter run --flavor prod -t lib/main_prod.dart
/// Build with: flutter build apk --flavor prod -t lib/main_prod.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load prod environment (production Supabase + Razorpay live key).
  await dotenv.load(fileName: '.env.prod');

  await HiveService.instance.init();
  await SeedService.instance.seedIfNeeded();
  await UsageCounterService.instance.checkAndResetCounters();
  await SupabaseService.instance.initialize();

  runApp(
    const ProviderScope(
      child: ICanBeFitterApp(),
    ),
  );
}
