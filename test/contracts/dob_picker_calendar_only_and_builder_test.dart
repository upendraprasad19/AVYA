// Regression contract for bug e2b8a4's round-1 review findings (2026-09-19):
//
// Finding 1 — `lib/features/profile/screens/edit_profile_screen.dart`'s
// `_pickDateOfBirth()` had NO `builder:` at all, so it never received the
// `datePickerTheme.dayStyle/yearStyle/weekdayStyle` explicit-style fix that
// `identity_screen.dart`'s onboarding DOB picker got for the original Bug 1
// (4-digit years / 2-digit days wrapping in fixed-size grid cells). This is
// the SAME live bug, on a second real call site nobody re-grepped for when
// Bug 1 was first fixed — a user editing their DOB from Profile (rather
// than during onboarding) would still hit it. Fixed by wiring the same
// `builder: responsivePickerBuilder` used by `identity_screen.dart`.
//
// Finding 2 — NEITHER real `showDatePicker` call site set `initialEntryMode`,
// so both defaulted to `DatePickerEntryMode.calendar`, which — like
// `showTimePicker`'s default dial mode (bug e2b8a4's OTHER finding, see
// wake_workout_time_picker_dial_only_test.dart) — always shows a
// keyboard-toggle icon that switches to a differently-sized fixed layout
// never verified safe at MobileFrame's narrow web content width. Fixed by
// adding `initialEntryMode: DatePickerEntryMode.calendarOnly` to both real
// call sites, removing the toggle (and the input-mode layout it reaches)
// entirely — the same fix shape already applied to the time pickers.
//
// Same two-layer approach as the time-picker test: a source-grep pinning
// THIS APP's parameter choice at both real call sites (presence-only, but
// honest about what it proves), plus a behavioral test proving
// `calendarOnly` genuinely removes the toggle icon — which pins Flutter's
// own contract, not app code, so a future Flutter change to that behavior
// would be caught here too.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  group('e2b8a4 round 1 — DOB pickers pin builder + DatePickerEntryMode.calendarOnly',
      () {
    test(
        'source: edit_profile_screen.dart\'s _pickDateOfBirth uses the '
        'responsive builder AND calendarOnly', () {
      final source = File(
        'lib/features/profile/screens/edit_profile_screen.dart',
      ).readAsStringSync();

      final pickDob = RegExp(
        r'Future<void>\s+_pickDateOfBirth\(\)[\s\S]*?\n  \}',
      ).firstMatch(source);

      expect(pickDob, isNotNull,
          reason: 'e2b8a4: _pickDateOfBirth must still exist at this name — '
              'if it moved, repoint this regex rather than deleting the test');

      expect(pickDob!.group(0), contains('builder: responsivePickerBuilder'),
          reason: 'e2b8a4 round-1 finding: _pickDateOfBirth\'s showDatePicker '
              'must pass builder: responsivePickerBuilder — its absence '
              'reopens the SAME DM-Sans-family day/year-cell wrap Bug 1 was '
              'supposed to have fixed everywhere, on this second real DOB '
              'surface');
      expect(pickDob.group(0), contains('DatePickerEntryMode.calendarOnly'),
          reason: 'e2b8a4 round-1 finding: _pickDateOfBirth\'s showDatePicker '
              'must pass initialEntryMode: DatePickerEntryMode.calendarOnly '
              '— its absence reopens the keyboard-toggle path into an '
              'input-mode layout never verified safe at MobileFrame\'s '
              'narrow web width');

      // Also pin the import, since the builder reference alone would
      // silently compile-fail without it — a missing import is a distinct
      // failure mode from a missing parameter and deserves its own message.
      expect(
        source,
        contains(
            "import 'package:icanbefitter/shared/widgets/responsive_picker_builder.dart';"),
        reason: 'e2b8a4: edit_profile_screen.dart must import '
            'responsive_picker_builder.dart for the builder reference above '
            'to resolve',
      );
    });

    test(
        'source: identity_screen.dart\'s DOB picker also pins '
        'calendarOnly (already had the builder)', () {
      final source = File(
        'lib/features/onboarding/screens/identity_screen.dart',
      ).readAsStringSync();

      expect(source, contains('builder: responsivePickerBuilder'),
          reason: 'e2b8a4: identity_screen.dart\'s DOB picker must keep '
              'using the responsive host — this was already true before '
              'round 1, pinned here as a baseline so a future edit to this '
              'file trips this test too, not just the calendarOnly line '
              'below');
      expect(source, contains('DatePickerEntryMode.calendarOnly'),
          reason: 'e2b8a4 round-1 finding: identity_screen.dart\'s DOB '
              'picker must also pass initialEntryMode: DatePickerEntryMode.'
              'calendarOnly — same reachable-toggle reasoning as '
              'edit_profile_screen.dart\'s DOB picker above');
    });

    testWidgets(
        'behavior: DatePickerEntryMode.calendarOnly removes the '
        'keyboard-toggle icon entirely', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDatePicker(
                context: context,
                initialDate: DateTime(2001, 1, 15),
                firstDate: DateTime(1950),
                lastDate: DateTime.now(),
                initialEntryMode: DatePickerEntryMode.calendarOnly,
              ),
              child: const Text('pick'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.edit_outlined), findsNothing,
          reason: 'e2b8a4: calendarOnly must render with NO entry-mode '
              'toggle icon — its presence is exactly what lets a user reach '
              'an input-mode layout never verified safe at MobileFrame\'s '
              'narrow web width. This pins Flutter\'s own calendarOnly '
              'contract, not app code.');
      // Day 15 (the seeded initialDate) must still be visible — a usable,
      // confirmable calendar, not an empty/broken dialog.
      expect(find.text('15'), findsWidgets,
          reason: 'calendarOnly must still render a usable calendar grid');
    });

    testWidgets(
        'behavior: DatePickerEntryMode.calendarOnly still confirms via OK',
        (tester) async {
      DateTime? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDatePicker(
                  context: context,
                  initialDate: DateTime(2001, 1, 15),
                  firstDate: DateTime(1950),
                  lastDate: DateTime.now(),
                  initialEntryMode: DatePickerEntryMode.calendarOnly,
                );
              },
              child: const Text('pick'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(result, DateTime(2001, 1, 15),
          reason: 'e2b8a4: OK must still confirm and return the selected '
              'date — calendarOnly must not silently break the happy path '
              'while removing the toggle icon');
    });
  });
}
