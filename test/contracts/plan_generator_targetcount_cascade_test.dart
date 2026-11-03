// Source-grep contract for plan generator targetCount + cascade depth.
//
// Originally landed as T-10 of `audit_2026_05_11_t1_t11_contracts_test.dart`.
// Split per concept per tech-debt audit 2026-05-20 T12.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('T-10 plan generator targetCount + cascade depth', () {
    test('VolumeFilter keeps every slot but the deload rule (targetCount deleted)',
        () {
      final src =
          _src('lib/shared/repositories/plan_engine/volume_filter.dart');
      // Comments are stripped: the doc comment names the deleted table.
      final code = src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(code.contains('targetCount'), isFalse,
          reason: 'the fixed-count table was deleted with the B2 flip');
      expect(src.contains("weekCharacter == 'deload'"), isTrue,
          reason: 'the deload (priority-1 only) rule must stay');
    });

    test('exercise_selector cascade has the 5-attempt pattern', () {
      final src = _src(
          'lib/shared/repositories/plan_engine/exercise_selector.dart');
      // Per lib/shared/repositories/plan_engine/CLAUDE.md the cascade has 5 attempts ending in
      // universalPool. The canonical entry point is `_cascadeFill`
      // and the comment "5-attempt cascade" / "5 attempts" pins the
      // shape.
      expect(src.contains('_cascadeFill'), isTrue,
          reason: '_cascadeFill cascade entry point must exist.');
      expect(
        src.contains('5-attempt') ||
            src.contains('5 attempt') ||
            src.contains('5 attempts'),
        isTrue,
        reason: 'cascade must be documented as 5-attempt per lib/shared/repositories/plan_engine/CLAUDE.md.',
      );
      expect(src.contains('universalPool'), isTrue,
          reason: 'universalPool fallback must exist (terminal attempt).');
    });
  });
}
