// test/contracts/user_preferences_coaching_notes_writer_to_reader_test.dart
//
// SoT contract for user_preferences_coaching_notes (single-owner-a2a,
// 2026-09-27, dependent #7 of the round-4 a2a/a2b split — see
// docs/plans/2026-09-26-single-owner-batch-a.md:262).
//
// This concept is DISTINCT from the pre-existing `coaching_notes` concept
// (Hive singleton / coach_memory.coach_notes) — same English name, different
// Postgres table+column, unrelated writers. Two server-side Edge Functions
// read-merge-write ONE JSON blob at user_preferences.coaching_notes, and the
// client (sync_profile.dart) is a pure consumer that must never write this key
// back — a null-carrying client write clobbers both writers' data (OI-98
// round-3 review). Comment-stripped so a contract described only in a comment
// cannot satisfy it.
//
// closes-diagnose: (coverage — no bug; registration of a correct-but-unpinned
// path, found by the single-owner-a2a B-pass, per the plan's own round-4
// dependents list)

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  final dailySnapshot = _strip(
      File('supabase/functions/daily-snapshot/index.ts').readAsStringSync());
  final assessBodyCompRaw =
      File('supabase/functions/assess-body-composition/index.ts')
          .readAsStringSync();
  final assessBodyComp = _strip(assessBodyCompRaw);
  final restoreSnapshot = _strip(
      File('supabase/functions/restore-user-snapshot/index.ts')
          .readAsStringSync());
  final syncProfileRaw =
      File('lib/core/services/sync/sync_profile.dart').readAsStringSync();
  final syncProfile = _strip(syncProfileRaw);

  group('user_preferences_coaching_notes writer→reader contract', () {
    test('daily-snapshot read-merge-writes coaching_notes, never a blind overwrite', () {
      expect(dailySnapshot.contains('async function mergeCoachingNotes'), isTrue);
      final start = dailySnapshot.indexOf('async function mergeCoachingNotes');
      final end = dailySnapshot.indexOf('async function mergeCoachMemoryFields');
      expect(end, greaterThan(start), reason: 'could not bound mergeCoachingNotes');
      final body = dailySnapshot.substring(start, end);
      expect(body.contains('.select("coaching_notes")'), isTrue,
          reason: 'must read the existing blob before merging');
      expect(body.contains('JSON.parse'), isTrue,
          reason: 'existing coaching_notes is a JSON string, must be parsed before merge');
      expect(body.contains('.upsert('), isTrue,
          reason: 'merged result must be written back');
      expect(body.contains('onConflict: "user_id"'), isTrue);
    });

    test('assess-body-composition also read-merge-writes the same blob for its rate-limit stamp', () {
      expect(
          assessBodyCompRaw.contains('user_preferences.coaching_notes'), isTrue,
          reason: 'the piggyback intent must stay documented, not just coded '
              '(checked against the RAW file — this phrase lives only in a '
              '// comment, which _strip() would otherwise erase)');
      expect(assessBodyComp.contains('.select("coaching_notes")'), isTrue,
          reason: 'must read the existing blob before writing its own stamp');
      expect(assessBodyComp.contains('JSON.parse'), isTrue);
      expect(assessBodyComp.contains('last_bf_assessed_at'), isTrue);
      expect(assessBodyComp.contains('.upsert('), isTrue);
    });

    test('client never includes coaching_notes in its own user_preferences push payload', () {
      // The removal is the fix — assert the guarding comment's own anchor
      // phrase survives (checked against the RAW file: it lives only in a
      // // comment, which _strip() would otherwise erase), and that no
      // LIVE-CODE line in this file names coaching_notes as a key it
      // assembles for the upsert (checked against the STRIPPED file: the
      // comment itself quotes the exact forbidden pattern as a warning,
      // which would false-fail an unstripped check).
      expect(
          syncProfileRaw.contains('coaching_notes` REMOVED from this payload'),
          isTrue,
          reason:
              'OI-98 round-3 review removed this key from the client push — '
              'if this string is gone, check whether the removal itself was reverted');
      expect(syncProfile.contains("p['coaching_notes']"), isFalse,
          reason:
              'the client must never re-add coaching_notes to its own '
              'user_preferences upsert payload — a null-carrying key nulls '
              "both server writers' data");
    });

    test('client restore path pulls the whole user_preferences row (incl. coaching_notes) back into Hive', () {
      expect(syncProfile.contains('_restoreUserPreferences'), isTrue);
      final start = syncProfile.indexOf('_restoreUserPreferences(String userId');
      expect(start, greaterThanOrEqualTo(0));
      final body = syncProfile.substring(start, start + 1200);
      expect(body.contains(".from('user_preferences')"), isTrue);
      expect(body.contains('.select()'), isTrue,
          reason:
              'generic select — this concept round-trips opaquely, the '
              'client never parses individual coaching_notes keys');
    });

    test('server-side restore-user-snapshot also selects user_preferences.* back to the client', () {
      expect(restoreSnapshot.contains('db.from("user_preferences")'), isTrue);
      expect(restoreSnapshot.contains('.select("*")'), isTrue);
    });
  });
}
