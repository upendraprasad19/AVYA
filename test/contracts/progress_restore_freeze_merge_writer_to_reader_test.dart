// c9d2f6 — writer -> reader NAME contract for the streak-freeze family that a
// whole-row `user_progress` restore merges (SoT concept
// `progress_restore_freeze_merge`; Gate 9 requires this file by name).
//
// SOURCE-GREP, so it proves PRESENCE and SPELLING ONLY
// (`feedback_source_grep_false_confidence`). The behaviour — what the merge
// returns, what is pushed, the owner guard — is
// `progress_restore_freeze_merge_behavioral_test.dart`, which carries the
// mutation proof. What this file adds is the thing a behavioral test over a
// fixture cannot see: that the SPELLINGS the post-pass reads and writes are the
// ones its sibling writers and readers use. The local map says
// `streak_freeze_used_dates` (singular), the cloud column says
// `streak_freezes_used_dates` (plural); a post-pass that wrote the plural into
// the local map would pass a fixture built from its own spelling and the
// freeze chip would never see the ledger.
//
// Comments are stripped before every assertion
// (`feedback_source_grep_strip_comments_first`): this batch's comments spell the
// pre-fix shape in prose.
//
// Run: flutter test test/contracts/progress_restore_freeze_merge_writer_to_reader_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _stripComments(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

String _read(String path) {
  final f = File(path);
  expect(f.existsSync(), isTrue, reason: '$path moved or was renamed');
  return _stripComments(f.readAsStringSync());
}

/// The text of the `{ ... }` body that follows [signature] (first `) {` or
/// `) async {` after it), brace-matched. Fails loudly when the signature is gone
/// so a rename cannot turn a pin into a no-op.
String _bodyOf(String src, String signature) {
  final at = src.indexOf(signature);
  expect(at, isNonNegative,
      reason: '`$signature` not found - renamed? This pin would watch nothing.');
  final open = RegExp(r'\)\s*(?:async\s*)?\{').firstMatch(src.substring(at));
  expect(open, isNotNull, reason: 'no body found after `$signature`');
  var i = at + open!.end;
  final start = i;
  var depth = 1;
  while (i < src.length && depth > 0) {
    final c = src[i];
    if (c == '{') depth++;
    if (c == '}') depth--;
    i++;
  }
  return src.substring(start, i - 1);
}

Set<String> _assignedKeys(String body, String mapName) =>
    RegExp("$mapName\\['([A-Za-z0-9_]+)'\\]\\s*=")
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toSet();

void main() {
  const userRepo = 'lib/shared/repositories/user_repository.dart';
  const completeness = 'lib/core/services/sync/sync_restore_completeness.dart';

  group('the post-pass and its sibling writers spell the freeze keys alike', () {
    test('local ledger is SINGULAR, cloud column is PLURAL, and the post-pass '
        'keeps them apart', () {
      final body = _bodyOf(_read(userRepo), 'static bool _mergeFreezeFamily(');
      expect(body, contains("local['streak_freeze_used_dates']"),
          reason: 'the local ledger key is singular (workout_repository reads it)');
      expect(body, contains("cloud['streak_freezes_used_dates']"),
          reason: 'the cloud COLUMN is plural');
      expect(body, contains("merged['streak_freeze_used_dates']"),
          reason: 'the merged ledger goes into the SINGULAR local key');
      expect(body.contains("merged['streak_freezes_used_dates']"), isFalse,
          reason: 'the plural key must never be copied into the local map: the '
              'chip and the streak walk read the singular one');
    });

    test('_restoreFreezes (the other merge site) uses the same two spellings',
        () {
      final body = _bodyOf(_read(completeness), 'Future<void> _restoreFreezes(');
      expect(body, contains("res['streak_freezes_used_dates']"));
      expect(body, contains("existingMap['streak_freeze_used_dates']"));
    });

    test('every key the post-pass writes is a key _restoreFreezes also writes',
        () {
      final post = _assignedKeys(
          _bodyOf(_read(userRepo), 'static bool _mergeFreezeFamily('),
          'merged');
      final restore = _assignedKeys(
          _bodyOf(_read(completeness), 'Future<void> _restoreFreezes('),
          'existingMap');
      expect(post, isNotEmpty,
          reason: 'the post-pass writes nothing: this pin watches nothing');
      expect(restore, isNotEmpty);
      expect(restore.containsAll(post), isTrue,
          reason: 'the post-pass writes ${post.difference(restore)} that '
              '_restoreFreezes never writes: two merge sites drifting apart is '
              'how the pre-fix clobber started');
    });

    test('the loop skips exactly the cloud-side names of the family', () {
      final src = _read(userRepo);
      final at = src.indexOf('_freezeFamilyKeys');
      expect(at, isNonNegative);
      final decl = src.substring(at, src.indexOf('};', at));
      for (final k in const [
        'streak_freezes_available',
        'streak_freezes_last_refill',
        'streak_freezes_first_pro_grant_done',
        'streak_freezes_used_dates',
      ]) {
        expect(decl, contains("'$k'"),
            reason: '$k is a freeze-family cloud column the loop must skip');
      }
    });
  });

  group('both whole-row writers push what the merge kept ahead', () {
    for (final entry in const {
      'lib/core/services/sync/sync_profile.dart': 'result',
      'lib/core/services/auth_session_bootstrapper.dart': 'progressMerge',
    }.entries) {
      test('${entry.key} fires syncFreezes() on ${entry.value}.scheduleFreezeSyncUp',
          () {
        final src = _read(entry.key);
        final re = RegExp(
            '${entry.value}\\.scheduleFreezeSyncUp\\s*\\)\\s*\\{[^}]*syncFreezes\\(\\)');
        expect(re.hasMatch(src), isTrue,
            reason: 'a merge that keeps local ahead of the cloud row but whose '
                'caller never pushes is the stale-cloud clobber again, one '
                'restore later');
      });
    }

    test('syncFreezes reads the same family keys the post-pass merges', () {
      final body = _bodyOf(_read(completeness), 'Future<void> syncFreezes(');
      for (final k in const [
        'streak_freezes_available',
        'streak_freeze_used_dates',
        'streak_freezes_last_refill',
        'streak_freezes_first_pro_grant_done',
      ]) {
        expect(body, contains("'$k'"),
            reason: 'syncFreezes no longer reads $k: the push would not carry '
                'what the merge kept');
      }
    });
  });
}
