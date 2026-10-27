// Batch A Task 1 (docs/plans/2026-10-22-library-data-repair.md) — the bundled
// library's coaching text sits in the right fields, one cue per list item.
//
// Before the repair, 136 rows had every text field shifted one column to the
// right (OI-149): breathing_cue held a number, coaching_cues held the breathing
// text, common_mistakes held the cues, warmup_protocol held the mistakes and
// pro_tip held the warm-up. Healthy rows stored their cues as ONE "; "-joined
// string, which coaching_content_panel.dart renders as a single packed bullet.
//
// The pinned E013 / E064 values were computed from the pre-repair file with the
// plan's mapping (2026-10-22 dry-run), not read back from the repaired file.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _numeric = RegExp(r'^\d+(\.\d+)?$');

void main() {
  final rows = (jsonDecode(
    File('assets/data/exercise_library.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, dynamic>>();
  Map<String, dynamic> row(String id) => rows.singleWhere((r) => r['id'] == id);

  group('exercise_library coaching text (OI-149 repair)', () {
    test('no row has a numeric breathing_cue', () {
      final numeric = rows
          .where((r) => _numeric.hasMatch((r['breathing_cue'] as String).trim()))
          .map((r) => r['id'])
          .toList();
      expect(numeric, isEmpty, reason: 'shifted rows remain: $numeric');
    });

    test('coaching_cues and common_mistakes are non-empty lists of single items',
        () {
      final offenders = <String>[];
      for (final r in rows) {
        for (final key in ['coaching_cues', 'common_mistakes']) {
          final v = r[key];
          if (v is! List || v.isEmpty) {
            offenders.add('${r['id']}.$key empty or not a list');
            continue;
          }
          for (final item in v) {
            if (item is! String || item.trim().isEmpty || item.contains(';')) {
              offenders.add('${r['id']}.$key item "$item"');
            }
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.take(10).join('\n'));
    });

    test('E013 Lateral Raise is repaired into the right columns', () {
      final r = row('E013');
      expect(r['breathing_cue'], 'Natural breathing');
      expect(r['coaching_cues'],
          ['Slight forward lean', 'lead with elbows not hands', 'stop at shoulder height']);
      expect(r['common_mistakes'],
          ['Swinging body', 'going above shoulder height', 'too heavy']);
      expect(r['warmup_protocol'], 'None needed');
      expect(r['met_value'], 3.0);
      expect(r['cal_per_set_est'], 5.0);
      expect(r['pro_tip'], '');
    });

    test('E064 Rowing Machine (the one multi-item cue list) is repaired', () {
      final r = row('E064');
      expect(r['breathing_cue'], 'Exhale on the drive (pull)');
      expect(r['coaching_cues'], [
        'Legs first, then lean back, then pull',
        'reverse on return',
        'keep back straight',
      ]);
      expect(r['common_mistakes'],
          ['Pulling with arms first', 'rounding back', 'rushing the stroke']);
      expect(r['cal_per_set_est'], 18.0);
    });

    test('the Indian fields the shift had pushed into source are recovered', () {
      for (final id in ['E076', 'E077', 'E078', 'E200']) {
        expect(row(id)['is_indian_context'], isTrue, reason: id);
      }
      for (final id in ['E054', 'E061', 'E062', 'E063', 'E076', 'E077', 'E078', 'E200']) {
        expect((row(id)['indian_alternative'] as String).trim(), isNotEmpty,
            reason: id);
      }
    });

    test('met_value and cal_per_set_est decode as doubles', () {
      final offenders = <String>[];
      for (final r in rows) {
        for (final key in ['met_value', 'cal_per_set_est']) {
          final v = r[key];
          if (v != null && v is! double) offenders.add('${r['id']}.$key=$v');
        }
      }
      expect(offenders, isEmpty, reason: offenders.take(10).join(', '));
    });
  });
}
