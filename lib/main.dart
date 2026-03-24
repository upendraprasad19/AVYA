import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Hive — registers adapters and opens all 10 boxes.
  await HiveService.instance.init();

  // 2. Seed bundled JSON data on first launch.
  await SeedService.instance.seedIfNeeded();

  // 3. Reset stale usage counters (daily/monthly) based on date.
  await UsageCounterService.instance.checkAndResetCounters();

  // 4. Initialize Supabase.
  await SupabaseService.instance.initialize();

  runApp(
    const ProviderScope(
      child: ICanBeFitterApp(),
    ),
  );
}
