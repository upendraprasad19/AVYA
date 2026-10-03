---
bug_id: c8f3d1
date: 2026-08-01
batch: oi45-phase-advance-monotonic (Unit 3c + task #41 of the OI-25/44/45/46/48/50 batch)
status: fixed
blast_radius: platform
symptom: >
  Every path that advances a user to the next training phase computed the new
  phase number BEFORE a real, slow plan generation and wrote it after. A
  concurrent advancer landing inside that window was silently overwritten by
  the stale, LOWER number — and graduation_screen generated its plan entirely
  outside the shared advance mutex, so two paths could generate the same phase
  and the second overwrote the first's schedule rows and plan_start under a
  user already looking at the plan.
concept: phase_progress_current_phase
sot_registry_entry: phase_progress_current_phase (docs/sot_registry.yaml)
writers: >
  All three now route through the ONE shared writer
  lib/shared/services/pro_phase_advance.dart commitPhaseAdvance:
  pro_phase_advance.dart runProPhaseAdvance (splash unawaited +
  PhaseGeneratingCard CTA) · graduation_screen.dart _onPro (the explicit
  unlock) · simulation_service.dart _maybeAdvancePhase (kDebugMode dev
  harness). Pre-fix each wrote its own updateProgress delta carrying a
  pre-await phase number. The other two current_phase writers are unchanged
  and were already monotonic or authoritative: phase_progress_reconciler.dart
  reconcile (boot heal, monotonic by reconciledPhase) and
  onboarding_provider.dart saveProgress (the first-ever write to a new
  account, legitimately phase 1).
readers: >
  week_selector.dart (_phaseRoman + _toPastPhases), train/plan_header.dart,
  train_provider.dart CurrentPlanNotifier.build, ai_snapshot_builder.dart
  (progress.current_phase into the coach snapshot), and the cloud projection
  user_progress.current_phase via sync_service.dart _syncUserProgress — every
  one of which would have rendered or transmitted the demoted number.
hive_key_prefix: userBox key 'progress' (the whole progress map).
hive_key_formula: >
  not_applicable — 'progress' is a single fixed userBox key, not a
  date/name-derived key. The field within it is progress['current_phase'].
sync_methods: >
  UserRepository.updateProgress fires unawaited SyncService.syncProgressNow(),
  which pushes progress via sync_profile.dart's user-progress RPC. Unchanged by
  this fix — the same call, with a value that is now guaranteed non-decreasing.
restore_methods: >
  not_applicable — no restore path changed. sync_service.dart's progress
  restore writes current_phase from the cloud snapshot and is not one of the
  advance writers.
cloud_table: user_progress
cloud_columns: >
  No column added, dropped or renamed. current_phase / current_week /
  phase_started_at / plan_generated_at are written with the same names and
  types as before; only the VALUE selection changed (monotonic) and the two
  timestamps now come from one instant instead of two DateTime.now() calls
  microseconds apart.
contract_test_path: test/contracts/pro_phase_advance_behavioral_test.dart
ist_handling: >
  not_applicable — phase_started_at / plan_generated_at are full ISO-8601
  instants, not IST date keys, and were already written that way. The dev sim
  keeps its nowWall() clock seam, threaded explicitly through
  commitPhaseAdvance's `now` parameter so simulated runs still stamp simulated
  time.
provider_invalidations: >
  Unchanged set. graduation_screen still invalidates currentPlan / todayWorkout
  / calendarWeek / workoutStats / streak / allExercisePRs / aiInsight /
  graduationStats on success, and now ALSO invalidates currentPlan +
  todayWorkout on the two early-out paths (already-advanced, and lock-busy) so
  /train cannot render the pre-advance plan.
telemetry_op_types: >
  Two new logEvent names, both integers-only (no PII, Gate 22 clean):
  phase_advance_conflict_skipped (source + live + intended) fires when the
  monotonic writer declines, and phase_unlock_advance_busy (phase) fires when
  graduation finds the shared lock held. Before this, both conditions were
  completely invisible.
cross_account_guard: >
  not_applicable to the new code — commitPhaseAdvance writes through
  UserRepository.updateProgress, which goes through the already-guarded
  user-scoped userBox. The existing cross-account belt inside
  markPhaseRepeatNudgePending (currentOwnerFullId != null) is untouched and
  still runs on the graduation repeat branch.
forbidden_patterns_checked: >
  - Container(color:+decoration:) — n/a, no decoration touched.
  - unawaited() without an error sink — the two new unawaited calls are
    ErrorTelemetry.logEvent, the repo's designated sink.
  - .functions.invoke without FunctionException handling — n/a, no invoke.
  - Source-grep without stripping comments — the group-E wiring assertions
    match code strings that do not appear in any comment in those files;
    verified by reading the files, not assumed.
  - BuildContext across an async gap — the new busy-path early-out is behind
    `if (!mounted) return;`, matching the surrounding code.
proposed_fix: >
  One monotonic writer (commitPhaseAdvance) that re-reads current_phase at
  write time and refuses to write a lower or equal value, plus a pure
  @visibleForTesting decision helper (phaseAdvanceTarget) mirroring
  PhaseProgressReconciler.reconciledPhase; the module-private advance mutex
  promoted to a shared withPhaseAdvanceLock that graduation_screen now takes
  around generation + write; graduation's live-phase abort check hoisted out
  of a ship-dark-flagged branch onto the default path; and the session
  bootstrap hoisted into the public wrapper so the advance core is drivable
  from a test.
regression_test_planned: >
  test/contracts/pro_phase_advance_behavioral_test.dart — 15 tests
  (re-measured on the final tree, not carried forward: `+15 All tests passed`). Both
  behavioral cases were proven to DISCRIMINATE by negative control, not
  assumed: reverting the monotonic guard makes the demotion test fail
  (current_phase 2, expected 3), and reverting the write to a whole-map
  saveProgress from the pre-await snapshot makes the unrelated-field test fail
  (total_workouts_done 11, expected 12).
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "4 lib/ files changed (pro_phase_advance.dart, graduation_screen.dart, simulation_service.dart, phase_progress_reconciler.dart). `flutter analyze --no-fatal-infos lib/` reports 43 issues, all pre-existing info-level in unrelated files (share_plus deprecations, dart:html, nutrition_screen BuildContext infos); zero in the touched lib/ files, verified by filtering the output to those paths. Round-1 review corrected an earlier draft that called 43 the REPO-WIDE count — it is the lib/ count; repo-wide is higher because test/ carries its own infos. The new test file itself contributes 2 (`depend_on_referenced_packages` for path_provider_platform_interface + plugin_platform_interface, measured directly), identical to the two the existing day_rollover_provider_invalidation_behavioral_test.dart carries for the same imports; analyze runs --no-fatal-infos so neither blocks." }
  - { tier: 2_hive, status: fixed_in_this_batch, evidence: "The bug and the fix both live in the userBox 'progress' map. 14 behavioral tests run against real Hive boxes in a temp dir; 6 of them assert Hive state directly after commitPhaseAdvance (write / skip-whole-delta / never-demote / null-progress default), and 2 drive the real advance with a concurrent interposed Hive write." }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "No DDL. current_phase, current_week, phase_started_at and plan_generated_at all already exist on user_progress; no column added, renamed or retyped, so backups/live_schema_columns.json is unchanged." }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "No backfill and no data repair. A phase demoted by this bug in the past is not detectable after the fact (the write leaves no trace distinguishing it from a legitimate value) and at 18 live users with a single device each there is no evidence any occurred — stated as unknown rather than claimed clean." }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "This batch adds no migration; backups/applied_migrations.json is unchanged and no apply_migration call was made." }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "Client-only change. No supabase/functions/ file is touched, so no function needs deploying and no git-vs-deployed delta is created." }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "No cron function reads or writes current_phase on the advance path. weekly-recalc writes user_progress counters but not current_phase (verified by reading its update payload)." }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "No policy changed; the write reaches Postgres through the same already-authorized user-progress sync path." }
  - { tier: 9_storage, status: not_applicable, evidence: "No bucket or object touched." }
  - { tier: 10_secrets, status: not_applicable, evidence: "No secret read, written or rotated." }
  - { tier: 11_external_services, status: not_applicable, evidence: "OneSignal / Gemini / Razorpay untouched. No push or payment surface reads current_phase on this path." }
  - { tier: 12_client_server_contract, status: verified, evidence: "Traced the full chain by direct read: commitPhaseAdvance -> UserRepository.updateProgress -> saveProgress (Hive put + deployments_complete monotonic stamp) -> unawaited syncProgressNow -> _syncUserProgress -> sync_profile.dart's user-progress RPC params (p_phase_started_at / p_plan_generated_at present, same keys). The cloud payload SHAPE is unchanged; the fix changes only which value is chosen." }
impact_analysis: >
  Nothing here is a reported live incident, and this doc does not claim one. The
  concurrency window needs two advance paths active at once — the splash's
  unawaited pass or the Home/Train card CTA overlapping a graduation unlock, or
  either overlapping the boot reconciler's heal — which at 18 single-device
  users is rare rather than impossible. What the fix removes is the failure MODE:
  a demoted current_phase is user-visible everywhere (the Train phase label, the
  week selector, the AI coach's snapshot) and self-inconsistent, because
  deployments_complete is already monotonic and would NOT follow the phase back
  down. The double-generate is the more likely of the two: it silently rewrites
  the schedule rows and plan_start of a plan the user may already be looking at.
  Both were also completely untelemetered before this batch; each now emits a
  distinct event when it happens.
---

# c8f3d1 — Stale phase target + unguarded generation across the three advance paths

Closes **OI-45** (with Unit 3a `6258622b` and Unit 3b `fa05aa88`). Unit 3c of the
OI-25/44/45/46/48/50 batch, bundled with task #41's behavioral-coverage gap
because both needed the same test seam.

## What was actually wrong

`current_phase` is the one progress field with **no monotonic guard anywhere**.
`UserRepository.saveProgress` (`lib/shared/repositories/user_repository.dart:128-135`)
guards `deployments_complete` — `max(prior, phase-1)`, explicitly for this bug
class — and writes `current_phase` straight through.

All three advance paths read the phase, then `await` real plan generation
(tens-to-hundreds of ms of Hive writes), then write:

| path | reads | awaits | writes |
|---|---|---|---|
| `pro_phase_advance.dart` | `:72` | `autoGenerateNextPhaseIfNeeded` `:90-101` | `:117` |
| `graduation_screen.dart` | `:568,573` | `generateAndSchedule` `:663-680` | `:707` |
| `simulation_service.dart` | `:536` | same `:549-558` | `:565` |

Unit 3a converted the latter two from `saveProgress(wholeStaleMap)` to
`updateProgress(delta)`. That fixed the clobber of *other* fields — but the
`current_phase` **value** inside the delta was still the pre-await one. So the
residual was common to all three, not unique to graduation as OI-45's
blocked-on line described.

Concurrent writers that can land in that window, all confirmed by direct read:
`advanceProPhaseIfExpired`, reached from `splash_screen.dart:225`'s
`unawaited(_autoGenerateNextPhaseForPro())` (the helper at `:255-262` then
awaits the advance — so the *call* at `:257` is awaited, the *pass* is not; an
earlier draft cited `:257` as "fired unawaited", which round-1 review corrected)
and on tap from `phase_generating_card.dart:55`; `PhaseProgressReconciler.reconcile`
(`phase_progress_reconciler.dart:86`), which can jump by more than +1 and is
called from `restoring_screen.dart:384,696` — NOT from the splash boot path, as
an earlier draft's "boot heal" shorthand implied; and the dev sim.

### The existing guard did not run

`graduation_screen.dart` already had an abort-if-changed re-read — but inside
`if (offerChoice)`, and `offerChoice` requires
`PlanEngineFlags.adherenceGateEnabled`, which is **ship-dark, default OFF**
(`plan_engine_flags.dart:212-218`). On the production default path that branch
has never executed. It looked like protection and was not.

### The second, likelier failure

Graduation ran `generateAndSchedule` entirely **outside** the module-private
`_advanceInFlight` mutex that `advanceProPhaseIfExpired` uses. So a splash pass
and a graduation unlock could each generate the same phase — two generations
writing overlapping `schedule_*` rows, each moving `plan_start`, the second
overwriting the first under a user already looking at the plan.

## Recurrence

Third instance of the monotonic-demotion class
(`feedback_monotonic_field_recompute_demotion.md`):

- `3a7b9f` (2026-05-27) — rank demoted SD1 → SD2; `weekly-recalc` overwrote
  `total_workouts_done` with a recomputed current-state value.
- Migration 115 / Unit 3b `fa05aa88` — `GREATEST`-guarded `total_workouts_done`
  and `deployments_complete` in the new progress RPC.
- `c8f3d1` (this) — `current_phase` written from a pre-await read.

The through-line: **a field that only ever moves forward needs an
only-increment writer, and every parallel writer needs the same guard.** The
guards for rank (`RankService.shouldPromote`) and for the phase reconciler
(`reconciledPhase`) already existed in exactly this shape; the advance paths
simply never got one.

## The fix

`lib/shared/services/pro_phase_advance.dart` gains three things:

- **`phaseAdvanceTarget({livePhase, intendedPhase})`** — pure,
  `@visibleForTesting`, returns the phase to write or `null` to skip. Same shape
  as `PhaseProgressReconciler.reconciledPhase`.
- **`commitPhaseAdvance({intendedPhase, source, now})`** — the single writer.
  Re-reads `current_phase` from Hive **at write time**, applies the helper, and
  writes the delta. A skip skips the **whole** delta: writing `current_week: 1`
  and `phase_started_at` against somebody else's advance would reset the week
  and the phase-start date under them, which is the same damage by another
  route. `now` is threaded so the dev sim keeps its `nowWall()` seam.
- **`withPhaseAdvanceLock(body, {ifBusy})`** — the former private
  `_advanceInFlight` mutex, now shared. Graduation takes it around generation +
  write, and **never across the choice sheet** — a modal waiting on human input
  must not block the splash's advance.

Graduation additionally hoists its live-phase re-check onto the default path,
and shows the same "still finishing up" recourse the `PhaseGeneratingCard`
already gives when it finds the advance busy.

**What the hoist actually buys, stated precisely** (round-1 review caught this
over-claim — an earlier draft said "so it guards every unlock"): on the flag-OFF
production path there is **no `await`** between the `progress` read at `:568` and
the re-check, so `live == currentPhase` always and the early-out is
provably unreachable today. It is load-bearing only across the choice-sheet
await — which is exactly the window it was written for, and which becomes real
the moment the ship-dark adherence gate flips ON. The default path's real
protection is the shared lock plus `commitPhaseAdvance`'s write-time re-read.
The hoist is still right (it is now correct for both branches instead of one),
it is just not what closes the default-path hole.

**The guard deliberately does NOT go in `saveProgress`**, which looks like the
right choke point because that is where `deployments_complete` is stamped. A
blanket monotonic `current_phase` there would break the two legitimate resets to
phase 1 — `onboarding_provider.dart:472` and the dev `resetJourney` — both of
which call `saveProgress` directly. The guard belongs to the *advance*
operation, not to the storage primitive.

## Why the lock was kept, when the last two mutexes were not

This repo has twice built a mutex for a suspected progress race, tested it, and
found it bought nothing — once removing it again (`user_repository.dart:95-116`,
where it also broke two tests). The same question was asked here and answered by
test, not by argument: `withPhaseAdvanceLock` **is** observably load-bearing.
The Group C test starts one holder, calls a second entrant while the first is
suspended, and asserts the second body never runs. That assertion fails the
moment the lock stops excluding — which is exactly the discrimination the
removed `UserRepository` mutex could never produce, because Hive's `Box.put()`
lands synchronously and `Future.wait([a(), b()])` runs `a()` to its first
suspend point before `b()` is invoked. The difference is that this lock guards
*entry to a long async body*, not the ordering of two synchronous Hive writes.

## Task #41 — the coverage gap, and what the B-pass got slightly wrong

The B-pass on Unit 3a (finding 4, `docs/reviews/9d758b27ab29-review.md`)
correctly reported that no test drove the real advance functions, so a revert of
Unit 3a's fix would pass the full suite. It attributed this to needing
"genuinely novel test infrastructure ... no `workoutScheduleServiceProvider`
override exists anywhere in the suite today."

That was half right. Driving **real plan generation** in a test was already
established — `repeat_content_scheduling_test.dart:154-195` seeds the real
`assets/data/exercise_library.json` into `exerciseBox`, opens a Hive user
session, and calls the real `generateAndSchedule`. No provider override is
needed, and this batch's tests use none.

The actual blocker was narrower and was the **auth seam**:
`advanceProPhaseIfExpired` called `HiveUserSession.ensureOpenedForCurrentSession()`
(`hive_user_session.dart:111-126`), which reads
`SupabaseService.instance.currentUser` and returns `null` whenever Supabase was
never initialised — so in a unit test the function returned `false` on its
second line and nothing downstream ran.

Fix: the two bootstrap lines move up into the public wrapper (still after the
in-flight check, so ordering is unchanged), leaving `runProPhaseAdvance`
`@visibleForTesting` as the drivable core.

**Rejected alternative:** teaching `ensureOpenedForCurrentSession` to consult the
existing `debugAuthUidResolverForTests` seam (`guarded_box.dart:223-227`). It
would work and it is an established pattern in this repo — but
`hive_user_session.dart` is platform-tier cross-account-guard code, and widening
a test-only auth bypass there buys a test convenience at the cost of a real leak
vector.

## The tests, and how each was proven to discriminate

`test/contracts/pro_phase_advance_behavioral_test.dart`, 15 tests:

- **A (3)** — pure `phaseAdvanceTarget`: normal +1, live == intended, live >
  intended.
- **B (4)** — `commitPhaseAdvance` against real Hive: writes the full delta;
  **skips the whole delta** (asserting `current_week` and `phase_started_at` are
  untouched); never demotes; defaults a missing progress map to phase 1.
- **C (3)** — `withPhaseAdvanceLock` excludes a second entrant, releases even
  when the body throws, and becomes a pass-through under its kill-switch.
- **D (2)** — the real path. `runProPhaseAdvance` with real generation and an
  interposed concurrent write.
- **E (3)** — wiring: each of the three writers routes through the shared
  helper, and the bootstrap stays on the production entry point.

Both D tests were run against deliberately broken code to prove they can fail:

| negative control | test | result |
|---|---|---|
| `commitPhaseAdvance` writes `intendedPhase` unconditionally | D1 | FAILS — `current_phase` 2, expected 3 |
| write reverted to `saveProgress(Map.from(preAwaitSnapshot)..addAll(...))` | D2 | FAILS — `total_workouts_done` 11, expected 12 |

D2 exists because D1 **cannot** pin Unit 3a's fix: under the monotonic guard a
demotion scenario ends in *no write at all*, so it can never expose a whole-map
clobber. D2 therefore uses a scenario with no phase conflict — the advance
really does write 1 → 2 — and interposes an unrelated field.

### One false green, caught and fixed

D1's first draft interposed the concurrent write after a 20 ms
`Future.delayed`. It passed. It was also **wrong**: if generation had finished
inside those 20 ms, the interposed write would simply be the last writer and
`current_phase == 3` would hold even against the pre-fix code. Two changes: an
explicit `expect(advanceDone, isFalse)` precondition so a miss fails loudly
instead of passing vacuously, and the delay replaced with a single
`Future.delayed(Duration.zero)` event-loop yield — **shorter is safer here**,
because calling an async function runs it to its first suspend point, so one
yield guarantees the advance is parked inside generation. The 20 ms version then
proved the point by failing the precondition on D2's second (JIT-warm) run.
Stable across three consecutive full-file runs afterwards.

## Round-1 review — 9 findings, all dispositioned

No P0. Four P2, five P3. Every one is recorded because several corrected *this
doc*, not the code.

| # | Finding | Disposition |
|---|---|---|
| P2-1 | The registry's `behavioral_test_path:` still pointed at `phase_progress_reconciler_test.dart` — a PURE test that can't fail if the writer breaks. The new behavioral test had been added under `readers:`, where no gate looks. | Fixed: field now points at the new test; the reconciler's pure test is cited on its writer entry. |
| P2-2 | "Hoisted so it guards every unlock" over-claims — on the flag-OFF path there is no `await` between the read and the check, so it is unreachable today. | Fixed: restated in the code comment, this doc, and the OI closure. |
| P2-3 | 7 writers `put('progress')`; only one is `saveProgress`. Two cloud-wins restore merges can demote the phase, bypassing everything this batch added. | Filed as **OI-83** + the residual section below. Scoped out deliberately, with the reason stated. |
| P2-4 | `PhaseProgressReconciler` was the one phase writer left outside the new lock — and the most dangerous, since it buckets the very `schedule_*` rows a locked generate is rewriting, and its own header says an over-advance is unrecoverable. Also: it is called from `restoring_screen.dart`, not the splash "boot" path. | Fixed both: `reconcile` now runs under `withPhaseAdvanceLock` (skipping when busy, with telemetry — it is idempotent and runs every restore), and the citation corrected. |
| P3-1 | `advanced == false` fell through to `phase_unlock_completed` + "Phase N unlocked" — asserting a write that never happened. | Fixed: distinct event `phase_unlock_counter_already_advanced` + truthful copy. |
| P3-2 | The `Duration.zero` comment claimed a guarantee; a zero-timer is an event-queue item, so it is a strong ordering assumption. | Fixed: comment restated. Kept the design — the precondition makes a miss fail loudly, which is the property that matters. |
| P3-3 | If a group-C `expect` threw before `release.complete()`, the module-level lock stayed held for the rest of the file. | Fixed with `addTearDown`. |
| P3-4 | Group-E source-greps didn't strip comments (nothing vacuous today; a future comment would make it so). | Fixed. |
| P3-5 | "43 issues repo-wide" is the **lib/** count; the new test file adds 2 infos of its own; the `splash_screen.dart:257` "fired unawaited" citation is one frame off (`:225`). | All three fixed. |

**Refuted by round 1, and reverted:** mid-review I had hardened both live-phase
reads from `as int?` to `as num?)?.toInt()`, on the theory that a cloud restore
could deliver `current_phase` as a double and silently collapse the guard to
phase 1. The reviewer's live `information_schema` query says the column is
`integer`, and testing the case directly showed `saveProgress`
(`user_repository.dart:129`) casts `as int?` on the same field and **throws**
on a double — loudly, before this read could ever see it. So the failure the
hardening defended against cannot occur, and the hardening was dead code
carrying a false rationale. Both the cast and its test case were removed rather
than kept "just in case", per this repo's own rule that a detector which can
never fire is worse than none.

## Round-2 review — 4 findings, ALL of them round-1 regressions

Run on the hardened diff per §4.12.1, with the reviewer told explicitly that its
primary job was to attack round-1's corrections. It was the right instruction:
**every one of the four findings was caused by a round-1 remediation.** No P0/P1;
severity strictly decreasing (1 P2, 3 P3). That profile — later rounds finding
fewer and lighter defects, all traceable to the prior round rather than newly
discovered in the original work — is the convergence signal §4.12.1 describes,
not the "unit is too large, split it" signal.

| # | Finding | Disposition |
|---|---|---|
| P2 | **Round-1's own fix introduced a starvation bug.** `withPhaseAdvanceLock` is a TRY-lock — it returns `ifBusy` immediately, it does not queue. So wrapping `reconcile` in it meant a contended boot silently DROPPED the two-Phase-1 heal, with nothing to retrigger it, and `reconcile`'s only callers are on the restore path (`restoring_screen.dart:384,696`) which may not run again for months. Round-1's safety argument — "idempotent, runs on every restore" — was wrong in a subtle way: idempotence makes *re-running* safe, not *skipping* safe. Before the change the heal ran unconditionally. | Fixed: bounded retry (3 attempts, 1.5s apart) before giving up, with the give-up telemetry carrying the attempt count. The delay is paid only when contended — and in that case the user is already waiting on the advance that holds the lock. |
| P3 | "The one remaining `current_phase` writer outside the lock is none" — false, and contradicting the paragraph five lines above it. | Fixed: restated as "no ADVANCE-operation writer remains outside", with the by-design writers enumerated. |
| P3 | The revert's stated rationale was wrong. It claimed `saveProgress` would throw on a double first — true only for writers that go through it, and **four do not** (`sync_profile.dart:613-622`, `auth_session_bootstrapper.dart:323-328`, `sync_restore_completeness.dart:242,411`). Reviewer flagged it could not verify the column type itself. | Fixed: rationale replaced with the one that actually holds — the SCHEMA. I verified it myself rather than taking either reviewer's word: live `information_schema` says `current_phase` is `integer`/`int4`. Also corrected "matching every other reader" (`sync_profile.dart:100,289,301` use `num?)?.toInt()` on the cloud-payload side). |
| P3 | Calling the primitive a "mutex" misleads — one primitive now serves two semantics, and the reconciler wanted the one it doesn't have. | Fixed in the doc comment (explicitly a TRY-lock, with the required `ifBusy` argument named as the signature-level reminder). Not renamed: the retry above resolves the semantic mismatch at the caller, which is where it belongs, and a rename would churn three call sites and the wiring tests for no behavioural gain. |

## B-pass — 2 P2, 1 P3, no P0/P1

Self-triggered before the merge (§4.3). All five lenses plus the project gates;
it independently reproduced the negative control (bypassing `phaseAdvanceTarget`
→ D1 fails `Expected: <3> Actual: <2>`).

**F1 (P2) — a consequence neither review round had named.** When
`commitPhaseAdvance` declines (`advanced == false`), the `schedule_*` rows and
`plan_start` that `generateAndSchedule` already wrote for `nextPhase` are not
rolled back. The counter stays correct; the schedule content can be stale
against whatever the concurrent writer delivered. Both remedies applied:
- **Narrowed in code**: graduation now re-reads the live phase *once more inside
  the lock*, immediately before generating. The pre-lock check cannot see a bump
  that lands between it and acquisition — and the OI-83 restore writers do not
  take this lock at all. One Hive read replaces a wasted full generation, with
  its own event (`phase_unlock_preempted_before_generate`, distinct from the
  post-generate decline).
- **Named in OI-83** for the window this does *not* close: a bump landing
  *during* generation. That belongs to OI-83's design question, and is now
  written there explicitly so it is not rediscovered as a fresh incident.

**F2 (P2) — the frontmatter said `account`; the staged set measures `platform`.**
Correct, and my own earlier measurement was the fault: I classified a hand-typed
list of four `lib/` files instead of the actual staged set. Every `lib/` file
here is `account`; the tier is driven entirely by this batch editing
`docs/blast_radius.yaml`, which is platform-tier by the registry's own
self-referential rule. Frontmatter corrected to `platform`.

That tier's `requires:` list (`docs/blast_radius.yaml:25`) is
`[regression_test, behavioral_test_path, code_review_b_pass, feature_flag]` —
the first three were already satisfied; `feature_flag` was not. Added
`configBox['disable_phase_advance_lock']`, gating **the lock only**, in the same
default-OFF-means-active `disable_*` shape as `disable_phase_reconciler` and
`disable_bg_restore`. The split is deliberate: the lock is the risky new
primitive (round 2 already found one starvation bug in it), so a runtime escape
hatch is real value; the monotonic guard is pure and cannot wedge anything, and
a switch whose only effect would be to re-enable the demotion bug is not a
safety valve. Both halves of that reasoning are in the code.

**F3 (P3) — the reconciler retry adds latency to a foreground path.** Confirmed
by direct read: `restoring_screen.dart:384` awaits it, and its own comment says
the corrected counter must land before /home reads `currentPlanProvider`. The
reviewer quoted ~4.5 s; the arithmetic is 2 gaps for 3 attempts, not 3, so it
was 3 s. Retry gap tightened 1.5 s → 1 s, making the worst case **2 s**, bounded
in any event by the restore screen's documented 15 s CONTINUE escape hatch.

## Gate 43 blocked this commit — and the resolution was a founder call

`graduation_screen.dart` was **794 lines against Gate 43's 800-line ceiling** —
six to spare — so this fix could not touch that file at all without tripping the
gate. It is now 892 (+98, of which **77 are comment lines added at the direct
request of the three review rounds**, which is its own small lesson about where
rationale belongs).

I checked the gate for a per-run exception before proposing anything: there is
none. No env var, no `--warn-only`, `exit(1)` unconditional. The only two routes
past it are an allow-list entry or `--no-verify`, and the second is the
route-around-a-gate move §4.3 forbids.

Three options were put to the founder with measured line counts: hoist the
locked block into the shared advance service (~120 lines out, screen → ~770);
split the screen per the gate's own prescription (`screens/graduation/` +
parts, mirroring `active_workout/`); or add the allow-list entry. **Founder
chose the allow-list entry**, explicitly, after being shown that the list is a
one-way ratchet whose every prior movement was a removal (C3: 2430→456; C4:
three screens 2419/2274/1906 → 312/376/357) and that this would be the first
addition ever made to it.

Recorded rather than done quietly, because the difference between "the founder
paused the ladder" and "we deferred" is whether it is written down and owned:
the allow-list entry carries the full reason inline, and the split is filed as
**OI-84** with the recommended shape and an instruction to remove the entry in
the same commit. One correction I made to my own framing while presenting it:
this is a NEW seventh entry, not a reopening of C3/C4 — `graduation_screen.dart`
was never one of their targets.

## Residuals, stated — what is NOT monotonic after this

`current_phase` is now monotonic **on the advance operation**. It is not
monotonic as a field. `grep -rn "put('progress'" lib/` returns **7** direct
writers of the whole progress map; exactly one is `saveProgress`. Two of the
others are cloud→Hive merges that copy the PostgREST row verbatim, cloud-wins,
straight into `userBox` (`sync/sync_profile.dart:612-622`,
`auth_session_bootstrapper.dart:322-328`), and two more write the map directly
(`sync_restore_completeness.dart:242,411`). A stale cloud row restored over a
locally-advanced value demotes the phase with no guard and no telemetry.

That is out of this batch's scope on purpose, and the scope line is not a
convenience: a restore that refuses to lower `current_phase` is right for a
second device that is behind and **wrong** for a genuine account restore where
the cloud row is the only truth left. Picking between those is a product call,
not a mechanical fix. Filed as **OI-83** with the scoping question stated, rather
than left implied by this doc's `restore_methods: not_applicable` — which is
scoped-correct but reads, on its own, as if the field were now safe everywhere.

Scoped precisely, because an earlier draft of this paragraph said "the one
remaining `current_phase` writer outside the shared lock after this batch is
none" — which round-2 review correctly called false, and self-contradicting
against the paragraph directly above it. What is true: **no ADVANCE-operation
writer remains outside the lock.** `PhaseProgressReconciler.reconcile` was
brought under it here (round-1 review), because it derives its target from the
very `schedule_*` rows a locked `generateAndSchedule` is mid-rewrite of. The
writers still outside are outside by design and are not advances: the two
legitimate resets to phase 1 (`onboarding_provider.dart:472`, the dev
`resetJourney` at `simulation_service.dart:146`), the cloud-payload builders
that never touch Hive (`sync_service.dart:1102`,
`onboarding_provider.dart:785`), `updateProgress`'s own default seed
(`user_repository.dart:191`), and the four restore-path map writers now tracked
as OI-83.

## Coverage stated honestly

`simulation_service._maybeAdvancePhase` is `kDebugMode` dev-harness code and
`graduation_screen._onPro` is a full screen behind a router; neither is driven
end-to-end here. Their **write semantics** are covered because both now route
through the `commitPhaseAdvance` that group B tests behaviorally; group E pins
that routing by source-grep. That is behavioral coverage for the writer and
presence coverage for the wiring — said plainly rather than implied
(`feedback_source_grep_false_confidence.md`).
