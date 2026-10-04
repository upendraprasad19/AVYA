// Regression contract for bug e2b8a4 (2026-09-19), 3rd finding: Edit
// Profile's wake-time / workout-time `showTimePicker` calls used to accept
// Flutter's default `TimePickerEntryMode.dial`, which shows a
// keyboard-toggle icon letting the user manually switch to "Enter time"
// (input) mode. Live-reproduced this session in the Browser pane: at the
// app's real MobileFrame web content width, Material's input-mode layout
// clips its AM/PM toggle and OK button off-screen entirely — Cancel remains
// tappable but OK does not, so the user can never confirm a time after
// switching modes.
//
// This is reachable from BOTH real call sites regardless of what
// `initialEntryMode` they pass, because the toggle icon is present in
// `TimePickerEntryMode.dial` (Flutter's default) — the earlier same-day
// diagnose-doc wrongly scoped an adjacent finding (a QA button that opened
// DIRECTLY in input mode) as "not a live bug" by checking only whether any
// call site explicitly requests input mode. None do — but that check missed
// that a user reaches the identical broken layout by tapping the toggle icon
// from ordinary dial mode, which every real call site exposes by default.
//
// Writer: lib/features/profile/screens/edit_profile_screen.dart
// `_pickWakeUpTime` / `_pickPreferredWorkoutTime` — both now pass
// `initialEntryMode: TimePickerEntryMode.dialOnly`. Flutter only renders the
// toggle icon for `.dial`/`.input` (time_picker.dart's `actions` Row,
// conditioned on `_entryMode.value == TimePickerEntryMode.dial ||
// TimePickerEntryMode.input`), never for `.dialOnly`/`.inputOnly` — so the
// fix makes the broken state structurally unreachable rather than patching
// Material's own input-mode layout math.
//
// Two layers, deliberately not one:
//   1. A source-grep pinning THIS APP'S choice at both real call sites —
//      presence-only, per this project's rule that source-greps don't count
//      alone, but honest about what it proves (our parameter choice, not
//      picker behavior).
//   2. A behavioral test on the showTimePicker(...) call shape itself,
//      proving `dialOnly` genuinely removes the toggle icon and still
//      returns a confirmed time via OK — this pins FLUTTER's own dialOnly
//      contract, not a defect in this app's code, so a future Flutter
//      upgrade that silently changed this behavior would be caught here.
// EditProfileScreen itself is NOT pumped directly: it has zero prior test
// coverage and non-trivial Riverpod/Hive provider setup — standing up a full
// harness for a 2-line parameter fix would be disproportionate scope creep
// for this bug batch. The source-grep is what actually ties these two layers
// to the real product call sites.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  group('e2b8a4 — Edit Profile time pickers pin TimePickerEntryMode.dialOnly',
      () {
    test(
        'source: both _pickWakeUpTime and _pickPreferredWorkoutTime pass '
        'initialEntryMode: TimePickerEntryMode.dialOnly', () {
      final source = File(
        'lib/features/profile/screens/edit_profile_screen.dart',
      ).readAsStringSync();

      final wakeUp = RegExp(
        r'Future<void>\s+_pickWakeUpTime\(\)[\s\S]*?\n  \}',
      ).firstMatch(source);
      final workout = RegExp(
        r'Future<void>\s+_pickPreferredWorkoutTime\(\)[\s\S]*?\n  \}',
      ).firstMatch(source);

      expect(wakeUp, isNotNull,
          reason: 'e2b8a4: _pickWakeUpTime must still exist at this name — '
              'if it moved, repoint this regex rather than deleting the test');
      expect(workout, isNotNull,
          reason:
              'e2b8a4: _pickPreferredWorkoutTime must still exist at this '
              'name — if it moved, repoint this regex rather than deleting '
              'the test');

      expect(wakeUp!.group(0), contains('TimePickerEntryMode.dialOnly'),
          reason: 'e2b8a4: _pickWakeUpTime\'s showTimePicker must pass '
              'initialEntryMode: TimePickerEntryMode.dialOnly — its absence '
              'reopens the keyboard-toggle path into the clipped, '
              'unconfirmable Enter-time layout at MobileFrame\'s narrow web '
              'width');
      expect(workout!.group(0), contains('TimePickerEntryMode.dialOnly'),
          reason: 'e2b8a4: _pickPreferredWorkoutTime\'s showTimePicker must '
              'pass initialEntryMode: TimePickerEntryMode.dialOnly — same '
              'reason as _pickWakeUpTime above');
    });

    testWidgets(
        'behavior: TimePickerEntryMode.dialOnly removes the keyboard-toggle '
        'icon entirely', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 6, minute: 30),
                initialEntryMode: TimePickerEntryMode.dialOnly,
              ),
              child: const Text('pick'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.keyboard_outlined), findsNothing,
          reason:
              'e2b8a4: dialOnly must render with NO entry-mode toggle icon '
              '— its presence is exactly what lets a user reach the broken '
              'input-mode layout. This pins Flutter\'s own dialOnly '
              'contract, not app code.');
      expect(find.text('OK'), findsOneWidget,
          reason: 'dialOnly must still render a usable, confirmable dial');
    });

    testWidgets('behavior: TimePickerEntryMode.dialOnly still confirms via OK',
        (tester) async {
      TimeOfDay? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 6, minute: 30),
                  initialEntryMode: TimePickerEntryMode.dialOnly,
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

      expect(result, const TimeOfDay(hour: 6, minute: 30),
          reason:
              'e2b8a4: OK must still confirm and return the picked time — '
              'dialOnly must not silently break the happy path while '
              'removing the toggle icon');
    });
  });
}
