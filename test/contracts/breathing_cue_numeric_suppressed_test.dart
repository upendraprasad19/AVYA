// test/contracts/breathing_cue_numeric_suppressed_test.dart
//
// Until 2026-10-22, 136 of 292 rows carried a bare number in breathing_cue: a
// spreadsheet column shift had moved every field from met_value to source one
// place right (OI-149). BOTH surfaces that render the field suppress a numeric
// value; guarding only one would leave two surfaces disagreeing about one
// field, the writer/reader drift class this repo has hit 15+ times. The guards
// stay after the data repair, because a future library edit can re-introduce
// the shape.
//
// OI-149 was CLOSED by the Batch A repair (docs/plans/2026-10-22-library-data-
// repair.md): the text was never lost, only shifted. The field order and the
// repaired values are pinned in exercise_library_text_shape_contract_test.dart.
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

  test('0 numeric breathing_cue rows remain (OI-149 repaired)', () {
    final lib =
        (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
                as List)
            .cast<Map<String, dynamic>>();
    final numeric = lib
        .where((e) => RegExp(r'^\d+(\.\d+)?$').hasMatch('${e['breathing_cue']}'))
        .map((e) => e['id'])
        .toList();
    expect(numeric, isEmpty);
    // The shift's other fingerprint: met_value was null on exactly the same
    // rows. After the repair no row has lost it.
    expect(lib.where((e) => e['met_value'] == null).map((e) => e['id']),
        isEmpty);
  });
}
