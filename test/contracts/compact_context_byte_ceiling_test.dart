// Source-grep contract for _compactContext 9500-byte ceiling.
//
// Originally landed as T-9 of `audit_2026_05_11_t1_t11_contracts_test.dart`.
// Split per concept per tech-debt audit 2026-05-20 T12.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('T-9 _compactContext 9500-byte ceiling', () {
    test('AiService._compactContext targets <9500 bytes', () {
      final src = _src('lib/core/services/ai_service.dart');
      expect(src.contains('_compactContext'), isTrue);
      // Target threshold must be present somewhere in the file.
      expect(
        src.contains('9500') ||
            src.contains('9_500') ||
            src.contains('compactionTarget'),
        isTrue,
        reason: '_compactContext must enforce a target under the '
            '10KB server limit (9500 bytes per docs/architecture/ai.md). Without '
            'the ceiling, historical-query enriched contexts blow past '
            'the limit and the server rejects with 400.',
      );
    });
  });
}
