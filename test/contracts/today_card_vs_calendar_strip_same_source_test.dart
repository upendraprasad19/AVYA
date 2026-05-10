// APK Test #13 / Bug a9f3d2 — pins the "completed-today" rendering contract.
//
// Symptom: home today-card showed DONE but calendar-strip showed no checkmark
// for the same Saturday. Root cause: the checkmark icon used AppColors.accent
// (gold) — the same color as the full-gold today-border — making it visually
// invisible. The fix adds an explicit `isCompleted && isToday` branch in
// WeeklyCalendar._buildIndicator that uses AppColors.ok (green) so both
// signals are independently visible.
//
// This source-grep test prevents two regression patterns:
//
//   1. Suppression regression — `if (isCompleted)` appears AFTER `if (isToday)`
//      in _buildIndicator, causing today's em-dash to override the checkmark.
//
//   2. Color-merge regression — the `isCompleted && isToday` case is removed or
//      collapsed into the plain `isCompleted` branch that uses the gold accent
//      color (invisible against the gold today-border).

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calendarFile =
      'lib/features/home/widgets/weekly_calendar.dart';
  const homeProviderFile =
      'lib/features/home/providers/home_provider.dart';

  late String calendarSource;
  late String homeProviderSource;

  setUpAll(() {
    calendarSource = File(calendarFile).readAsStringSync();
    homeProviderSource = File(homeProviderFile).readAsStringSync();
  });

  // ── Contract 1: both files derive completion from status == 'completed' ───

  test('weekly_calendar.dart derives isCompleted from status == "completed"',
      () {
    // The calendar must use the same string as the today-card.
    expect(
      calendarSource.contains("status == 'completed'"),
      isTrue,
      reason:
          'WeeklyCalendar must derive isCompleted from `status == "completed"` '
          '(same field read by todayWorkoutProvider). '
          'If you changed the completion sentinel, update BOTH readers.',
    );
  });

  test('home_provider.dart derives isCompleted from status == "completed"',
      () {
    expect(
      homeProviderSource.contains("status == 'completed'"),
      isTrue,
      reason:
          'todayWorkoutProvider (home_provider.dart) must also derive '
          'completion from `status == "completed"`. '
          'Both readers must agree on the sentinel.',
    );
  });

  // ── Contract 2: no suppression regression ────────────────────────────────
  //
  // The regression pattern: `if (isToday)` guard before `if (isCompleted)`.
  // In _buildIndicator the safe ordering is:
  //   isSwapped → isCompleted (with isToday variants) → ... → isToday
  //
  // We detect the specific bad ordering by asserting that the raw text
  // "if (isToday)" does NOT appear before "if (isCompleted)" in _buildIndicator.
  // We do this by extracting the _buildIndicator method body and checking
  // the relative positions of the two patterns.

  test(
      '_buildIndicator checks isCompleted before bare isToday '
      '(no suppression regression)', () {
    // Locate _buildIndicator method in source.
    final indicatorStart = calendarSource.indexOf('Widget _buildIndicator(');
    expect(indicatorStart, isNot(-1),
        reason: '_buildIndicator must exist in weekly_calendar.dart');

    // Extract from method start to end of file (the method goes to end).
    final indicatorBody = calendarSource.substring(indicatorStart);

    // Find positions of the critical if-guards inside the extracted body.
    final posCompleted = indicatorBody.indexOf('if (isCompleted)');
    final posTodayBare = indicatorBody.indexOf('if (isToday)');

    expect(posCompleted, isNot(-1),
        reason: '_buildIndicator must contain `if (isCompleted)` guard');
    expect(posTodayBare, isNot(-1),
        reason: '_buildIndicator must contain `if (isToday)` guard (for '
            'non-completed today cells)');

    expect(
      posCompleted < posTodayBare,
      isTrue,
      reason:
          'Bug a9f3d2 regression guard: `if (isCompleted)` must appear '
          'BEFORE `if (isToday)` in _buildIndicator. '
          'If isToday fires first, completed-today cells get an em-dash '
          'instead of a checkmark.',
    );
  });

  // ── Contract 3: isCompleted+isToday uses a contrasting (non-accent) color ─
  //
  // The original bug: gold checkmark on gold-bordered cell = invisible.
  // Fix: when isCompleted AND isToday, use AppColors.ok (green) so both
  // the today-border (gold) and the completion indicator (green) are visible.
  //
  // We assert:
  //   a) There is an explicit `isCompleted && isToday` (or `isToday && isCompleted`)
  //      branch in _buildIndicator.
  //   b) That branch does NOT use AppColors.accent for the check icon color
  //      (that would make it invisible against the gold today-border).

  test(
      '_buildIndicator has explicit isCompleted+isToday branch '
      'with non-accent checkmark color', () {
    final indicatorStart = calendarSource.indexOf('Widget _buildIndicator(');
    expect(indicatorStart, isNot(-1));
    final indicatorBody = calendarSource.substring(indicatorStart);

    // The combined guard must be present in one of its two orderings.
    final hasCombinedBranch =
        indicatorBody.contains('isCompleted && isToday') ||
            indicatorBody.contains('isToday && isCompleted');

    expect(
      hasCombinedBranch,
      isTrue,
      reason:
          'Bug a9f3d2 regression guard: _buildIndicator must have an explicit '
          '`isCompleted && isToday` (or `isToday && isCompleted`) branch. '
          'Without it, the plain `isCompleted` branch uses AppColors.accent '
          '(gold), which is invisible against the full-gold today-border.',
    );
  });

  test(
      '_buildIndicator isCompleted+isToday branch uses AppColors.ok not accent',
      () {
    final indicatorStart = calendarSource.indexOf('Widget _buildIndicator(');
    expect(indicatorStart, isNot(-1));
    final indicatorBody = calendarSource.substring(indicatorStart);

    // Extract the region around the combined branch.
    // We find `isCompleted && isToday` or `isToday && isCompleted`,
    // then scan the next ~200 chars for `AppColors.ok` vs `AppColors.accent`.
    final combinedIdx = indicatorBody.contains('isCompleted && isToday')
        ? indicatorBody.indexOf('isCompleted && isToday')
        : indicatorBody.indexOf('isToday && isCompleted');

    expect(combinedIdx, isNot(-1));

    // Take a window of the next 200 chars after the branch head.
    final window = indicatorBody.substring(
      combinedIdx,
      (combinedIdx + 200).clamp(0, indicatorBody.length),
    );

    expect(
      window.contains('AppColors.ok'),
      isTrue,
      reason:
          'Bug a9f3d2 regression guard: the isCompleted+isToday checkmark '
          'must use AppColors.ok (green, contrasting) so it is visible against '
          'the full-gold today-border. '
          'AppColors.accent (gold on gold) is invisible — the original bug.',
    );

    // Belt-and-suspenders: the first check icon in this window must NOT be accent.
    final accentInWindow = window.indexOf('AppColors.accent');
    final okInWindow = window.indexOf('AppColors.ok');

    // If accent appears in the window, ok must appear before it (the ok branch
    // fires first and returns, so accent could appear later for the plain branch).
    if (accentInWindow != -1) {
      expect(
        okInWindow < accentInWindow,
        isTrue,
        reason:
            'Bug a9f3d2: AppColors.ok must appear before AppColors.accent in '
            'the isCompleted+isToday window — ensures the green variant fires '
            'first and returns, not the invisible gold variant.',
      );
    }
  });

  // ── Contract 4: no forbidden pattern — bare `if (isToday)` before check ──

  test(
      'no forbidden pattern: isCompleted is not nested inside an else-isToday '
      'block in _buildIndicator', () {
    final indicatorStart = calendarSource.indexOf('Widget _buildIndicator(');
    expect(indicatorStart, isNot(-1));
    final indicatorBody = calendarSource.substring(indicatorStart);

    // The regression pattern would look like:
    //   if (isToday) { return em-dash; }
    //   if (isCompleted) { return check; }
    //
    // We detect it by finding `if (isToday)` that occurs BEFORE `if (isCompleted)`
    // — this test is the flip of Contract 2's assertion and exists for clarity.
    final posCompleted = indicatorBody.indexOf('if (isCompleted)');
    final posTodayBare = indicatorBody.indexOf('if (isToday)');

    // posCompleted < posTodayBare is already asserted in Contract 2;
    // this test asserts the positive form that makes the intent explicit.
    expect(
      posCompleted,
      lessThan(posTodayBare),
      reason:
          'Forbidden pattern absent: `if (isCompleted)` must come before '
          '`if (isToday)` in _buildIndicator. '
          'Regression pattern: isToday returns em-dash before isCompleted check '
          '→ completed-today shows dash instead of tick.',
    );
  });
}
