// Contract test — every `ref.invalidate(...)` / `ref.invalidateSelf()` call
// inside a Notifier method in nutrition_provider.dart that follows an
// `await` must be guarded by `if (ref.mounted)`.
//
// Diagnose b7f3e2 fixed FoodLogNotifier.logFood's UnmountedRefException
// (a widget tree disposed while an awaited write was still in flight makes
// the following ref.invalidate throw). The B-pass on that fix
// (docs/reviews/merge-reconciliation-82844bfd-review.md, Finding 2) found 6
// MORE call sites in this same file with the identical shape, unguarded:
// FoodLogNotifier.deleteFoodLog, SavedMealsNotifier.{saveMealPreset,
// relogSavedMeal,deleteSavedMeal}, ScanMealNotifier.scanImage,
// CartAuditorNotifier.analyseCart. All 7 are now fixed with the same guard.
//
// This test is source-grep, not behavioral (the same accepted limitation as
// b7f3e2's own original regression test: the race is timing-dependent on
// full-suite concurrency and not reliably reproducible in isolation). It
// pins PRESENCE of the guard at every known call site and, by scanning the
// whole file rather than naming line numbers, catches a FUTURE unguarded
// `ref.invalidate`/`ref.invalidateSelf()` addition too.

import 'dart:io';
import 'package:test/test.dart';

const _providerPath =
    'lib/features/nutrition/providers/nutrition_provider.dart';

void main() {
  group('nutrition_provider ref.mounted guard (diagnose b7f3e2)', () {
    late List<String> lines;

    setUpAll(() {
      lines = File(_providerPath).readAsLinesSync();
    });

    /// Returns the nearest non-blank, non-comment line ABOVE [index],
    /// skipping blank lines and lines that are pure `//` comments.
    String? nearestCodeLineAbove(int index) {
      for (var i = index - 1; i >= 0; i--) {
        final trimmed = lines[i].trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.startsWith('//')) continue;
        return trimmed;
      }
      return null;
    }

    test('every ref.invalidate(...) call is guarded by ref.mounted', () {
      final callSites = <int>[];
      final callRegex = RegExp(r'ref\.invalidate\(');
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.startsWith('//')) continue; // skip comment-only lines
        if (callRegex.hasMatch(lines[i])) callSites.add(i);
      }

      expect(callSites.length, greaterThanOrEqualTo(3),
          reason: 'Expected at least the 3 known ref.invalidate(...) call '
              'sites (logFood, deleteFoodLog, scanImage/cart_auditor share '
              'the pattern) -- found ${callSites.length}. If this dropped, '
              'a call site may have been removed or renamed; if it grew, '
              'the new site needs its own ref.mounted guard verified below.');

      for (final i in callSites) {
        final guardLine = nearestCodeLineAbove(i);
        expect(
          guardLine,
          contains('if (ref.mounted)'),
          reason: 'lib/features/nutrition/providers/nutrition_provider.dart:'
              '${i + 1} -- "${lines[i].trim()}" is not directly preceded by '
              'an `if (ref.mounted)` guard (found: "$guardLine"). Every '
              'ref.invalidate call following an await must check '
              'ref.mounted first (diagnose b7f3e2).',
        );
      }
    });

    test('every ref.invalidateSelf() call is guarded by ref.mounted', () {
      final callSites = <int>[];
      final callRegex = RegExp(r'ref\.invalidateSelf\(\)');
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.startsWith('//')) continue; // skip comment-only lines
        if (callRegex.hasMatch(lines[i])) callSites.add(i);
      }

      expect(callSites.length, greaterThanOrEqualTo(3),
          reason: 'Expected at least the 3 known ref.invalidateSelf() call '
              'sites (saveMealPreset, relogSavedMeal, deleteSavedMeal) -- '
              'found ${callSites.length}.');

      for (final i in callSites) {
        final guardLine = nearestCodeLineAbove(i);
        expect(
          guardLine,
          contains('if (ref.mounted)'),
          reason: 'lib/features/nutrition/providers/nutrition_provider.dart:'
              '${i + 1} -- "${lines[i].trim()}" is not directly preceded by '
              'an `if (ref.mounted)` guard (found: "$guardLine"). Every '
              'ref.invalidateSelf call following an await must check '
              'ref.mounted first (diagnose b7f3e2).',
        );
      }
    });
  });
}
