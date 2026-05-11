// C-11 (audit-2026-05-11) — regression test that all 3
// `TemplatesNotifier` mutation methods fire the workout-domain
// fan-out + snapshot push. Pre-fix only `deleteTemplate` fired
// `pushSnapshot` (and even that missed `syncWorkoutData`), so newly
// created or edited templates silently never reached cloud until the
// next weekly full sync; deleted templates re-appeared on restore.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

/// Slice the body of a named `Future<void> X(` method.
String _methodBody(String src, String signature) {
  final idx = src.indexOf(signature);
  if (idx < 0) return '';
  // Find the opening `{` after the parameter list, then walk the
  // matching braces.
  final openBraceIdx = src.indexOf('{', idx + signature.length);
  if (openBraceIdx < 0) return '';
  var depth = 1;
  var i = openBraceIdx + 1;
  while (i < src.length && depth > 0) {
    final ch = src[i];
    if (ch == '{') depth++;
    if (ch == '}') depth--;
    i++;
  }
  return src.substring(idx, i);
}

void main() {
  const path = 'lib/features/train/providers/train_provider.dart';

  group('C-11 TemplatesNotifier sync fan-out', () {
    test('saveTemplate fires syncWorkoutData + pushSnapshot', () {
      final body =
          _methodBody(_src(path), 'Future<void> saveTemplate(');
      expect(body, isNotEmpty,
          reason: 'saveTemplate must exist on TemplatesNotifier');
      expect(
        body,
        contains('unawaited(SyncService.instance.syncWorkoutData())'),
        reason:
            'saveTemplate must call syncWorkoutData so new tmpl_* rows '
            'reach workout_templates / template_exercises cloud tables '
            'immediately (CLAUDE.md §15 Sync fan-out contract).',
      );
      expect(
        body,
        contains('unawaited(SyncService.instance.pushSnapshot())'),
        reason:
            'saveTemplate must call pushSnapshot so AI coach context '
            'reflects the new template without waiting for cold-start.',
      );
    });

    test('updateTemplate fires syncWorkoutData + pushSnapshot', () {
      final body =
          _methodBody(_src(path), 'Future<void> updateTemplate(');
      expect(body, isNotEmpty,
          reason: 'updateTemplate must exist on TemplatesNotifier');
      expect(
        body,
        contains('unawaited(SyncService.instance.syncWorkoutData())'),
        reason:
            'updateTemplate must call syncWorkoutData so edited '
            'tmpl_* rows reach cloud immediately.',
      );
      expect(
        body,
        contains('unawaited(SyncService.instance.pushSnapshot())'),
        reason:
            'updateTemplate must call pushSnapshot so AI coach picks '
            'up the rename / new exercise list.',
      );
    });

    test('deleteTemplate fires syncWorkoutData + pushSnapshot', () {
      final body =
          _methodBody(_src(path), 'Future<void> deleteTemplate(');
      expect(body, isNotEmpty,
          reason: 'deleteTemplate must exist on TemplatesNotifier');
      expect(
        body,
        contains('unawaited(SyncService.instance.syncWorkoutData())'),
        reason:
            'deleteTemplate must call syncWorkoutData so the cloud '
            'workout_templates row is deleted in the same fan-out. '
            'Pre-fix only pushSnapshot ran, leaving the cloud row '
            'orphaned — next restore re-imported the "deleted" '
            'template.',
      );
      expect(
        body,
        contains('unawaited(SyncService.instance.pushSnapshot())'),
        reason:
            'deleteTemplate must call pushSnapshot so AI coach stops '
            'referencing the deleted template immediately.',
      );
    });
  });
}
