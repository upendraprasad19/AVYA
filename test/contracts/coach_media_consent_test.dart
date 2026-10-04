// test/contracts/coach_media_consent_test.dart
//
// Behavioral contract: coach_media_consent (Unit 8, coach-media-consent,
// OI-25, 2026-07-30).
//
// Writers:
//   lib/features/ai_coach/repositories/coach_interaction_repository.dart
//     - saveUserMessagePending(..., mediaStoragePath:) writes
//       media_storage_path onto the coach_<ms> row.
//     - recordMediaSaveDecision(key, saved:) writes media_save_state
//       ('saved' | 'declined') in place on the same row.
// Reader:
//   lib/features/ai_coach/providers/ai_coach_provider.dart
//     - ChatHistoryNotifier.build() projects coachKey, mediaStoragePath,
//       mediaAnalysisComplete, mediaSaveState onto the USER ChatMessage.
//
// Assert:
//   1. saveUserMessagePending persists mediaStoragePath.
//   2. recordMediaSaveDecision(saved:true/false) writes the right string,
//      and no-ops (does not throw) on a key that doesn't exist.
//   3. A ChatHistoryNotifier.build()-simulated rebuild carries coachKey on
//      the USER bubble — this is the regression the fix closes: pre-Unit-8
//      only the AI/error bubble carried coachKey (for Retry); the success-
//      path user bubble did not, so nothing could key a Hive write back to
//      the right row from that bubble.
//   4. mediaAnalysisComplete is false while pending/failed/no aiResponse,
//      true only once the SAME row resolves successfully — never before,
//      per the founder's migration-070 design note ("After AI analysis
//      returns, app prompts").
//
// This test FAILS if:
//   - mediaStoragePath is dropped anywhere in the write chain
//   - the user bubble stops carrying coachKey (chip would lose its target)
//   - mediaAnalysisComplete is computed from the wrong flags or the wrong row

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/read_screen_source.dart';

// Mirrors the exact success-path branch of ChatHistoryNotifier.build() in
// ai_coach_provider.dart — kept in lock-step with that logic (not a
// simplification of it), so drift between the two shows up as a test
// failure rather than silently.
class _SimUserBubble {
  final String? coachKey;
  final String? mediaStoragePath;
  final bool mediaAnalysisComplete;
  final String? mediaSaveState;
  const _SimUserBubble({
    this.coachKey,
    this.mediaStoragePath,
    required this.mediaAnalysisComplete,
    this.mediaSaveState,
  });
}

_SimUserBubble? _simulateUserBubbleFor(String key) {
  final raw = HiveService.instance.coachBox.get(key);
  if (raw is! Map) return null;
  final interaction = Map<String, dynamic>.from(raw);
  final userMsg = interaction['user_message'] as String?;
  if (userMsg == null || userMsg.isEmpty) return null;

  final aiResponse = interaction['ai_response'] as String?;
  final isPending = interaction['pending'] == true;
  final isFailed = interaction['failed'] == true;
  final mediaAnalysisComplete =
      !isPending && !isFailed && aiResponse != null && aiResponse.isNotEmpty;

  return _SimUserBubble(
    coachKey: key,
    mediaStoragePath: interaction['media_storage_path'] as String?,
    mediaAnalysisComplete: mediaAnalysisComplete,
    mediaSaveState: interaction['media_save_state'] as String?,
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  test('saveUserMessagePending persists mediaStoragePath', () async {
    final key = await CoachInteractionRepository.instance
        .saveUserMessagePending(
      userMessage: '[Photo] Analyse this photo',
      mode: 'media',
      mediaUrl: 'https://example.supabase.co/storage/v1/object/sign/chat-media/u/1.jpg?token=x',
      mediaType: 'image',
      mediaStoragePath: 'u1/12345.jpg',
    );

    final raw = HiveService.instance.coachBox.get(key);
    expect(raw, isA<Map>());
    final row = Map<String, dynamic>.from(raw as Map);
    expect(row['media_storage_path'], equals('u1/12345.jpg'),
        reason: 'the raw Storage path must survive the write — media_url\'s '
            '600s TTL means it cannot be recovered from that field later');
  });

  test('recordMediaSaveDecision(saved: true) writes media_save_state=saved',
      () async {
    final key = await CoachInteractionRepository.instance
        .saveUserMessagePending(
      userMessage: '[Photo] test',
      mode: 'media',
      mediaStoragePath: 'u1/1.jpg',
    );

    await CoachInteractionRepository.instance
        .recordMediaSaveDecision(key, saved: true);

    final row = Map<String, dynamic>.from(
        HiveService.instance.coachBox.get(key) as Map);
    expect(row['media_save_state'], equals('saved'));
  });

  test(
      'recordMediaSaveDecision(saved: false) writes media_save_state=declined',
      () async {
    final key = await CoachInteractionRepository.instance
        .saveUserMessagePending(
      userMessage: '[Photo] test',
      mode: 'media',
      mediaStoragePath: 'u1/1.jpg',
    );

    await CoachInteractionRepository.instance
        .recordMediaSaveDecision(key, saved: false);

    final row = Map<String, dynamic>.from(
        HiveService.instance.coachBox.get(key) as Map);
    expect(row['media_save_state'], equals('declined'));
  });

  test('recordMediaSaveDecision on a missing key is a safe no-op', () async {
    // Must not throw — mirrors updateInteractionWithResponse/Error's own
    // `if (raw is! Map) return;` guard.
    await CoachInteractionRepository.instance
        .recordMediaSaveDecision('coach_does_not_exist', saved: true);
  });

  test(
      'simulated rebuild: user photo bubble carries coachKey (regression — '
      'previously only the AI/error bubble did)', () async {
    final key = await CoachInteractionRepository.instance
        .saveUserMessagePending(
      userMessage: '[Photo] Analyse this photo',
      mode: 'media',
      mediaStoragePath: 'u1/1.jpg',
    );

    final bubble = _simulateUserBubbleFor(key);
    expect(bubble, isNotNull);
    expect(bubble!.coachKey, equals(key),
        reason: 'without coachKey on the user bubble, the save-consent chip '
            'has nothing to write its decision against');
  });

  test('mediaAnalysisComplete is false while the row is still pending',
      () async {
    final key = await CoachInteractionRepository.instance
        .saveUserMessagePending(
      userMessage: '[Photo] test',
      mode: 'media',
      mediaStoragePath: 'u1/1.jpg',
    );
    // saveUserMessagePending leaves pending:true, ai_response:'' — the
    // AI call hasn't resolved yet.
    final bubble = _simulateUserBubbleFor(key);
    expect(bubble!.mediaAnalysisComplete, isFalse,
        reason: 'the consent chip must never appear before analysis '
            'completes, per the founder\'s migration-070 design note');
  });

  test('mediaAnalysisComplete is false while the row is failed', () async {
    final key = await CoachInteractionRepository.instance
        .saveUserMessagePending(
      userMessage: '[Photo] test',
      mode: 'media',
      mediaStoragePath: 'u1/1.jpg',
    );
    await CoachInteractionRepository.instance
        .updateInteractionWithError(key, errorText: 'boom');

    final bubble = _simulateUserBubbleFor(key);
    expect(bubble!.mediaAnalysisComplete, isFalse);
  });

  test(
      'mediaAnalysisComplete flips true once the SAME row resolves with a '
      'non-empty AI response', () async {
    final key = await CoachInteractionRepository.instance
        .saveUserMessagePending(
      userMessage: '[Photo] test',
      mode: 'media',
      mediaStoragePath: 'u1/1.jpg',
    );
    await CoachInteractionRepository.instance.updateInteractionWithResponse(
      key,
      aiResponse: 'That looks like a solid squat depth.',
      modelUsed: 'gemini-2.5-flash-lite',
    );

    final bubble = _simulateUserBubbleFor(key);
    expect(bubble!.mediaAnalysisComplete, isTrue);
    expect(bubble.mediaSaveState, isNull,
        reason: 'undecided until the user taps Save/No thanks');
  });

  group('round-1 review fix — decline cannot clobber an in-flight save', () {
    // Source-grep, presence-only (feedback_source_grep_false_confidence.md
    // — honestly labelled as such): _onDeclineCoachMedia/_onSaveCoachMedia
    // are private State methods with no public seam, and this exact screen
    // has no existing widget+Riverpod+Hive integration harness to simulate
    // the actual async race against. Pins that BOTH handlers guard on the
    // SAME _savingCoachMediaKeys set before either performs its Hive write.
    test(
        '_onDeclineCoachMedia checks _savingCoachMediaKeys before writing, '
        'same guard _onSaveCoachMedia already used', () {
      final src = readScreenSource('ai_coach');
      final declineIdx = src.indexOf('Future<void> _onDeclineCoachMedia(');
      expect(declineIdx, greaterThan(-1),
          reason: '_onDeclineCoachMedia moved or renamed — re-baseline');

      final declineBody =
          src.substring(declineIdx, (declineIdx + 400).clamp(0, src.length));
      final guardIdx = declineBody.indexOf('_savingCoachMediaKeys');
      final writeIdx = declineBody.indexOf('recordMediaSaveDecision');
      expect(guardIdx, greaterThan(-1),
          reason: 'without this guard, a decline tap that lands while a '
              'save for the same photo is still in flight silently gets '
              'overwritten back to saved once the save completes');
      expect(writeIdx, greaterThan(guardIdx),
          reason: 'the guard check must come BEFORE the Hive write, not '
              'after (an after-the-fact check cannot prevent the race)');
    });
  });

  group('round-2 review fix — symmetric guard (save cannot clobber an '
      'in-flight decline)', () {
    // Round-1's guard was one-directional: _onDeclineCoachMedia checked
    // _savingCoachMediaKeys but never ADDED itself to it, so a SAVE tap
    // landing between _onDeclineCoachMedia's Hive write and its state
    // update could still start a copy that later overwrote the decline
    // back to 'saved'. Pins that _onDeclineCoachMedia now takes the SAME
    // lock _onSaveCoachMedia does — add before the write, remove in a
    // finally — for full mutual exclusion, not one-sided.
    test(
        '_onDeclineCoachMedia adds to _savingCoachMediaKeys before its '
        'write and removes it in a finally block', () {
      final src = readScreenSource('ai_coach');
      final declineIdx = src.indexOf('Future<void> _onDeclineCoachMedia(');
      expect(declineIdx, greaterThan(-1),
          reason: '_onDeclineCoachMedia moved or renamed — re-baseline');

      final declineBody =
          src.substring(declineIdx, (declineIdx + 700).clamp(0, src.length));
      final addIdx = declineBody.indexOf('_savingCoachMediaKeys.add(');
      final writeIdx = declineBody.indexOf('recordMediaSaveDecision');
      final finallyIdx = declineBody.indexOf('} finally {');
      final removeIdx =
          declineBody.indexOf('_savingCoachMediaKeys.remove(', finallyIdx);

      expect(addIdx, greaterThan(-1),
          reason: 'without adding itself to the lock, a concurrent SAVE '
              'tap can still start a copy that later overwrites this '
              'decline back to \'saved\' once it completes');
      expect(addIdx, lessThan(writeIdx),
          reason: 'the lock must be taken BEFORE the Hive write, not after');
      expect(finallyIdx, greaterThan(writeIdx),
          reason: 'the release must be unconditional (finally), so an '
              'exception from the write does not leave the key stuck '
              'locked forever');
      expect(removeIdx, greaterThan(finallyIdx));
    });

    test(
        '_onSaveCoachMedia and _onDeclineCoachMedia guard on the exact '
        'same field, _savingCoachMediaKeys', () {
      final src = readScreenSource('ai_coach');
      final saveIdx = src.indexOf('Future<void> _onSaveCoachMedia(');
      final declineIdx = src.indexOf('Future<void> _onDeclineCoachMedia(');
      expect(saveIdx, greaterThan(-1));
      expect(declineIdx, greaterThan(-1));

      final saveBody =
          src.substring(saveIdx, (saveIdx + 900).clamp(0, src.length));
      final declineBody =
          src.substring(declineIdx, (declineIdx + 700).clamp(0, src.length));

      expect(saveBody.contains('_savingCoachMediaKeys.add('), isTrue);
      expect(declineBody.contains('_savingCoachMediaKeys.add('), isTrue,
          reason: 'both handlers must lock the SAME set for mutual '
              'exclusion to actually hold — a handler-local or '
              'differently-named lock would not stop the other handler');
    });
  });
}
