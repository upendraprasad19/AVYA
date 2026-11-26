---
bug_id: b6e1f4
date: 2026-08-21
batch: fob3-coach-hold-block
blast_radius: account
status: fixed
symptom: >
  FOB-3 of OI-60. The AI coach asserts a falsehood to every holder, every week.
  The snapshot sends `progress.current_week` and `current_plan_summary.week`
  derived from `getCurrentWeekNumber()`, which ends in `.clamp(1, 4)`, and a
  hold week starts at `plan_start + 28` — so the number is 4 (or its program-week
  projection) on EVERY hold day at EVERY ordinal, forever. Nothing under
  `supabase/functions/` read `is_hold` or `hold_ordinal` at all, so the model had
  no way to know a hold was happening.
  The consequence is not a cosmetic off-by-one. `captain_manual.ts` also states
  "free locks at Phase I after 4 weeks", and a free holder's snapshot carries
  `tier: free`. Week 4 + free + locks-after-4-weeks composes into "final week of
  Phase I / upgrade now" — a false milestone the model can regenerate every
  single week, aimed precisely at the user who just chose to stay rather than
  advance. The hold mechanic exists to retain that user; the coach was pitching
  at them instead.
concept: hold_snapshot_block
sot_registry_entry: hold_snapshot_block
writers:
  - { file: lib/core/services/workout_schedule_write_service.dart, line: 288, source: "holdWeek()'s is_hold / hold_ordinal stamps (the method opens at :236) — the ONLY writer of is_hold / hold_ordinal. Unchanged here; cited because the block is derived entirely from these row stamps, so a writer field rename silently empties it" }
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 939, source: "holdSnapshotBlock() — NEW. Returns the facts map on a live hold day, or NULL. Reads activeHoldOrdinalFor/activeHoldWeeks, the SAME gated pair every other production consumer reads, so a hold the flag hides here cannot be visible there. ALL-OR-NOTHING after the B-pass: a missing HoldWeekInfo returns null rather than a 4-key block" }
  - { file: lib/core/utils/hold_week_labels.dart, line: 36, source: "holdIdentityLabel — NEW, and the ONE place the `H` prefix is spelled. All nine on-screen hold labels and the snapshot's hold.label now compose from it. Added by this batch's B-pass" }
  - { file: lib/core/services/workout_schedule_service.dart, line: 182, source: "facade delegation — the snapshot builder already imports this service, so FOB-3 adds no new import to the AI feature" }
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, line: 202, source: "'hold': ?holdBlock — the null-aware element OMITS THE KEY when the seam returns null. That omission is the ship-dark property; 'hold': null would change every snapshot in the fleet" }
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, line: 273, source: "'hold' added to trimSnapshotToBudget's keep set. The trimmer halves a non-kept MAP by insertion order, so an unkept block loses sessions_total first and keeps ordinal — saying LESS the more the user logged" }
readers:
  - { file: supabase/functions/_shared/captain_manual.ts, line: 126, source: "the HOLD WEEKS section — NEW. The instruction half: read snapshot.hold, quote hold.label, IGNORE both projected week fields BY NAME, and NEVER say final-week-of-Phase-I. Inert until ai-proxy is redeployed" }
  - { file: supabase/functions/_shared/captain_manual.ts, line: 109, source: "the PRO-unlock line gains a holder caveat. 'free locks at Phase I after 4 weeks' is TRUE for an advancing user and FALSE for a holder; unqualified it is the premise the model reasons from, ~17 lines above the hold section" }
hive_key_prefix: schedule_
hive_key_formula: "'schedule_' + formatDateKey(date)"
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/hold_snapshot_block_behavioral_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 939, fn: "holdSnapshotBlock reads nowWall() — the seam holdWeek() writes against, so the test clock drives it at three different ordinals" }
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, line: 69, fn: "the seam is read ONCE into a local. Two calls inside the map literal (null-check, then value) would read nowWall() twice and could straddle IST midnight on the last request of a hold's final day" }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  Unchanged. Every row read goes through the user-scoped GuardedBox workoutBox
  via the existing hold read path; no new cloud read or write is introduced. The
  block is assembled client-side from rows already served to this user and is
  carried on the request the coach already sends.
forbidden_patterns_checked:
  - "4 + ordinal projection into user_progress.current_week — FOB-1's explicit do_not, inherited here. NOT done: the block carries `ordinal` and the literal label `Hn`, never a week number, and the two existing week fields are left EXACTLY as they were rather than rewritten. Suppressing them was considered and rejected: they are also read by non-hold logic, and the honest fix is to tell the model to ignore them, which the manual now does by name."
  - "a second flag gate — a fresh PlanEngineFlags.holdWeeksEnabled read inside the snapshot builder. NOT done: holdSnapshotBlock delegates to activeHoldOrdinalFor/activeHoldWeeks so the gate stays in the one place FOB-1 put it."
  - "unescaped backticks in the captain_manual template literal. CAUGHT, not avoided: the first draft added 20 unescaped backticks inside `export const CAPTAIN_MANUAL = \\`...\\``, which terminates the literal at line 126 and stops the module parsing. Escaped, then verified by extracting the declaration and parsing it with a real JS engine (node v22): 19831 chars, closing backtick at line 412, zero unescaped ${."
  - "Container(color:+decoration:) — no widget touched."
proposed_fix: >
  A `holdSnapshotBlock()` seam on the read service returning a FACTS-ONLY map
  (ordinal, label, week_start, is_deload, sessions_completed, sessions_total) or
  null; a null-aware element in the snapshot builder so a non-holder's snapshot
  gains no key at all; `hold` in the trim keep set; and the instruction — what
  the coach must DO with those facts — in captain_manual.ts rather than in the
  per-user snapshot, so the prose is sent once per request instead of being
  charged against the 8500-char trim budget on every holder's snapshot.
regression_test_planned: >
  test/contracts/hold_snapshot_block_behavioral_test.dart — 7 cases driving the
  REAL holdWeek() writer and the REAL buildAiContext(). Mutation-proven on five
  legs, each reddening exactly one test: drop 'hold' from the keep set; change
  the null-aware element to an always-emitted key; swap the gated
  activeHoldOrdinalFor for the raw holdOrdinalForDate; hardcode the label to H1;
  hardcode sessions_completed to 0.
  ⚠ THE KEEP-SET TEST HAD TO BE REWRITTEN, and that is the more useful record:
  the first version bloated the snapshot with two giant non-kept fields, and
  dropping 'hold' from the keep set left all its tests GREEN. The trimmer shrinks
  the LARGEST non-kept field each pass, so the two giants absorbed the whole
  overage and the ~110-char hold block was never reached. A mutation that changes
  nothing observable is not a proof — it is the Gate-44 shape. The replacement
  makes the KEPT fields alone exceed the budget, which forces the loop to reach
  `hold` as the only remaining non-kept field; it then reddens with a 3-key
  block, and the test asserts the key count directly so a partial block cannot
  pass on a loose matcher.
  Plus supabase/functions/_shared/captain_manual_hold_test.ts — 6 Deno tests.
  Importing the module at all is the parse guard; the rest pin the instruction
  the Dart half cannot enforce.
  Two further mutations after the B-pass hardened the label path: respelling
  holdIdentityLabel's return to `W$ordinal` reddens 11 assertions across the
  on-screen surfaces AND the snapshot (which is the point of sharing the token),
  and re-inlining a literal in the seam reddens 1.
  Plus test/contracts/hold_snapshot_block_writer_to_reader_test.dart — 6 cases,
  required by Gate 9 once the concept declared its key prefix, and worth having
  independently: it hand-writes CORRUPT rows, which the real writer cannot
  produce, and pins the four ways the contract can break (renamed hold_ordinal,
  renamed is_hold, is_hold with no ordinal, a hold week that is not today) plus
  the exact 6-key set and the fact that the row's stamped `week` (4 + ordinal,
  the number OI-60's do_not forbids) never reaches the block. A happy-path
  behavioral test cannot reach any of those: it only ever writes correct rows.
  ⚠ Its leak assertion was WRONG on first run, in a way worth recording: with
  ordinal 2 the row carries week 6 and `sessions_total` is ALSO 6 for a
  6-workout week, so `values.contains(6)` went red on a legitimate coincidence.
  A matcher that cannot tell a leak from a collision is not a leak test. Fixed
  by using ordinal 5, where 9 is reachable only from the stamp.
  ONE PATH IS NOT BEHAVIOURALLY COVERED and is stated rather than papered over:
  the `info == null` early return. Both reads derive from the same row stamps,
  so an ordinal present in one and absent from the other is not expressible
  today — the guard exists for if that ever changes, and a test cannot reach it
  without faking a divergence the type system and the data model both forbid.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze: 0 errors, 0 warnings. Full CI-equivalent suite 4790 passed / 7 skipped / exit 0 (baseline 4783 before this batch's 7 cases). 7 mutations run: 5 on the block itself and 2 on the shared label, each reddening at least one test. B-pass returned 2 findings (variable key set; a second `H` literal bypassing the shared formatter) — both fixed in-batch, verdict accepted" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "read-only over existing schedule_* rows; the test drives the real holdWeek() writer and reads back through the new seam. No new key, no schema change" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "no column added, dropped or renamed" }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "no write path touched" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this batch" }
  - { tier: 6, name: edge_function_deploy, status: blocked_on_user, evidence: "⚠ THE ONE OPEN TIER. It is a CREDENTIAL blocker, not a decision and not a choice to do it later — precedent for this status on a tier: diagnose e6b9c4 tier 5. captain_manual.ts is INERT until ai-proxy is redeployed; no Management API token reaches this container (OI-133 item 1 documents the same absence). Verified as far as is possible without deploying: the literal parses under node v22 and all 6 Deno assertions hold when evaluated against the extracted string. Commands for the founder laptop are in docs/operations/FOUNDER_LAPTOP_HANDOFF.md §2-4. CI's deno-edge-functions job type-checks the full tree on this push, which is the parse gate this container cannot run." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron-dispatched function touched" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no table read or written" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no bucket or object touched" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret read or added" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no third-party surface touched" }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "this batch IS the contract change: the Dart half adds the `hold` key, the TS half teaches the model to read it. Both halves move in the same commit precisely so a redeploy cannot land against a snapshot that never sends the key, or vice versa. While enable_hold_weeks is OFF the key is never emitted, so the halves are consistent in either deploy order" }
impact_analysis: >
  Inert until the flip, and the inertness is measured rather than assumed. With
  `enable_hold_weeks` OFF, `activeHoldOrdinalFor` returns null for every date,
  so `holdSnapshotBlock()` returns null and the null-aware element omits the key
  entirely — the snapshot is byte-identical to the pre-FOB-3 one for every user
  in the fleet. The ship-dark group asserts exactly that against a tree with REAL
  hold rows on disk and the flag turned OFF afterwards, which is the state a
  fleet rollback would leave and the state a misplaced flag check would miss.

  WHAT THIS DELIBERATELY DOES NOT DO. It does not suppress or rewrite
  `progress.current_week` / `current_plan_summary.week` for a holder. Those are
  read by non-hold logic too, and blanking them would trade a wrong number for a
  missing one. The honest fix for a PROMPT is to tell the reader what to ignore,
  by name — which the manual now does, naming both fields and explaining WHY the
  number is the same every hold week. That also keeps the Dart half free of any
  behaviour that could break a non-holder.

  THE HALVES SHIP TOGETHER BUT GO LIVE APART, stated plainly. The Dart half
  reaches users with the next APK; the manual half reaches them only when
  ai-proxy is redeployed. In between, a holder's snapshot carries a `hold` block
  the model has not been taught to read — strictly better than today (the facts
  are present and unexplained rather than absent and contradicted), but not the
  finished behaviour. Neither half can go live at all until `enable_hold_weeks`
  flips, which is a separate commit needing the full x2.

  Does not move OI-60 to closeable. FOB-4 and FOB-7(a)/(b) remain, and FOB-4 was
  found during this batch to need MORE than the redeploy its ledger entry
  promises: the live schema carries no hold column of any spelling, so
  weekly-recap-ready and weekly-report cannot branch on a hold whatever is
  deployed to them. That is recorded on OI-60.
---

# The coach asserts a falsehood to every holder, every week (FOB-3)

## What the model was actually reading

A free-tier holder in hold week H2 sent a message. The snapshot carried:

```
"progress": { "current_phase": 1, "current_week": 4, ... }
"current_plan_summary": { "phase": 1, "week": 4, ... }
"subscription": { "tier": "free", ... }
```

and the static manual carried `Phases II-XII auto-generated (free locks at
Phase I after 4 weeks)`.

Every one of those statements is individually true-ish and the composition is
false. `current_week: 4` is not the user's position — it is the last position
before the hold, frozen there by `.clamp(1, 4)` for as long as the hold lasts.
There was nothing anywhere in the payload to say so.

## Why a "just fix the number" fix was rejected

The obvious repair is to make the snapshot send the right week. There isn't one.
A hold week sits OUTSIDE the phase's four weeks — that is FOB-1's finding and
the rule the shipped UI already follows (`plan_header.dart` drops the week
counter while holding). `4 + ordinal` is explicitly forbidden by OI-60's own
`do_not`: it manufactures the number the UI ruled dishonest and demotes a
phase-2 holder from program week 8 to 5 (diagnose `c9f4a2`).

So the snapshot gains an identity it can state honestly (`H2`) and the manual
gains an instruction to prefer it. The two false numbers stay where they are and
are named as things to ignore — because they are also read by non-hold logic,
and because a prompt can be told what to disregard in a way a data field cannot.

## The two things that nearly shipped broken

**Unescaped backticks.** The HOLD WEEKS section refers to `snapshot.hold`,
`hold.label`, `hold.is_deload` and so on. `CAPTAIN_MANUAL` is a template
literal. Twenty unescaped backticks would have terminated it at line 126 and
stopped the module parsing — and per deploy-skill bug-class 6.5 that does not
fail loudly: ai-proxy 503s at boot while the old bundle keeps serving. Found by
reading the file's own existing escapes at lines 403-410, then verified by
parsing the extracted declaration with node.

**A keep-set test that proved nothing.** See `regression_test_planned`. The
first mutation run is what caught it: dropping `'hold'` from the keep set left
every test green.

## What is owed

The `ai-proxy` redeploy. Until then the manual half is inert. It is a credential
blocker in this container, not a decision — the commands are in
`docs/operations/FOUNDER_LAPTOP_HANDOFF.md`.
