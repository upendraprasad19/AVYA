// OI-493 Landing B (B6, plan docs/plans/oi493b-duplicate-meals.md R6): a coach
// tag card (LogConfirmCard) that is unmounted while its save runs still marks
// its action logged and clears it, so a card rebuilt for the same action
// (chat scrolled, list rebuilt) never starts a second save of the same meal.
//
// Writer: lib/features/ai_coach/widgets/log_confirm_card.dart _execute
//   (captures the pendingLogActionsProvider notifier before the await).
// Reader: pendingLogActionsProvider (the chat renders a card per action;
//   _onAutoConfirm reads action.isLogged), the nlog_ rows.
//
// Fonts render first (before Hive mocks path_provider); Hive opens lazily in
// runAsync and closes in tearDownAll.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/services/coach_meal_log.dart';
import 'package:icanbefitter/features/ai_coach/widgets/log_confirm_card.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';

import '../helpers/hive_test_setup.dart';

Directory? _dir;

List<String> _nlogKeys() => HiveService.instance.nutritionBox.keys
    .map((k) => k.toString())
    .where((k) => k.startsWith('nlog_'))
    .toList();

class _Seeded extends PendingLogActionsNotifier {
  _Seeded(this.seed);
  final PendingLogAction seed;
  @override
  List<PendingLogAction> build() => [seed];
}

void main() {
  tearDownAll(() async {
    CoachMealLog.debugBadgeCheck = null;
    ErrorTelemetry.debugOnLogEventForTests = null;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    SyncService.pausedForSimulation = false;
    if (_dir != null) await tearDownHiveForTests(_dir!);
  });

  testWidgets('fonts degrade before any Hive mock', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        Text('a', style: AppTypography.h3),
        Text('b', style: AppTypography.mono),
        Text('c', style: AppTypography.monoXs),
        Text('d', style: AppTypography.bodySm),
        Text('e', style: AppTypography.body),
        Text('f', style: AppTypography.label),
      ]),
    ));
  });

  testWidgets('a card unmounted while its save runs still marks the action '
      'logged and clears it; one row', (tester) async {
    _dir ??= await tester.runAsync(setUpHiveForTests);
    SyncService.pausedForSimulation = true;
    CoachMealLog.debugBadgeCheck = () {};
    ErrorTelemetry.debugOnLogEventForTests = (op, {String? message}) {};
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required String reason, Map<String, String>? extra}) {};

    final action = PendingLogAction(
      id: 'tag-card-1',
      type: LogActionType.food,
      data: const {
        'food_name': 'Upma',
        'calories_estimate': 250,
        'protein_estimate': 6,
        'meal_type': 'breakfast',
      },
      displayText: 'Upma — Breakfast',
      createdAt: DateTime.utc(2026, 11, 12, 3),
    );
    final c = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWithValue('u'),
      pendingLogActionsProvider.overrideWith(() => _Seeded(action)),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(body: LogConfirmCard(action: action)),
      ),
    ));
    expect(find.text('CONFIRM'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('CONFIRM'));
      // Unmount while the save awaits Hive.
      await tester.pumpWidget(const SizedBox());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(_nlogKeys(), hasLength(1));
    expect(action.isLogged, isTrue,
        reason: 'a card rebuilt for this action must see it logged and not '
            'start its countdown save again');
    expect(c.read(pendingLogActionsProvider), isEmpty,
        reason: 'the logged action is cleared even though its card was gone');
  });
}
