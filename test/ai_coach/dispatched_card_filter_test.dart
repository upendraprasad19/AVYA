// test/ai_coach/dispatched_card_filter_test.dart
//
// B-5: pin AiCoachScreen.filterVisibleIntents — the pure / static helper
// extracted in B-4 — so the chat thread shows live cards but hides
// already-dispatched and dismissed ones.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/screens/ai_coach/screen.dart';

import '../helpers/hive_test_setup.dart';

ToolIntent _make(String id, ToolIntentStatus status) => ToolIntent(
      id: id,
      type: 'log_set',
      payload: const {},
      confirmationClass: ConfirmationClass.reviewable,
      previewSummary: 'Log',
      createdAt: DateTime.now(),
      status: status,
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  test('chat thread filters cards with dispatched_at set', () async {
    await HiveService.instance.coachBox.put(
      'intent_dispatched_dispatched_at',
      DateTime.now().toIso8601String(),
    );

    final dispatched = _make('dispatched', ToolIntentStatus.pending);
    final live = _make('live', ToolIntentStatus.pending);

    final visible =
        AiCoachScreen.filterVisibleIntents([dispatched, live]);

    expect(visible.length, 1);
    expect(visible.first.id, 'live');
  });

  test('chat thread filters cards with dismissed_at set', () async {
    await HiveService.instance.coachBox.put(
      'intent_x_dismissed_at',
      DateTime.now().toIso8601String(),
    );

    final dismissed = _make('x', ToolIntentStatus.pending);
    final live = _make('y', ToolIntentStatus.pending);

    final visible = AiCoachScreen.filterVisibleIntents([dismissed, live]);

    expect(visible.length, 1);
    expect(visible.first.id, 'y');
  });

  test('settled (executed/rejected/expired) intents stay visible '
      'as terminal pills', () async {
    final intents = [
      _make('a', ToolIntentStatus.executed),
      _make('b', ToolIntentStatus.rejected),
      _make('c', ToolIntentStatus.expired),
    ];
    final visible = AiCoachScreen.filterVisibleIntents(intents);
    expect(visible.length, 3);
  });

  // audit-fixwave B-pass fix — the executed pill's staleness keys on the SETTLE
  // marker (intent_<id>_dispatched_at), NOT createdAt. Both intents below were
  // CREATED 10 min ago; only the one whose SETTLE marker is old is dropped —
  // proving a slow-to-confirm user (old createdAt, fresh settle) keeps their ✓.
  ToolIntent _executed(String id) => ToolIntent(
        id: id,
        type: 'log_set',
        payload: const {},
        confirmationClass: ConfirmationClass.reviewable,
        previewSummary: 'Log',
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
        status: ToolIntentStatus.executed,
      );

  test('executed pill drops when its SETTLE marker is >2min old (not createdAt)',
      () async {
    await HiveService.instance.coachBox.put('intent_stale_dispatched_at',
        DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String());
    await HiveService.instance.coachBox.put('intent_fresh_dispatched_at',
        DateTime.now().toIso8601String());

    final visible = AiCoachScreen
        .filterVisibleIntents([_executed('stale'), _executed('fresh')]);
    expect(visible.map((i) => i.id).toList(), ['fresh'],
        reason: 'stale SETTLE → dropped; fresh SETTLE → visible, even though '
            'BOTH were created 10 min ago (staleness keys on settle time, not '
            'the AI-reply time — a slow confirm must still show its ✓ Logged)');
  });

  test('executed pill with NO settle marker is kept (never hide a real success)',
      () async {
    // createdAt 10 min ago, but no dispatched_at marker → keep the ✓.
    final visible = AiCoachScreen.filterVisibleIntents([_executed('nomarker')]);
    expect(visible.map((i) => i.id).toList(), ['nomarker']);
  });
}
