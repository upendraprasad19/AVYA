---
reviewed_at: 2026-11-19T20:40:00+05:30
staged_against: d1c2e67887b1
blast_radius: account
reviewer: claude-sonnet-via-skill (two fresh seats: read-only lenses, then the mutation seat)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 19
verdict: accepted
verdict_note: reviewed head 2d34fa0d (branch oi518-maintain-followon, PR #303, CI green on that head); every finding fixed in the commit that adds this file (tests and docs only, no product-code change)
---

# Code Review (B-pass) — OI-518 follow-on: Maintain skips the half-week rule, "as of" suffix

Reviewed: `git diff origin/main...2d34fa0d` (14 files, +718/-66), hash d1c2e67887b1. Plan `docs/plans/oi518-maintain-followon.md`
(revision 4, three plan-review rounds). Seat 1 read the diff under all eight lenses; seat 2 applied 100 mutations to the three
product files (91 applied). No P0, no P1 defect in the shipped code.

## Seat 1 (read-only lenses): 2 findings

### Finding 1 — P2 — asserted_fixture_value (documentation form)
- **file:line:** docs/diagnoses/2026-11-18-weekly-report-maintain-callout-8b48f1.md (follow-on section)
- **claim:** the doc said 146 tests / four files; the three listed files hold 140 (147 with the call-site pin file).
- **verification:** `flutter test` on the three files printed +140; on four, +147 (re-run by the author).
- **status:** accepted, fixed (counts restated; now 146 / 153 after the new tests).

### Finding 2 — P2 — writer_reader_drift (clock seam)
- **file:line:** lib/features/profile/widgets/weight_projection_callout.dart (`now ?? nowWall()` vs the Cut / Build `DateTime.now()`)
- **claim:** the suffix follows the dev/test clock seam while the date sentence and the screen's window cutoff do not; dev panel only.
- **status:** accepted as residue (recorded in the diagnose doc); changing Cut / Build sites is outside the founder-approved scope.

## Seat 2 (mutation): 17 survivors, all missing pins

- **P1 pins (production clock, M1 M2 M3):** every test injected `now`; the screen passes none. Fixed: `setTestClockTo` test through `WeightProjectionLine`.
- **P1/P2 (three or more weigh-ins, M93 M94 M95 M100):** all fixtures had two entries. Fixed: three-entry Maintain and Cut rows.
- **P2 (gate pins, M44 M49 M37 M35):** hidden conditions on the exemption at large gaps / targets, Cut / Build at the target, negative span. Fixed: pure rows.
- **P3 (M77 18:30Z, M67 M68 key digits, M75 M76 very old key):** fixed: the exact-midnight row, bad keys `2026-1-05` / `026-11-18`, a 2014 key.
- All 17 re-run after the fixes: confirmed applied, killed, tree restored and re-hashed (diagnose doc 8b48f1, "Follow-on B-pass mutation seat").

## Founder triage notes
Decisions of 2026-11-19 (chart label as is; "as of" over 7 days; Maintain skips the half-week rule) were quoted to both seats; neither reopened them.

## Tuning entry
- **2026-11-19** - blast-radius account - 19 findings; 1 false_alarm (an unreachable-key mutant, M67 / M68, reachable only through the pure parser); tuning: none. Seat 2 again found only pin gaps the author's own ~45 mutants missed: the production default branch (`now ?? nowWall()`) and fixtures with exactly two entries, so a mutation seat should be told to look at every default and every `entries.last` / `entries.first` read when the fixtures are all one size.
