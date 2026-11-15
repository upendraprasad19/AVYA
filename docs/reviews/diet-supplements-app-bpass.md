---
reviewed_at: 2026-11-15T15:10:00+05:30
staged_against: c0fe1332 (diet plan Unit 4a, PR #283, base main 708f9049)
blast_radius: platform
reviewer: claude-sonnet-via-skill (three fresh agents, no conversation context, one lens group each)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 26
verdict: accepted
verdict_note: no P0; the P1s were a test that needed the held-back migration file (now in the branch) and a calendar-day worry that was measured away; every other finding fixed or accepted with a reason below
---

# Code Review (B-pass) — diet plan Unit 4a, the client half of opt-in Supplements (`diet-supplements-app`, PR #283) at c0fe1332

Seats: A writer/reader drift and blast radius (the key from writer to Hive, push, restore, snapshot, Edit Profile, registry, docs); B guards and their mirrors, missing input (age rule, PRO, kill switch, shake, stamp, listener, toggle); C test honesty, doses against the manual, user-facing copy. Counts: A 9, B 6, C 11.

## What the pass found that mattered

- **A real restore gap (found by writing seat A's missing test).** `dietSupplementsActiveProvider` read the switch and the date of birth from `userProfileProvider`'s state, and a restore (sign-in on a second device) writes Hive without touching that state: the restored `true` would not have switched Supplements on until a restart. **Fixed:** a `dietSupplementsInputsProvider` that rebuilds on the restore tick and reads Hive; the section and the eligibility provider use it. Mutant N4 (tick dropped) red.
- **B1 / A5 — the kill switch left a saved shake in place.** With the flag off the stamp check was skipped, so a plan saved with the shake still loaded and gave Nutrition-tab hints with the whey item, and a re-save wrote it without the stamp. **Fixed:** the flag off means "not active": a stamped plan is not loaded and gives no hints; an unstamped plan (everyone who never opted in) is unchanged. Test and mutant N2, N3 red.
- **B3 / C10 / A6 — a lapsed user could not switch a stored `true` off** (the switch showed the active state, so every tap was an ON, which went to the paywall; the header comment said otherwise). **Fixed:** the switch shows the stored choice; OFF is allowed without PRO. Test and mutant N1 red.

## P1

- **C1 — the migration pin test had no input.** The migration file was held out of the branch until its apply. **Fixed:** migration 180 applied (founder go, 2026-11-15) and the file, ledger entry and schema snapshot are in the branch.
- **C2 — "6 percent of calendar days the shake tests go red".** The reach test's old header said 47 of 50 seeds. **Measured, not changed:** after the replacement rule the real generator shakes the 1500 kcal / 130 g veg and vegan profiles on 400 of 400 seeds; the reach test now asserts every seed of 200 for both, and its header says what was measured.

## P2

- **A1 — registry ranges.** **Fixed:** recomputed from the anchors (`_generatePlan`, `_generatePlan + _changeFoodType`, `setDietStrategy + _applyDietStrategy`, `_dietStrategyTargets + buildAiContext`, the strategy listener, the blast-radius paths list).
- **A2 — the registry listed too few readers; `dietSupplementsEligibleProvider` was dead code; "one reader" overstated.** **Fixed:** the section now reads eligibility from the provider (one door for the age rule); the registry names the inputs provider, the section, the saved-plan load check, the stamp writer `_savePlan` and the stamp readers; the rule header and the profile CLAUDE.md say what reads what.
- **A3 — restore and Edit Profile were answered by code reading only.** **Fixed:** tests that a cloud `true` and a cloud `false` land over the local value, a cloud NULL leaves it, an Edit Profile-shaped patch keeps it, and a restore tick flips the provider.
- **B1 / B2 — see above (B2 below).**
- **C3 — the dose test compared digits only (B12 weekly vs daily unpinned).** **Fixed:** the period and the unit of each dose are derived from the vector token and asserted; mutant N10 (B12 "a day") red.
- **C4 — the PDF test passed for any content.** **Fixed:** the table's text is made in one place (`supplementTableData`, `kSupplementTableHeaders`) and tested; the PDF test checks the document grows with rows, and its source pin strips comments; mutant N8 red.
- **C5 — PRO and restore reactivity unpinned.** **Fixed:** a mid-session lapse and renewal, a restore tick; mutants N9, N4 red.
- **C6 — the lock icon unasserted.** **Fixed:** present for a free adult and a lapsed user, absent for PRO; mutant N6 red.
- **B2 — a switch flip empties the Nutrition-tab hints with no notice.** **Accepted:** same shape as a change of strategy (3b), whose precedent gives no notice; the user just flipped the switch and sees the rebuilt plan, and the hints return when the plan is saved.

## P3

- **A4 — OI-513 and the rule header cited the legacy chat flow.** **Fixed:** the live `identity_screen.dart:85-102` is cited, "Done when" names both steps.
- **A7 — an offline off-then-on can be undone by the next restore (cloud wins).** **Accepted:** the same behaviour as every profile field; not worse here.
- **A8 — the age is counted on the device's calendar day, not IST.** **Accepted:** a one-day edge on a self-attested date; said in the rule header.
- **A9 — the migration header says "no server code reads this column", `restore-user-snapshot` does `select("*")`.** **Accepted:** wording only, the file is applied and its hash is in the ledger.
- **B4 — the age rule written twice.** **Fixed** (A2).
- **B5 — a zero-calorie item was removed first and freed nothing.** **Fixed:** skipped; test and mutant N5 red.
- **B6 — apply the column before the client merges.** **Done:** applied first.
- **C7 — the coffee line lacks "one cup, no sugar".** **Not changed:** the line is the founder's wording (2026-11-14); it is now pinned exactly.
- **C8 — the doctor line came after the coffee line.** **Fixed:** the doctor line is first (mutant N11 red).
- **C9 — heading "Daily supplements" with a weekly row; "best-evidenced", "needed" firmer than the manual.** **Fixed:** "Your supplements"; the manual's own wording.
- **C11 — accessibility and the one-scoop rule.** **Fixed:** the row is one semantics node, the lock has a label, a footer line states the one scoop a day. **Not changed:** `WardToggle`; the Material switch matches the Diet Strategy block next to it.

## Mutations

The first round (38 mutants M1-M34, H1-H4): all red except M26 (the screen's flag clause, behind the provider's own kill-switch return) and M27 (the swap guard, unreachable from the UI); M19 reds by a hang that CI would also fail. This round, N1-N11 all red, M26 still equivalent.

## Founder triage notes

Not needed: no P0, no product decision. The migration apply and the merge are the founder's gos, given or pending in chat.

## Tuning entry
- **2026-11-15** - blast-radius platform - 26 findings; 1 false_alarm; tuning: a provider that reads a profile through a Riverpod provider whose state a restore never refreshes is stale after a restore, and only a test that drives a restore (or its tick) can see it; seat A asked for that test and writing it found the bug, so a "restore is free" claim in a CLAUDE.md needs a reader-side test, not a reading of the restore code.
