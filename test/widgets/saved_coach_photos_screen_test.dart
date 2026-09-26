// test/widgets/saved_coach_photos_screen_test.dart
//
// Unit 8 (coach-media-consent, OI-25) — B-pass finding (2026-07-30):
// _delete() had no failure-feedback branch. Source-grep, honestly labelled
// as such (feedback_source_grep_false_confidence.md) — CoachMediaRepository
// has no dependency-injection seam for mocking a failed live Storage
// delete (same reason coach_media_repository_test.dart's Storage-call
// pins are source-grep too), so this pins the fix's shape rather than
// simulating the actual async failure.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SavedCoachPhotosScreen._delete failure feedback', () {
    late String src;
    setUpAll(() {
      src = File('lib/features/profile/screens/saved_coach_photos_screen.dart')
          .readAsStringSync();
    });

    test('shows a SnackBar when CoachMediaRepository.delete returns false',
        () {
      final repoCallIdx = src.indexOf('final ok = await _repo.delete(path);');
      expect(repoCallIdx, greaterThan(-1),
          reason: '_delete\'s repo call moved or was renamed — re-baseline');

      final body =
          src.substring(repoCallIdx, (repoCallIdx + 700).clamp(0, src.length));
      final snackBarIdx = body.indexOf('showSnackBar');
      expect(snackBarIdx, greaterThan(-1),
          reason: 'a failed delete (repo returns false) must surface a '
              'SnackBar — silently doing nothing is indistinguishable from '
              'a success that just did not refresh the grid');
    });

    test('the success path still returns before reaching the SnackBar '
        '(no double-feedback on a successful delete)', () {
      final repoCallIdx = src.indexOf('final ok = await _repo.delete(path);');
      final body =
          src.substring(repoCallIdx, (repoCallIdx + 700).clamp(0, src.length));
      final ifOkIdx = body.indexOf('if (ok)');
      final returnIdx = body.indexOf('return;', ifOkIdx);
      final snackBarIdx = body.indexOf('showSnackBar');
      expect(ifOkIdx, greaterThan(-1));
      expect(returnIdx, greaterThan(ifOkIdx));
      expect(snackBarIdx, greaterThan(-1));
      expect(returnIdx, lessThan(snackBarIdx),
          reason: 'the success branch must return before the SnackBar '
              'code, or a successful delete would also show a failure '
              'toast');
    });
  });
}
