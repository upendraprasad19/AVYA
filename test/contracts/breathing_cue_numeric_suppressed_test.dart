// test/contracts/breathing_cue_numeric_suppressed_test.dart
//
// 136 of 292 rows carry a bare number in breathing_cue — a spreadsheet column
// shift that dropped met_value into the field and left its own column null,
// live in the shipped app. BOTH surfaces that render it must suppress a numeric
// value; guarding only the new sheet would leave two surfaces disagreeing about
// one field, which is the writer/reader drift class this repo has hit 15+ times.
//
// The data repair is OI-149 — blocked on the founder, because the original cues
// exist nowhere: the field is absent from all 20 columns of both seed
// migrations, and all 19 git revisions of the library carry the numeric value.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//.*'), '');

void main() {
  const surfaces = [
    'lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart',
    'lib/features/train/screens/active_workout/coaching_content_panel.dart',
  ];

  test('both breathing_cue surfaces guard against a numeric value', () {
    for (final p in surfaces) {
      final src = _strip(File(p).readAsStringSync());
      expect(src.contains(r'^\d+(\.\d+)?$'), isTrue,
          reason: '$p renders breathing_cue without the numeric guard');
    }
  });

  test('the defect is still exactly 136 rows — if this moves, re-read OI-149',
      () {
    final lib =
        (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
                as List)
            .cast<Map<String, dynamic>>();
    final numeric = lib
        .where((e) => RegExp(r'^\d+(\.\d+)?$').hasMatch('${e['breathing_cue']}'))
        .length;
    final nullMet = lib.where((e) => e['met_value'] == null).length;
    expect(numeric, 136);
    // The two sets coincide exactly — that is what identifies it as a column
    // shift rather than 136 unrelated bad values.
    expect(nullMet, 136);
  });
}
