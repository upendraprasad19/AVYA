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

  // Audit 2026-05-20 / A3: TemplatesNotifier.saveTemplate + updateTemplate
  // routed through WorkoutWriteService.upsertTemplate (which itself fires
  // syncWorkoutData + pushSnapshot in the canonical body). Per
  // feedback_source_grep_false_confidence, tests accept EITHER the legacy
  // direct call OR the canonical WriteService route.
  group('C-11 TemplatesNotifier sync fan-out', () {
    test('saveTemplate fires syncWorkoutData via WriteService or directly', () {
      final body =
          _methodBody(_src(path), 'Future<void> saveTemplate(');
      expect(body, isNotEmpty,
          reason: 'saveTemplate must exist on TemplatesNotifier');
      final routedThroughWriteService =
          body.contains('WorkoutWriteService.instance.upsertTemplate');
      final firesSyncWorkoutData = body
              .contains('unawaited(SyncService.instance.syncWorkoutData())') ||
          routedThroughWriteService;
      expect(firesSyncWorkoutData, isTrue,
          reason:
              'saveTemplate must EITHER directly call syncWorkoutData OR '
              'route through WorkoutWriteService.upsertTemplate (which '
              'fires syncWorkoutData internally). CLAUDE.md §15 Sync '
              'fan-out contract.');

      final firesPushSnapshot = body
              .contains('unawaited(SyncService.instance.pushSnapshot())') ||
          routedThroughWriteService;
      expect(firesPushSnapshot, isTrue,
          reason:
              'saveTemplate must EITHER call pushSnapshot directly OR '
              'route through WorkoutWriteService.upsertTemplate.');
    });

    test('updateTemplate fires syncWorkoutData via WriteService or directly', () {
      final body =
          _methodBody(_src(path), 'Future<void> updateTemplate(');
      expect(body, isNotEmpty,
          reason: 'updateTemplate must exist on TemplatesNotifier');
      final routedThroughWriteService =
          body.contains('WorkoutWriteService.instance.upsertTemplate');
      final firesSyncWorkoutData = body
              .contains('unawaited(SyncService.instance.syncWorkoutData())') ||
          routedThroughWriteService;
      expect(firesSyncWorkoutData, isTrue,
          reason:
              'updateTemplate must EITHER directly call syncWorkoutData OR '
              'route through WorkoutWriteService.upsertTemplate.');

      final firesPushSnapshot = body
              .contains('unawaited(SyncService.instance.pushSnapshot())') ||
          routedThroughWriteService;
      expect(firesPushSnapshot, isTrue,
          reason:
              'updateTemplate must EITHER call pushSnapshot directly OR '
              'route through WorkoutWriteService.upsertTemplate.');
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
