import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 0. Load environment variables (.env bundled as Flutter asset).
  await dotenv.load(fileName: '.env');

  // 1. Initialize Hive — registers adapters and opens all 10 boxes.
  await HiveService.instance.init();

  // 2. Seed bundled JSON data on first launch.
  await SeedService.instance.seedIfNeeded();

  // 3. Reset stale usage counters (daily/monthly) based on date.
  await UsageCounterService.instance.checkAndResetCounters();

  // 4. Initialize Supabase.
  await SupabaseService.instance.initialize();

  // 5. Initialize OneSignal push notifications (mobile only).
  if (!kIsWeb) {
    OneSignal.initialize(AppConstants.oneSignalAppId);
    await OneSignal.Notifications.requestPermission(true);
  }

  runApp(
    const ProviderScope(
      child: ICanBeFitterApp(),
    ),
  );
}
