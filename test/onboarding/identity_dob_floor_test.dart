// OI-305 (2026-10-16): the onboarding identity step's date picker stops at
// today minus 13 years. Behavioural: opens the real picker and reads the
// dialog's own lastDate, so the old floor of 10 (lastDate = today minus 10
// years) fails here.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/utils/age_floor.dart';
import 'package:icanbefitter/features/onboarding/screens/identity_screen.dart';

// Note: the expected ceiling is computed here and again in production from
// DateTime.now(); a run that straddles local midnight could differ by a day
// (a sub-second window once a day; accepted, B-pass A-P3-8).
void main() {
  testWidgets('the DOB picker offers nothing later than today minus 13 years',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: IdentityScreen()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Tap to pick'));
    await tester.tap(find.text('Tap to pick'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    final expected = latestAllowedDob(DateTime.now());
    expect(dialog.lastDate.year, expected.year);
    expect(dialog.lastDate.month, expected.month);
    expect(dialog.lastDate.day, expected.day);
    expect(
      dialog.lastDate.year,
      DateTime.now().year - 13,
      reason: 'a floor of 13 years, not the old 10',
    );
  });

  // The picker only bounds a NEW pick; a date of birth carried in through the
  // route extras (an earlier session, or the old 10-year floor) must also be
  // refused at CONTINUE.
  testWidgets('CONTINUE refuses a carried-in date of birth younger than 13',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final latest = latestAllowedDob(DateTime.now());

    Future<void> pumpWith(DateTime dob) async {
      await tester.pumpWidget(
        MaterialApp(
          home: IdentityScreen(
            initial: {
              'full_name': 'Test User',
              'date_of_birth': dob.toIso8601String(),
              'sex': 'male',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final tooYoung = DateTime(latest.year, latest.month, latest.day + 1);
    await pumpWith(tooYoung);
    final cont = find.textContaining('CONTINUE');
    await tester.ensureVisible(cont);
    await tester.tap(cont);
    await tester.pump();
    expect(
      find.textContaining('You must be $kMinAgeYears or older'),
      findsOneWidget,
      reason: 'a date of birth one day short of 13 is refused',
    );
  });

  // The old floor admitted 10 to 12 year olds; opening the picker with such a
  // value as its seed must clamp initialDate to lastDate (Flutter asserts
  // initialDate <= lastDate), not throw.
  testWidgets('the picker opens on lastDate when the carried-in date of birth '
      'is younger than 13', (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final latest = latestAllowedDob(DateTime.now());
    final tooYoung = DateTime(latest.year, latest.month, latest.day + 1);
    await tester.pumpWidget(
      MaterialApp(
        home: IdentityScreen(
          initial: {
            'full_name': 'Test User',
            'date_of_birth': tooYoung.toIso8601String(),
            'sex': 'male',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.byIcon(Icons.calendar_today_outlined);
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(dialog.initialDate, dialog.lastDate);
    expect(dialog.lastDate.day, latest.day);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CONTINUE accepts a date of birth of exactly 13 today (no '
      'off-by-one at the boundary)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Exactly 13 today, WITH a time of day: a stored date of birth may carry
    // one, and the check compares the calendar date only.
    final base = latestAllowedDob(DateTime.now());
    final latest = DateTime(base.year, base.month, base.day, 15, 30);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => IdentityScreen(
            initial: {
              'full_name': 'Test User',
              'date_of_birth': latest.toIso8601String(),
              'sex': 'male',
            },
          ),
        ),
        GoRoute(
          path: '/onboarding/goal',
          builder: (_, _) => const Scaffold(body: Text('GOAL STEP')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final cont = find.textContaining('CONTINUE');
    await tester.ensureVisible(cont);
    await tester.tap(cont);
    await tester.pumpAndSettle();
    expect(find.text('GOAL STEP'), findsOneWidget);
  });
}
