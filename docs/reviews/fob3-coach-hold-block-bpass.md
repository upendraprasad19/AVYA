---
reviewed_at: 2026-08-21T02:10:00+05:30
staged_against: fob3-coach-hold-block (branch claude/oi-pending-hold-weeks-1od97o)
blast_radius: platform
reviewer: claude-b-pass-self-driven
lens_set: [writer_reader_drift, guard_without_its_mirror, ship_dark_flag_off_equality, prompt_injection_surface, test_proves_nothing, fabricated_default]
findings_count: 2
verdict: accepted
---

# Code Review — FOB-3 (coach snapshot `hold` block + captain_manual)

Two findings, both fixed in-batch. Plus one thing that was caught by running a
mutation rather than by reading code, recorded because the *how* is the useful
part.

## Finding 1 — P2 — fabricated_default / guard_without_its_mirror

- **file:line:** `lib/core/services/workout_schedule_read_service.dart` — `week_start` and `is_deload` were emitted behind `if (info != null)`.
- **claim:** The block's key SET was variable. A hold with no matching
  `HoldWeekInfo` produced a 4-key block that looks complete, and that interacts
  with the exact hazard the keep-set entry exists for: `trimSnapshotToBudget`
  halves a map **by insertion order**, so a 4-key block degrades to
  `{ordinal, label}` — losing the session counts entirely — rather than the
  6-key contract `hold_snapshot_block_behavioral_test.dart` asserts.
- **verification:** the trim proof asserts `(trimmed['hold'] as Map).length == 6`.
  That assertion is only meaningful if the block's key count is fixed; with the
  conditionals it was an assumption about data, not a property of the code.
- **status:** accepted — FIXED, all-or-nothing. A missing `HoldWeekInfo` returns
  null. Both alternatives are worse: a partial block that looks complete is
  dishonest, and defaulting `is_deload` to `false` is a fabricated value — the
  same class as the `body_fat ?? 18.0` this session's Hermes pass rejected.
  **Stated rather than papered over:** the branch is not behaviourally reachable
  today. `activeHoldOrdinalFor` returns today's stamped `hold_ordinal` and
  `activeHoldWeeks` groups every hold row by that same stamp, so an ordinal
  present in one and absent from the other is not expressible. It has no test,
  and a test that faked the divergence would be testing the fake.

## Finding 2 — P2 — writer_reader_drift (the sharper one)

- **file:line:** the seam wrote its own `'H$ordinal'`, beside `lib/core/utils/hold_week_labels.dart` which owns exactly that token.
- **claim:** `hold_week_labels.dart` exists BECAUSE inlined hold-label string
  logic drifts — its own header records a B-pass inverting an inlined ternary
  while all 16 tests stayed green, since a source grep cannot see a logic
  inversion. The first draft of this seam then wrote a second `'H$ordinal'`
  literal: the same mistake, in the batch whose entire purpose is making the
  model quote the SAME identity the user is reading on screen. Two independent
  spellings of that token is precisely how the coach ends up saying "H2" while a
  future UI edit says something else.
- **verification:** `grep -rn 'H\$holdOrdinal\|H\$ordinal' lib/` found **nine**
  sites — seven in the util, `plan_header.dart:186`, `hold_chip_group.dart:203` —
  and the seam would have been the tenth.
- **status:** accepted — FIXED. `holdIdentityLabel(int ordinal) => 'H$ordinal'`
  is now the one place the prefix is spelled, and **all nine** sites compose
  from it, not seven with two named for later: the two widget sites are one line
  each, and leaving them would have left the class open while reporting it
  closed. Output is byte-identical — the existing 73-test hold set stays green —
  and mutation-proven in both directions: respelling the shared token to
  `W$ordinal` reddens **11** assertions across the screen surfaces AND the
  snapshot (which is the whole point of sharing it), and re-inlining a literal
  in the seam reddens 1.

## Not a finding, but the most useful thing this pass produced

**The first keep-set test proved nothing, and only the mutation showed it.**
The initial trim test bloated the snapshot with two giant non-kept fields.
Dropping `'hold'` from the keep set left every test green — because the trimmer
shrinks the *largest* non-kept field each pass, so the two giants absorbed the
whole overage and the ~110-char hold block was never reached. A test written
specifically to pin a line, which the line's removal does not redden, is the
Gate-44 shape inside the guard against it. Replaced with a case where the KEPT
fields alone exceed the budget, forcing the loop to reach `hold` as the only
remaining non-kept field.

## Checks that came back clean, listed so the green is legible

- **No other snapshot field leaks the row-stamped `4 + ordinal`.**
  `workout_schedule_write_service.dart:285` persists `copy['week'] = 4 + n` onto
  every hold row, so any snapshot field reading a row's `week` would carry a
  second false number. Grepped every `schedule[...]` read in
  `ai_snapshot_builder.dart`: the row reads take `type`, `workout_name`,
  `status`, `exercises` — never `week`. The only `'week':` emitted is
  `_getCurrentPlanSummary`'s, which comes from the projection.
- **The flag gate is not duplicated.** The seam delegates to
  `activeHoldOrdinalFor` / `activeHoldWeeks` rather than reading
  `PlanEngineFlags.holdWeeksEnabled` itself, so FOB-1's single-gate property
  holds.
- **The seam is read once.** Hoisted to a local before the map literal; two
  calls would read `nowWall()` twice and could straddle IST midnight on a hold's
  final day.
- **The template literal parses.** 20 unescaped backticks in the first draft
  would have terminated `CAPTAIN_MANUAL` at line 126 and boot-failed ai-proxy
  silently on the next deploy (deploy-skill 6.5). Escaped, then verified by
  extracting the declaration and parsing it with node v22 — 19831 chars, closing
  backtick at line 412, zero unescaped `${`. Deno is not installable here (the
  proxy 403s deno.land), so CI's `deno-edge-functions` type-check is the gate
  this container cannot run.
- **Prompt surface.** The new manual text is static and contains no
  interpolation. The only user-influenced values reaching it are the block's
  ints and an IST date string, all produced by app code, never free text.

## What this review does NOT clear

The `ai-proxy` redeploy. Until it happens the manual half is inert and a
holder's snapshot carries facts the model has not been taught to read — better
than today, not the finished behaviour. Credentials, not permission; commands in
`docs/operations/FOUNDER_LAPTOP_HANDOFF.md` §2-4.
