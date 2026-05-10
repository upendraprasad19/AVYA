// APK Test #14 / Bug B.1 — pins the sequencing rule that
// `_syncWorkoutTemplates` MUST complete before `_syncScheduledWorkouts`
// in every combined push path.
//
// Pre-fix both ran inside `Future.wait` in `weeklyFullSync` and
// `syncWorkoutData`. On a cold-start where templates haven't reached
// cloud yet, the schedule push races ahead and FK-references a
// `workout_templates.id` that doesn't exist → 23503.
//
// This test source-greps both call sites for the pattern:
//   • `_syncWorkoutTemplates` is `await`-ed sequentially before the
//     `Future.wait` that contains `_syncScheduledWorkouts`
//   • `_syncWorkoutTemplates` does NOT appear inside the same
//     `Future.wait([...])` as `_syncScheduledWorkouts`
//
// See docs/diagnoses/2026-05-10-fk-violation-saturday-c8e4a1.md.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(
    'templates → schedules sequencing (APK Test #14 / Bug B.1)',
    () {
      late String src;

      setUpAll(() {
        src = File('lib/core/services/sync_service.dart').readAsStringSync();
      });

      /// Extract a method body by locating the signature line and
      /// reading source until the next top-level method signature
      /// (`  Future<...>` / `  Stream<...>` / `  void ` / `  static `
      /// at exactly 2-space indent — same column as the target). Avoids
      /// fragile balanced-brace regex.
      ///
      /// Comments are stripped from the result so `body.indexOf('foo')`
      /// only matches CODE references, not commentary about the bad
      /// pattern.
      String extractMethodBody(String source, String signaturePattern) {
        final sigRe = RegExp(signaturePattern);
        final sigMatch = sigRe.firstMatch(source);
        if (sigMatch == null) return '';
        final start = sigMatch.end;
        // Find the next top-level method declaration on a line
        // starting with 2 spaces (class member indent).
        final nextRe = RegExp(
          r'\n {2}(?:Future<|Stream<|void |static |[A-Z][A-Za-z]*\??\s+\w+\()',
        );
        final nextMatch = nextRe.firstMatch(source.substring(start));
        final end = nextMatch != null ? start + nextMatch.start : source.length;
        final raw = source.substring(start, end);
        // Strip line + block comments to avoid commentary false-positives.
        return raw
            .replaceAll(RegExp(r'//.*'), '')
            .replaceAll(RegExp(r'/\*[\s\S]*?\*/', multiLine: true), '');
      }

      test('weeklyFullSync awaits sync_templates before parallel batch', () {
        final body = extractMethodBody(
          src,
          r'Future<void>\s+weeklyFullSync\(\)\s*async\s*\{',
        );
        expect(body, isNotEmpty,
            reason: 'weeklyFullSync method body must be extractable');

        final templateAwaitIdx = body.indexOf("_syncWorkoutTemplates(userId)");
        final futureWaitIdx = body.indexOf('Future.wait');
        expect(templateAwaitIdx, isNonNegative,
            reason: '_syncWorkoutTemplates must appear in weeklyFullSync');
        expect(futureWaitIdx, isNonNegative,
            reason: 'Future.wait must appear in weeklyFullSync');
        expect(
          templateAwaitIdx < futureWaitIdx,
          isTrue,
          reason:
              '_syncWorkoutTemplates must be sequenced BEFORE the Future.wait '
              'parallel batch, not inside it',
        );
      });

      test(
          'weeklyFullSync Future.wait does NOT contain _syncWorkoutTemplates',
          () {
        final futureWaitMatch = RegExp(
          r'Future\.wait\s*\(\s*\[([\s\S]*?)\]\s*,\s*eagerError:\s*false',
          multiLine: true,
        ).allMatches(src);
        expect(futureWaitMatch, isNotEmpty);

        for (final m in futureWaitMatch) {
          final block = m.group(1)!;
          // Schedule push lives inside one of these blocks; ensure
          // template push does NOT.
          if (block.contains('_syncScheduledWorkouts(userId)')) {
            expect(
              block.contains('_syncWorkoutTemplates(userId)'),
              isFalse,
              reason:
                  '_syncWorkoutTemplates must NOT be in the same Future.wait '
                  'as _syncScheduledWorkouts (templates run sequentially first)',
            );
          }
        }
      });

      test('syncWorkoutData awaits sync_workout_templates before parallel batch',
          () {
        final body = extractMethodBody(
          src,
          r'Future<void>\s+syncWorkoutData\(\)\s*async\s*\{',
        );
        expect(body, isNotEmpty,
            reason: 'syncWorkoutData method body must be extractable');

        final templateAwaitIdx = body.indexOf("_syncWorkoutTemplates(userId)");
        final futureWaitIdx = body.indexOf('Future.wait');
        expect(templateAwaitIdx, isNonNegative,
            reason: '_syncWorkoutTemplates must appear in syncWorkoutData');
        expect(futureWaitIdx, isNonNegative,
            reason: 'Future.wait must appear in syncWorkoutData');
        expect(
          templateAwaitIdx < futureWaitIdx,
          isTrue,
          reason:
              '_syncWorkoutTemplates must be sequenced BEFORE the Future.wait '
              'parallel batch in syncWorkoutData too',
        );
      });
    },
  );
}
