import 'package:flutter/material.dart';

import 'package:icanbefitter/core/theme/colors.dart';

/// Shared `builder:` for `showTimePicker` / `showDatePicker`.
///
/// Three jobs:
///  1. Apply the Wardroom dark theme to the stock Material picker.
///  2. Give `CalendarDatePicker`/`YearPicker`'s day/weekday/year cells an
///     EXPLICIT `datePickerTheme` instead of letting them fall back to the
///     ambient `textTheme`. Diagnose e2b8a4 (2026-09-19, live web E2E)
///     originally diagnosed this as "the app's global textTheme routes
///     display/headline/title to an oversized Fraunces" and fixed it by
///     resetting the WHOLE `textTheme` to `ThemeData(brightness:).textTheme`
///     — that fix passed a widget test built around a synthetic oversized
///     `TextTheme` fixture, but did NOT stop the real day-grid text wrap in
///     the live browser (caught on a second live-verify pass the same day).
///     Root cause, confirmed by inspecting Flutter's own
///     `_DatePickerDefaultsM3`: `dayStyle`/`yearStyle` resolve to
///     `Theme.of(context).textTheme.bodyLarge`, and `weekdayStyle` to
///     `bodySmall`. The app's `bodyLarge`/`bodySmall` are built via
///     `AppTypography.dmSansFamily()`, which deliberately omits `fontSize`
///     ("seed" pattern, so callers merge onto Material's own default size).
///     Resetting the textTheme wholesale did make `fontSize` resolve
///     correctly (confirmed 16.0 in a widget test against this exact
///     picker), but the DM Sans *family* itself still reached the day
///     cells — and DM Sans's real web-font metrics (only available once
///     genuinely downloaded in a browser; a `flutter test` run never fetches
///     it and silently falls back to a placeholder, which is why the
///     original widget test could not see this) are wide enough that 2-digit
///     days and 4-digit years still wrap inside Material's fixed-size grid
///     cells. Rather than chase the exact textTheme-merge chain further,
///     `datePickerTheme.dayStyle`/`weekdayStyle`/`yearStyle` are set
///     EXPLICITLY here with no custom font family at all (Flutter's own
///     bundled default) — `dayStyle`/`weekdayStyle`/`yearStyle` on
///     `DatePickerThemeData` take absolute precedence over the
///     textTheme-derived fallback (`_DatePickerDefaultsM3.dayStyle` is only
///     ever consulted via `datePickerTheme.dayStyle ?? defaults.dayStyle`),
///     so this sidesteps the app's font pipeline for these cells entirely
///     instead of depending on how it resolves.
///  3. The SAME class of bug, confirmed live for `showTimePicker` too
///     (2026-09-19, live re-verify after the datePickerTheme fix landed):
///     `TimePickerDialog`'s hour/minute display resolves via
///     `Theme.of(context).textTheme.displayMedium` (Flutter's own
///     `_TimePickerDefaultsM3.hourMinuteTextStyle`), and the app's
///     `displayMedium` is Fraunces (a serif VARIABLE font) — via the same
///     `AppTypography.frauncesFamily()` null-fontSize "seed" pattern.
///     Live-reproduced: the dial + OK/Cancel action row rendered as
///     genuinely absent (sampled canvas pixels confirmed flat background,
///     not a color/opacity issue) even with the bounded ConstrainedBox from
///     job #4 in place — the oversized real-Fraunces header apparently
///     consumes enough of the fixed dialog height that TimePickerDialog's
///     internal (non-scrolling) layout has nothing left for the dial. Fixed
///     identically to job #2: `timePickerTheme`'s text styles set EXPLICITLY
///     with no custom font family, which take precedence over the
///     textTheme-derived fallback the same way `datePickerTheme` does.
///  4. Keep the dialog bounded to the viewport instead of letting it size
///     itself unboundedly. Obs#5 (2026-06-13) fixed OK/Cancel falling below
///     the fold by wrapping the dialog in an unbounded `SingleChildScrollView`
///     — but `SingleChildScrollView` gives ITS CHILD unbounded extent along
///     the scroll axis by design, regardless of what constrains the scroll
///     view itself. Diagnose e2b8a4 (2026-09-19) found this let the time
///     picker's dial claim more space than the actual viewport, so its
///     internal `GestureDetector` hit-region no longer stayed bounded to its
///     visual circle: taps on Cancel/OK/the keyboard-toggle instead rotated
///     the clock hand, and at the default viewport the dial + action row
///     didn't render at all (not scrolled off — genuinely absent). Giving
///     the dialog a genuinely bounded max size (not just a bounded outer
///     wrapper around an unbounded scroll child) lets Flutter's own
///     TimePickerDialog/CalendarDatePicker adapt their internal layout to
///     the space actually available, the way they're designed to.
///  5. The calendar header (`headerHeadlineStyle`/`headerHelpStyle`) gets the
///     same explicit-no-family treatment as job #2's day/year/weekday
///     fields, for the same reason — `_DatePickerDefaultsM3` resolves it
///     via `textTheme.headlineLarge`/`labelLarge` when unset, the same
///     Fraunces-carrying chain implicated in the hour/minute bug (job #3).
///     e2b8a4 round-1 review separately proposed REMOVING job #1's
///     wholesale `textTheme: stockTextTheme` reset entirely, on the theory
///     that it had become redundant collateral damage once every at-risk
///     field had its own explicit override — stripping DM Sans/Fraunces
///     from OK/Cancel button labels and other never-at-risk text for no
///     remaining benefit. TRIED, then REVERTED: this file's own 2nd-pass
///     regression test caught it live. Every explicit style field here
///     (`dayStyle`, `yearStyle`, `hourMinuteTextStyle`, etc.) deliberately
///     carries NO custom `fontFamily` — and an unset `fontFamily` doesn't
///     mean "Flutter's bundled default", it means the field MERGES onto
///     whichever ambient `DefaultTextStyle` is in scope. Without job #1's
///     reset, that ambient style is `baseTheme.textTheme` — the app's real
///     DM Sans theme — so removing it let DM Sans straight back into the
///     day cell via the merge chain (confirmed: the rendered day cell's
///     `fontFamily` became `DMSans_regular` again). Job #1's reset is
///     therefore the safety net every family-less field below depends on,
///     not redundant — the OK/Cancel-label brand inconsistency it causes is
///     a real but minor, and now explicitly documented, trade-off rather
///     than something to engineer away.
///
/// NOTE (device verify): `showTimePicker`/`showDatePicker` are Flutter's own
/// cross-platform Material dialogs, not bridged native pickers — Android
/// runs the SAME dialog code as web. What's actually web-specific is the
/// bug this file exists to fix: only `MobileFrame` (web-only, activates
/// above 500px) forced a root-navigator dialog to lay out against a wrong,
/// far-larger outer size while being clipped into a much smaller box (see
/// `lib/app.dart`). A real Android device's `MediaQuery` always matches its
/// actual screen, so it was never exposed to that specific defect — but
/// confirm this file's OWN theme hardening (jobs #1-5 above) looks correct
/// on device regardless, since nothing here is web-gated.
Widget responsivePickerBuilder(BuildContext context, Widget? child) {
  final baseTheme = Theme.of(context);
  final stockTextTheme = ThemeData(brightness: baseTheme.brightness).textTheme;
  // No custom font family — Flutter's own bundled default. Deliberately NOT
  // derived from the app's textTheme; see the class doc above for why that
  // reset alone did not stop the real-browser wrap.
  const safeDayStyle = TextStyle(fontSize: 14, letterSpacing: 0);
  const safeWeekdayStyle = TextStyle(fontSize: 12, letterSpacing: 0);
  const safeHourMinuteStyle = TextStyle(fontSize: 48, letterSpacing: 0);
  const safeDayPeriodStyle = TextStyle(fontSize: 14, letterSpacing: 0);
  const safeHelpStyle = TextStyle(fontSize: 12, letterSpacing: 0);
  const safeDialStyle = TextStyle(fontSize: 16, letterSpacing: 0);
  final themed = Theme(
    data: baseTheme.copyWith(
      // e2b8a4 round-1 review raised removing this wholesale reset (it
      // strips DM Sans/Fraunces from OK/Cancel button labels and other text
      // that isn't in a fixed-size cell — a real, if minor, CLAUDE.md
      // rule-10 brand-consistency cost, since those elements were never
      // actually at risk of wrapping). TRIED and REVERTED after this
      // file's own 2nd-pass regression test caught it live: `dayStyle` (and
      // every other explicit style below) has NO custom fontFamily, so an
      // UNSET field merges onto whatever ambient `DefaultTextStyle` is in
      // scope — which, without this reset, is `baseTheme.textTheme`, i.e.
      // the app's real DM Sans theme. Removing this line therefore let DM
      // Sans back into the day cell via the merge chain (confirmed:
      // rendered "15" cell's `fontFamily` became `DMSans_regular` again),
      // reintroducing the exact bug this file exists to fix. This IS the
      // safety net for every explicit-but-family-less style field below,
      // not redundant collateral — keeping it is the correct call, and the
      // OK/Cancel-label brand nuance is an accepted, documented trade-off
      // rather than a bug.
      textTheme: stockTextTheme,
      colorScheme: baseTheme.colorScheme.copyWith(
            primary: AppColors.accent,
            onPrimary: AppColors.bgDeep,
            surface: AppColors.card,
            onSurface: AppColors.textPrimary,
          ),
      dialogTheme: const DialogThemeData(backgroundColor: AppColors.card),
      datePickerTheme: DatePickerThemeData(
        dayStyle: safeDayStyle,
        yearStyle: safeDayStyle,
        weekdayStyle: safeWeekdayStyle,
        // e2b8a4 round-1 review finding: the calendar header ("SELECT
        // DATE" + the big date line) resolves via textTheme.headlineLarge/
        // labelLarge (_DatePickerDefaultsM3) when unset — the SAME Fraunces
        // family implicated in the hour/minute wrap bug below. Reusing
        // stockTextTheme's own values here (not inventing new sizes) gives
        // Flutter's exact intended header appearance with zero custom
        // family, consistent with every other field in this theme.
        headerHeadlineStyle: stockTextTheme.headlineLarge,
        headerHelpStyle: stockTextTheme.labelLarge,
      ),
      timePickerTheme: const TimePickerThemeData(
        hourMinuteTextStyle: safeHourMinuteStyle,
        dayPeriodTextStyle: safeDayPeriodStyle,
        helpTextStyle: safeHelpStyle,
        dialTextStyle: safeDialStyle,
        timeSelectorSeparatorTextStyle:
            WidgetStatePropertyAll(safeHourMinuteStyle),
      ),
    ),
    child: child ?? const SizedBox.shrink(),
  );
  final viewport = MediaQuery.sizeOf(context);
  return Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: viewport.height * 0.9,
        maxWidth: viewport.width * 0.95,
      ),
      child: themed,
    ),
  );
}
