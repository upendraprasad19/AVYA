// test/widgets/diet_plan_screen_no_modal_test.dart
//
// Widget test for DietPlanScreen ensuring the saved-plan-found modal is not shown.
// Obs 8: when a saved diet plan exists, it should be rendered immediately without
// a blocking dialog. The AppBar's Regenerate and Save icons already provide
// user actions.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/nutrition/screens/diet_plan_screen.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('diet_plan_screen_no_modal_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.closeAll();
  });

  testWidgets('renders saved plan immediately with no dialog',
      (WidgetTester tester) async {
    const testUserId = 'eeee5555-eeee-eeee-eeee-eeeeeeeeeeee';
    await HiveUserSession.openForUser(testUserId);

    // Seed Hive with a saved diet plan via UserRepository
    final savedPlan = <String, dynamic>{
      'id': 'diet_plan_1234567890',
      'created_at': DateTime(2026, 9, 20).toIso8601String(),
      'meals': [
        {
          'name': 'Breakfast',
          'items': [
            {
              'food_id': 'oats_001',
              'name': 'Oats',
              'serving_desc': '50g',
              'serving_g': 50.0,
              'calories': 180,
              'protein': 6,
              'carbs': 27,
              'fat': 5,
              'category': 'grains'
            }
          ],
          'targetCalories': 400,
          'targetProtein': 15,
        },
        {
          'name': 'Lunch',
          'items': [
            {
              'food_id': 'rice_001',
              'name': 'Brown rice',
              'serving_desc': '150g',
              'serving_g': 150.0,
              'calories': 400,
              'protein': 8,
              'carbs': 85,
              'fat': 3,
              'category': 'grains'
            }
          ],
          'targetCalories': 600,
          'targetProtein': 20,
        }
      ],
    };
    await UserRepository.instance.saveDietPlan(savedPlan);

    // Render the DietPlanScreen
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: DietPlanScreen())),
    );
    await tester.pumpAndSettle();

    // Verify no AlertDialog is shown (obs 8 — the modal must not appear)
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'obs 8 — the saved-plan-found dialog must not appear');
    expect(find.text('Saved Diet Plan Found'), findsNothing,
        reason: 'the modal title must not be visible');

    // Verify the toolbar icons are present (these already give users
    // the actions the old dialog offered)
    expect(find.byIcon(Icons.refresh), findsOneWidget,
        reason: 'toolbar Regenerate icon must be present');
    expect(find.byIcon(Icons.save_outlined), findsOneWidget,
        reason: 'toolbar Save icon must be present');
  });
}
