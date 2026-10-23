# An absent denominator is not 0% — and a coach "fabrication" it can quote is a writer bug (2026-10-23)

**1. Never report an empty bucket as 0.** `getDayOfWeekCompletionRates` returned `0` for a weekday with nothing
scheduled (`total > 0 ? done / total : 0`), and the day-of-week pattern took the lowest rate below 0.5, so the coach
told users they skip their REST day 100% of the time. `getWorkoutAdherence` had the same `rate_percent: 0`. Rule: when
the denominator is 0, omit the key or return null, and count only what was due (`classifyScheduleDay`). A reader that
names a bucket needs a minimum sample and a "singled out" rule, not just the lowest rate.

**2. If the coach can quote it, look for a writer first.** Bug C (APK Test #3) and OBS-3 (APK Test #4) were fixed
prompt-side as model fabrication; the claim kept coming back because `PatternDetector` put it in
`snapshot.coach_notices`, which the anti-fabrication rule explicitly allows the model to cite. Before calling a coach
statement fabricated, grep the snapshot (`coach_notices`, `workout_adherence`, …) for it.

Refs: OI-390, diagnose `132315`, `test/contracts/day_of_week_completion_writer_to_reader_test.dart`, debugging §2.115.
