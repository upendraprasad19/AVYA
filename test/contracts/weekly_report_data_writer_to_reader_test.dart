import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `weekly_report_data`
/// from docs/sot_registry.yaml.
///
/// Writers: WorkoutWriteService.logExercise (workout series),
///          NutritionWriteService.logMeal (calorie+protein series)
/// Reader: weeklyReportDataProvider in weekly_report_data_provider.dart
///
/// Consumed only by WeeklyReportCard. Weight series is forward-filled;
/// calories/protein/workouts are zero-filled.
void main() {
  late String weeklyProvSrc;
  late String wws;
  late String nws;

  setUpAll(() {
    final wf = File(
        'lib/features/profile/providers/weekly_report_data_provider.dart');
    expect(wf.existsSync(), isTrue,
        reason:
            'weekly_report_data_provider.dart must exist (reader for weekly_report_data)');
    weeklyProvSrc = wf.readAsStringSync();

    final wws_f = File('lib/core/services/workout_write_service.dart');
    expect(wws_f.existsSync(), isTrue,
        reason: 'workout_write_service.dart must exist (writer for workout series)');
    wws = wws_f.readAsStringSync();

    final nws_f = File('lib/core/services/nutrition_write_service.dart');
    expect(nws_f.existsSync(), isTrue,
        reason: 'nutrition_write_service.dart must exist (writer for calorie+protein series)');
    nws = nws_f.readAsStringSync();
  });

  group('weekly_report_data writer↔reader source contract', () {
    test('reader weeklyReportDataProvider defined', () {
      expect(weeklyProvSrc.contains('weeklyReportDataProvider'), isTrue,
          reason:
              'weekly_report_data_provider.dart must define weeklyReportDataProvider');
    });

    test('reader WeeklyReportDataNotifier exists', () {
      expect(
          weeklyProvSrc.contains('WeeklyReportDataNotifier') ||
              weeklyProvSrc.contains('WeeklyReportSeries'),
          isTrue,
          reason:
              'weekly_report_data_provider must define the notifier or series class');
    });

    test('reader reads from healthBox for weight series', () {
      expect(weeklyProvSrc.contains('healthBox') || weeklyProvSrc.contains('weight_'),
          isTrue,
          reason:
              'weeklyReportDataProvider must read weight series from healthBox (weight_ key prefix)');
    });

    test('reader reads from nutritionBox for calorie+protein series', () {
      expect(
          weeklyProvSrc.contains('nutritionBox') ||
              weeklyProvSrc.contains('nlog_') ||
              weeklyProvSrc.contains('total_calories'),
          isTrue,
          reason:
              'weeklyReportDataProvider must read calorie+protein series from nutritionBox');
    });

    test('reader reads from workoutBox for workout 0/1 series', () {
      expect(
          weeklyProvSrc.contains('workoutBox') ||
              weeklyProvSrc.contains('schedule_') ||
              weeklyProvSrc.contains('exlog_'),
          isTrue,
          reason:
              'weeklyReportDataProvider must read workout series from workoutBox');
    });

    test('writer WorkoutWriteService.logExercise stamps exlog_ key prefix', () {
      expect(wws.contains("'exlog_") || wws.contains('"exlog_'), isTrue,
          reason: 'WorkoutWriteService must write exlog_ keys consumed by weekly series');
    });

    test('writer NutritionWriteService.logMeal stamps nlog_ key prefix', () {
      expect(nws.contains("'nlog_") || nws.contains('"nlog_'), isTrue,
          reason:
              'NutritionWriteService must write nlog_ keys consumed by weekly calorie series');
    });

    test('WeeklyReportCard consumes weeklyReportDataProvider', () {
      final cardFile =
          File('lib/features/profile/widgets/weekly_report_card.dart');
      if (!cardFile.existsSync()) return; // optional check
      final src = cardFile.readAsStringSync();
      expect(src.contains('weeklyReportDataProvider'), isTrue,
          reason: 'WeeklyReportCard must read from weeklyReportDataProvider (single consumer)');
    });
  });
}
