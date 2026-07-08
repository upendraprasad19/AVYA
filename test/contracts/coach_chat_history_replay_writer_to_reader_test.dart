// Unit 2 (coach-memory-snapshot) — SoT `coach_chat_history_replay`.
//
// THE FEATURE: the coach now forwards the last N COMPLETE exchanges as a
// `history` field so the model has turn-to-turn continuity (previously the
// client sent ZERO history — a bare "what?" reset the coach).
//
// WRITER  → `CoachInteractionRepository.recentHistoryExchanges()` (this test,
//           behavioral: reads coachBox rows → ordered alternating {role,text}).
// READER  → the ai-proxy `history` body field → `tool-loop.ts` seeds messages[]
//           via `repairHistoryAlternation` (source-seam asserted below; the
//           runtime repair/cap logic has its own Deno test tool-loop.test.ts).
//
// Behavioral assertions FAIL against the pre-feature behavior (no method / an
// unsorted or unfiltered list):
//   (a) complete exchanges → flat user→model alternating list, oldest→newest,
//       SORTED by created_at (Hive iteration order is NOT chronological);
//   (b) EXCLUDES pending / failed / media / kind-tagged / empty-text rows and
//       the `coach_memory` singleton — so the current turn never self-leaks;
//   (c) `limit` counts EXCHANGES: 10 exchanges @ limit 8 → 8 rows = 16 entries,
//       the oldest 2 dropped.
//
// Pure Hive (path_provider-mocked) — no Supabase — runs in the pre-commit gate.
// Mirrors coach_completion_prompt_test.dart's setup.

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';

/// Strips `//` line comments and `/* */` block comments so a source-seam
/// presence check can't be satisfied by a comment mentioning the token
/// (feedback_source_grep_strip_comments_first).
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_coach_history');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    for (final name in [
      HiveService.coachBoxName,
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'coachBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
  });

  // Writes a coach interaction row (a complete exchange unless overridden).
  Future<void> putRow(
    String key, {
    String? user = 'u',
    String? ai = 'a',
    String mode = 'quick',
    required String createdAt,
    bool? pending,
    bool? failed,
    String? kind,
  }) async {
    final box = HiveService.instance.coachBox;
    await box.put(key, {
      'id': key,
      'user_message': ?user,
      'ai_response': ?ai,
      'model_used': 'Gemini 2.5 Flash',
      'mode': mode,
      'is_user_message': true,
      'created_at': createdAt,
      'pending': ?pending,
      'failed': ?failed,
      'kind': ?kind,
    });
  }

  test('(a) complete exchanges → alternating, oldest→newest, sorted by created_at',
      () async {
    // Insert OUT OF chronological order to prove the sort (Hive keeps insertion
    // order). Keys are non-monotonic on purpose.
    await putRow('coach_300', user: 'third', ai: 'A3', createdAt: '2026-07-07T03:00:00.000');
    await putRow('coach_100', user: 'first', ai: 'A1', createdAt: '2026-07-07T01:00:00.000');
    await putRow('coach_200', user: 'second', ai: 'A2', createdAt: '2026-07-07T02:00:00.000');

    final history = CoachInteractionRepository.instance.recentHistoryExchanges();

    expect(history, [
      {'role': 'user', 'text': 'first'},
      {'role': 'model', 'text': 'A1'},
      {'role': 'user', 'text': 'second'},
      {'role': 'model', 'text': 'A2'},
      {'role': 'user', 'text': 'third'},
      {'role': 'model', 'text': 'A3'},
    ]);
  });

  test('(b) excludes pending / failed / media / kind / empty / singleton', () async {
    await putRow('coach_100', user: 'good', ai: 'GA', createdAt: '2026-07-07T01:00:00.000');
    await putRow('coach_110', user: 'pend', ai: '', pending: true, createdAt: '2026-07-07T01:10:00.000');
    await putRow('coach_120', user: 'fail', ai: '', failed: true, createdAt: '2026-07-07T01:20:00.000');
    await putRow('coach_130', user: '[Photo] meal', ai: 'looks good', mode: 'media', createdAt: '2026-07-07T01:30:00.000');
    await putRow('coach_140', user: '', ai: 'orphan', createdAt: '2026-07-07T01:40:00.000');
    await putRow('coach_150', user: 'noai', ai: '', createdAt: '2026-07-07T01:50:00.000');
    // A completion_prompt action row (Unit 1) — kind-tagged, must be excluded.
    await putRow('coach_160', user: 'x', ai: 'y', kind: 'completion_prompt', createdAt: '2026-07-07T01:60:00.000');
    // The coach_memory singleton shares the coach_ prefix but has no user_message.
    await HiveService.instance.coachBox.put('coach_memory', {'coach_notes': 'note'});

    final history = CoachInteractionRepository.instance.recentHistoryExchanges();

    expect(history, [
      {'role': 'user', 'text': 'good'},
      {'role': 'model', 'text': 'GA'},
    ]);
  });

  test('(c) limit counts EXCHANGES — 10 exchanges @ limit 8 → 16 entries, oldest dropped',
      () async {
    for (var i = 1; i <= 10; i++) {
      final hh = i.toString().padLeft(2, '0');
      await putRow('coach_${i * 100}',
          user: 'u$i', ai: 'a$i', createdAt: '2026-07-07T$hh:00:00.000');
    }

    final history =
        CoachInteractionRepository.instance.recentHistoryExchanges(limit: 8);

    expect(history.length, 16); // 8 exchanges × 2
    // Oldest two exchanges (u1/u2) dropped; window is u3..u10.
    expect(history.first, {'role': 'user', 'text': 'u3'});
    expect(history.last, {'role': 'model', 'text': 'a10'});
  });

  test('empty coachBox → empty history', () {
    expect(CoachInteractionRepository.instance.recentHistoryExchanges(), isEmpty);
  });

  // ── Reader-seam source assertions (server side is TS; the runtime repair/cap
  // logic is behaviorally covered by supabase/functions/_shared/tool-loop.test.ts).
  test('server reader seam threads history through all three layers', () {
    final aiService = _stripComments(File(
            'lib/core/services/ai_service.dart')
        .readAsStringSync());
    // Both the primary body and the _directHttpCall fallback body attach history.
    expect("'history': history".allMatches(aiService).length, greaterThanOrEqualTo(2),
        reason: 'ai_service.chat() must attach history in BOTH request bodies');

    final toolLoop = _stripComments(File(
            'supabase/functions/_shared/tool-loop.ts')
        .readAsStringSync());
    expect(toolLoop.contains('repairHistoryAlternation(opts.history'), isTrue,
        reason: 'tool-loop must seed messages[] with repaired history');
    expect(toolLoop.contains('export function capCoachHistory'), isTrue);
    expect(toolLoop.contains('export function repairHistoryAlternation'), isTrue);

    final index = _stripComments(File(
            'supabase/functions/ai-proxy/index.ts')
        .readAsStringSync());
    expect(index.contains('capCoachHistory(history)'), isTrue,
        reason: 'ai-proxy must size-cap client history before runToolLoop');
    expect(index.contains('history: cappedHistory'), isTrue,
        reason: 'ai-proxy must pass the capped history into runToolLoop');
  });

  // R2 fix: history must reach BOTH chat() call sites in the provider — the
  // primary send AND the auth-retry re-call (ai_coach_provider.dart:810).
  // Threading only the primary silently drops continuity on a token refresh.
  test('provider threads history into BOTH chat() call sites (primary + retry)',
      () {
    final provider = _stripComments(File(
            'lib/features/ai_coach/providers/ai_coach_provider.dart')
        .readAsStringSync());
    // Assembled once, kill-switched.
    expect(provider.contains("configBox.get('disable_coach_history')"), isTrue,
        reason: 'history assembly must honor the disable_coach_history flag');
    expect(provider.contains('recentHistoryExchanges()'), isTrue);
    // Both the primary and the auth-retry chat() calls pass history.
    expect('history: coachHistory'.allMatches(provider).length,
        greaterThanOrEqualTo(2),
        reason:
            'both the primary send AND the auth-retry re-call must carry history');
  });
}
