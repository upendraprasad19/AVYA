# Batch 11 UNIT 11-A — W3.3 ID-keyed history (HARDENED, ships on `workout-idkey-variety-11`)

> Off main `187e0fdd`. Blast radius **platform** (`plan_engine` reader + sync seam). Ship-dark.
> Companion to `batch11-idkey-variety-injurysub.md` (the full 3-item ground-truth). **This branch
> ships 11-A ONLY.** 11-B (①.1d injury-sub) + 11-C (W3.4 variety) — they share the `_cascadeFill`
> seam and Reviewer B (cascade lens) died on the session limit un-converged — move to their OWN
> branch + a FRESH ×2. Explicit founder-approved decomposition per the plan sequencing, **NOT a
> deferral** (each item reaches a terminal shipped state in its own unit).

## Ground truth (Reviewer-A + me, verified against code — byte-exact)
- `logExercise` (`workout_write_service.dart:55-70`, entry map `:166-179`, key `:1056-1063`) takes
  `exerciseName`, NO `exercise_id`; write is `box.put(key, entry)` `:186`.
- **CLOUD-SAFETY (verified):** `sync/sync_workout.dart:198-199` — `final exerciseId =
  (log['exercise_name'] as String?) ?? key;` populates the cloud `exercise_id` column with the NAME;
  summary onConflict `:308` + per-set `:374-384/:395` = `user_id,workout_log_id,exercise_id,set_number`.
  Both upserts are hand-built maps — NO generic row-spread, NO read of `log['exercise_id']` — so a new
  Hive field cannot leak. `workout_log_sets` has `exercise_id` but NO `exercise_name`
  (`live_schema_columns.json:56`). **INVARIANT: the Hive library-`exercise_id` must NEVER reach
  `sync_workout.dart`'s exlog path.**
- id availability: `ExerciseData` (`train_provider.dart:136-161`) has no id; schedule map carries
  `exercise_id` (`:331/:365`) but it's dropped at the `ExerciseData(...)` build (`:378-394`). Coach
  `tool_dispatcher.dart:287` has the id, discarded (`:332`). `conversational_log_handler.dart:252`
  = a 2nd coach path, name-only.
- Readers (name): `ProgressionResolver:82,:90-92,:131-132`; `TrainingHistoryAnalyzer:63` (NAME-keyed
  `taxonomy[name]` — no plan-exercise to id-match). `swap_service` id-aware but on SCHEDULE rows only
  (orthogonal). `exlog_key_canonical_test` = key-string source-grep (no fields).

## Round-1 (Reviewer A) — findings folded (design was `needs-changes`)
| # | Sev | Finding | Resolution |
|---|---|---|---|
| A-P1 | P1 | id-keying `TrainingHistoryAnalyzer` → `taxonomy[<id>]`=null → session volume DROPPED (flag-ON). | **EXCLUDE it from id-keying** — keep name-based (canonical names stable; id adds no value + only drop-risk). Correct scoping, not a deferral (a name-keyed taxonomy MUST read by name). |
| A-P2 | P2 | `ProgressionResolver` `id ?? name` keying SPLITS pre-flag name-logs from post-flag id-logs → lookback loses history. | **INCLUSIVE match:** a log matches a plan exercise iff `log.exercise_id == planEx.id` OR canonical-name matches. Thread the plan exercise's id into `resolve()`. |
| A-P2 | P2 | Cloud pin should be an ABSENCE grep. | **ABSENCE gate** (comment-stripped incl `/* */`): `log['exercise_id']`/`sm['exercise_id']` NEVER in `sync_workout.dart`'s exlog path. |
| A-P2 | P2 | SoT collision (cloud `exercise_id`=name-derived vs Hive=library id). | **Annotate** `hive_field_name_exlog`: Hive `exercise_id` is DELIBERATELY NOT the cloud column's source. |
| A-P2 | P2 | Write not sticky (null-id re-log drops a prior id). | **Sticky:** `exerciseId ?? (existing as Map?)?['exercise_id']`. |
| A-P2 | P2 | 2nd coach path (`submitWorkoutDraft`) omitted. | Stays name-only (harmless); documented as intentional. |

## Converged design (implement)
1. **WRITE (unflagged-additive):** `logExercise` gains `String? exerciseId`; write `exercise_id` when
   non-null, STICKY. Thread onto `ExerciseData` + from the schedule map `:378-394`; coach
   `tool_dispatcher.dart` passes the id. Key + cloud sync UNCHANGED (name-keyed).
2. **READ (GATED `enable_exercise_id_history`, default OFF):** `ProgressionResolver` inclusive
   id-OR-name match (thread plan-exercise id); `TrainingHistoryAnalyzer` EXCLUDED. Flag OFF → byte-identical.
3. **ONE flag** `enable_exercise_id_history` (reader switch only).
4. **CLOUD-SAFETY:** `sync_workout.dart` unchanged + `sync_exlog_no_library_id_test.dart` absence gate.
5. **SoT** `hive_field_name_exlog` field + collision annotation; new `exercise_id_history` concept + behavioral_test.
6. **Tests** `exlog_exercise_id_behavioral_test.dart`: (a) id-log → resolver matches by id (flag ON);
   (b) no-id → name fallback; (c) **split-history**: name-log + id-log same exercise → BOTH counted;
   (d) flag-OFF byte-identical; + the absence gate.
7. No migration; `feat:` → no diagnose-doc; platform → self-B-pass + plan-review record before merge.

## Round-2 (on THIS hardened 11-A) — pending
Verify: inclusive-match avoids split-history loss; `ExerciseData`→resolver id threading is complete +
flag-OFF byte-identical; excluding `TrainingHistoryAnalyzer` is correct; the absence gate catches the
per-set `:377` hole (comment-stripped); no NEW defect from the hardening.
