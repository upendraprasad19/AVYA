---
reviewed_at: 2026-11-17T01:30:00+05:30
staged_against: 5c260f1b1a2dc83c84ca04e7915645c0f1a50931
branch: generator-step4
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh seats)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 11
verdict: accepted
verdict_note: self-triaged under the standing directive; 0 P0/P1, 2 P2 and 9 P3; 10 fixed in the B-pass commit (code, tests, gate, docs), 1 (A-F2) no change with evidence; none a false alarm
---

# B-pass: generator-step4 (volume titration and plateau escalation switched on, OI-53)

The self-initiated ≥account B-pass (§4.3), on the committed head 5c260f1b with review CI green on that SHA (PR #291).
Two fresh Sonnet seats read the three-dot diff `origin/main...5c260f1b`: seat A the mechanism (read-only), seat B the
tests, gate, harness and records (mutation under a backup / sha256 protocol on `volume_titration.dart` only; file
restored, sha256 verified, tree clean).

## Seat A (mechanism): 0 P0-P2, 4 P3

### A-F1 — P3 — guard_without_its_mirror — accepted, fixed
- **file:line:** `lib/shared/repositories/plan_engine/volume_titration.dart` (T2's lead guard, `keepsR2`)
- **claim:** the guard skipped unbudgeted rows, but R5 (`periodization_engine.dart` `_weekTwoGains`, the `unranked`
  rows with `budgeted: false`) holds them to the lead + 1 too, so a lead trim could leave a custom or timed row at the
  lead + 2.
- **fix:** the guard counts every non-focus row of the day (budgeted or not). Test "T2: an UNBUDGETED row past the
  lead's new sets + 1 blocks the lead's -1 too"; mutant "guard skips unbudgeted rows" red (1).
- **status:** fixed

### A-F2 — P3 — guard_without_its_mirror — no change
- **claim:** `leadFirst: false` switches off only the lead checks; the -1 order and the 2-set floor stay (the old
  first-match / 1-set behaviour is not restored).
- **evidence:** the docs say exactly that (`applyToWeeks` doc, plan engine CLAUDE.md); titration was dark before, so
  no live behaviour is lost; the full revert is `disable_volume_titration`. No doc calls `disable_lead_first` a
  titration revert (grep).
- **status:** no_change_needed

### A-F3 — P3 — unawaited_no_error_sink / reachability — accepted, fixed
- **claim:** the `_toggleKillSwitch` comment said "on a device"; the dev panel exists only in debug builds.
- **fix:** reworded ("on a debug build ... a release build has none, OI-95"); release reachability of every kill
  switch is OI-95 (open, architectural, the board already names step 4's two toggles).
- **status:** fixed

### A-F4 — P3 — writer_reader_drift (docs) — accepted, fixed
- **claim:** `sot_registry.yaml` (12-B reader gates, titration seam (1), plateau seam (1)) and
  `ship_dark_pending_review.yaml` (the readiness row's note) read the retired `enable_*` keys as current rules.
- **fix:** each now says the key is retired and names the kill switch.
- **status:** fixed

## Seat B (tests, gate, harness, records): 2 P2, 5 P3

### B-F1 — P2 — guard_without_its_mirror (mutation) — accepted, fixed
- **claim:** the guard's equality boundary (`current(o) > cur`) was unpinned: `>=` reddened nothing.
- **fix:** test "T2: a row exactly at the lead's new sets + 1 does not block the lead's -1" (`leadTrim(4)` ->
  `[[3, 4], [3, 3], [3]]`); mutant red (1).
- **status:** fixed

### B-F2 — P2 — guard_without_its_mirror (mutation) — accepted, fixed
- **claim:** `declining = a < b` -> `<=` (a flat e1RM read as a decline) reddened nothing; flat is exactly the plateau
  input.
- **fix:** test "a FLAT e1RM is held, not declining: +1 with recovery"; mutant red (1).
- **status:** fixed

### B-F3 — P3 — mutation — accepted, fixed
- **claim:** the 40 % fatigue rule's `.ceil()` -> `.floor()` reddened nothing (only 3/3 and sparse rows were seeded).
- **fix:** test "the 40 % rule: 2 of 6 sore still recovered, 3 of 6 not"; mutant red (1).
- **status:** fixed

### B-F4 — P3 — mutation — accepted, fixed
- **claim:** `creditedOf` -> `of` in `groupsOf` reddened nothing (every fixture had `quadPrimaryCreditsGlutes` true).
- **fix:** test "the quad-first credit: with quadPrimaryCreditsGlutes false a squat earns no Glutes +1"; mutant red (1).
- **status:** fixed

### B-F5 — P3 — asserted_fixture_value (gate strength) — accepted, fixed
- **claim:** the gate's R2 check compared break NAMES, so a break OFF already had that ON made deeper would pass.
- **fix:** `HistorySim.r2Breaks` returns each break's excess over the lead; the gate fails on a new break OR a deeper
  one. Gate re-run on the fixed tree (below).
- **status:** fixed

### B-F6 — P3 — missing_input — accepted, fixed
- **claim:** `history_sim_lib.dart` `isCompound`'s library fallback did `toString()` on the LIST `exercise_type`
  (`['compound']`), which never equals `'compound'`; reached only when a planned row has no type.
- **fix:** the fallback unwraps the list. Gate re-run (the mixed scenario's pins re-measured).
- **status:** fixed

### B-F7 — P3 — records — accepted, fixed
- **claim:** the resolved `enable_volume_titration` row in `ship_dark_pending_review.yaml` kept its 2026-09-01 warning
  ("_recovered() has no readiness gate") verbatim, which T4 made false.
- **fix:** the note now opens "CLOSED by generator step 4 (T4 ...); the warning below is history". The OI-53 text in
  `closed_issues.md` is an archive and stays as written.
- **status:** fixed

## Checked clean (from the seats' reports)

Every reader of the retired and new keys (code: only `plan_engine_flags.dart`); `workingSets` readers (the triggered
un-deload reads an int stash; T3 no longer writes `workingSets: 1`); the lead index stays valid after `copyWith`; the
+1 / -1 mirrors on top / bottom / lead / order; deload and 6-day paths; no non-advance caller opts in (both callers
pass `pins == null`); the flag getters' catch-to-ON is safe (every reader has its own catch to `{}`); T4 mirrors
`PlateauScan`; every new behavioral expectation recomputed by hand and produced for the stated reason; the gate's
variant mapping, timeout, counts, identity worlds, focus groups and time bound; exlog / readiness / library shapes; the
closure ledger; `plan_generator.dart` comment-only (d83). Seat B's own extra mutants M1 (slot tie order) and M4 (band
guard skipped for the lead) were red.

## Founder triage notes

Self-triaged under the standing directive ("let's complete everything"); no finding reopens a recorded decision.

## Tuning entry

- **2026-11-17** - blast-radius platform - 11 findings (0 P0/P1, 2 P2, 9 P3); 0 false_alarm; tuning: two lessons.
  - A rule restated in a new place ("the T1 / R5 predicate") must restate its INPUT SET too, not only its comparison:
    R5 caps unbudgeted rows, the copy filtered them out. Seat A found it by reading the original's loop, not its doc.
  - The author's mutation table covered the new rules but not the pre-existing evidence code the flip makes live
    (`declining`, the 40 % ceil, `creditedOf`): a flip turns old untested boundaries into live behaviour, so the B-pass
    mutation seat should target them by default.
