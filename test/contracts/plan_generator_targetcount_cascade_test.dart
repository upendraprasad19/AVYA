// Source-grep contract for plan generator targetCount (the cascade-depth half went with the cascade, Unit 1B-F).
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
    // Unit 1B-F: the source-grep for the cascade's 5-attempt shape (`_cascadeFill`, the universal pool) was
    // deleted with the cascade; the core-list path's own tests hold the picker.
  });
}
