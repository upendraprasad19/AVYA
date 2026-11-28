---
reviewed_at: 2026-11-28T18:00:00+05:30
staged_against: 3727bccd567c67f21c2e53f9bc7edef4f20d80e7
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 19
verdict: accepted
verdict_note: marked by the coordinating session after triage; the founder approved the last fix and its review, and the merge still needs their go. 16 fixed, 2 unchanged with the reason below, 1 older gap added to OI-403
---

# Code Review (B-pass) — OI-348 walk, the non-referral items

PR https://github.com/upendraprasad19/AVYA/pull/349. Five context-blind Sonnet seats, read-only (named
`flutter test` files and `dart analyze` only). Each seat after the first two reviewed only the fixes made
for the one before it.

| Seat | Reviewed | Result |
|---|---|---|
| A (profile, chart) | `origin/main...b8e970e6`, its half | 2 P2, 3 P3 |
| B (exercise names, equipment, pickers) | the other half | 4 P3 |
| C | `b8e970e6..264b7488` | 2 P2, 4 P3 |
| D | `264b7488..9208c360` | 1 P2, 1 P3 |
| E | `9208c360..3727bccd` | 2 P3 |

The lens `blast_radius_mismatch` was run by seats A and B. Seat C said it did not verify it; the tier of the
whole diff is `platform` (`blast_radius_from_diff.dart` on the PR's file list).

## Seat A

### A1 — P2 — a late body-fat result overwrote a value saved while the AI call ran
- **status:** fixed (264b7488, diagnose d7a2e4). The newer saved value wins; the founder was told and can reverse it.

### A2 — P2 — the next-assessment date was shown as the UTC day
- **status:** fixed (264b7488, diagnose b9e4c3).

### A3 — P3 — the account was checked before the write queued on the profile lock
- **status:** fixed (264b7488): checked inside `patchProfileWith`.

### A4 — P3 — a diagnose-doc tier and line cites were wrong
- **status:** fixed (264b7488).

### A5 — P3 — a re-send after a gateway error could lose the assessment
- **status:** fixed (264b7488): `spendsQuotaPerCall`.

## Seat B

### B1 — P3 — two diagnose docs understated their tier
- **status:** fixed (264b7488).

### B2 — P3 — two stale line cites
- **status:** fixed (264b7488).

### B3 — P3 — the coach swap list showed several hundred exercises with no search
- **status:** fixed (264b7488, diagnose a6f3d9).

### B4 — P3 — a swap could take the community copy over the author's own custom (already on main)
- **status:** fixed (264b7488, diagnose e7c4a1).

## Seat C

### C1 — P2 — a refused result stayed in the open form, so the next SAVE wrote it
- **status:** fixed (9208c360, diagnose d7a2e4).

### C2 — P2 — the start value came from the provider cache, the guard compared with Hive
- **status:** fixed (9208c360, diagnose d7a2e4).

### C3 — P3 — with one send, the function's own 502 answers are no longer retried
- **status:** not changed. All three return before the month's use is recorded, so nothing is spent and the
  user can try again. Retrying them would need the function to answer with a different status.

### C4 — P3 — other id lookups still take the exercise box first
- **status:** fixed where a field the author can edit is read (the injury planner's replaced exercise) and where
  the coach picker listed both rows (9208c360). The confirm card, swap preview, `log_set` name resolution and the
  coach duplicate check read only the name, which cannot be edited on a custom: unchanged.

### C5 — P3 — stale line cites
- **status:** fixed (9208c360).

### C6 — P3 — the swap options were rebuilt on every keystroke; no small-screen test
- **status:** fixed (9208c360).

## Seat D

### D1 — P2 — the planner still picked substitutes from a stale community copy (the same code is on main)
- **status:** fixed (3727bccd, diagnose e7c4a1). The founder was asked first and chose fix and review.

### D2 — P3 — one registry range ran past its method
- **status:** fixed (3727bccd).

## Seat E (no P0, P1 or P2)

### E1 — P3 — an own custom with missing fields replaces the community row's fields
- **status:** not changed. The own row is the one the swap writes, so it is the one to judge. Create stores a
  category and a muscle list.

### E2 — P3, older — the planner does not check equipment
- **claim:** `_findSubstitute` offers a replacement the user's equipment cannot do; `swapExerciseInDay` then
  refuses it on confirm with `equipment_unavailable`. Not introduced by this branch.
- **verification:** `grep -c equipment lib/features/ai_coach/services/injury_swap_planner.dart` gives 0 on the
  branch and on main.
- **status:** added to OI-403 (the same function's open item), not fixed here.

## Founder triage notes
Merge is not covered by this record; it needs the founder's go.

## Tuning entry
- **2026-11-28** - blast-radius platform - 19 findings; 0 false_alarm; tuning: three of the five seats found a gap in the fix written for the seat before (the mirror of the new guard), so a review of the fixes alone earned its cost; the cite sweep sub-check now says to cover every file type.
