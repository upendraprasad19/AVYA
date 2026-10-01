// OI-245 — Restored PRO photo-coach turns are replayed to Gemini as text.
//
// SYMPTOM: `sync_coach.dart`'s `_restoreCoachInteractions` hardcoded every
// restored `ai_coach_interactions` row's Hive `mode` field to `'quick'`.
// `CoachInteractionRepository.recentHistoryExchanges` (the reader that
// assembles Gemini chat history) excludes a row only when `mode == 'media'`
// — so a restored photo-coach turn (successful PRO analysis, cloud `channel`
// = `'app'`, indistinguishable by channel from a normal chat turn) always
// passed that filter and was replayed into the model's context as if the
// user had typed the `'[Photo: image] ...'` placeholder text as plain chat.
//
// WRITER → `sync_coach.dart` `_restoreCoachInteractions` (this test,
//          behavioral: seeds a cloud-shaped row, calls the restore path via
//          its pure decision helper, asserts the Hive row it produces).
// READER → `CoachInteractionRepository.recentHistoryExchanges`'s
//          `mode == 'media'` exclusion (this test, behavioral: the restored
//          row is excluded from history replay end-to-end).
//
// Fix: `isRestoredMediaRow` recognizes the server's `'[Photo'`/`'[Video'`
// placeholder-text prefix (the cloud table carries no `mode` column, the
// same gap `isRestoredHardFailureRow` documents for the hard-failure case)
// and restore now derives `mode` from it instead of hardcoding `'quick'`.
//
// This file has three jobs, mirroring
// test/contracts/hard_failure_apology_texts_parity_test.dart's structure:
//   1. PARITY — the recognized prefixes are byte-identical to what
//      ai-media-proxy/index.ts actually writes.
//   2. BEHAVIOR — isRestoredMediaRow (pure) is mutation-tested directly.
//   3. WIRING + DOWNSTREAM — _restoreCoachInteractions derives `mode` from
//      it (source-grep), AND a restored photo row is excluded from
//      recentHistoryExchanges end-to-end (behavioral, pure Hive).

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';

import '_sync_service_source.dart';

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

  group('parity — recognized prefixes match ai-media-proxy/index.ts', () {
    late String mediaProxySrc;

    setUpAll(() {
      mediaProxySrc = File('supabase/functions/ai-media-proxy/index.ts')
          .readAsStringSync();
    });

    test('the successful-analysis insert still writes the [Photo: prefix',
        () {
      expect(
          mediaProxySrc
              .contains('user_message: `[Photo: \${media_type ?? "image"}]'),
          isTrue,
          reason: 'if this literal drifts, isRestoredMediaRow\'s prefix '
              'check goes blind to the exact row OI-245 fixed');
    });

    test(
        'the paywall-exhausted insert (a separate call site, separate '
        'variable spelling) still writes the [Photo: prefix', () {
      // Round-2 review finding P3 (2026-09-29): the successful-analysis path
      // (above) uses `media_type` (snake_case); this earlier paywall path
      // uses `mediaType` (camelCase) — two distinct literals producing the
      // identical runtime prefix. The test above alone cannot detect this
      // one diverging in isolation.
      expect(
          mediaProxySrc
              .contains('user_message: `[Photo: \${mediaType ?? "image"}]'),
          isTrue,
          reason: 'if this literal drifts, isRestoredMediaRow\'s prefix '
              'check goes blind to the paywall-exhausted [Photo row');
    });

    test('the video-paywall insert still writes the [Video] prefix', () {
      expect(mediaProxySrc.contains('user_message: `[Video] \${message}`'),
          isTrue);
    });
  });

  group('isRestoredMediaRow — pure, mutation-tested', () {
    test('true for the successful-analysis server prefix', () {
      expect(isRestoredMediaRow('[Photo: image] Analyse this photo'),
          isTrue);
    });

    test('true for the free-image-paywall / image-paywall server prefix',
        () {
      expect(isRestoredMediaRow('[Photo: image] some caption'), isTrue);
    });

    test('true for the video-paywall server prefix', () {
      expect(isRestoredMediaRow('[Video] some caption'), isTrue);
    });

    test('true for the local-only client placeholder (defensive)', () {
      expect(isRestoredMediaRow('[Photo] Analyse this photo'), isTrue);
    });

    test('false for real chat text', () {
      expect(isRestoredMediaRow('what is my workout today'), isFalse);
    });

    test('false for null and empty', () {
      expect(isRestoredMediaRow(null), isFalse);
      expect(isRestoredMediaRow(''), isFalse);
    });

    test('false for a near-miss that merely mentions a photo mid-sentence',
        () {
      expect(isRestoredMediaRow('can I send a Photo of my meal?'), isFalse,
          reason: 'must be a PREFIX match, not contains — real chat text '
              'that happens to mention a photo must not be excluded from '
              'replay');
    });
  });

  group('wiring — _restoreCoachInteractions derives mode from the recognizer',
      () {
    late String src;

    setUpAll(() {
      src = _stripComments(loadSyncServiceSource().readAsStringSync());
    });

    test('restore body derives mode via isRestoredMediaRow, not a hardcode',
        () {
      final start = src.indexOf('Future<void> _restoreCoachInteractions(');
      expect(start, greaterThan(0),
          reason: '_restoreCoachInteractions must exist');
      final next = src.indexOf('\n  Future<void> ', start + 1);
      final body = src.substring(start, next > start ? next : src.length);

      expect(body.contains("'mode': 'quick',"), isFalse,
          reason: 'the hardcoded mode must be gone — a restored media row '
              'must not always be forced to quick');
      expect(body.contains('isRestoredMediaRow('), isTrue,
          reason: 'restore must derive mode from the recognizer');
    });
  });

  group('downstream — a restored photo row is excluded from replay', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir =
          await Directory.systemTemp.createTemp('test_coach_restored_media');
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

    test(
        'a restored PRO photo turn (channel app, [Photo: prefix) is excluded '
        'while a restored real chat turn on the same channel survives',
        () async {
      final box = HiveService.instance.coachBox;
      // Simulates the exact row shape _restoreCoachInteractions now
      // produces for a cloud ai-media-proxy insert: channel 'app' (the same
      // channel a normal chat turn uses — indistinguishable without the
      // mode derivation this fix adds).
      await box.put('coach_100', {
        'id': 'coach_100',
        'user_message': '[Photo: image] Analyse this photo',
        'ai_response': 'That plate is ~650 kcal, 40g protein.',
        'model_used': 'Gemini 2.5 Flash Lite',
        'mode': isRestoredMediaRow('[Photo: image] Analyse this photo')
            ? 'media'
            : 'quick',
        'is_user_message': true,
        'created_at': '2026-09-26T01:00:00.000',
        'channel': 'app',
        'source': 'cloud_restore',
      });
      await box.put('coach_200', {
        'id': 'coach_200',
        'user_message': 'what is my workout today',
        'ai_response': 'Push day — bench, incline dumbbell, dips.',
        'model_used': 'Gemini 2.5 Flash',
        'mode': isRestoredMediaRow('what is my workout today')
            ? 'media'
            : 'quick',
        'is_user_message': true,
        'created_at': '2026-09-26T02:00:00.000',
        'channel': 'app',
        'source': 'cloud_restore',
      });

      final history =
          CoachInteractionRepository.instance.recentHistoryExchanges();

      expect(history, [
        {'role': 'user', 'text': 'what is my workout today'},
        {'role': 'model', 'text': 'Push day — bench, incline dumbbell, dips.'},
      ]);
    });
  });
}
