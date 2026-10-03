---
bug_id: f4c7a9
date: 2026-09-26
batch: day-swapper-sync-load
status: fixed
blast_radius: platform
symptom: |
  Two workout-completion sync paths, plus 12 other sync-payload sites, fall back to `DateTime.now()`
  when a timestamp describing something that already happened is missing, so a past event gets
  re-stamped with the sync pass's own wall-clock time on every push. `markCompleted`
  (lib/core/services/workout_write_service.dart:502, :511) stamps the schedule row with
  `completed_at_ms` only; the ISO `completed_at` is written on the `wlog_<date>` row instead
  (:541). `_syncScheduleCompletions` (lib/core/services/sync/sync_workout.dart:629) sends
  `entry['completed_at'] ?? DateTime.now().toUtc().toIso8601String()`, which is "now" on every pass
  because the schedule row never carries an ISO `completed_at`. `_syncScheduledWorkouts`
  (sync_workout.dart:1707-1710) sends the raw (usually null) `completed_at`, so completed scheduled
  days show a null time in the cloud. Live evidence cited from the spec's own investigation (§1.6,
  read-only SQL, 2026-09-26): 17 of 37 completion records are stamped more than a day after the
  workout; 4 records for days older than 3 days were re-stamped within the last 3 days; 9 of 37
  completed scheduled days have a null time. This is a recurrence of `5a36ad` (2026-05-08), which
  fixed the identical "now" fallback for workout and exercise logs using `_resolveCompletedAt`
  (sync_workout.dart:532) — the two completion paths above were never moved onto that resolver. The
  plan's own re-grep (deviation D2) found the fallback recurs at 14 sites total, not the 11 the spec
  first counted: three more sit in `lib/core/services/sync/sync_restore_completeness.dart`
  (notifications push at :290/:293, notifications restore at :492), missed by a one-line grep because
  the `??` sits at a line break.
concept: sync_completion_time_resolution
sot_registry_entry: sync_schedule_completion_payload_hash_index (re-pointed by Task 31 — DEVIATING
  from the plan-time ruling's proposed name `sync_completion_time_resolution`: Task 29 never
  registered a concept under that name; the resolver's primary domain, `_syncScheduleCompletions`'s
  fingerprint over the resolved completion time, is registered at docs/sot_registry.yaml:12108 as
  `sync_schedule_completion_payload_hash_index`, whose own description names
  `ScheduleCompletionTime`/Task 14 directly. The resolver is also consumed by
  `sync_scheduled_payload_hash_index` (docs/sot_registry.yaml:2115, the `_syncScheduledWorkouts`
  payload's `completed_at`) and by the 13 other now-fallback sites' own domain concepts — extends the
  existing _resolveCompletedAt resolver from 5a36ad)
writers:
  - { file: lib/core/services/workout_write_service.dart, method: "markCompleted (completed_at_ms only, no ISO completed_at, on the schedule row)", line: 502 }
  - { file: lib/core/services/workout_write_service.dart, method: "markCompleted (ISO completed_at, on the wlog_<date> row)", line: 541 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method: "_syncScheduleCompletions (now-fallback, the recurrence)", line: 629 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "_syncScheduledWorkouts (sends the unresolved, usually-null completed_at)", line: 1707 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "_resolveCompletedAt (the existing 5a36ad resolver, not reused by the two readers above)", line: 532 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "_resolveCompletedAt call site #1", line: 102 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "_resolveCompletedAt call site #2", line: 244 }
  - { file: lib/core/services/sync/sync_restore_completeness.dart, method: "notifications push now-fallback", line: 290 }
  - { file: lib/core/services/sync/sync_restore_completeness.dart, method: "notifications restore now-fallback", line: 492 }
hive_key_prefix: "schedule_ (completed_at_ms) and wlog_ (completed_at ISO)"
hive_key_formula: "schedule_${formatDateKey(date)} and wlog_${formatDateKey(date)}"
sync_methods: [_syncScheduleCompletions, _syncScheduledWorkouts, _syncWorkoutTemplates, _syncCoachInteractions, _syncSavedMeals, _syncReadiness, syncSleepNow, _syncSleepLogs, _syncWeightLogs, _syncMeasurements]
restore_methods: [_resolveCompletedAt]
cloud_table: workout_schedule_completions
cloud_columns: [completed_at]
contract_test_path: "test/sync/schedule_completion_time_test.dart (the completion-time order,
  incl. never updated_at_ms; extends the test/sync/completed_at_preservation_test.dart pattern from
  5a36ad) plus the G2 gate tests test/scripts/sync_no_now_fallback_lib_test.dart and
  test/scripts/sync_no_now_fallback_e2e_test.dart. The plan-time names
  completion_time_resolver_extended_test.dart and check_sync_no_now_fallback_test.dart were never
  created — repointed by the B-pass 2026-09-28."
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [sync_completed_at_fallback]
cross_account_guard: n/a — the fix corrects what timestamp value is sent for the current session's
  own rows; it introduces no cross-account read.
forbidden_patterns_checked:
  - { pattern: "Reusing _resolveCompletedAt's existing field order (created_at, completed_at, logged_at, updated_at_ms, completed_at_ms) unchanged for the schedule-completion paths", absent: true }
  - { pattern: "A completion-time resolver whose last resort is DateTime.now() rather than omitting the field", absent: true }
proposed_fix: |
  A completion time gets its OWN resolver order, distinct from the general `_resolveCompletedAt`
  order: `completed_at` (ISO) -> `completed_at_ms` -> the matching `wlog_<date>` row's `completed_at`
  -> omit the field entirely. It deliberately never falls back to `updated_at_ms`, because every
  schedule row carries `updated_at_ms` from its last `upsertScheduled` (often plan generation), which
  would silently reintroduce a wrong-but-plausible timestamp instead of the real completion time
  (spec §1.6's explicit warning: "the resolver cannot be reused as-is"). `_resolveCompletedAt`'s own
  last-resort "now" becomes "omit", keeping its existing `sync_completed_at_fallback` telemetry event.
  All 14 `?? DateTime.now()` sync-payload sites (spec §5.12 table, corrected to 14 by plan deviation
  D2) are fixed with the general rule: recorded value -> derived from a `*_ms` sibling or a timestamp
  embedded in the Hive key (`coach_<ms>`, `tmpl_<ms>`) -> omit, so the database keeps its existing
  value and the column default applies on insert. New gate `scripts/check_sync_no_now_fallback.dart`
  (G2, spec §7) fails on any `?? DateTime.now()` inside sync payload code, comment-stripped; it must
  fail on today's tree (14 hits after D2) and pass once this fix lands.
regression_test_planned: |
  test/sync/schedule_completion_time_test.dart (planned as completion_time_resolver_extended_test.dart)
  proves the new completion-time order picks
  the ISO `completed_at`, then `completed_at_ms`, then the matching `wlog_<date>`'s `completed_at`,
  then omits — never `updated_at_ms` even when it is the freshest field present, reproducing the exact
  trap spec §1.6 names. A live-evidence-shaped fixture reproduces the "17 of 37 stamped >1 day late"
  and "9 of 37 null" symptom and asserts the fix stops re-stamping an old completion with the sync
  pass's own time. G2's own test mutates a fixture file to insert `?? DateTime.now()` inside the sync
  payload path and confirms the gate goes red; a second mutation restores the omit-only fallback and
  confirms it goes green again. Mutation proof planned for the resolver itself: reverting the order to
  fall back to `updated_at_ms` before omitting must redden the "never updated_at_ms" assertion.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "ScheduleCompletionTime resolver + its two call sites landed in Task 14 (commit ebddb44c, docs commit d370a0bc for a review-fixed hardcoded literal). The other 13 now-fallback sites landed in Task 16 (commit 875c8f3e/b22592ed, templates/nlog/exlog), Task 17 (commit 0a1a0548/b1c3ddc2/ea33eacb + fix round b503bcd6, integrated 53a177e0/745fdb98), Task 18 (commit 865d891d, 5 health domains), and Task 19 (commit 70f1922b, coach/onboarding-replay/notifications). All 14 sites verified fixed by test/sync/ + test/contracts/ green at each integration." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "The Hive key patterns the fix reads from (coach_<ms>, tmpl_<ms>, wlog_<date>) already exist and are read as-is by the existing sync code; the fix only changes what is chosen and sent, not the Hive schema." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL is needed; the fix changes what value the client sends for an existing column." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Spec §1.6's own live, read-only SQL investigation (2026-09-26) found 17 of 37 completion records stamped more than a day late, 4 records for days older than 3 days re-stamped within the last 3 days, and 9 of 37 completed scheduled days with a null time. This drafting pass cites that evidence and did not re-query the database." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration is required for this fix; existing wrong cloud values heal on the first sync after the client update, once the new SyncSkipIndex has no stored fingerprint yet for any row (spec §5.12)." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function reads or writes either completion-time column (plan-time verification #12: grep of supabase/functions/ and supabase/migrations/ found no server-side reader of either column)." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job reads either completion-time column (plan-time verification #12)." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No RLS policy change; the existing own-rows write is unchanged." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No Storage bucket or object is involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret is involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "None involved." }
  - { tier: 12, name: client_to_server_contract, status: fixed_in_this_batch, evidence: "The sync payload itself stops sending 'now' as a stand-in for a past event across all 14 sites (Tasks 14/16/17/18/19, commits listed under tier 1), which is the client-to-server contract this bug violates. G2 (scripts/check_sync_no_now_fallback.dart, Task 2, commit e7a0cffa) is green against the final tree, having gone from 14 hits pre-fix to 0." }
impact_analysis: |
  Severity: P2, systemic. Every completed workout's cloud completion time is wrong today whenever the
  sync pass runs later than the workout itself (the common case), which corrupts any feature that
  reads completion timing from the cloud (analytics, the weekly-recalc / rank-engine class of
  functions, if any is later added to read it) and confuses support investigations that trust the
  cloud timestamp. Because this is a recurrence of `5a36ad`, the same class will keep resurfacing at
  new sync sites unless the new gate (G2) makes the "now"-fallback pattern structurally impossible in
  sync payload code going forward, which is why G1/G2 land before the domain fixes per CLAUDE.md
  §4.11.
recurrence: 5a36ad (2026-05-08, docs/diagnoses/2026-05-08-sync-stack-templates-streak-pill-5a36ad.md)
related_bugs: [5a36ad]
---

# Completion times are overwritten with "now" on sync (recurrence of 5a36ad, 14-instance class)

## Why this is a recurrence, precisely

`5a36ad` fixed the "now" fallback for workout and exercise logs by introducing `_resolveCompletedAt`
(`lib/core/services/sync/sync_workout.dart:532`) and a regression test,
`test/sync/completed_at_preservation_test.dart`. The two schedule-completion paths this doc covers
(`_syncScheduleCompletions`, `_syncScheduledWorkouts`) were never migrated onto that resolver — they
are a DIFFERENT pair of call sites writing the SAME class of bug the earlier fix was supposed to close
everywhere. `docs/diagnoses/INDEX.md`'s own `5a36ad` line records "completed_at was overwritten..." as
one of several fixes in that batch, confirming the class name and scope.

## Why the general resolver order cannot be reused as-is (spec §1.6)

`_resolveCompletedAt`'s order is `created_at`, `completed_at`, `logged_at`, `updated_at_ms`,
`completed_at_ms`. Every schedule row carries `updated_at_ms` from its last `upsertScheduled` — often
just plan generation — so applying the general resolver here would return the plan-generation time
instead of omitting the field, which is a plausible-looking wrong answer rather than an honest gap.
The completion-time-specific order in `proposed_fix` above deliberately excludes `updated_at_ms`.

## Fix ownership in the plan

- The completion-time resolver order and its two call sites: Task 14 (coordinator). Landed `ebddb44c`
  + a coordinator literal-hardening commit `d370a0bc`.
- Template `created_at`: Task 16 (commit `875c8f3e`/`b22592ed`). Saved-meal `created_at` and the
  exlog/nlog sites: Task 17 (commit `0a1a0548`/`b1c3ddc2`/`ea33eacb`, fix round `b503bcd6`, integrated
  `53a177e0`/`745fdb98`). The five health-domain sites: Task 18 (commit `865d891d`). Coach,
  onboarding-replay and notifications sites (the D2-discovered three): Task 19 (commit `70f1922b`).
- Gate G2 (`scripts/check_sync_no_now_fallback.dart`): Task 2 (coordinator, Wave 0, commit `e7a0cffa`,
  lands before any domain fix per CLAUDE.md §4.11).

## Commits

`e7a0cffa`, `ebddb44c`/`d370a0bc`, `875c8f3e`/`b22592ed`, `0a1a0548`/`b1c3ddc2`/`ea33eacb`/`b503bcd6`/
`53a177e0`/`745fdb98`, `865d891d`, `70f1922b`.

## Mutation evidence

Gate G2 (`e7a0cffa`): 8/2/1 mutations across the gate's own test file (`// file-only:` escape for
`check_gate_existssync_file_vs_dir`); a mutation fixture insert of `?? DateTime.now()` inside a sync
payload path reddens the gate, a restore to omit-only fallback greens it again.

Task 14 (`ebddb44c`), 4/4 legs, restored via content-diff (new file, no `git diff` available pre-first-commit):

| # | Mutation | Confirm-applied | Reds | Failure reason |
|---|---|---|---|---|
| 1 | Delete `if (row['status'] != 'completed') return null;` from `scheduledCompletedAtIso` | `grep -c` 2→1 | 1 | "not completed -> null" test: expected null, got a real ISO string |
| 2 | `ms > 0` → `ms >= 0` | `grep -c "ms >= 0"` → 1 | 1 | "completed_at_ms == 0 is not treated as a real timestamp": expected null, got the epoch |
| 3 | `resolvedCompletedAt` reverted to bare `entry['completed_at']` (pre-fix shape) | `grep -c` → 1 | 1 | "the pushed completed_at is the REAL completion time": runtime cast exception at the test's own assertion, the live demonstration the field is silently omitted |
| 4 | Revert restore carve-out to `existingMap['completed_at'] as String?` | `grep -c` → 1 | 1 | "restore carve-out ... local completed row must survive": Expected 'completed', Actual 'planned' (exact pre-fix bug reproduced) |

Task 18 (`865d891d`), 3 legs (per-domain fingerprint sent-at exclusion): mutation 2 (`_syncUrineColorLogs`
fingerprint: delete the `e.key != 'updated_at'` filter) reddened 1 test one assertion earlier than
predicted ("an unchanged second pass sends nothing", not "touchSentAtOnly") because `updated_at` now
sits inside the fingerprint and is always-fresh — same underlying mechanism, verified not a compile
error.

Task 19 (`70f1922b`), 5/5 legs: all 6 timestamp fixes independently confirmed real (server COALESCEs
on UPDATE / no default, or DEFAULT now() only on a genuine first INSERT). Mutation 2
(`_coachCreatedAtFromKey` hard `return null;`) → 1 red ("derives from the coach_<ms> key": expected
ISO string, got null). Mutation 5 (revert `_restoreNotificationsInbox`'s hiveEntry fallback) → 1 red
("omits the Hive field": expected false, got true). Every mutation reddened exactly 1 test, no
compile errors, no zero-red surprises.

## B-pass remediation (2026-09-28, review `docs/reviews/day-swapper-sync-load-bpass.md`)

- **R4-F1 (P1) — gate G2 missed the compound-assignment spelling.** `nowFallbackPattern` required
  `??` then whitespace then `DateTime`, so `completedAt ??= DateTime.now();` — the identical fallback
  — passed. Pattern is now `\?\?=?`. No live `??=` now-fallback existed (checked before widening, so
  the hard-fail gate stayed green). Test: "`x ??= DateTime.now()` (compound assignment) is the same
  class" (`test/scripts/sync_no_now_fallback_lib_test.dart`). Mutation — restore `\?\?` → 1 red.
  Residue documented in the lib: a fallback routed through a local or helper is still invisible to a
  grep; the payload-level tests below are the behavioural guard.
- **Coordinator-found (P2) — stale test citations in this doc's frontmatter.** `contract_test_path`
  and `regression_test_planned` named plan-time files that were never created
  (`completion_time_resolver_extended_test.dart`, `check_sync_no_now_fallback_test.dart`); repointed
  to `test/sync/schedule_completion_time_test.dart` and the two `sync_no_now_fallback_*_test.dart`
  files. The same drift was fixed in d5a1e7, e2b9d4 and a9d3f6.
