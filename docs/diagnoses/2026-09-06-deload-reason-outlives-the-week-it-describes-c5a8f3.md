---
bug_id: c5a8f3
date: 2026-09-06
batch: unitb-deload-reason
status: fixed
blast_radius: platform
related_bugs: [e3b7d1]
recurrence: >
  Not a recurrence of any named bug in `docs/diagnoses/INDEX.md` — `grep -inE "deload" INDEX.md`
  returns ZERO lines, and the nearest neighbours (`f4c8e1` hold-week clamp, `d7f3a9` `redoWeek4`,
  `a7d3f1` restore week/phase drift) are week-4 IDENTITY bugs that never touch the reason string.
  Recorded explicitly so a future audit can verify the check happened.

  It IS an instance of the repo's default suspect class, writer/reader drift
  (`feedback_writer_reader_field_drift_recurring.md`, >=15x): two facts about ONE decision — the
  wave character and the prose explaining it — were stored in two places, and only one of them
  was maintained by the paths that change it. It is also the FOURTH consecutive ship-dark flip to
  find the dark code was not ready (see `e3b7d1`); this one differs in that the defect was found
  by review BEFORE the flip rather than during it.
symptom: >
  A user who completes a week-4 deload that the evaluator LIFTS (week becomes `working`, reason
  stamped "Working week — you've recovered"), and then edits their profile and taps Reschedule —
  or asks the AI coach to regenerate — would see the phase-arc strip render a DELOAD node with
  the line "Working week — you've recovered" directly beneath it, for the remainder of that
  phase. Not transient and not self-healing: nothing in `lib/` deletes the reason key, and the
  idempotency flag blocks the only code that could rewrite it.

  Never observed in production because the render is behind `enable_deload_reason_line`, which
  has been OFF since it was built. The WRITE, however, has been live since 2026-09-01, so the
  stale values already exist in real users' Hive.
concept: deload_decision_reason
sot_registry_entry: deload_decision_reason
sot_registry_note: >
  Updated in this commit: the stored VALUE is now a map (`{week_character, text}`) rather than a
  bare String; the reader is documented as self-validating against `currentWaveCharacters()[3]`;
  the ship-dark note became the `disable_deload_reason_line` kill-switch; and the new behavioral
  test is cited. The description previously named only ONE re-stamping path (`:388`); it now
  distinguishes the TWO blob-rewriting paths (`:388`, `:227`) that this guard can see from the
  AI-coach regen, which writes rows only and is therefore invisible to it (OI-166).
writers:
  - { file: lib/core/services/deload_evaluator.dart, method: "maybeEvaluate — stamps deload_reason_phase_<P> as {week_character, text}; week_character is liftedAny ? working : deload, the same predicate the copy branches on", line: 159 }
  - { file: lib/core/utils/deload_reason.dart, method: "deloadDecisionReason — pure + total; structural-before-evidence; had-data-gated; outcome-based on liftedAny", line: 16 }
  - { file: lib/core/services/deload_evaluator.dart, method: "_liftWeekFour — rewrites week_plans[3].week_character to 'working'; the blob edit the reader now validates against", line: 244 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "generateAndScheduleFromDate — re-stamps the blob unconditionally on a mid-phase regen; live caller edit_profile_screen.dart:2029 passes the CURRENT phase", line: 388 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "generateAndSchedule — the third blob writer; moves plan_start, so usually a NEW phase (absent key) but re-stamps in-phase on a faithful repeat", line: 227 }
  - { file: lib/features/ai_coach/services/regenerate_plan_planner.dart, method: "AI-coach regen — re-stamps week_character on ROWS ONLY; writes NO blob, so it is invisible to this guard by construction. Filed as OI-166, not fixed here", line: 294 }
readers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "currentDeloadReason — SELF-VALIDATING: returns text only while the stamped week_character equals waves[3]", line: 1116 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "the equality check itself — EQUALITY not '== working', so the mirror (stored deload, blob working) drops too", line: 1167 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "currentWaveCharacters — the blob the strip renders; the validation source, deliberately not the scheduled rows", line: 1273 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "deloadReasonProvider — watches currentPlanProvider so a regen rebuilds it", line: 944 }
  - { file: lib/features/train/widgets/phase_arc_strip.dart, method_or_widget: "the flag gate + week-4 condition; null reason renders no line", line: 74 }
hive_key_prefix: deload_reason_phase_
hive_key_formula: >
  workoutBox['deload_reason_phase_<P>'] where P = deloadPhaseFromWeek4(getWeek(4)) — the SHARED
  derivation the evaluator's flag/marker also use, so the key cannot drift between writer and
  reader. Value shape as of this commit: {week_character: 'working'|'deload', text: String}.
  A bare String is a LEGACY value (2026-09-01 until this commit) and resolves to no line.
sync_methods: >
  not_applicable for the reason key itself — it is LOCAL-only and is never pushed. The blob it is
  validated against IS synced (`sync_workout.dart:1108`), which is precisely why the mirror case
  is reachable and why the check is an equality rather than a one-sided test.
restore_methods: >
  `sync_workout.dart:1107-1108` restores `current_plan` only when no local blob exists. A restore
  onto a device holding a stale reason therefore lands a blob whose week 4 may disagree with the
  stamped character — which now suppresses the line instead of rendering a contradiction. No
  restore path writes the reason key, so a restored device shows no line until its next
  evaluation, which is correct: the decision was never made on that device.
cloud_table: not_applicable — the reason key is local-only; no column, no migration.
cloud_columns: not_applicable — nothing in this batch reads or writes a cloud column.
contract_test_path: test/contracts/deload_reason_staleness_behavioral_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "getWeek — derives week-4 dates from plan_start via IST date keys; unchanged by this batch", line: 1070 }
provider_invalidations: >
  `deloadReasonProvider` watches `currentPlanProvider` (`train_provider.dart:945`), so the regen
  that re-stamps the blob also rebuilds the reason read — the suppression takes effect on the
  same rebuild that shows the DELOAD node. The new dev-panel toggle invalidates
  `currentPlanProvider` for the same reason its phase-arc sibling does: the flag is read
  non-reactively, so without the invalidate the kill-switch looks inert.
telemetry_op_types: >
  none added. Deliberate: a suppressed line is the EXPECTED steady state after any regen, not an
  anomaly, so logging it would emit noise on an ordinary user action. Contrast
  `phase_arc_truncated_week_plans`, which fires on a genuinely malformed blob.
cross_account_guard: >
  The reason key lives in the user-scoped `workoutBox` (opened per-user by `HiveUserSession`), so
  it cannot leak across accounts. The new test exercises it through `HiveUserSession.openForUser`
  exactly as the sibling behavioral tests do.
forbidden_patterns_checked: >
  No `setState` for shared state; no direct Hive/Supabase access from a widget (the strip reads
  through `deloadReasonProvider` -> the service facade); no inline `isPro` check; no API key; no
  new `unawaited(` without an error sink; `Container(color:+decoration:)` not introduced. The
  dev-panel toggle is `kDebugMode`-gated like every sibling.
proposed_fix: >
  (1) WRITER `deload_evaluator.dart:159` stores {week_character: liftedAny ? 'working' : 'deload',
  text: deloadDecisionReason(...)} instead of a bare String. `liftedAny` is already the predicate
  the copy branches on, so this records what the text always assumed.
  (2) READER `currentDeloadReason()` returns `text` only when the stamped character equals
  `currentWaveCharacters()[3]`. Mismatch, malformed map, legacy bare String, or a blob shorter
  than 4 weeks -> null -> no line, byte-identical to the pre-flip state.
  (3) FLIP `enable_deload_reason_line` -> `disable_deload_reason_line`, catch-block default ON;
  dev-panel toggle added (it never had one).

  REJECTED, with reasons, so neither is re-proposed: clearing
  `deload_evaluated_for_phase_<P>` on regen so the eval re-runs and writes a correct line —
  it mutates the LIVE `triggered_deload` feature, since a re-eval could lift the freshly
  regenerated week 4; and `_liftWeekFour` returning blob-write state, which round 2 of the
  phase-arc review proved targets an unreachable contradiction while creating a reachable one.
regression_test_planned: >
  `test/contracts/deload_reason_staleness_behavioral_test.dart` (20 tests) covers the regression,
  a positive control, the mirror, both legacy/malformed shapes, the short-blob and absent-blob
  cases, phase mismatch, and that the kill-switch gate still works on a VALID value (a bare
  String there would have passed for the wrong reason). `deload_eval_behavioral_test.dart` gained
  an end-to-end REGEN case driven by the real evaluator, asserting the key SURVIVES and the flag
  stays set while the reader suppresses.

  MUTATION-PROVEN on four legs, each leaving the code compiling (a compile error is not a
  proof), each confirmed applied by `grep -c` first, and each MEASURED ACROSS ALL FOUR
  TOUCHED TEST FILES — not one — because the first attempt ran leg 1 against a
  single file and under-reported it as 2. Deleting the equality guard reddens 4; making it
  one-sided (`stamped == 'working' && ...`) reddens 2 (the mirror in both layers); reverting
  the writer to a bare String reddens 3 (lift shape, keep shape, regen precondition);
  deleting the `waves.length < 4` guard reddens 1.

  That last leg is why `validatedDeloadReason` exists as a separate pure function. With the
  guards inline in `currentDeloadReason`, plan-review round 1 measured that deleting the
  length guard, the `is! Map` guard or the `stamped`-shape guard reddened ZERO of twelve
  assertions: the resulting RangeError / NoSuchMethodError was swallowed by that method's
  crash-safety `catch` and produced the SAME null the tests asserted. Four assertions were
  testing the exception handler. The extraction makes every null come from an explicit guard.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze lib/ + the three touched test files — 0 warnings, 0 errors (44 infos, all pre-existing deprecations)" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "the stored value shape changed from String to Map; 12 new behavioral assertions drive real Hive boxes through HiveUserSession, plus the end-to-end evaluator round-trip" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "local-only key; no column touched" }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "no cloud read or write in this batch" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "no Edge Function touched" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron dispatch involved" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no table accessed" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no bucket or object touched" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret read or added" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no Razorpay / OneSignal / Firebase surface" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "the reason key is never synced; the blob it validates against is, and the restore path (sync_workout.dart:1107-1108) only seeds when absent — traced and recorded under restore_methods" }
impact_analysis: >
  User-visible change is the flip itself: the week-4 deload line becomes visible for the first
  time. Its content is unchanged; what changed is that it can now be SUPPRESSED. Suppression is
  strictly a reduction — every state that previously rendered a line either still renders the
  same line or renders none.

  ⚠ An earlier draft ended that sentence "so no new copy reaches a user", which was FALSE
  and load-bearing: it is true of the GUARD and false of the FLIP. This commit makes ALL FIVE
  copy branches of `deloadDecisionReason` user-visible for the first time, and plan-review
  round 2 found one of them stating a falsehood — the backstop branch told a first-block user
  they were "two blocks in", because `notBackstop` is ALSO false when no deload has ever been
  recorded. Fixed in this batch; see diagnose `d9e1b4`. The lesson is that one clause exempted
  every copy branch from review at precisely the commit §4.12.4 calls "the moment real user
  risk starts".

  Existing users carry LEGACY bare-String values written since 2026-09-01. These resolve to no
  line for the remainder of their current phase and self-heal at the next phase advance, when the
  evaluator stamps the new shape. Since the render has never been on, nobody loses a line they
  can currently see.

  The blast radius is `platform` (verified via `blast_radius_from_diff.dart -`, with the explicit
  stdin dash), driven by the flag file and the core read service, so this batch takes the full x2
  plan review plus `bpass: accepted`. Section 4.12.4's lighter ship-dark tier explicitly does not
  apply to a flip: the flip is the moment real user risk starts.
---

# c5a8f3 — the deload reason outlives the week it describes

## What happens

`DeloadEvaluator.maybeEvaluate()` decides, once per phase, whether to lift the week-4 deload. It
stamps the outcome into the schedule rows and the plan blob, and stamps a one-line explanation
into `deload_reason_phase_<P>`. It then sets `deload_evaluated_for_phase_<P>` so it never runs
again for that phase.

Three code paths rewrite the plan afterwards, and each re-derives week 4 from the generator, which
always makes it a `deload`:

| Path | Line | Reachable in-phase by |
|---|---|---|
| `generateAndScheduleFromDate` | `workout_schedule_read_service.dart:388` | Profile edit -> Reschedule (`edit_profile_screen.dart:2029`, passing `phase: currentPhase`) |
| `generateAndSchedule` | `workout_schedule_read_service.dart:227` | Phase advance; in-phase only on a faithful repeat |
| AI-coach regen | `regenerate_plan_planner.dart:294` | "Regenerate my plan" in chat (`resolvedPhase`) |

None of them touches `deload_reason_phase_<P>`; no code in `lib/` deletes it. And the evaluator
cannot fix it, because `deload_evaluator.dart:79` returns early on the idempotency flag.

So after a lift followed by any regen: the node says DELOAD, the line says "Working week — you've
recovered", and nothing will ever reconcile them.

## Why the fix is at the reader

A deleter would have to be added to both blob-rewriting call sites, and a third added later
would owe one silently — with no gate to notice. The reader is a single seam that also
covers cross-device sync and restore, neither of which any deleter would have caught.

## What this does NOT close, stated precisely

Both independent reviewers pushed on the same two boundaries, and an earlier draft of this
doc overclaimed both. Recording them so nobody reads the class as closed.

**1. The AI-coach regen is invisible to this guard, by construction.**
`RegeneratePlanPlanner` writes schedule ROWS only — applied one at a time through
`WorkoutWriteService.upsertScheduled` — and touches no blob (a `current_plan` /
`_planKey` / `week_plans` grep over both files returns 0). So it cannot make the line
contradict the node: it moves neither. What it does is leave BOTH stale together, which is a
pre-existing defect of the phase-arc strip itself, shipped with flag 3 on 2026-09-05.
**Filed as OI-166**, with fix options and a recommendation, because the honest repair
changes an AI-coach WRITE path — a different blast radius from the read-side display fix
this batch is.

**2. A KEEP reason survives a regen that produces another deload week.** Stamp `deload`,
blob `deload` after the regen — the equality holds and the line renders. Round 1 read this
as the defect still being live for the common case. It is not the same defect: the shipped
bug was a CONTRADICTION (a `working` line under a `DELOAD` node), and here node and line
agree, both saying recovery week, which is what the user is actually doing. The reason's
*evidence* is older than the regen, but its *claim* — "this is a recovery week" —
remains true. The guard detects an OUTCOME change; it deliberately does not attempt "was
this decision re-made", which would need a generation nonce and cannot be inferred from the
wave character. Said plainly rather than letting "SELF-VALIDATING" imply more than it does.

What made this possible cheaply is that the writer already computes the answer. `liftedAny` is the
exact predicate `deloadDecisionReason` branches on to choose between "Working week" and "Recovery
week logged" — the copy was already asserting the outcome, just not recording it. Storing it turns
an assumption into a checkable fact.

## The one subtlety worth remembering

The strip renders the **blob** (`currentWaveCharacters` -> `week_plans[i].week_character`), while
`currentDeloadReason` derives its phase from the **scheduled rows** (`getWeek(4)`). Validating
against rows would have been the obvious choice — the method already reads them — and would have
allowed the line to contradict the node above it any time the two disagreed. The validation reads
the blob for exactly the same reason `deloadPhaseFromWeek4` is shared between writer and reader:
whatever the display uses is what the guard must use.

## The concept, in full

(This was the `concept:` field until plan-review round 1 pointed out that
`build_bug_index.dart` renders that field verbatim into a markdown TABLE CELL and a
heading, so a multi-paragraph block scalar breaks the generated `INDEX.md` — the file
§4.1.5 tells every session to grep first. `concept:` is specified as a name from
`docs/sot_registry.yaml`; the prose belongs here.)

The reason string and the wave character are two views of ONE decision, and only the character
is maintained by the three paths that rewrite a plan. The prose is written once, by the
evaluator, under an idempotency flag that guarantees it is written AT MOST ONCE per phase —
which is exactly what makes it unable to track anything that happens afterwards.

The fix does not add a deleter to each rewriting path. There are three today
(`generateAndSchedule`, `generateAndScheduleFromDate`, the AI-coach regen) and any fourth added
later would silently owe one — the "fixed the instance, not the class" shape from
`feedback_mistake_guard_without_its_mirror.md`. Instead the writer records the OUTCOME beside
the prose and the READER refuses to return prose whose outcome no longer matches the plan. One
seam covers both blob-rewriting paths, plus cross-device sync, restore, and anything added
later. (It does NOT cover the AI-coach regen, which writes no blob at all — see "What this does
NOT close" above. This paragraph said "all three paths" until plan-review round 2 caught that the
retraction had been added without the original claim being struck.)

The validation reads the BLOB, not the scheduled rows, because the blob is what the strip
renders (`phaseArcProvider` -> `currentWaveCharacters`). Validating against rows would have let
the line contradict the node directly above it whenever the two disagreed — the same
writer/reader question the fix exists to answer, one level down.

## Mutation results

Measured across ALL FOUR touched test files (`deload_reason_staleness_behavioral_test.dart`,
`deload_eval_behavioral_test.dart`, `phase_arc_reader_behavioral_test.dart`,
`readiness_flag_no_hive_default_test.dart`) — 63 assertions green at baseline.

| Mutation | Compiles | Red | Which |
|---|---|---|---|
| Delete the equality guard | yes | 4 | regression + mirror, in both the behavioural and pure layers |
| One-sided: `stamped == 'working' && ...` | yes | 2 | the mirror alone, in both layers |
| Writer stores a bare String again | yes | 3 | lift shape, keep shape, regen precondition |
| Delete `if (waves.length < 4) return null;` | yes | 1 | the pure-layer index guard |

Each was confirmed applied with `grep -c` before running, and each failure was an assertion
failure rather than a compile error.

⚠ **The first three were originally reported as 2 / 1 / 3, measured against ONE file.**
That is this repo's own "a green check is only as wide as its input set" rule, broken by
the person who had just written it down. Leg 4 previously reddened ZERO — it is the leg
that motivated extracting `validatedDeloadReason`.
