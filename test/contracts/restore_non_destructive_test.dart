// APK Test #14 / Bug B.2 — pins the timestamp-aware merge in
// `_restoreScheduledWorkouts`. Pre-fix this method was unconditionally
// cloud-authoritative on `status` and `completed_at`, which destroyed
// local 'completed' state any time `_syncScheduledWorkouts` push had
// failed (Bug B.1). Cloud still held the older 'planned' row and the
// restore overwrote the fresher local copy.
//
// Source-grep contract test pinning the conditional logic.
//
// See docs/diagnoses/2026-05-10-restore-overwrite-d9b2c5.md.

import 'package:flutter_test/flutter_test.dart';

import '_sync_service_source.dart';

void main() {
  group(
    '_restoreScheduledWorkouts non-destructive merge (APK Test #14 / Bug B.2)',
    () {
      late String src;

      setUpAll(() {
        src = loadSyncServiceSource().readAsStringSync();
      });

      test('reads existing local status before merge (`localStatus`)', () {
        expect(
          src.contains('localStatus'),
          isTrue,
          reason:
              'Merge must inspect local status — pre-fix it was thrown away',
        );
      });

      test('compareTo is used for timestamp-newest-wins logic', () {
        // The "both completed, newest wins" branch uses .compareTo on
        // ISO strings.
        expect(
          src.contains('localCompletedAt.compareTo(cloudCompletedAt)'),
          isTrue,
          reason:
              'Both-completed branch must compare timestamps via compareTo',
        );
      });

      test('keep-local-when-cloud-stale conditional present', () {
        // The defining branch: local completed + cloud planned + local
        // has completed_at → keep local.
        final hasConditional = src.contains(
              "localStatus == 'completed' &&",
            ) &&
            src.contains("cloudStatus == 'planned'");
        expect(
          hasConditional,
          isTrue,
          reason:
              'Merge must contain the "local completed + cloud planned → keep local" branch',
        );
      });

      test(
        'forbidden: bare unconditional `\'status\': cloudStatus` overlay absent',
        () {
          // Pre-fix the merge always wrote cloud's status under a
          // simple `if (cloudStatus != null && cloudStatus.isNotEmpty)`
          // gate. Post-fix it writes `mergedStatus` (the conditional
          // result). Strip comments first so old commentary doesn't
          // false-positive.
          final stripped = src
              .replaceAll(RegExp(r'//.*'), '')
              .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '');

          // The merge block writes `mergedStatus`, not `cloudStatus`.
          expect(
            stripped.contains("'status': mergedStatus"),
            isTrue,
            reason: 'Merge must write the conditional result mergedStatus',
          );
          // Sanity: ensure the exact pre-fix line is gone. The old
          // shape had `'status': cloudStatus` directly inside the
          // merged map.
          expect(
            stripped.contains("'status': cloudStatus,"),
            isFalse,
            reason:
                'Pre-fix unconditional cloud overlay `\'status\': cloudStatus,` must be removed',
          );
        },
      );
    },
  );
}
