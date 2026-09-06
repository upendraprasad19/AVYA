---
bug_id: d9e1b4
date: 2026-09-06
batch: unitb-deload-reason
status: fixed
blast_radius: platform
related_bugs: [c5a8f3, e3b7d1]
recurrence: >
  Not a recurrence of a named bug. The check must be run against the tree BEFORE this batch, or
  it returns this batch's own two entries and reads as a recurrence of itself:
  `git show 12e7906c:docs/diagnoses/INDEX.md | grep -icE deload` → **0**. (At HEAD the same
  grep returns 4, all of them `c5a8f3` and `d9e1b4`. An earlier draft of this line published
  the unscoped command with the answer "zero" — a command that self-refutes on the tree it
  ships in, caught by plan-review round 3.) The sibling `c5a8f3` filed in this same batch is a
  different mechanism (a stale stored value, not a wrong branch). It IS the FOURTH consecutive ship-dark flip to find the dark code
  was not ready (`e2d6b8`, the 2026-09-01 readiness flip, `e3b7d1`, now this) — and the sharpest
  instance of the class, because the defect is not in the flag's own code at all but in copy the
  flag makes reachable.
symptom: >
  A user in their FIRST training block, on week 4, would be told: "Recovery week — you're two
  blocks in. Time to bank the gains." They are in block one. The same line appears for any user
  after a reinstall, at any phase, because the state it reads is local-only and never restored.

  Never seen in production: the render is behind `enable_deload_reason_line`, which had never
  been ON. This batch is the commit that turns it ON, which is exactly why it had to be found
  here — §4.12.4 calls the flip "the moment real user risk starts".
concept: deload_decision_reason
sot_registry_entry: deload_decision_reason
sot_registry_note: >
  Updated in this commit: `deloadDecisionReason` gains a required `hasDeloadOnRecord` argument
  and the backstop branch becomes two strings. The registry's description of the copy contract
  now states that a decision boolean may not be reused as an explanation without checking what
  else makes it false.
writers:
  - { file: lib/core/services/deload_evaluator.dart, method: "maybeEvaluate — the ONLY writer of last_actual_deload_phase anywhere in lib/; sets it only on a FIRM keep, so it is null until the first firm decision ever made", line: 138 }
  - { file: lib/core/services/deload_evaluator.dart, method: "notBackstop — collapses never-recorded / overdue / future-marker into one false; correct for the decision, ambiguous as an explanation", line: 114 }
  - { file: lib/core/services/deload_evaluator.dart, method: "passes hasDeloadOnRecord: markerPhase != null — the fix; the evaluator already had the distinction and was discarding it", line: 167 }
readers:
  - { file: lib/core/utils/deload_reason.dart, method_or_widget: "the backstop branch — now two strings; the marker-absent one no longer claims a history the app does not have", line: 56 }
  - { file: lib/core/services/deload_evaluator.dart, method_or_widget: "marker read — box.get(_kMarkerKey) returns null on a fresh install and after any reinstall", line: 110 }
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "archetypeForPhase — phase 1 is 'hypertrophy', so notDeloadPhase is TRUE and the structural branch above the backstop is skipped; this is why phase 1 reaches the bad copy at all", line: 15 }
  - { file: lib/features/train/widgets/phase_arc_strip.dart, method_or_widget: "renders the reason line beneath the wave node", line: 111 }
hive_key_prefix: last_actual_deload_phase
hive_key_formula: >
  workoutBox['last_actual_deload_phase'] — an int phase number, LOCAL-ONLY, written ONLY by
  DeloadEvaluator on a firm keep. Null means "no deload has ever been recorded on this device",
  which is NOT the same as "the last deload was long ago" — and the old copy asserted the second
  for both.
sync_methods: >
  not_applicable — the marker is never pushed. `grep -rn last_actual_deload_phase lib/core/services/sync/`
  returns nothing, and the evaluator's own header (`:18-19`) records the design intent: a lost
  marker biases toward KEEP, which is the prudent decision. That is true and is precisely the
  trap — safe for the decision, false as an explanation.
restore_methods: >
  none. The marker is not in any restore bundle, so a reinstall resets it to null at whatever
  phase the user is on. Before this fix that produced the falsehood at ANY phase, not just
  phase 1; after it, such a user correctly reads "no recovery block on record yet".
cloud_table: not_applicable — local-only Hive key; no column, no migration.
cloud_columns: not_applicable — nothing in this fix reads or writes a cloud column.
contract_test_path: test/contracts/deload_reason_test.dart
ist_handling:
  - { file: lib/core/services/deload_evaluator.dart, method: "the eval runs off IST-keyed week-4 rows via getWeek(4); unchanged by this fix", line: 65 }
provider_invalidations: >
  none added. The copy is computed inside `maybeEvaluate` and stamped into Hive; the render path
  (`deloadReasonProvider` -> `PhaseArcStrip`) is untouched by this fix.
telemetry_op_types: >
  none added. A first-block user reading the correct string is the ordinary case, not an anomaly.
cross_account_guard: >
  `last_actual_deload_phase` lives in the user-scoped `workoutBox` opened per-user by
  `HiveUserSession`, so one account's marker can never be read as another's. Unchanged.
forbidden_patterns_checked: >
  Copy work, so the non-shaming brand voice was the live constraint: the new string states a fact
  about the app's own records, assigns the user no blame, and keeps the established
  `<state> — <reason>. <action>.` shape of its six siblings. No `setState`, no widget-level Hive
  or Supabase access, no inline isPro, no API key, no new unawaited without a sink.
proposed_fix: >
  `deloadDecisionReason` takes a required `hasDeloadOnRecord` and the backstop branch becomes:
  true -> "Recovery week — you're two blocks in. Time to bank the gains." (unchanged, and accurate
  for an overdue deload); false -> "Recovery week — no recovery block on record yet. Bank this
  one; it sets your baseline." The evaluator passes `markerPhase != null`, a distinction it had
  already computed at `:110` and was throwing away.

  REJECTED: widening `notBackstop` itself, or making the marker syncable. The first changes a
  live DECISION to fix a string; the second is a real sync-contract change with its own blast
  radius. Neither is warranted by a copy defect.
regression_test_planned: >
  `test/contracts/deload_reason_test.dart` gains four assertions: marker-absent never says "two
  blocks" and does say the new string; marker-present keeps the old copy; the two branches are
  DIFFERENT strings (which catches a collapsed ternary that a per-branch test would not); and
  `hasDeloadOnRecord` is INERT in every other branch. The existing non-shaming sweep was widened
  to include the new branch.

  MUTATION-PROVEN: collapsing the ternary back to the single pre-fix string — the exact defect —
  reddens 2, both real assertion failures with the file still compiling. Confirmed applied by
  `grep -c` first (the removed literal went to 0). 75/75 green across the five touched test files
  after restore.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze lib/ + the five touched test files — 0 warnings, 0 errors" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "last_actual_deload_phase read at :110, written only at :138; no schema change — the fix reads a distinction that already existed" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "local-only key" }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "no cloud read or write" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "no Edge Function touched" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron dispatch" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no table accessed" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no bucket or object" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret involved" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no third-party surface" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "the marker is local-only and in no restore bundle — traced under restore_methods; that is WHY a reinstalled user hit the same falsehood" }
impact_analysis: >
  Corrects a factually false sentence shown to a user. Before the fix, every user reaching their
  first firm week-4 keep — which is every generated phase 1, 2, 3, 5, 6, 7 (phases 4/8/12 take the
  structural "scheduled recovery" branch instead, since archetypeForPhase returns 'deload' there)
  — would read "you're two blocks in" while in block one.

  Reachability is not marginal: `plan_generator.dart` gates the week-4 stash on
  `triggeredDeloadEnabled`, live since 2026-09-01, so every plan generated since then satisfies
  the evaluator's stash guard and reaches the decision.

  No user has seen it: the render flag has never been ON, and this batch is the commit that turns
  it on. Blast-radius platform, so full ×2 plan review plus `bpass: accepted` — which is the
  process that caught it, on round 2, after a B-pass and round 1 both passed over the copy.
---

# d9e1b4 — the backstop branch claims a history the app does not have

## What happens

`DeloadEvaluator` decides whether to lift a week-4 deload. One clause is a backstop:

```dart
// deload_evaluator.dart:114
final notBackstop = markerPhase != null &&
    markerPhase <= phase &&
    (phase - markerPhase) < 2;
```

`notBackstop == false` means *"I cannot confirm a recent real deload"*. That is the correct,
conservative polarity for a **decision** — all three of its causes should produce a keep. The
causes are not interchangeable, though:

| Cause | True statement |
|---|---|
| `markerPhase == null` | no deload has ever been recorded on this device |
| `phase - markerPhase >= 2` | the last deload was two or more blocks ago |
| `markerPhase > phase` | the marker is ahead of the current phase (corrupt) |

`deloadDecisionReason` reused that one boolean as an **explanation** and picked wording for the
middle row only: *"Recovery week — you're two blocks in."*

`last_actual_deload_phase` is written by exactly one line in the whole repo
(`deload_evaluator.dart:138`) and is never synced or restored. So it is null on a user's first
ever firm keep — and again after any reinstall, at any phase.

Phase 1 reaches this branch because `archetypeForPhase(1)` is `'hypertrophy'`
(`periodization_engine.dart:15-18`), so `notDeloadPhase` is true and the structural branch above
the backstop is skipped.

## Why nobody caught it earlier

The line had never been rendered. It was written in Batch 10 behind a flag that stayed OFF, and
this batch is the flip. Round 1 and a B-pass both reviewed this commit and neither read the copy,
because the diagnose-doc asserted, one sentence after *"the line becomes visible for the first
time"*, that *"no new copy reaches a user"*. That clause is true of the guard the batch adds and
false of the flip it performs, and it exempted all five copy branches from scrutiny at exactly
the commit §4.12.4 identifies as the start of real user risk. It has been struck.

## The rule worth keeping

**A decision boolean is not an explanation.** Any flag computed to make a safe choice may be
false for several unrelated reasons; the safe choice is identical for all of them, and the
sentence explaining it is not. Before writing copy off a decision flag, enumerate what else makes
that flag false — and if more than one thing does, the copy needs the distinction the decision
did not.

The evaluator already had it. `markerPhase` was read at `:110`, used at `:114`, and discarded.
The fix passes one more boolean.
