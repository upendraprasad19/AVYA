// Unit 3C (OI-396, d77; B-pass seat B F1): `modifyWorkoutForInjury` is a DESTRUCTIVE intent, so the user confirms it on
// `ToolConfirmSheet` (chat_area.dart sends every destructive intent there), not on `ToolConfirmCard`. After a confirm
// that saved the injury to the profile, the sheet announces it: `Workouts updated · Knee added to your injuries`. A
// success with nothing added says nothing (as before); a failure keeps its error text.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/providers/pending_tool_intents_provider.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/ai_coach/widgets/tool_confirm_sheet.dart';

final _intent = ToolIntent(
  id: 'sheet_injury',
  type: 'modify_workout_for_injury',
  payload: const {'bodyPart': 'quad', 'severity': 'mild'},
  confirmationClass: ConfirmationClass.destructive,
  previewSummary: 'Swap knee-loaded exercises',
  createdAt: DateTime(2026, 11, 16),
);

/// Returns [result] from `confirm` without touching the dispatcher.
class _FakeIntents extends PendingToolIntentsNotifier {
  _FakeIntents(this.result);
  final ToolExecutionResult result;

  @override
  List<ToolIntent> build() => [_intent];

  @override
  Future<ToolExecutionResult> confirm(String intentId) async => result;
}

Future<void> _confirmWith(WidgetTester tester, ToolExecutionResult result) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [pendingToolIntentsProvider.overrideWith(() => _FakeIntents(result))],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ToolConfirmSheet.show(context, intent: _intent, diffPreview: const SizedBox()),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a saved injury is announced after the sheet closes', (tester) async {
    await _confirmWith(
        tester, const ToolExecutionResult.success(data: {'swaps': <Object>[], 'profile_injury_added': 'knee'}));
    expect(find.byType(ToolConfirmSheet), findsNothing);
    expect(find.text('Workouts updated · Knee added to your injuries'), findsOneWidget);
  });

  testWidgets('a success that added nothing says nothing (unchanged)', (tester) async {
    await _confirmWith(tester, const ToolExecutionResult.success(data: {'swaps': <Object>[]}));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failure keeps its error text', (tester) async {
    await _confirmWith(tester,
        const ToolExecutionResult.failure("Couldn't change your workouts. Knee was added to your injuries.",
            data: {'profile_injury_added': 'knee'}));
    expect(find.text("Couldn't change your workouts. Knee was added to your injuries."), findsOneWidget);
  });
}
