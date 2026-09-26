---
bug_id: e5c2d1
date: 2026-08-06
batch: post38-auth-fixes (Unit 5 classes 1+2 — one root, two symptoms)
status: fixed
blast_radius: platform
symptom: >
  In one 1.0.0+38 session the founder signed out of user d7a67a37 (12:31:01 UTC)
  and signed into 9e6bde97 via Google (12:31:37). client_errors then shows, over
  roughly twelve seconds, 22 × "new row violates row-level security policy for
  table nutrition_logs" (42501) at 12:35:12.72-21.59, then 14 × "HiveError: Box
  has already been closed" at 12:35:22.07-24.92 across seven distinct restore
  ops (7 ops × 2). Nobody reported either — both are silent to the user. The
  previous Android build with telemetry, 1.0.0+33 (791 rows spanning 54 days,
  2026-06-09 → 2026-08-02), has ZERO of either.
  ⚠ CORRECTED after round-1 review: this paragraph first said "a four-second
  window at 12:35:17-24" and "+33, 184 rows over 11 days". Both were written
  from recollection rather than re-queried; the real RLS storm STARTS five
  seconds before that window opens. The "ZERO of either" claim was and is true.
concept: session_owner_inflight_guard
sot_registry_entry: auth_hive_owner_agreement
writers: >
  CLASS 1 — `_syncNutritionLogs(String userId)` (sync_nutrition.dart:201)
  RECEIVES the id as a PARAMETER and stamps it into every row's 'user_id'
  (:279), upserted a few lines later. The capture happens in its CALLERS:
  sync_nutrition.dart:159 (syncNutritionDataNow), :885
  (pushNutritionLogsForSyncDomain) and sync_service.dart:1047 (weeklyFullSync).
  ⚠ CORRECTED AGAIN 2026-08-17 (closure R2-N8): this line previously cited
  `:856 (_replayPendingNutritionSync)` and `sync_service.dart:1063 (restore
  dispatch)`. `_replayPendingNutritionSync` DOES NOT EXIST — it was invented
  while correcting the R1-A1 fabrication, i.e. a fabricated citation
  introduced by the act of fixing a fabricated citation. All three callers
  above were re-derived by `grep -n "_syncNutritionLogs("` and their enclosing
  methods read directly.
  ⚠ CORRECTED after round-1 review: this first read "sync_nutrition.dart:185
  captures … ONCE at method entry". `:185` is inside `syncSavedMealsNow()`, a
  DIFFERENT writer. The mechanism (an identity resolved once, then carried
  across awaits to a sink) was right; the coordinates were wrong, and the wrong
  provenance had been copied into two code comments before review caught it.
  CLASS 2 — lib/core/services/sync_service.dart restoreFromCloudForUser (:1275+)
  runs a long sequence of _restoreXxx steps, each writing into user-scoped Hive
  boxes, with `if (_restoreCancelled) return RestoreResult.cancelled()` guards
  between steps.
readers: >
  CLASS 1 — Postgres RLS on nutrition_logs: INSERT/UPDATE with_check
  ((SELECT auth.uid()) = user_id). auth.uid() comes from the LIVE bearer token,
  which had already advanced to the new user while the captured userId had not.
  CLASS 2 — HiveUserSession/HiveService close the user-scoped boxes during the
  account swap; the still-running restore's next write finds them closed.
  lib/core/services/sync_service.dart:158 _onUserChanged is the swap hook.
hive_key_prefix: "all user-scoped boxes (userBox / workoutBox / nutritionBox / healthBox / coachBox)"
hive_key_formula: >
  Unchanged. No key format is touched; the defect is about WHEN a write executes
  relative to the session swap, not what it is keyed by.
sync_methods: >
  _syncNutritionLogs (sync_nutrition.dart) gains a sink-side owner re-check.
  All other fan-out methods share the same capture-at-entry shape and are
  candidates for the same guard — see impact_analysis for the honest scope
  statement.
restore_methods: >
  restoreFromCloudForUser and every _restoreXxx step it drives, via the
  between-step guard which now also compares the session owner.
cloud_table: nutrition_logs
cloud_columns: "user_id, date, meal_type (the natural-key arbiter), plus the meal payload columns"
contract_test_path: test/contracts/session_owner_inflight_guard_behavioral_test.dart
ist_handling: >
  not_applicable to the fix. The rows carry IST date keys already and that is
  unchanged; the bug is an identity race, not a date-boundary one.
provider_invalidations: >
  None added. _onUserChanged already reassigns the three sync coalescers and
  drops the realtime subscription; this fix adds the missing restore/write
  half of the same swap contract.
telemetry_op_types: >
  No new op_type. The existing upsert_nutrition_log and restore_sync_* failure
  events are what surfaced this; the fix REMOVES their cause rather than adding
  a signal. The RLS rejections were the server reporting the race for us.
cross_account_guard: >
  This IS a cross-account-guard defect, and the direction matters. RLS rejecting
  those 22 writes was the LAST line of defence, not the intended one: the same
  race with the opposite interleaving — captured id equal to the NEW user while
  the ROWS came from the previous user's Hive box — would satisfy
  auth.uid() = user_id and be written, and Postgres cannot distinguish that from
  a legitimate write. The client-side guard is what makes the direction not
  matter.
forbidden_patterns_checked: >
  No raw Hive.box; no setState; no inline isPro; no secrets; no new
  functions.invoke; no Container(color:+decoration:). Specifically checked that
  the new guard is not itself a check-then-act — see proposed_fix.
proposed_fix: >
  CLASS 2 — a per-invocation owner binding. restoreAbortedFor(ownerId) returns
  true when _restoreCancelled OR ownerId != the live currentUser?.id, and every
  between-step guard passes the restore's own `userId`.
  ⚠ The FIRST attempt at this was WRONG and is recorded here deliberately: a
  private _restoreOwnerId FIELD, cleared in _onUserChanged. That DISARMS the
  guard exactly when it is needed — the outgoing loop reads null, concludes
  "no owner bound", and keeps running. A parameter has no shared state to
  sequence, so there is no ordering to get wrong.
  CLASS 1 — ownerChangedSince(ownerId) checked at the WRITE SINK, immediately
  before the nutrition_logs upsert, not at function entry. Per
  feedback_pause_flag_guard_the_sink: an in-flight call that is already past an
  entry check still reaches the sink.
  Also corrected: the comment at sync_service.dart:181 asserted "the previous
  user's restore loop has already short-circuited". It had not —
  cancelInflightRestore()'s only two callers are RestoringScreen's own decisions
  (:116 new-user, :182 continue-anyway), so NOTHING cancelled a restore on an
  account swap.
regression_test_planned: >
  test/contracts/session_owner_inflight_guard_behavioral_test.dart — drives the
  two predicates against a stubbed live-owner source. Cases: same owner -> not
  aborted (the discriminator: a guard that always aborts would break every
  normal restore and must fail here); different owner -> aborted; explicit
  cancel -> aborted regardless of owner; and the ORDERING case that the first
  attempt failed — an owner change must abort the OUTGOING restore even though
  _onUserChanged has already run and reset the shared cancellation flag.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze lib/ -> 0 errors, 0 warnings, 44 infos (identical count to pre-batch, so no new infos)" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "the restore now stops at its next between-step guard once the owner changes, so it can no longer write into boxes the swap has closed" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "no schema change" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "nutrition_logs: user 9e6bde97 has 0 rows, d7a67a37 has 12 — confirming the rejected writes carried the PREVIOUS user's id against the NEW user's token, not the reverse" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this unit" }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "direct PostgREST writes; no Edge Function in this path" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "client-side race; no cron involvement" }
  - { tier: 8, name: rls_policies, status: verified, evidence: "pg_policies nutrition_logs INSERT/UPDATE with_check ((SELECT auth.uid()) = user_id) — unchanged and deliberately so; it is the backstop that caught this, and the fix makes the client stop relying on it" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage access" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret involved" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no third-party service" }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "the contract is that a row's user_id matches the token that carries it; the client now re-checks that identity at the sink instead of trusting an entry-time snapshot" }
impact_analysis: >
  No data was lost or leaked in the observed incident: RLS refused every
  mismatched write and the closed-box errors aborted writes that would have gone
  to the wrong owner's storage anyway. The severity is in what the SAME race
  does with different timing — a write that satisfies the RLS check is
  indistinguishable from a legitimate one, so the failure mode on the other side
  of the interleaving is a silent cross-account write, which is the exact class
  the two-layer guard exists to prevent.
  SCOPE, STATED HONESTLY: the sink guard covers all FOUR sinks in the nutrition
  fan-out (nutrition_logs, nutrition_log_items, water_logs, user_saved_meals) —
  round-1 review caught that the first version guarded only the first of them,
  and that its `return` exited `_syncNutritionLogs` alone while its two siblings
  ran on under the same `Future.wait`. Every OTHER sync domain still shares the
  resolve-once-then-carry shape and remains susceptible. The restore-side fix
  (class 2) IS global, because its guard lives in the shared between-step check.
  Filed as OI-102 — and that filing was itself a round-1 finding: the first
  version of this paragraph said "Filed as OI-102" when no such entry existed,
  which is a scope gap closed against a tracker that does not exist. The entry
  is real now (`docs/audit/open_issues.md`).
  Not a 1.0.0+38 regression in origin: +33 is simply the previous Android build
  with telemetry, and +36/+37 were web-only, so "new since +33" spans several
  batches and does not identify a culprit commit.
related_bugs: b8e3f1, a7f2e1, c5a1f2
recurrence: >
  Fourth in the cross-account-guard family (b8e3f1 blank Home, a7f2e1 stale
  cached uid, c5a1f2 concurrent background restore, now e5c2d1 in-flight writes).
  The generalisable rule: an identity captured before an await is a SNAPSHOT, and
  every await is a chance for the session to change underneath it. Re-read the
  owner at the side-effect, not at the door.
---

# One root, two symptoms (e5c2d1)

The RLS storm and the closed-box errors look like separate bugs and are the same
event: an account swap landed in the middle of work that had already decided who
it was working for.

## The two shapes

| Class | Captured | Went stale against | Caught by |
|---|---|---|---|
| 1 — nutrition | `userId` param of `_syncNutritionLogs` (`sync_nutrition.dart:201`), captured by its callers | the live bearer token | Postgres RLS (42501) |
| 2 — restore | the whole in-flight restore | the open Hive boxes | Hive (`Box has already been closed`) |

## The fix I got wrong first

Binding the restore to an owner **field** and clearing it in `_onUserChanged`
reads naturally and is backwards: clearing the binding is what disarms the guard
for the loop that still needs it. The outgoing restore sees `null`, concludes
nothing is bound, and continues into the new user's session — the precise
behaviour the fix was meant to stop.

A per-invocation parameter has no shared state, so there is no clearing step and
no ordering to get wrong. Recorded because the wrong version looked correct.
