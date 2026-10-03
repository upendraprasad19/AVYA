// test/contracts/train_provider_reads_set_number_dual_name_test.dart
//
// Drift-fix batch 2026-05-24 / T16 orphan finding.
//
// `train_provider.dart` was reading legacy `sets_completed` from exlog
// rows. The canonical Hive writer (WorkoutWriteService.logExercise)
// emits `set_number` (per docs/architecture/sync.md Hive field-name contract).
// Reader sites must prefer canonical, fall through to legacy.
//
// This test pins that every `sets_completed` read in train_provider.dart
// is accompanied by a `set_number` dual-name read on the same line.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('train_provider.dart prefers set_number over sets_completed', () {
    final file = File(
      'lib/features/train/providers/train_provider.dart',
    );
    expect(file.existsSync(), isTrue);

    final source = file.readAsStringSync();
    final stripped = _stripComments(source);

    // Every line that reads `sets_completed` must also reference
    // `set_number` (dual-name fallback per the codebase's established
    // drift pattern). Find every line with `sets_completed` and
    // assert it also contains `set_number`.
    final lines = stripped.split('\n');
    final violations = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('sets_completed') && !line.contains('set_number')) {
        // Look at adjacent lines too — sometimes the dual-name is on
        // the previous or next line in a multiline expression.
        final before = i > 0 ? lines[i - 1] : '';
        final after = i + 1 < lines.length ? lines[i + 1] : '';
        if (!before.contains('set_number') && !after.contains('set_number')) {
          violations.add('train_provider.dart:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Every `sets_completed` read in train_provider.dart '
          'must be paired with a `set_number` canonical-first read. '
          'Violations:\n${violations.join('\n')}',
    );
  });
}

String _stripComments(String src) {
  final block = RegExp(r'/\*[\s\S]*?\*/');
  var out = src.replaceAll(block, '');
  final line = RegExp(r'//.*');
  out = out.replaceAll(line, '');
  return out;
}
