---
reviewed_at: 2026-11-18T22:54:11+05:30
staged_against: bb5a04f8a371
blast_radius: account
reviewer: claude-sonnet-via-skill (two fresh seats: read-only lenses, then the mutation seat on the post-fix tree)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 10
verdict: accepted
verdict_note: reviewed commit b25313cd (branch oi518-maintain-callout, CI green on that head); every finding triaged and fixed or recorded as accepted residue in the diagnose doc 8b48f1
---

# Code Review (B-pass) — OI-518 Weekly Report weight card, Maintain by distance

Reviewed: `git diff origin/main...HEAD` at b25313cd (17 files, +1264/-106), hash bb5a04f8a371. Plan
`docs/plans/oi518-maintain-callout.md` (revision 4, three plan-review rounds). Seat 1 read the diff under all eight lenses;
seat 2 mutated the four product files (82 mutant applications) after seat 1's fixes. No P0.

## Seat 1 (read-only lenses)

### Finding 1 — P2 — guard_without_its_mirror
- **file:line:** lib/features/onboarding/target_weight_check.dart:135 (history gate above the Maintain branch)
- **claim:** a Maintain user keeps the two trend-era gates (two weigh-ins, half a week apart) though distance needs neither.
- **verification:** `sed -n 281,282p test/onboarding/target_weight_check_test.dart`
- **status:** accepted (recorded plan choice; added to the diagnose doc's accepted residue)

### Finding 2 — P2 — asserted_fixture_value
- **file:line:** test/contracts/maintain_weight_callout_behavioral_test.dart (narrow width, empty list, bad last date)
- **claim:** the 320 px test pumped only the offTarget line; the length guard was only exercised by a one-entry list (no kill); a bad LAST date was untested.
- **verification:** `grep -n "not-a-date\|entries: \[" test/contracts/maintain_weight_callout_behavioral_test.dart`
- **status:** accepted, fixed: both Maintain lines pumped at 320 px, an empty-list row, a bad-last-date row; the length-guard mutant and a compiling last-date mutant both redden.

### Finding 3 — P2 — writer_reader_drift
- **file:line:** docs/naming_conventions.md:686-688
- **claim:** the three glossary rows sat after the section-8 horizontal rule, outside the table.
- **verification:** `sed -n 683,690p docs/naming_conventions.md`
- **status:** accepted, fixed: rows moved directly under the last table row.

### Finding 4 — P2 — writer_reader_drift
- **file:line:** docs/diagnoses/2026-11-18-weekly-report-maintain-callout-8b48f1.md (writer/reader line anchors)
- **claim:** `_save` cited at 1936 (is 1941), `_executeSwitchGoal` at 1395 (is 1398), widget `build` at 58 (is 38).
- **verification:** `grep -n "Future<void> _save" lib/features/profile/screens/edit_profile_screen.dart`
- **status:** accepted, fixed: re-anchored.

### Finding 5 — P2 — guard_without_its_mirror
- **file:line:** lib/features/profile/screens/reports_screen.dart (the "All" filter) with the widget's `entries.last`
- **claim:** on "All" the callout judges the last weigh-in whatever its age, a stronger present-tense claim for Maintain.
- **verification:** `sed -n 756,765p lib/features/profile/screens/reports_screen.dart`
- **status:** accepted as residue (same staleness the old reached line had; a cutoff is an undecided product rule), recorded in the diagnose doc.

## Seat 2 (mutation, 82 applications, restore proof: sha256 of the four files equals the baseline)

66 killed by a runtime assertion, 2 killed only by a source-grep pin, 8 equivalent, 6 real survivors.

### Finding 6 — P2 — guard_without_its_mirror
- **file:line:** lib/features/onboarding/target_weight_check.dart:140-149
- **claim:** a trend gate on a LARGE swing (`abs(lastW - firstW) > 5` returns none for an in-window weigh-in) survived: no fixture ended in the window after a big swing.
- **verification:** mutant A32, `+112: All tests passed!`
- **status:** accepted, fixed: four big-swing rows (85 to 75, 65 to 75, 65 to 79, 90 to 79).

### Finding 7 — P2 — guard_without_its_mirror
- **file:line:** lib/features/profile/widgets/weight_projection_callout.dart (`now ?? DateTime.now()`)
- **claim:** the injected clock was the authoring day, equal to the wall clock, so ignoring `now` stayed green until the month moved.
- **verification:** mutant C3, `+112: All tests passed!`
- **status:** accepted, fixed: the clock is 2031-03-05 ("around Apr 2031"); the ignore-`now` mutant now reddens 2 tests.

### Finding 8 — P2 — guard_without_its_mirror
- **file:line:** lib/features/profile/widgets/weight_projection_callout.dart:42-44 (null-date guard)
- **claim:** an unparseable LAST date mapped to `DateTime(2000)` survived.
- **verification:** mutant C11b
- **status:** false_alarm for that exact mutant (a year-2000 last date gives a negative `weeksDiff`, so `none`: the output is identical, an equivalent mutant); the real guard is covered by the bad-first-date and bad-last-date rows, and a compiling `lastDate!` mutant reddens the bad-last-date row.

### Finding 9 — P1 — guard_without_its_mirror
- **file:line:** lib/features/profile/screens/reports_screen.dart:738-748 (the call site)
- **claim:** the screen's wiring was protected only by source-grep pins; seven mutants that satisfy the grep and break the behaviour survived (always-empty goal, a re-derived goal, callout hidden for Maintain, a wrong or rounded target, reversed or truncated entries, target >= 0).
- **verification:** mutants D1, D4, D5, D9 to D13: `+112: All tests passed!`
- **status:** accepted, fixed: a runtime test was needed, not a stronger grep. The whole profile-to-callout chain moved into `WeightProjectionLine` (takes the raw profile map and the filtered entries; reads the goal and target itself; `goal` stays required on the callout). New runtime rows: Maintain / Cut / Build profiles to the rendered text, an int target, a missing goal, a Cut with no target, the 10 px spacing, the entries read oldest first. The screen's call is pinned to the EXACT arguments `profile: profile, entries: filtered` (whitespace-normalised) and built once. Re-run mutants: reversed entries, truncated entries, a forced-empty goal and a removed call each redden a test; the widget-side mutants (goal always empty, the wrong target key, the removed target guard, the removed spacing, the ignored clock) redden runtime rows.

### Finding 10 — P2 (low) — guard_without_its_mirror
- **file:line:** lib/features/onboarding/target_weight_check.dart:113 (`canProjectGoalDate`, `<= 0.1`)
- **claim:** the inclusive 0.1 kg boundary has no test (unchanged code, surfaced by the mutation seat).
- **verification:** mutant A27, `+112: All tests passed!`
- **status:** accepted, fixed: a row at exactly 0.1 (`0.2 - 0.1 == 0.1` in doubles, asserted as the premise) and one just above.

## Checked and clean (seat 1)

Lens 1: no live reference to the removed `_buildProjectionCallout` outside plans, diagnoses and a historical spec; the screen's `profile` is the one read for chart and callout; the registry rows and the behavioural-test sibling key resolve; `getWeightEntries` sorts ascending. Lens 2: no `.functions.invoke(` in the diff. Lens 3: path tiers match `docs/blast_radius.yaml` (onboarding and core account, profile feature). Lens 4: no credential-shaped literal. Lens 5: no `unawaited(`. Lens 7: every named file and symbol exists; `dart analyze` clean; the four test files pass. Lens 8: every literal in the new tests recomputed by hand (the date, the gaps, the 66.9 / 70.0 float edge, `targetLabel(99.95)`). Lens 6 (read-only half): the Cut / Build path is byte-identical except the flat-series guard; every new guard's mirror was walked.

## Founder triage notes

(none yet; the founder's merge go and the device check are the remaining gates)

## Tuning entry
- **2026-11-18** - blast-radius account - 10 findings; 1 false_alarm; tuning: none. The one P1 (wiring pinned by source grep only) was found by the mutation seat applying this skill's own "if the guard is a SOURCE GREP, assume it is defeatable and try indirection" rule; the read-only seat accepted the same pins.
