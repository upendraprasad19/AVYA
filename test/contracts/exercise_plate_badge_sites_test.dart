// test/contracts/exercise_plate_badge_sites_test.dart
//
// A source-grep contract. It cannot prove the widget renders — the widget tests
// do that — but it CAN prove no site silently reverts to the numeric badge,
// which a widget test on one screen would miss.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _sites = [
  'lib/features/train/screens/active_workout/exercise_card.dart',
  'lib/features/train/widgets/expandable_day_card.dart',
  'lib/features/home/widgets/day_detail_sheet.dart',
];

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//.*'), '');

void main() {
  test('all three badge sites render the thumb and open the sheet', () {
    for (final p in _sites) {
      final src = _strip(File(p).readAsStringSync());
      expect(src.contains('ExercisePlateThumb'), isTrue, reason: '$p: no thumb');
      expect(src.contains('ExercisePlateSheet.show'), isTrue,
          reason: '$p: the thumb opens nothing');
    }
  });

  test('no site still renders a bare index badge', () {
    for (final p in _sites) {
      final src = _strip(File(p).readAsStringSync());
      expect(
          RegExp(r"\$\{\s*(widget\.)?(exerciseIndex|index)\s*\+\s*1\s*\}")
              .hasMatch(src),
          isFalse,
          reason: '$p still renders the numeric badge the thumb replaced');
    }
  });

  test('the FORM & CUES bar offers the plate as a second door', () {
    final src = _strip(File(
            'lib/features/train/screens/active_workout/coaching_content_panel.dart')
        .readAsStringSync());
    expect(src.contains('ExercisePlateSheet.show'), isTrue,
        reason: 'the expanded card has no route to the plate');
  });

  test('the SoT registry carries the plate read path, with line ranges', () {
    final y = File('docs/sot_registry.yaml').readAsStringSync();
    expect(y.contains('concept: exercise_plate_read_path'), isTrue,
        reason: 'the new writer/reader contract is unregistered');
    // Take the WHOLE entry, to the next concept or EOF. A fixed-size window
    // cut off the writers/readers block, whose line_range keys are the point.
    final i = y.indexOf('concept: exercise_plate_read_path');
    final next = y.indexOf('\n  - concept:', i);
    final w = y.substring(i, next == -1 ? y.length : next);
    expect(w.contains('behavioral_test_path:'), isTrue,
        reason: 'rule 21 is strict — a bare registry entry blocks the commit');
    // Without line_range BOTH registry validators skip the entry entirely, so
    // it would pass rule 21's gate while nothing ever checks its citations.
    expect(w.contains('line_range:'), isTrue);
  });

  test('demo_slug and demo_pair are in the naming glossary (§4.7)', () {
    final n = File('docs/naming_conventions.md').readAsStringSync();
    expect(n.contains('demo_slug'), isTrue);
    expect(n.contains('demo_pair'), isTrue);
  });

  test('sync_community cannot strip demo_slug — the add-only guard is pinned',
      () {
    // NOTE: this one is GREEN TODAY. It is a pin against future relaxation, not
    // a red-first test. Saying so because asserting a red state without running
    // it is exactly the class that produced an earlier unfalsifiable test here.
    final src = _strip(
        File('lib/core/services/sync/sync_community.dart').readAsStringSync());
    expect(src.contains('exerciseBox.get(id) == null'), isTrue,
        reason: 'the add-only guard was relaxed; community sync can now '
            'overwrite a library row and strip demo_slug');
  });

  test('the batch closure ledger exists and is terminal', () {
    final f = File('docs/audit/exercise-plates.closure.yaml');
    expect(f.existsSync(), isTrue,
        reason: '§4.2 requires one for a batch of ≥4 units');
    // A line-anchored KEY, not a substring. The ledger's own header comment
    // says "no `deferred:` key", and a substring check matched that — the
    // self-matching-check class, in the test written to catch deferrals.
    expect(RegExp(r'^\s*deferred:', multiLine: true)
            .hasMatch(f.readAsStringSync()),
        isFalse,
        reason: 'the schema has no deferred key');
  });
}
