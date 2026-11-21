import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/seed_service.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';

/// Initialises Hive and seeds data for integration tests.
/// Must be called before the app is pumped in each test.
Future<void> initHiveForTest() async {
  await HiveService.instance.init();
  await SeedService.instance.seedIfNeeded();
  await UsageCounterService.instance.checkAndResetCounters();
}

/// Clears all Hive boxes between tests (call in tearDown).
Future<void> clearHiveForTest() async {
  final boxes = [
    HiveService.instance.userBox,
    HiveService.instance.workoutBox,
    HiveService.instance.nutritionBox,
    HiveService.instance.healthBox,
    HiveService.instance.coachBox,
    HiveService.instance.configBox,
  ];
  for (final box in boxes) {
    await box.clear();
  }
}
