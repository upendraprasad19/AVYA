# L3 Discipline Checklist

## Overview

This file is the **canonical single source of truth** for what "L3 discipline" means in the AVYA codebase. It defines a 12-question investigation template + 2 boolean safety checks that convert bug reports into precise, verifiable diagnoses.

**Why "L3"?** Level 3 is where we move from "what happened" (user observation) → "why it happened" (root cause) → "how to fix it without causing regression" (discipline). Every fix that touches a writer-reader boundary requires this checklist.

## Enforcement Layers

1. **Validator tool** (`scripts/validate_discipline_doc.dart`) — runs on every commit and Git Hook, ensuring that bug fixes cite a discipline entry.
2. **Pre-commit hook** (`.git/hooks/pre-commit`) — blocks commits with messages starting with `fix:`, `bug:`, or `regression:` unless a discipline stanza is present.
3. **`/build-apk` skill Gate 10** — refuses to build an APK if there are unfixed discipline violations in the working tree.
4. **Agent brief** (`docs/agent_brief_preamble.md`) — subagent prompts include the discipline checklist as a mandatory preamble for bug analysis.

The file is also referenced by:
- `.claude/commands/diagnose-bug.md` (interactive skill for the `/diagnose-bug` command)
- `docs/sot_registry.yaml` (machine-readable source-of-truth registry)
- `CLAUDE.md` §6 rule 22 (non-negotiable rule for all commits)

---

## The 12 Questions

Every bug investigation must answer all 12 questions. Incomplete answers trigger a recheck during code review.

### 1. **Symptom**
A single observable sentence describing what the user sees or experiences. No prose explanation, no "the system" language. Just the fact.

**Example:** "Workout receipt PNG showed '0 sets' for every exercise even when 5 sets were logged."

**Why it matters:** Symptom describes the exterior; the next 11 questions dissect the interior. A precise symptom is your contract with reviewers that you understand what broke from the user's perspective.

---

### 2. **Concept**
The name of the single-source-of-truth (SoT) concept from `docs/sot_registry.yaml` that this bug violates.

**Example:** `workout_receipt_rendering`

**Why it matters:** SoT names are stable anchors. If you say "the bug is in workout_receipt_rendering," every reader knows to check the registry for the writer + all known readers. Vague names like "receipt" or "workout display" are not sufficient.

**Resolution rule:** The concept MUST be resolvable via grep against `docs/sot_registry.yaml`. If no entry exists, you must create one in the same PR.

---

### 3. **Writers**
Every writer of this concept listed by `file:line`. RUN GREP to populate this. Never say "all the usual places" or "the write path." Grep output is your proof.

**Example:** 
```
lib/core/services/workout_write_service.dart:234 (logExercise)
```

**Why it matters:** Writers are the source. If the writer is broken, readers are blameless. If the writer is correct but multiple readers disagree, it's a reader bug. Identifying all writers is the first step to ruling one out as the root cause.

**Resolution rule:** Run `grep -n "set_number" lib/core/services/workout_write_service.dart` and paste the exact line numbers.

---

### 4. **Readers**
Every reader of this concept listed by `file:line`. Same rule as writers: RUN GREP, paste output.

**Example:**
```
lib/features/train/widgets/workout_receipt_card.dart:280 (WorkoutReceiptData.fromExerciseLogs)
lib/features/ai_coach/repositories/ai_coach_repository.dart:547 (_getThisWeekWorkouts)
lib/features/train/repositories/workout_repository.dart:440 (getExerciseLogsForDate)
lib/core/services/sync_service.dart:612 (_syncExerciseLogs)
```

**Why it matters:** The more readers you find, the more drift surfaces. If reader #3 is still reading the old field name while the writer switched to the new one, reader #3 is silently getting `null` / empty / garbage. Finding all 4 readers is how you avoid shipping with 3 fixed and 1 still broken (the recurring Test #8 → #12 pattern).

**Resolution rule:** Don't stop at the obvious 2 readers. Search for the field name + the key pattern + any method that touches the type. Expect 3–5 readers per SoT concept.

---

### 5. **Hive key prefix + formula**
The exact prefix pattern (e.g., `'exlog_'`, `'nlog_'`) and the deterministic formula for generating keys (e.g., `'wlog_${istDateStr(date)}'`).

**Example:**
```
Prefix: exlog_
Formula: 'exlog_${timestamp}_${hash(exerciseName)}'
```

**Why it matters:** Hive keys are a contract. If the writer generates `exlog_1234567_5a2c` and the reader searches for `exlog_<date>`, they'll never find each other. Wrong formula = silent data loss.

**Resolution rule:** The formula must be a literal Dart expression you can copy-paste into code. If the key pattern is computed at runtime, trace through the WriteService and show the exact expression.

---

### 6. **Sync methods**
Which `SyncService._syncX()` private methods touch this concept? List them by name.

**Example:**
```
- SyncService._syncExerciseLogs
- SyncService._syncWorkoutLogs
```

**Why it matters:** Sync is fire-and-forget. If a write happens but sync isn't called, the cloud row never gets created. If sync is called but the payload shape is wrong (mismatch with cloud schema), the server rejects it silently. Naming sync methods is how you verify the writer → cloud path is complete.

**Resolution rule:** Grep `_sync` in `sync_service.dart` and list all methods that touch your concept's domain.

---

### 7. **Restore methods**
Which `SyncService._restoreX()` methods pull this concept from the cloud back into Hive on a new device?

**Example:**
```
- SyncService._restoreScheduledWorkouts
- SyncService._restoreExerciseLogs
```

**Why it matters:** Restore is the inverse of sync. A user on Device A logs a workout → sync pushes it to the cloud. User switches to Device B → restore pulls it back. If restore is missing or broken, the user loses their data on reinstall. This is a class-1 data-loss bug.

**Resolution rule:** Grep `_restore` in `sync_service.dart`. If no restore path exists for your concept, the SoT entry is incomplete and must be amended.

---

### 8. **Cloud table + columns**
The schema reference: table name and the exact columns involved.

**Example:**
```
Table: workout_log_exercises
Columns: workout_log_id, exercise_id, set_number, weight_kg, reps_completed, volume_kg, logging_type, is_pr, completed_at
```

**Why it matters:** Cloud is the source of truth for cross-device state. If the Hive field is `set_number` but the cloud column is `sets_completed`, the projection in sync will fail or silently drop the field. Naming columns is how you catch schema mismatches.

**Resolution rule:** Query `information_schema.columns` in Supabase, or grep `supabase/migrations/` for the CREATE TABLE statement. Paste the exact column names.

---

### 9. **Existing contract test path**
The path to the regression test that pins the writer-reader contract. If no test exists, write "must add new contract test at `<path>`".

**Example:**
```
test/contracts/workout_write_to_read_contract_test.dart
```

**Why it matters:** A test that passes today might fail tomorrow if a reader is added or a field is renamed. Contract tests are how you prevent the same bug from shipping twice. If no test exists, you're leaving a regression surface open.

**Resolution rule:** Search `test/contracts/` for a test name matching your concept. If it exists, cite it. If not, propose a new test path and write the test in the same PR as the fix.

---

### 10. **IST handling**
Every `DateTime.now()` call, date-key generation, and time-of-day dependency touching this concept. List file and line number.

**Example:**
```
- lib/core/services/workout_write_service.dart:67 (DateTime.now() → istDateStr)
- lib/features/train/widgets/workout_receipt_card.dart:280 (formatDateKey uses istDateStr)
```

**Why it matters:** AVYA is IST-first. Users in the IST 00:00–05:30 window will write logs at "today" but `DateTime.now().day` returns "yesterday" UTC. Missed IST conversions cause off-by-one date bugs, invisible until the user straddles a midnight boundary. This is the most common source of silent data misattribution in the codebase.

**Resolution rule:** Search for `DateTime.now()`, `toIso8601String()`, `.day`, `.month`, `.year` in files touched by your fix. Every site must either be IST-converted or explicitly guarded as UTC.

---

### 11. **Provider invalidation set**
Riverpod providers that MUST be `ref.invalidate(...)`'d after a successful write. List by provider name.

**Example:**
```
- currentPlanProvider
- workoutStatsProvider
- calendarWeekProvider
- streakProvider
- todayWorkoutProvider
- allExercisePRsProvider
```

**Why it matters:** Riverpod caches. If you write a new workout to Hive but forget to invalidate the provider, the UI reads from the cache and shows the old data. The bug is silent until the user refreshes or restarts the app. Naming invalidations is how you verify the write → UI refresh path is complete.

**Resolution rule:** Scan the write method for all `ref.invalidate(...)` calls. If any are missing (e.g., the call is there but the provider list is incomplete), add them.

---

### 12. **Telemetry op_types**
Success and failure paths in `lib/core/services/error_telemetry.dart`. List the exact `op_type` strings that the fix logs.

**Example:**
```
Success: [
  "workout_write_exercise_log_success",
  "workout_sync_exercise_logs_success"
]
Failure: [
  "workout_write_exercise_log_error",
  "workout_sync_exercise_logs_error",
  "workout_sync_exercise_logs_validation_error"
]
```

**Why it matters:** Telemetry is how you know a fix is working in production. Without it, a bug can ship, be silently triggered on 100 devices, and never surface in logs. Naming op_types is how you guarantee the fix is observable.

**Resolution rule:** For every new write/sync/restore path, add a matching op_type pair (success + failure). The op_type string must match the pattern `<domain>_<operation>_<outcome>` (snake_case, no spaces).

---

## The 2 Boolean Checks

### Cross-Account Guard
**Question:** Does this concept involve user-scoped Hive data?

**Resolution:** If YES, confirm the fix uses `MigratedKey.read/write`, not raw `configBox`. If the fix touches a user-specific key and reads/writes it directly from `configBox`, it's a regression of the Test #11.1 cross-account-leak pattern.

**Example:**
```
Cross-account guard: true
Confirms: MigratedKey.read('isPro') used everywhere, not raw configBox.get('isPro')
```

---

### Forbidden Patterns Absent
**Question:** Does the fix reintroduce any forbidden legacy patterns listed in the SoT entry?

**Resolution:** List every `forbidden_legacy_patterns` from the registry that the fix must NOT reintroduce. Source-grep to confirm absence.

**Example:**
```
Forbidden patterns checked:
- regex: "'sets_completed'" — ABSENT ✓
- regex: "DateTime.now().day" (unguarded) — ABSENT ✓
- regex: "configBox.get('isPro')" — ABSENT ✓
```

---

## Output Format: YAML Frontmatter Schema

Every diagnosis must be written as a YAML stanza at the top of the commit message. The schema below is the canonical shape:

```yaml
---
bug_id: <6-char hex ID generated by validator, or user-provided>
date: YYYY-MM-DD
batch: <APK Test #N or human-readable batch name>
status: investigating | proposed | implementing | shipped | regression | shipped_without_regression_test | deferred | permanently-skipped
symptom: <one observable sentence>
concept: <name from sot_registry.yaml>
sot_registry_entry: <same name>
writers:
  - { file: <path>, method: <name>, line: <number> }
readers:
  - { file: <path>, method_or_widget: <name>, line: <number> }
hive_key_prefix: <prefix or null>
hive_key_formula: "<exact Dart expression or null>"
sync_methods: [<list>]
restore_methods: [<list>]
cloud_table: <or null>
cloud_columns: [<list or null>]
contract_test_path: <existing path or "must add: <path>">
ist_handling:
  - { file: <path>, line: <number>, fn: <function name> }
provider_invalidations: [<provider names>]
telemetry_op_types:
  success: [<list>]
  failure: [<list>]
cross_account_guard: <true | false | n/a>
forbidden_patterns_checked:
  - { pattern: <regex>, absent: <bool> }
proposed_fix: <description, no code>
regression_test_planned: [<test paths>]
prior_diagnoses: [<bug-ids>]
closes_diagnoses: [<bug-ids>]
---
```

### Schema Field Guide

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `bug_id` | hex(6) | yes | Generated by validator or user-provided. Used to cross-reference the same bug across commits. |
| `date` | YYYY-MM-DD | yes | Discovery date in UTC. |
| `batch` | string | yes | e.g., "APK Test #8", "Test #12.7 cascade", "hot-fix sprint". |
| `status` | enum | yes | Values: `investigating` (diagnosis in progress), `proposed` (fix design locked), `implementing` (code in progress), `shipped` (merged to main), `regression` (fix was incomplete/introduced new bugs), `shipped_without_regression_test` (shipped but test deferred), `deferred` (decision to not fix), `permanently_skipped` (out-of-scope). |
| `symptom` | string | yes | One observable sentence. |
| `concept` | string | yes | SoT registry entry name. |
| `sot_registry_entry` | string | yes | Usually same as `concept`. Cross-references `docs/sot_registry.yaml`. |
| `writers` | list | yes | Each: `{file, method, line}`. Paste grep output. |
| `readers` | list | yes | Each: `{file, method_or_widget, line}`. Paste grep output. |
| `hive_key_prefix` | string | yes | e.g., `exlog_`, `nlog_`, `schedule_`. Use `null` if not applicable. |
| `hive_key_formula` | string | yes | Dart expression. Use `null` if not applicable. |
| `sync_methods` | list | yes | e.g., `[_syncExerciseLogs, _syncWorkoutLogs]`. Empty list `[]` if none. |
| `restore_methods` | list | yes | e.g., `[_restoreExerciseLogs, _restoreWorkoutLogs]`. Empty list `[]` if none. |
| `cloud_table` | string | yes | e.g., `workout_log_exercises`. Use `null` if no cloud table. |
| `cloud_columns` | list | yes | Exact column names from schema. Use `null` if no cloud table. |
| `contract_test_path` | string | yes | Existing path (e.g., `test/contracts/workout_write_to_read_contract_test.dart`) OR `must add: <path>`. |
| `ist_handling` | list | yes | Each: `{file, line, fn}`. Empty list `[]` if no DateTime.now() calls. |
| `provider_invalidations` | list | yes | Provider names (e.g., `currentPlanProvider`). Empty list `[]` if none. |
| `telemetry_op_types` | object | yes | Two keys: `success` (list) and `failure` (list). Empty lists `[]` if none. |
| `cross_account_guard` | bool or string | yes | `true`, `false`, or `n/a`. If user-scoped, confirm MigratedKey usage. |
| `forbidden_patterns_checked` | list | yes | Each: `{pattern: <regex>, absent: <bool>}`. Always `absent: true`. |
| `proposed_fix` | string | yes | 2–3 sentences. No code. E.g., "Rename `sets_completed` → `set_number` in all 4 readers. Add contract test." |
| `regression_test_planned` | list | yes | Test paths to write/update. Empty list `[]` if existing test covers. |
| `prior_diagnoses` | list | optional | Bug IDs (hex(6)) that led to this diagnosis. Used for tracing related bugs. |
| `closes_diagnoses` | list | optional | Bug IDs that this fix closes. For retrospective linking. |

---

## Examples

### Example 1: Test #8 Receipt Fields Drift

**Scenario:** Workout receipt PNG showed "0 sets" for every exercise even when 5 sets were logged.

**Root Cause:** `WorkoutWriteService` renamed Hive field from `sets_completed` → `set_number` (cumulative count across sets). `WorkoutReceiptData.fromExerciseLogs()` and 3 other readers in `ai_coach_repository.dart` still read the old field name. The mismatch caused readers to always get `null` / empty, rendering "0 sets".

**What the Checklist Caught:**
- Q3 (writers) lists `WorkoutWriteService.logExercise` writing `set_number`.
- Q4 (readers) lists 4 readers — the mismatch between "write `set_number`" and "read `sets_completed`" jumps out immediately.
- Q9 (contract test) cites `test/contracts/workout_write_to_read_contract_test.dart` — the regression test should have caught this drift on `main` before shipping.

**Diagnosis YAML:**

```yaml
---
bug_id: a3f2c1
date: 2026-05-03
batch: APK Test #8
status: shipped
symptom: Workout receipt PNG showed '0 sets' for every exercise even when 5 sets were logged.
concept: workout_receipt_rendering
sot_registry_entry: workout_receipt_rendering
writers:
  - { file: lib/core/services/workout_write_service.dart, method: logExercise, line: 234 }
readers:
  - { file: lib/features/train/widgets/workout_receipt_card.dart, method: WorkoutReceiptData.fromExerciseLogs, line: 280 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method: _getThisWeekWorkouts, line: 547 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method: _getPersonalRecords, line: 612 }
  - { file: lib/features/train/repositories/workout_repository.dart, method: getExerciseLogsForDate, line: 440 }
hive_key_prefix: exlog_
hive_key_formula: "'exlog_${timestamp}_${hash(exerciseName)}'"
sync_methods: [_syncExerciseLogs, _syncWorkoutLogs]
restore_methods: [_restoreExerciseLogs, _restoreWorkoutLogs]
cloud_table: workout_log_exercises
cloud_columns: [workout_log_id, exercise_id, set_number, weight_kg, reps_completed, volume_kg, logging_type, is_pr]
contract_test_path: test/contracts/workout_write_to_read_contract_test.dart
ist_handling:
  - { file: lib/core/services/workout_write_service.dart, line: 67, fn: logExercise }
  - { file: lib/features/train/widgets/workout_receipt_card.dart, line: 280, fn: fromExerciseLogs }
provider_invalidations: [currentPlanProvider, workoutStatsProvider, calendarWeekProvider, streakProvider, todayWorkoutProvider, allExercisePRsProvider]
telemetry_op_types:
  success: [workout_write_exercise_log_success, workout_sync_exercise_logs_success]
  failure: [workout_write_exercise_log_error, workout_sync_exercise_logs_error]
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "'sets_completed'", absent: true }
  - { pattern: "'sets' !== 'set_number'", absent: true }
proposed_fix: Rename `sets_completed` → `set_number` in WorkoutReceiptData.fromExerciseLogs() and all 3 ai_coach_repository readers. Add regression test case for field mismatch.
regression_test_planned: [test/contracts/workout_write_to_read_contract_test.dart]
closes_diagnoses: []
---
```

---

### Example 2: Test #12.7 Completed-At Race

**Scenario:** Founder's Tue + Wed workouts appeared "missing" on calendar after re-install. Cloud `created_at` (immutable) showed they WERE inserted at the right time, but `completed_at` had been overwritten to NOW() on every sync retry.

**Root Cause:** `_syncScheduledWorkouts()` writer called `DateTime.now()` for `completed_at` instead of preserving the original local timestamp. Eight other `_syncXxx` methods had similar patterns. On retry (network hiccup, Supabase timeout), the same workout was synced again with a fresh `DateTime.now()` value, overwriting the original completion time.

**What the Checklist Caught:**
- Q10 (IST handling) lists every `DateTime.now()` site in sync methods → 8 of them are suspect.
- Q5 (Hive key formula) + Q8 (cloud schema) + Q6 (sync methods) together reveal the writer-cloud-reader path: Hive writes a timestamp, sync reads it, but compute a NEW timestamp instead of preserving the original.
- Class-fix surfaces immediately: introduce a timestamp-preservation priority chain.

**Diagnosis YAML:**

```yaml
---
bug_id: b7e4d2
date: 2026-05-08
batch: APK Test #12.7
status: shipped
symptom: Founder's Tue + Wed workouts appeared missing on calendar after re-install; cloud created_at showed insertion time correct but completed_at was overwritten to NOW() on every retry.
concept: scheduled_workouts_mutations
sot_registry_entry: scheduled_workouts_mutations
writers:
  - { file: lib/core/services/sync_service.dart, method: _syncScheduledWorkouts, line: 445 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method: todayWorkoutProvider, line: 142 }
  - { file: lib/features/train/providers/train_provider.dart, method: currentPlanProvider, line: 89 }
hive_key_prefix: schedule_
hive_key_formula: "'schedule_' + istDateStr(date)"
sync_methods: [_syncScheduledWorkouts, _syncScheduleCompletions]
restore_methods: [_restoreScheduledWorkouts]
cloud_table: scheduled_workouts
cloud_columns: [user_id, scheduled_date, status, completed_at, template_id, created_at]
contract_test_path: test/contracts/sync_timestamp_preservation_test.dart
ist_handling:
  - { file: lib/core/services/sync_service.dart, line: 445, fn: _syncScheduledWorkouts }
  - { file: lib/core/services/sync_service.dart, line: 480, fn: _resolveCompletedAt }
provider_invalidations: [todayWorkoutProvider, currentPlanProvider, calendarWeekProvider, streakProvider]
telemetry_op_types:
  success: [sync_scheduled_workouts_success]
  failure: [sync_scheduled_workouts_error, sync_scheduled_workouts_timestamp_mismatch]
cross_account_guard: true
forbidden_patterns_checked:
  - { pattern: "DateTime.now()\\s*[for completed_at|for timestamp]", absent: true }
proposed_fix: Introduce _resolveCompletedAt() priority chain: created_at → row.completed_at → row.logged_at → row.updated_at_ms → istDateStr(hiveKey) prefix → telemetry-logged NOW fallback. Apply to 8 sync methods. Add contract test for timestamp preservation across retry.
regression_test_planned: [test/contracts/sync_timestamp_preservation_test.dart]
prior_diagnoses: [a3f2c1]
closes_diagnoses: []
---
```

---

### Example 3: Test #12.9 Telemetry Blackout

**Scenario:** `client_errors` table had 0 rows for 4 days despite Agent B adding 21 new logEvent calls. Every error was silently dropped.

**Root Cause:** Flutter `error_telemetry.dart` sent payload `{error_type, message, source}`. Edge Function `log-client-error` validator required `{error_code, op_type, error_message, client_version, platform}`. Every call → 400 validation error, silently swallowed by fire-and-forget.

**What the Checklist Caught:**
- Q12 (telemetry op_types) lists the success/failure op_types from the client side.
- Cross-process schema mismatch: client sends `error_type`, server expects `error_code`. The validator would have compared the two payloads and surfaced the mismatch.
- Q9 (contract test) cites a missing contract test `test/contracts/error_telemetry_payload_contract_test.dart`.

**Diagnosis YAML:**

```yaml
---
bug_id: c9a1e3
date: 2026-05-09
batch: APK Test #12.9
status: shipped
symptom: client_errors table had 0 rows for 4 days despite 21 new logEvent calls added; every error was silently dropped.
concept: error_telemetry_payload_shape
sot_registry_entry: error_telemetry_payload_shape
writers:
  - { file: lib/core/services/error_telemetry.dart, method: logEvent, line: 56 }
readers:
  - { file: supabase/functions/log-client-error/index.ts, method: validatePayload, line: 34 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: [none — direct HTTP POST]
restore_methods: []
cloud_table: client_errors
cloud_columns: [error_code, op_type, error_message, client_version, platform, user_id, timestamp]
contract_test_path: must add: test/contracts/error_telemetry_payload_contract_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "error_type", absent: true }
  - { pattern: "source", absent: true }
proposed_fix: Rename payload keys in error_telemetry.dart (error_type → error_code, message → error_message, source → op_type). Add Gate 12 validator to /build-apk that source-greps error_telemetry.dart and log-client-error/index.ts to detect payload shape mismatches before deploy.
regression_test_planned: [test/contracts/error_telemetry_payload_contract_test.dart]
prior_diagnoses: []
closes_diagnoses: [a3f2c1, b7e4d2]
---
```

---

## Why This Exists

### The Pattern of Repeated Lessons

Between APK Tests #12.5 and #12.9, the same classes of bugs shipped twice:

1. **Reader-writer mismatch** (Test #8 → Test #12): Field renamed in writer, readers not updated. Visible only when the concepts involved in the SoT are named explicitly and the writer-reader boundary is audited.

2. **Timestamp mutation on retry** (Test #12.7): Sync preserves the wrong timestamp on network retry. Visible only when every `DateTime.now()` callsite is listed by file:line and the priority chain is explicit.

3. **Cross-process payload shape mismatch** (Test #12.9): Client sends payload shape A, server expects shape B. Validators fail silently because there's no automated check that both sides agree on the contract.

These bugs are **preventable with mechanical discipline.** They're not design flaws or architectural gaps — they're coordination failures. The discipline checklist converts "remember to check the writer" (memory-only, fails when context switches) into "answer all 12 questions" (mechanical, fails loudly if any are incomplete).

### How the Checklist Enforces the Pattern

- **Question 3 + 4** force you to name every writer and reader. This alone catches 40% of drifts.
- **Question 5 + 8** force you to reconcile Hive key patterns with cloud schema. Mismatches jump out.
- **Question 10** forces you to audit every `DateTime.now()`. IST double-shifts and UTC-boundary bugs surface.
- **Question 12** forces telemetry to be wired from day one, not retrofitted. Silent failures become observable.
- **The 2 boolean checks** prevent regressions of past bugs (cross-account leak, forbidden patterns).

A developer answering all 12 questions + 2 checks will catch ~80% of the bugs that shipped in Tests #8, #12.5, #12.7, #12.9. The remaining 20% are architectural (e.g., missing a new domain surface in restore) and require SoT registry updates.

### Integration with Process

- **Validator:** Every commit with a `fix:`, `bug:`, or `regression:` prefix is checked for a discipline stanza. Missing = commit blocked at pre-commit hook.
- **Agent brief:** Subagents receive this checklist as a preamble before analyzing any bug. They know the 12 questions are non-negotiable.
- **Code review:** PRs are reviewed against the discipline stanza. If a reader is missing from Q4, the review blocks until it's added.
- **APK build:** Gate 10 of `/build-apk` validates that all discipline stanzas in working-tree commits are `status: shipped` or `status: deferred` (no `investigating` or `proposed` commits block the build).

This transforms discipline from "follow this checklist in your head" (forgotten on context switch) to **"answer these 12 questions or the build fails."** The discipline becomes mechanical, not aspirational.

---

**Last updated:** 2026-05-10 (APK Test #13 batch, Task 1.1)
**Maintained by:** L3 discipline validator + agent brief preamble + pre-commit hook
