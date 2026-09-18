---
bug_id: b2d9f4
date: 2026-09-18
batch: Task 5 (C5) — ai-coach-ux-tool-integrity spec 2026-09-18
status: fixed
blast_radius: account
symptom: |
  Tool-integrity audit (2026-09-18, spec
  docs/superpowers/specs/2026-09-18-ai-coach-ux-tool-integrity-design.md, item C5)
  found three defects:
    1. `_appendInjuryToCoachMemory` (tool_dispatcher.dart) performs a
       read-modify-write of coachBox 'coach_memory' with NO mutex. Two intent
       cards from one multi-intent turn are confirmed INDEPENDENTLY — each user
       tap runs its own `ToolDispatcher.execute`
       (pending_tool_intents_provider.dart:52) — so two concurrent executes can
       race the RMW and one injury append is lost.
    2. `_executePausePlan`'s `on PausePlanException` catch returned a failure
       WITHOUT ErrorTelemetry, while every sibling failure path logs
       (reschedule `tool_dispatch_reschedule_week_failed` at :805,
       modify-for-injury `tool_dispatch_modify_workout_for_injury_failed` at
       :643).
    3. Doc drift: the ai_coach CLAUDE.md `coach_derived_completion` SoT row
       claimed "Idempotent: per-date lock + under-lock status re-check" — but
       the per-date lock lives inside markCompleted
       (workout_write_service.dart:424) and `_maybeCompleteScheduledDay`'s
       status re-check (tool_dispatcher.dart:399) runs OUTSIDE it; the
       benign-race posture is documented at workout_write_service.dart:430-439.
concept: coach_memory_injury_append
sot_registry_entry: null
writers:
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: _appendInjuryToCoachMemory (writer of coach_memory.injuries), line: 1626 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: _executePausePlan PausePlanException catch (telemetry writer), line: 1129 }
readers:
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, method_or_widget: _getCoachMemoryForContext (coach_memory excerpt fed to the AI prompt; 'injuries' projection at :541), line: 163 }
  - { file: lib/features/ai_coach/CLAUDE.md, method_or_widget: coach_derived_completion SoT row (doc reader of the lock topology), line: 40 }
hive_key_prefix: coach_memory
hive_key_formula: coachBox 'coach_memory' singleton map → ['injuries'] list of {part, severity, since}
sync_methods: []
restore_methods: []
cloud_table: ""
cloud_columns: []
contract_test_path: test/contracts/coach_memory_injury_append_mutex_test.dart
ist_handling:
  - "No date arithmetic changed — 'since' keeps its existing DateTime.now().toIso8601String().split('T').first derivation inside the locked body, untouched."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - tool_dispatch_pause_plan_failed
cross_account_guard: "No new write paths — the mutex serializes the EXISTING coachBox write (HiveService.instance.coachBox, user-scoped); the telemetry fire-and-forget writes no Hive state."
forbidden_patterns_checked:
  - { pattern: "over-serialization: the mutex covers ONLY the coach_memory RMW — the swap loop and planner-cache clears stay outside the lock, so a slow swap can never stall an unrelated intent card", absent: false }
  - { pattern: "lock without release: the chained-future pattern completes the Completer in a `finally`, so a throw inside the RMW body cannot deadlock every later append", absent: false }
proposed_fix: |
  1. Mutex (plan's exact shape): a static chained-future lock —
     `static Future<void> _coachMemoryLock = Future<void>.value();` — each
     call captures `prev`, installs a fresh Completer future as the new lock
     tail, `await prev;` under try/finally with `completer.complete()` in the
     finally. dart:async was already imported.
  2. Telemetry: `unawaited(ErrorTelemetry.logEvent('tool_dispatch_pause_plan_failed', message: '${e.code}: ${e.message}'))` before the failure return, mirroring the reschedule pattern at :805.
  3. CLAUDE.md row: replaced "Idempotent: per-date lock + under-lock status re-check." with the corrected topology sentence citing workout_write_service.dart:424, tool_dispatcher.dart:399 and workout_write_service.dart:430-439.
regression_test_planned:
  - test/contracts/coach_memory_injury_append_mutex_test.dart
impact_analysis: |
  The mutex adds serialization only around the coach_memory RMW (microseconds
  of work between get and put) — no lock is held across the swap loop or any
  network call, so no throughput change is observable. The telemetry addition
  is fire-and-forget on a path that already returns a failure. The CLAUDE.md
  edit is doc-only. The @visibleForTesting seam
  (appendInjuryToCoachMemoryForTest) mirrors the existing
  maybeCompleteScheduledDayForTest pattern.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "tool_dispatcher.dart: mutex + seam + telemetry; flutter analyze on the touched file: zero warnings (run post-commit-prep)." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Behavioral tests drive the REAL coachBox via HiveUserSession.openForUser + the new seam; sequential and concurrent appends both accumulate correctly (4/4 green); 20-trial concurrency probe recorded below." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change — coach_memory.injuries is a Hive-local structure; the cloud coach_memory mirror path is untouched." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No cloud call added or removed; the snapshot push after injury ops is unchanged." }
mutation_proven:
  mutated: |
    TWO mutations, both verified applied by grep before the run:
    (M1) removed `await prev;` (grep count 1 -> 0) — compiles clean, semantically wrong (lock installed but never waited on = the exact pre-fix no-serialization defect).
    (M2) renamed `_coachMemoryLock` -> `_renameMut` throughout — compiles clean. An earlier field-DELETION mutation was REJECTED as invalid per rule 21: it reddened by compile error (loading [E]), which proves the file is invalid, not that any assertion detects the defect.
  result: "M1 reddened exactly the mutex source pin ('Expected: true / Actual: false' on the `await prev;` assertion) — read from the run output, an assertion failure, not a compile error and not a zero-red run. M2 reddened the same pin on the field-declaration assertion. Both reverted; 4/4 green after restore."
  confirmed_applied: "M1: grep 'await prev;' returned 0 while applied and 1 after restore; M2: the pin failed with the renamed field present in the run output."
---

## Summary

Item C5 of the 2026-09-18 tool-integrity audit. Three findings: an
unserialized coach_memory read-modify-write reachable from two concurrently
confirmed intent cards, a missing telemetry call on the pause_plan failure
path, and a CLAUDE.md SoT row that misdescribed where the completion lock and
status re-check actually live.

## Root cause

1. **Mutex**: `_appendInjuryToCoachMemory` is invoked from
   `_executeModifyWorkoutForInjury` (:626), and intent cards confirm
   independently (`pending_tool_intents_provider.confirm` →
   `ToolDispatcher.instance.execute`, one future per tap). Nothing serialized
   the RMW, so two `modify_workout_for_injury` intents in one turn raced.
2. **Telemetry**: the PausePlanException catch simply mapped the error to a
   user message and returned — the only dispatcher failure path without an
   ErrorTelemetry call, so pause failures were invisible to telemetry.
3. **Doc drift**: the CLAUDE.md row compressed "markCompleted takes a per-date
   lock (workout_write_service.dart:424)" and "the caller re-checks status"
   into "under-lock status re-check", which is false — the re-check at
   tool_dispatcher.dart:399 runs before the lock is ever acquired.

## Honest behavioral-test note (the race does NOT reproduce single-isolate)

The brief anticipated this and required the attempt be recorded: the RMW's
get→build→add section contains NO `await`, so within a single isolate the
whole read-modify-write is atomic; Hive's non-lazy box also updates its
in-memory map synchronously on `put`. A seam-only build (mutex absent) ran
the two-concurrent-appends test **20/20 trials green** — the lost-append
cannot be produced in the Flutter test harness. The mutex is therefore
**defense-in-depth** (it protects against a future `await` entering the RMW
body, a multi-isolate future, or a lazy-box switch — any of which would
open the window silently). The deterministic red legs are the source pins,
which is why the pin test exists; the 20-trial behavioral test is retained
as the canary for that future regression.

## Fix

- **Mutex** (tool_dispatcher.dart, `_coachMemoryLock` + `_appendInjuryToCoachMemory`):
  static chained-future lock, `await prev;` in try, `completer.complete()` in
  finally. `@visibleForTesting` seam `appendInjuryToCoachMemoryForTest` added,
  mirroring `maybeCompleteScheduledDayForTest`.
- **Telemetry**: `tool_dispatch_pause_plan_failed` fired before the failure
  return in the PausePlanException catch.
- **CLAUDE.md**: corrected topology sentence with live line cites
  (workout_write_service.dart:424 / :430-439, tool_dispatcher.dart:399).

## Verification

- Pre-fix: compile-red (seam absent); seam-only: behavioral 20/20 GREEN
  (recorded honestly above), both source pins RED.
- Post-fix: 4/4 green (new file) + 67 tests across 8 related
  dispatcher/coach_memory files green.
- Mutations (rule 21): M1 (`await prev;` removed) and M2 (field renamed),
  both grep-verified applied, each reddening the mutex pin as an assertion
  failure; reverted, green. Recorded above.
