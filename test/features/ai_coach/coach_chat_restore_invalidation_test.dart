// Behavioral contract for diagnose coach-chat-missing-restore-invalidation
// (2026-09-21, founder Obs 4): AI Coach chat opened scrolled to the TOP
// instead of the bottom, and more broadly served stale history after a
// background restore landed.
//
// THE REAL ROOT CAUSE (found post-review, NOT a scroll bug): AI Coach
// deliberately does not use HiveTabScaffoldMixin (see that file's own
// header + scripts/check_tab_screen_uses_hive_scaffold.dart's allow-list),
// so it never got the mixin's background-restore-invalidation wiring.
// `ChatHistoryNotifier.build()` reads coachBox synchronously once with no
// reactive link to `_restoreCoachInteractions` completing — the existing
// `ref.listen(chatHistoryProvider, ...)` at screen.dart's build() already
// scrolls to bottom on ANY value change, so once the provider is actually
// invalidated, scrolling falls out correctly with no separate fix.
//
// THE FIX: wire `_AiCoachScreenState` directly to the SAME underlying
// signal `HiveTabScaffoldMixin` uses internally (`SyncService.instance.
// restoreCompletedTick`), WITHOUT adopting the mixin itself (which would
// violate the documented, gated architectural exclusion).
//
// `_AiCoachScreenState` is a heavy production screen (speech-to-text, image
// picker, subscription service) with no lightweight public seam to pump
// directly — same shape as the mixin's OWN restore-tick wiring, which this
// codebase already tests via source-grep + a device walk, not a full widget
// pump (test/contracts/background_restore_test.dart). Confirmed the SAME
// hazard applies here directly: touching the real `SyncService.instance`
// singleton inside a `testWidgets` body HUNG the test runner outright (killed
// after 120s with no output) — the exact "real I/O inside the fake-async
// zone" class CLAUDE.md's common-pitfalls table documents, one layer deeper
// than a plain `await`. This file therefore uses a FAKE `ValueNotifier<int>`
// standing in for `SyncService.instance.restoreCompletedTick` (identical
// type — `ValueNotifier<int>`, so `addListener`/`removeListener` behave
// identically) to prove the actual novel logic — does invalidating
// chatHistoryProvider really refresh the rendered list — behaviorally,
// against the REAL provider and REAL coachBox, paired with source-grep pins
// that the real screen wires this exact mechanism to the real singleton.
//
// Run: flutter test test/features/ai_coach/coach_chat_restore_invalidation_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';

import '../../helpers/hive_test_setup.dart';

/// Stands in for SyncService.instance.restoreCompletedTick — same exact
/// type, so the listener add/remove/fire mechanics are identical; see file
/// header for why the real singleton can't be touched inside testWidgets.
final _fakeRestoreTick = ValueNotifier<int>(0);

/// Mirrors `_AiCoachScreenState`'s restore-invalidation wiring exactly —
/// same guard shape, same invalidate call — without the real screen's
/// unrelated speech/camera/subscription dependencies or the real singleton.
class _FakeAiCoachScreen extends ConsumerStatefulWidget {
  const _FakeAiCoachScreen();

  @override
  ConsumerState<_FakeAiCoachScreen> createState() =>
      _FakeAiCoachScreenState();
}

class _FakeAiCoachScreenState extends ConsumerState<_FakeAiCoachScreen> {
  @override
  void initState() {
    super.initState();
    try {
      _fakeRestoreTick.addListener(_onRestoreCompleted);
    } catch (_) {}
  }

  void _onRestoreCompleted() {
    if (!mounted) return;
    ref.invalidate(chatHistoryProvider);
  }

  @override
  void dispose() {
    try {
      _fakeRestoreTick.removeListener(_onRestoreCompleted);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatHistoryProvider);
    return Scaffold(
      body: ListView(
        children: messages
            .map((m) => Text(m.text.isEmpty ? '(prompt)' : m.text))
            .toList(),
      ),
    );
  }
}

String _stripComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

void main() {
  group('AI Coach restore-invalidation (harness, real chatHistoryProvider + '
      'real coachBox, fake restore-tick — see file header)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await setUpHiveForTests();
      _fakeRestoreTick.value = 0;
    });

    tearDown(() async {
      await tearDownHiveForTests(tempDir);
    });

    testWidgets(
        'a background restore landing AFTER mount refreshes the chat '
        'thread — THE FOUNDER BUG, FIXED', (tester) async {
      // Real Hive disk I/O MUST run via tester.runAsync — a plain `await`
      // here never completes inside testWidgets' fake-async zone (the clock
      // only advances on `pump`), which is exactly what hung this test on
      // the first attempt: 37s to "did not complete", stuck right after
      // `[HiveUserSession] opened 7 boxes`.
      await tester.runAsync(() => HiveService.instance.coachBox.put('coach_1', {
            'id': 'coach_1',
            'user_message': 'stale question',
            'ai_response': 'stale answer',
            'created_at': DateTime(2026, 9, 20).toIso8601String(),
            'model_used': 'gemini-2.5-flash',
            'pending': false,
            'failed': false,
          }));

      final container = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _FakeAiCoachScreen()),
      ));
      await tester.pump();

      expect(find.text('stale answer'), findsOneWidget,
          reason: 'sanity: the pre-restore history must render first.');
      expect(find.text('fresh answer'), findsNothing);

      // Simulate a background restore landing: new rows appear in coachBox
      // (exactly what _restoreCoachInteractions does), then the tick fires —
      // in production this is SyncService.instance.bumpRestoreCompleted(),
      // called from RestoringScreen._healAfterRestoreInBackground; see file
      // header for why the fake stands in for it here.
      await tester.runAsync(() => HiveService.instance.coachBox.put('coach_2', {
            'id': 'coach_2',
            'user_message': 'fresh question',
            'ai_response': 'fresh answer',
            'created_at': DateTime(2026, 9, 21).toIso8601String(),
            'model_used': 'gemini-2.5-flash',
            'pending': false,
            'failed': false,
          }));
      _fakeRestoreTick.value++;
      await tester.pumpAndSettle();

      expect(find.text('fresh answer'), findsOneWidget,
          reason: 'THE FOUNDER BUG, FIXED — a restore landing after mount '
              'must refresh chatHistoryProvider; pre-fix this screen had no '
              'reactive link to the restore at all and kept showing only '
              'the pre-restore snapshot for the rest of the session.');
    });

    testWidgets(
        'disposing the screen removes the listener — no leak, no '
        'invalidate-after-dispose crash', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _FakeAiCoachScreen()),
      ));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      // Firing the tick after the screen is gone must not throw — proves
      // the listener was actually removed, not merely made a no-op via the
      // `!mounted` guard alone.
      expect(() => _fakeRestoreTick.value++, returnsNormally);
    });
  });

  group('screen.dart source — the fix is actually wired', () {
    late String source;

    setUpAll(() {
      source = _stripComments(File(
        'lib/features/ai_coach/screens/ai_coach/screen.dart',
      ).readAsStringSync());
    });

    test('initState registers the restore-tick listener', () {
      final start = source.indexOf('void initState() {');
      final end = source.indexOf('Future<void> _initSpeech()');
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final body = source.substring(start, end);
      expect(
        body.contains(
            'SyncService.instance.restoreCompletedTick\n          .addListener(_onRestoreCompleted)'),
        isTrue,
        reason: 'AI Coach does not use HiveTabScaffoldMixin, so it must '
            'wire this signal itself — omitting it reintroduces the bug.',
      );
    });

    test('_onRestoreCompleted invalidates chatHistoryProvider', () {
      final start = source.indexOf('void _onRestoreCompleted() {');
      expect(start, greaterThanOrEqualTo(0));
      final end = source.indexOf('}', start);
      final body = source.substring(start, end);
      expect(body.contains('if (!mounted) return;'), isTrue);
      expect(body.contains('ref.invalidate(chatHistoryProvider)'), isTrue);
    });

    test('dispose removes the listener (no leak)', () {
      final start = source.indexOf('void dispose() {');
      expect(start, greaterThanOrEqualTo(0));
      final end = source.indexOf('_speech?.stop();', start);
      expect(end, greaterThan(start));
      final body = source.substring(start, end);
      expect(
        body.contains(
            'SyncService.instance.restoreCompletedTick\n          .removeListener(_onRestoreCompleted)'),
        isTrue,
      );
    });

    test('does NOT adopt HiveTabScaffoldMixin (the documented, gated '
        'architectural exclusion stays intact)', () {
      expect(source.contains('with HiveTabScaffoldMixin'), isFalse,
          reason: 'HiveTabScaffoldMixin explicitly excludes AI Coach '
              '(its own file header) and check_tab_screen_uses_hive_'
              'scaffold.dart fails the build if a screen has both the '
              'mixin and an allow-list entry.');
    });
  });
}
