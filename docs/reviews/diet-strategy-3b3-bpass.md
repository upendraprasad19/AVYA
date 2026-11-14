---
reviewed_at: 2026-11-15T02:40:00+05:30
staged_against: 248fe49e (3b-3 diff 687baa36..248fe49e; PR #278, stacked on #277 with #276 merged in); fix delta 26d646a7..7ca62cec plus #276's 59755c97..3321a9f3 (seat D)
blast_radius: platform
reviewer: claude-sonnet-via-skill (four fresh agents, no conversation context: three lens groups on the flip, one on the fix delta)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 21
verdict: accepted
verdict_note: no P0 or P1 in any seat; every P2 fixed except two definitions of the effective strategy (A3), accepted with reasons; P3s fixed or accepted (plan §9)
---

# Code Review (B-pass) — diet plan Unit 3b-3, turn the diet strategy on (`diet-strategy-3b3`, PR #278) at 248fe49e

Seats: A writer/reader drift (every reader of `DietStrategyFlags.enabled`, the snapshot keys, every server reader of the stored targets and the column); B guards and their mirrors (the kill switch, the catch, the server half, the flag-on sweep); C tests passing for the wrong reason; D the fix delta on both branches (the weekly-report line on #276 and the test and doc fixes here). The coordinator re-checked each finding against the code before acting. No P0 or P1. Dispositions: plan §9 (`docs/plans/diet-strategy-3b3.md`).

## P2

- **A2 — writer_reader_drift — the weekly report has no strategy.** `weekly-report/index.ts` reads the stored Balanced carbs/fat and shows the week's average carbs with no target, so the model may tell a Keto user to eat more carbs. **Fixed on #276** (`3321a9f3`): `weeklyReportDietStrategyLine` under the protein target (PRO, Low carb / Keto; off with `DISABLE_DIET_STRATEGY_MANUAL_RULES`), deployed with the step-2 functions before this flip. Mutants M1–M8: 8 of 8 red.
- **A3 — writer_reader_drift — two definitions of "effective".** The client applies the strategy only on a complete stored pack; `suggestMeal` caps carbs for any PRO user holding Low carb / Keto. **Accepted:** the incomplete pack is 3a's stated limit (onboarding writes all four), and the server follows the user's own choice in the safe direction.
- **B1 — guard_without_its_mirror — the kill switch is client-only.** **Fixed (docs):** the flag header names the server switches; OI-510 holds them.
- **C1 — tests passing for the wrong reason — the push pin.** It matched a commented-out call and a call outside the pushed map. **Fixed:** comment-stripped, bounded to the `payload` map `_syncUserProfile` upserts, one call site; plus the call-site expression against the real switch. Mutants N1, N2 red.
- **C2 — the fleet-wide-off guard cannot run.** **Fixed:** an order pin in `enabled` (seam, constant, box). Mutants N3, N4 red.
- **C3 — no screen test through the real switch.** **Fixed:** no seam, the real key: no strategy section, a stamped Keto plan loads with no generation, nothing stamped on save. Mutants N5 (key ignored: 9 red), N6–N9 (each screen gate forced) red.

## P3

- **A1** the "only the chat snapshot carries it" wording: fixed in the manual comment, `supabase/functions/CLAUDE.md`, the registry (#276) and `docs/snapshot_contract.yaml`.
- **A4** restore can revert an unpushed choice: accepted (every profile field's merge rule; test accounts only).
- **A5** an older build ignores the stamps: accepted (pre-launch; the Android app gets the flip and the check in one build).
- **B2** an unreadable box means ON: accepted with the reason in the header (configBox opens before `runApp`, cleared never closed at sign-out; only Hive-less tests reach the catch, pinned).
- **B3** the flag-on sweep: CI run 43636703531 ran the full suite on the flip; its two failures (`diet_plan_screen_no_modal_test.dart`) were fixed in `248fe49e`, whose run 43639385573 is green.
- **B4** no in-app lever: stated in the header and plan §5.
- **C4** the unstamped-plan seed names `non_veg`; **C5** the lock count is re-checked after a second wait; **C6** the no-Hive test asserts that `configBox` throws.

## Seat D (the fix delta)

No P0 or P1.
- **D1 (P2)** the weekly-report Deno pins (run with `--no-check` on the source text) stayed green with an import deleted. **Fixed on #276** (`306c89d5`): both imports pinned, comment-stripped; mutants 2 of 2 red. The pins match the exact text, so a reformat turns them red with correct code (loud): accepted.
- **D2 (P2)** the push pin did not see the payload changed after it is built, the queued send, or a second unflagged key. **Fixed:** the queued `_executeUserProfileUpsert(payload)` must follow the map in the same method; no `payload[..]`, cascade, mutating call or reassignment after the map; no literal `'diet_strategy'` key in the map. Mutants N10 (`payload.remove`), N11 (an unflagged key), N12 (the queued path sends another map), N13 (an index write): 4 of 4 red. The real upsert stays pinned by presence; the call-site expression runs against the real switch.
- **D3 (P3)** "a debug build sets it" was wrong: nothing in the app writes the key. **Fixed:** "set by hand (the Hive inspector)"; the catch claim now names `HiveService.init()` before `runApp` and the absence of a background isolate, as an observation of today.
- **D4 (P3)** the header described #276's weekly line as present. **Fixed:** the header says both functions are deployed before this flip (plan §3).
- **D5 (P3)** the late-lock re-check waits a real 200 ms: accepted as bounded.
- **D6 (P3)** the new range 206-217 stopped mid-statement: 206-218 (on #276).

## Mutations

N1–N9 and N10–N13 (client, `flutter test` on the touched files, each applied once, count checked, restored from a copy): 13 of 13 red. M1–M8 and the two import deletions (server, on #276): 10 of 10 red.

## CI

The full suite with the flag on: run 43636703531 on the flip (two failures, both in `diet_plan_screen_no_modal_test.dart`), then run 43639385573 on `248fe49e`: green.

## Founder triage notes

Not needed: no P0/P1, no product decision; dispositions in plan §9.

## Tuning entry
- **2026-11-15** - blast-radius platform - 21 findings; 0 false_alarm; tuning: a flag flip moves the reader question from "who reads the flag" to "who reads the value the flag now lets through": seat A found the weekly report, which never reads the flag and so was outside the plan's reader table, still reading the Balanced targets beside a Keto user's week.
