// OI-305 (2026-10-16): the three date-of-birth pickers (onboarding identity
// step, conversational onboarding step, Edit Profile) used to carry three
// different floors - 10, 16 and 13 - and now share latestAllowedDob. Source
// pins (presence only, said honestly): each picker file calls the shared helper
// and none keeps a floor literal of its own. The helper itself is
// behaviourally tested in test/utils/age_floor_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _pickers = <String>[
  'lib/features/onboarding/screens/identity_screen.dart',
  'lib/features/onboarding/screens/onboarding_chat_screen.dart',
  'lib/features/profile/screens/edit_profile_screen.dart',
];

// The exact ceiling expression each picker passes (B-pass: a bare
// `latestAllowedDob(` presence check survives `.add(Duration(days: 4000))`).
const _ceilings = <String, List<String>>{
  'lib/features/onboarding/screens/identity_screen.dart': [
    'final max = latestAllowedDob(now);',
    'lastDate: max,',
    'initialDate: seed.isAfter(max) ? max : seed,',
  ],
  'lib/features/onboarding/screens/onboarding_chat_screen.dart': [
    'lastDate: latestAllowedDob(DateTime.now()),',
  ],
  'lib/features/profile/screens/edit_profile_screen.dart': [
    'final max = latestAllowedDob(now);',
    'lastDate: max,',
    'initialDate: initial.isAfter(max) ? max : initial,',
  ],
};

String _code(String path) => File(path)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .map((l) => l.replaceFirst(RegExp(r'\s//.*$'), ''))
    .join('\n');

void main() {
  for (final path in _pickers) {
    test('$path takes its picker ceiling from latestAllowedDob', () {
      final src = _code(path);
      expect(src.contains('latestAllowedDob('), isTrue);
      expect(
        src.contains("core/utils/age_floor.dart'"),
        isTrue,
        reason: 'the import the call resolves through',
      );
    });

    test('$path passes the ceiling expression unmodified', () {
      final src = _code(path);
      for (final line in _ceilings[path]!) {
        expect(src.contains(line), isTrue, reason: 'missing: $line');
      }
    });

    test('$path keeps no age-floor literal of its own', () {
      final src = _code(path);
      // `now.year - 13`, `DateTime.now().year - 10`, `today.year - 16` ...
      expect(RegExp(r'\.year\s*-\s*1[0-9]\b').hasMatch(src), isFalse);
      expect(src.contains('365 * 16'), isFalse);
      expect(src.contains('365 * 13'), isFalse);
    });
  }

  test('no other file opens a date picker: a new one must decide its floor '
      '(add it to the list above or give it a reason)', () {
    final callers = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final src = _code(e.path);
      const openers = [
        'showDatePicker(',
        'showDateRangePicker(',
        'ScrollDatePicker(',
        'CalendarDatePicker(',
        'InputDatePickerFormField(',
        'CupertinoDatePicker(',
        'DatePickerDialog(',
      ];
      if (openers.any(src.contains)) {
        // Normalise: a Windows clone lists lib\\features\\...
        callers.add(e.path.replaceAll('\\', '/'));
      }
    }
    callers.sort();
    expect(
      callers,
      [..._pickers, 'lib/shared/widgets/scroll_date_picker.dart']..sort(),
    );
  });
}
