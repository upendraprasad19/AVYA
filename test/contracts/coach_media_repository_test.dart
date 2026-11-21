// test/contracts/coach_media_repository_test.dart
//
// Unit 8 (coach-media-consent, OI-25).
//
// Part 1 — pure-Dart behavioral test for ChatMessage.copyWithMediaState
// (no Hive/Supabase dependency; the method is a plain field-copy).
//
// Part 2 — source-grep contract pinning CoachMediaRepository's Storage
// call shape. CoachMediaRepository.saveForLater/list/delete hit live
// Supabase Storage (.copy/.list/.remove) with no dependency-injection seam
// in this codebase (ProgressPhotoRepository, the closest precedent, has no
// behavioral test of its own network calls either — see
// test/contracts/chat_media_signed_url_test.dart for the same source-grep
// approach applied to the sibling chat-media upload path). This test FAILS
// if:
//   - the copy call stops targeting the coach-media bucket
//   - the free-tier source cleanup stops being conditional on !isPro
//     (PRO users must keep BOTH copies; the clean-orphan-media cron
//     already special-cases PRO the same way)
//   - either path-ownership assertion is removed

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('migration 116 — chat_media_delete_own RLS policy', () {
    // Round-2 review (2026-07-30) live-queried pg_policies on
    // dedsavbjuwgarrhphgnl directly and found chat-media had NO
    // authenticated-DELETE policy — saveForLater's free-tier cleanup call
    // had been silently RLS-denied on every invocation. This pins the
    // migration's DDL shape; live re-verification (the policy actually
    // exists post-apply) happens via a direct pg_policies query cited in
    // the diagnose-doc once migration 116 is applied (§4.3 — live apply
    // needs its own explicit authorization, separate from this batch).
    test('creates chat_media_delete_own scoped to chat-media, mirroring '
        "coach_media_delete_own's own shape (migration 070)", () {
      final src =
          _src('supabase/migrations/116_chat_media_delete_own_policy.sql');
      expect(src.contains('CREATE POLICY "chat_media_delete_own"'), isTrue);
      expect(src.contains('ON storage.objects FOR DELETE'), isTrue);
      expect(src.contains('TO authenticated'), isTrue);
      expect(
        src.contains(
            "bucket_id = 'chat-media' AND (storage.foldername(name))[1] = (auth.uid())::text"),
        isTrue,
        reason: 'must scope to the caller\'s own path prefix, exactly like '
            'coach_media_delete_own — a missing ownership clause would let '
            'any authenticated user delete any other user\'s chat-media',
      );
    });

    test('is idempotent (drops any pre-existing policy of the same name '
        'before creating)', () {
      final src =
          _src('supabase/migrations/116_chat_media_delete_own_policy.sql');
      final dropIdx = src.indexOf('DROP POLICY "chat_media_delete_own"');
      final createIdx = src.indexOf('CREATE POLICY "chat_media_delete_own"');
      expect(dropIdx, greaterThan(-1),
          reason: 'a re-run of this migration must not 42710 on an '
              'already-applied environment');
      expect(createIdx, greaterThan(dropIdx));
    });
  });

  group('ChatMessage.copyWithMediaState', () {
    test('overrides only the targeted fields, preserves everything else',
        () {
      final original = ChatMessage(
        text: 'Analyse this photo',
        isUser: true,
        timestamp: DateTime(2026, 7, 30),
        mediaUrl: 'https://example.com/x.jpg',
        mediaType: 'image',
        coachKey: 'coach_123',
        mediaStoragePath: 'u1/1.jpg',
        mediaAnalysisComplete: false,
        mediaSaveState: null,
      );

      final updated = original.copyWithMediaState(mediaAnalysisComplete: true);

      expect(updated.mediaAnalysisComplete, isTrue);
      expect(updated.mediaSaveState, isNull);
      // Everything else must survive untouched.
      expect(updated.text, equals(original.text));
      expect(updated.isUser, equals(original.isUser));
      expect(updated.timestamp, equals(original.timestamp));
      expect(updated.mediaUrl, equals(original.mediaUrl));
      expect(updated.mediaType, equals(original.mediaType));
      expect(updated.coachKey, equals(original.coachKey));
      expect(updated.mediaStoragePath, equals(original.mediaStoragePath));
    });

    test('null args mean "keep existing value", not "clear to null"', () {
      final saved = ChatMessage(
        text: 'x',
        isUser: true,
        timestamp: DateTime(2026, 7, 30),
        mediaSaveState: 'saved',
        mediaAnalysisComplete: true,
      );

      // Calling with only mediaAnalysisComplete set must NOT wipe the
      // already-recorded mediaSaveState — updateMessageMediaState relies
      // on this to make single-field updates safely.
      final stillSaved = saved.copyWithMediaState(mediaAnalysisComplete: true);
      expect(stillSaved.mediaSaveState, equals('saved'));
    });

    test('mediaSaveState transitions null -> declined', () {
      final undecided = ChatMessage(
        text: 'x',
        isUser: true,
        timestamp: DateTime(2026, 7, 30),
        mediaAnalysisComplete: true,
      );
      final declined = undecided.copyWithMediaState(mediaSaveState: 'declined');
      expect(declined.mediaSaveState, equals('declined'));
      expect(declined.mediaAnalysisComplete, isTrue);
    });
  });

  group('CoachMediaRepository source-grep contract', () {
    late String src;
    setUpAll(() {
      src = File(
              'lib/features/ai_coach/repositories/coach_media_repository.dart')
          .readAsStringSync();
    });

    test('source bucket is chat-media, destination is coach-media', () {
      expect(src.contains("_sourceBucket = 'chat-media'"), isTrue);
      expect(src.contains("_destBucket = 'coach-media'"), isTrue);
    });

    test('copy targets coach-media via destinationBucket', () {
      expect(
        src.contains(
            '.copy(chatMediaPath, chatMediaPath, destinationBucket: _destBucket)'),
        isTrue,
        reason: 'saveForLater must copy ACROSS buckets via the '
            'destinationBucket param — a same-bucket copy would silently '
            'do nothing useful',
      );
    });

    test('free-tier source cleanup is gated on !isPro', () {
      final isProIdx = src.indexOf('if (!isPro)');
      final removeIdx = src.indexOf('.remove([chatMediaPath])');
      expect(isProIdx, greaterThan(-1),
          reason: 'PRO users must keep the chat-media source (retention), '
              'only free-tier gets it cleaned up immediately post-copy');
      expect(removeIdx, greaterThan(isProIdx),
          reason: 'the source-bucket remove() call must be textually '
              'inside the !isPro branch');
    });

    test('saveForLater and delete both assert path ownership', () {
      final ownershipChecks =
          RegExp(r"startsWith\('\$userId/'\)").allMatches(src).length;
      expect(ownershipChecks, greaterThanOrEqualTo(2),
          reason: 'both saveForLater (copy source) and delete (coach-media '
              'target) must defense-in-depth check the path belongs to the '
              'caller before hitting Storage — RLS enforces this '
              'server-side too, but failing fast avoids a wasted round-trip '
              'on a plainly-wrong path');
    });

    test('list() reads from coach-media, not chat-media', () {
      final listCallIdx = src.indexOf('Future<List<Map<String, dynamic>>> list(');
      expect(listCallIdx, greaterThan(-1));
      final listBody = src.substring(
          listCallIdx, (listCallIdx + 800).clamp(0, src.length));
      expect(listBody.contains("from(_destBucket)"), isTrue,
          reason: 'the gallery must list saved (coach-media) photos, not '
              'transient (chat-media) ones');
    });

    // Round-2 review (2026-07-30) — a `.copy()` whose server-side write
    // succeeds but whose response the client never receives (network blip
    // / app backgrounded mid-request) makes a RETRY see the server's
    // already-exists failure for a photo that, from the user's tap, was
    // already successfully saved. Pins the fix: check before giving up.
    test('a copy failure checks _destinationExists before reporting failure '
        '(idempotent retry-after-success handling)', () {
      final catchIdx = src.indexOf('} catch (e) {');
      expect(catchIdx, greaterThan(-1));
      final catchBody =
          src.substring(catchIdx, (catchIdx + 2200).clamp(0, src.length));
      final existsIdx = catchBody.indexOf('_destinationExists(chatMediaPath)');
      final telemetryIdx =
          catchBody.indexOf('coach_media_save_for_later_failed');
      final returnFalseIdx = catchBody.indexOf('return false;');
      expect(existsIdx, greaterThan(-1),
          reason: 'a copy failure must first check whether the destination '
              'already exists (retry-after-server-side-success case) '
              'before concluding this is a genuine failure');
      expect(telemetryIdx, greaterThan(existsIdx),
          reason: 'failure telemetry must only fire once the existence '
              'check has ruled out the retry-already-succeeded case — '
              'otherwise every network-blip retry fires a false alarm');
      expect(returnFalseIdx, greaterThan(existsIdx),
          reason: 'the failure return must come after the existence check, '
              'not before it');
    });

    test('_destinationExists checks the destination (coach-media) bucket, '
        'not the source (chat-media) bucket', () {
      final idx = src.indexOf('Future<bool> _destinationExists(');
      expect(idx, greaterThan(-1),
          reason: '_destinationExists moved or was renamed — re-baseline');
      final body = src.substring(idx, (idx + 600).clamp(0, src.length));
      expect(body.contains('from(_destBucket)'), isTrue,
          reason: 'checking the SOURCE bucket for the destination path '
              'would always report false and defeat the idempotency fix');
    });
  });
}
