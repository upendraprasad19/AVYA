import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_copy.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';

const thu = '2026-09-24';
const fri = '2026-09-25';
const sat = '2026-09-26';
const week = '2026-09-21';
const nextWeek = '2026-09-28';

DayAllowance pro({int used = 0, String weekStart = week}) =>
    DayAllowance(weekStart: weekStart, used: used, limit: 3);
DayAllowance free({int used = 0}) =>
    DayAllowance(weekStart: week, used: used, limit: 1);

DaySwapDayState day(String date, String title, {bool rest = false}) =>
    DaySwapDayState(
      date: date,
      row: {'type': rest ? 'rest' : 'workout', 'workout_name': title},
      lock: null,
      isMoved: false,
      title: title,
    );

void main() {
  test('confirm sheet (spec §6.4)', () {
    expect(DaySwapCopy.confirmEyebrow, 'Swap workout days');
    expect(DaySwapCopy.confirmTitle(sat, fri), 'Swap Friday and Saturday?');
    expect(DaySwapCopy.confirmBody,
        'Each workout keeps its exercises, sets and weights. Only the day changes.');
    expect(DaySwapCopy.confirmMove(from: fri, title: 'Pull + Core', to: sat),
        'FRI 25 · Pull + Core → SAT 26');
    expect(DaySwapCopy.confirmAllowance(pro(), currentWeekStart: week),
        'Uses 1 of your 3 swaps this week. 2 left after this.');
    expect(DaySwapCopy.confirmSwap, 'Swap days');
    expect(DaySwapCopy.cancel, 'Cancel');
    expect(
        DaySwapCopy.restRunWarningLine(const RestRunWarning(
            runDates: ['2026-09-23', '2026-09-24', '2026-09-25'])),
        'Heads-up: this leaves Wed, Thu and Fri as rest days in a row.');
  });

  test('free confirm line pluralises by number (D15)', () {
    expect(DaySwapCopy.confirmAllowance(free(), currentWeekStart: week),
        'Uses 1 of your 1 swap this week. 0 left after this.');
  });

  test('toast (spec §6.4)', () {
    expect(DaySwapCopy.toastTitle(fri, sat), 'Friday and Saturday swapped.');
    final subject = DaySwapCopy.toastSubject(
        day(fri, 'Pull + Core'), day(sat, 'Legs + Core'));
    expect(
        DaySwapCopy.toastBody(
            subject: subject,
            today: thu,
            after: pro(used: 1),
            currentWeekStart: week),
        'Legs + Core is now tomorrow. 2 swaps left this week.');
    expect(DaySwapCopy.movedTag, '⇄ MOVED');
  });

  test('toast names the other workout when the earlier date got a rest day',
      () {
    final subject = DaySwapCopy.toastSubject(
        day(fri, 'Pull + Core'), day(sat, 'Rest day', rest: true));
    expect(subject!.title, 'Pull + Core');
    expect(subject.date, sat);
  });

  test('allowance line (spec §6.4)', () {
    expect(DaySwapCopy.allowanceLine(pro(), currentWeekStart: week),
        '3 swaps left this week.');
    expect(
        DaySwapCopy.allowanceLine(pro(weekStart: nextWeek),
            currentWeekStart: week),
        '3 swaps left for Sep 28 – Oct 4.');
    expect(DaySwapCopy.allowanceHint,
        'Hold a day and drag it onto another, or tap ⇅');
  });

  test('picker (spec §6.4)', () {
    expect(DaySwapCopy.pickerTitle(fri), 'Swap Friday with…');
    expect(
        DaySwapCopy.pickerSubtitle(
            title: 'Pull + Core', a: pro(), currentWeekStart: week),
        'Pull + Core · 3 swaps left this week');
    expect(
        DaySwapCopy.pickerSubtitle(
            title: 'Pull + Core', a: free(used: 1), currentWeekStart: week),
        'Pull + Core · 0 of 1 swaps left this week');
    expect(DaySwapCopy.pickerButton(sat, fri), 'Swap Fri and Sat');
    expect(DaySwapCopy.pickerFooter,
        'DONE, STARTED, PAUSED AND PAST DAYS STAY PUT');
    expect(DaySwapCopy.pickerTodayTag, 'today');
    expect(DaySwapCopy.dayShort(sat), 'Sat 26');
    expect(DaySwapCopy.spentTitleFree, "This week's swap is spent.");
    expect(DaySwapCopy.spentBodyFree,
        'Your allowance resets Monday. PRO gets 3 swaps a week, from the Train tab, Home, or by asking the coach.');
    expect(DaySwapCopy.seePro, 'See PRO');
    expect(DaySwapCopy.close, 'Close');
  });

  test('errors (spec §6.4)', () {
    expect(DaySwapCopy.proSpent(3), 'All 3 swaps used. Resets Monday.');
    expect(DaySwapCopy.writeFailed, "Couldn't swap. Nothing was changed.");
    expect(DaySwapCopy.staleLine(DaySwapRefusal.completed, fri),
        'Friday is already done. Nothing was changed.');
  });

  test('errorFor maps every result', () {
    expect(
        DaySwapCopy.errorFor(
            DaySwapDone(
                dateA: fri, dateB: sat, allowanceAfter: pro(used: 1)),
            isPro: true,
            limit: 3),
        isNull);
    expect(DaySwapCopy.errorFor(const DaySwapFailed(), isPro: true, limit: 3),
        "Couldn't swap. Nothing was changed.");
    expect(
        DaySwapCopy.errorFor(
            const DaySwapRefused(
                reason: DaySwapRefusal.allowanceSpent, date: fri),
            isPro: true,
            limit: 3),
        'All 3 swaps used. Resets Monday.');
    expect(
        DaySwapCopy.errorFor(
            const DaySwapRefused(
                reason: DaySwapRefusal.allowanceSpent, date: fri),
            isPro: false,
            limit: 1),
        "This week's swap is spent.");
    expect(
        DaySwapCopy.errorFor(
            const DaySwapRefused(reason: DaySwapRefusal.completed, date: fri),
            isPro: true,
            limit: 3),
        'Friday is already done. Nothing was changed.');
  });

  test('coach card (spec §6.4)', () {
    expect(DaySwapCopy.coachCardTitle(sat, fri), 'Swap Fri 25 and Sat 26');
    expect(DaySwapCopy.coachCardMove(title: 'Pull + Core', from: fri, to: sat),
        'Pull + Core FRI → SAT');
    expect(DaySwapCopy.coachCardAllowance(pro(), currentWeekStart: week),
        'Uses 1 of your 3 swaps this week.');
  });

  test('titleOf', () {
    expect(DaySwapCopy.titleOf({'type': 'rest', 'workout_name': 'Rest Day'}),
        'Rest day');
    expect(DaySwapCopy.titleOf({'type': 'workout', 'workout_name': 'Pull'}),
        'Pull');
    expect(DaySwapCopy.titleOf({'type': 'workout'}), 'Workout');
    expect(DaySwapCopy.titleOf(null), '');
  });
}
