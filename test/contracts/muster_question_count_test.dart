import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/screens/muster_screen.dart';

import '../helpers/hive_test_setup.dart';

/// Pin the post-Phase-2 question count for `MusterScreen`. After dropping
/// Q1 (`why_now`) and Q2 (`definition_of_winning`) per founder direction
/// (APK Test #15.4 / B2a), exactly 3 questions remain: injuries → wake
/// time → physique focus. The progress bar shows 3 dots, and the first
/// question prompt is now the injuries question.
///
/// Without this lock-down, a future "let's add a question back" change
/// would silently drift the UX.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await HiveService.instance.coachBox.clear();
    await tearDownHiveForTests(tempDir);
  });

  // Swallow late-arriving google_fonts network-failure exceptions. They
  // are unavoidable in unit tests (no real network) and unrelated to the
  // assertions in this file (widget structure, text content). Without
  // this, the exception arrives during test teardown and fails the test
  // even though all assertions passed.
  Future<void> runWithFontFallback(Future<void> Function() body) async {
    final completer = Completer<void>();
    final result = runZonedGuarded(
      () async {
        try {
          await body();
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
      },
      (error, stack) {
        if (!error.toString().contains('Failed to load font')) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        }
      },
    );
    // `runZonedGuarded` returns the inner Future; await its completion
    // only via the completer above (which fires on body exit, not on
    // background errors).
    unawaited(result ?? Future<void>.value());
    await completer.future;
  }

  testWidgets('MusterScreen renders exactly 3 progress dots', (tester) async {
    await runWithFontFallback(() async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: MusterScreen()),
        ),
      );
      // Wait for the typing indicator to finish (1100ms).
      await tester.pump(const Duration(milliseconds: 1200));
    });

    // Drain any latent google_fonts exception so it doesn't fail teardown.
    tester.takeException();

    // The progress bar is the first Row in the tree. It should have exactly
    // 3 Expanded children, one per question dot.
    final expandedInProgress = find.descendant(
      of: find.byType(Row).first,
      matching: find.byType(Expanded),
    );
    expect(expandedInProgress, findsNWidgets(3),
        reason:
            'Progress bar must show exactly 3 dots, one per remaining muster question.');
  });

  testWidgets('First question prompt is the injuries question', (tester) async {
    await runWithFontFallback(() async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: MusterScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1200));
    });

    tester.takeException();

    expect(find.textContaining('injuries or niggles'), findsOneWidget,
        reason:
            'After dropping Q1+Q2, the first question must be injuries.');
    expect(find.textContaining('Why now'), findsNothing,
        reason: 'why_now question must be removed.');
    expect(find.textContaining('winning look'), findsNothing,
        reason: 'definition_of_winning question must be removed.');
  });
}
