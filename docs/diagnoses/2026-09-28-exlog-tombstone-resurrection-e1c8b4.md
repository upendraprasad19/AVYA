---
bug_id: e1c8b4
date: 2026-09-28
batch: oi-245-246-restore-fixes
status: fixed
blast_radius: platform
symptom: |
  OI-246. `WorkoutWriteService.deleteLog` removed only the local Hive
  `exlog_` key — it never issued a cloud delete for the matching
  `workout_log_exercises` row. `SyncService._restoreExerciseLogs`'s
  additive/local-wins restore (`if (_hive.workoutBox.get(logId) == null) {
  put... }`) re-inserts any cloud row whose Hive key is absent locally — the
  exact pattern `restore_local_wins_additive_test.dart` pins for this class —
  so a user-deleted exercise log silently reappeared on the next full restore
  (fresh install / new device / cleared Hive). Verified live-code-read
  2026-09-28: no `deleted_at`/status column existed on `workout_log_exercises`
  at all (`backups/live_schema_columns.json`), so nothing distinguished a
  deleted row from a live one at restore time.
concept: exercise_logs_read_path
sot_registry_entry: exercise_logs_read_path
writers:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "deleteLog — queues PendingExlogDeletes with the row's exact natural key (workoutLogId, exerciseId, setNumber) before deleting locally", line: 1140 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "resolveSummarySetCount — pure natural-key set-count resolver, shared reference point for the push side's summarySetCount", line: 1389 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_drainPendingExlogDeletes — UPSERTs a deleted_at tombstone per queued natural key, called before every exercise-log push", line: 190 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreExerciseLogs — skips a row with deleted_at != null", line: 849 }
hive_key_prefix: "exlog_"
hive_key_formula: "WorkoutWriteService.exlogKey(date, exerciseName) — exlog_<istDate>_<uuid5(name)[0:8]>"
sync_methods:
  - "SyncService._syncExerciseLogs (sync_workout.dart) — drains PendingExlogDeletes before pushing"
restore_methods:
  - "SyncService._restoreExerciseLogs (sync_workout.dart) — skips deleted_at rows"
cloud_table: workout_log_exercises
cloud_columns: [deleted_at]
contract_test_path: test/contracts/exlog_tombstone_delete_writer_to_reader_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  - "sync_drain_pending_exlog_deletes — ErrorTelemetry.recordNonFatal on a failed tombstone UPSERT; entry stays queued for the next push"
cross_account_guard: Not applicable — PendingExlogDeletes is stored in userBox, already cleared on sign-out/account-switch by the existing cross-account guard; no new account-scoped state introduced.
forbidden_patterns_checked:
  - "a hard DELETE of the cloud row instead of a soft-delete tombstone — rejected: mirrors migration 145's own reasoning exactly (workout_templates) — a delete queued before the row's own creating push has reached the cloud races a hard DELETE (delete-then-recreate) but a soft-delete UPSERT + a delete-final trigger resolves the race regardless of arrival order."
  - "mutating workout_log_id on the delete transition (mirroring templates' name mutation) — rejected: workout_log_id is shared by every exercise logged that DAY, not unique per row, so mutating it would corrupt every sibling exercise's join via idx_wle_workout_log_id. exercise_id (the true per-row stable identity) is mutated instead, mirroring templates' choice of `name` (also the stable-identity column there)."
  - "tombstoning workout_log_sets (the per-set table) too — rejected: _restoreExerciseLogs only reaches the per-set join AFTER finding a live workout_log_exercises row, so once the summary row is skipped, its orphaned per-set rows are never joined back into anything user-visible. Acceptable dead data, not a correctness bug — documented as a residual in migration 150's own header."
proposed_fix: |
  Migration 150 adds `workout_log_exercises.deleted_at` + a BEFORE UPDATE
  trigger (`workout_log_exercises_delete_final_rename`) mirroring migration
  145's `workout_templates` pattern exactly: any write to an already-deleted
  row is a total no-op (delete wins regardless of race order with a delayed
  creating push), and the delete transition suffixes `exercise_id` to free
  the `uniq_wle_user_wlog_ex_set (user_id, workout_log_id, exercise_id,
  set_number)` natural key for a genuine re-log of the same exercise.

  Client: `PendingExlogDeletes` (new queue class, mirrors
  `PendingTemplateDeletes`) — `deleteLog` queues the row's exact natural key
  (computed via the new `resolveSummarySetCount` helper, so it is
  byte-identical to what `_syncExerciseLogs`'s push last computed) BEFORE
  removing the local Hive key. `_drainPendingExlogDeletes` UPSERTs a
  `deleted_at` tombstone per queued entry, called before every exercise-log
  push. `_restoreExerciseLogs` skips any cloud row with `deleted_at != null`.

  Found and fixed during implementation (not a separate bug — the SAME
  commit): `PendingExlogDeletes.add`/`.remove` initially called `.add()` /
  `.removeWhere()` directly on `read()`'s return value, which is the `const
  []` literal (immutable) on a fresh box — the very first delete for any user
  threw `UnsupportedError` and the whole `deleteLog` call failed (caught by
  this batch's own test, not by review). Fixed by copying to a growable list
  first. `PendingTemplateDeletes` shares the identical `return const []`
  shape and is NOT independently fixed here — flagged separately (see Related
  below), out of this fix's approved scope.
regression_test_planned:
  - test/contracts/exlog_tombstone_delete_writer_to_reader_test.dart (new, 16 tests) — resolveSummarySetCount pure/mutation-tested across all 3 set-count shapes + the empty-list edge case (6); PendingExlogDeletes add/dedup/remove pure Hive behavior (4); WRITER — deleteLog queues the exact natural key for a 3-set log, for two same-day exercises sharing one workout_log_id, and for a legacy no-sets[] row falling back to sets_completed (3); WIRING — _syncExerciseLogs drains before pushing, _drainPendingExlogDeletes targets the exact uniq_wle_user_wlog_ex_set columns, _restoreExerciseLogs skips a deleted_at row (source-grep, 3).
  - test/sql/workout_log_exercises_delete_final_rename_live_verify.sql (new, extended 2026-09-29) — live-Postgres verification of the trigger, mirroring test/sql/workout_templates_delete_final_rename_live_verify.sql's shape: case 1 (delete transition suffixes + stamps deleted_at), case 2 (a further write to a deleted row is a total no-op), case 3 (a genuine re-log against the freed natural key succeeds as a fresh INSERT), case 4 (adversarial review round 1 finding P1 — a tombstone-shaped INSERT, i.e. the drain's UPSERT is the FIRST cloud write for a natural key, is suffixed on INSERT and a subsequent re-log lands cleanly with its own data). Requires migrations 150 AND 151 live. Case 4 confirmed live to FAIL against 150 alone (bug reproduced) and PASS post-151 (fix confirmed) — see touched_layers_checked tier 3.
  - "Mutations run (rule 21): (1) removed deleteLog's PendingExlogDeletes.add call — 3 WRITER assertions reddened. (2) removed _syncExerciseLogs's _drainPendingExlogDeletes(userId) call — 1 WIRING assertion reddened. (3) removed _restoreExerciseLogs's deleted_at skip — 1 WIRING assertion reddened. All 3 mutations applied simultaneously in one run; 5 of 16 assertions reddened as expected, confirmed via the exact expected/actual values printed, then all three reverted and the file re-ran green (16/16)."
impact_analysis: |
  - Every user who deletes an exercise log and later restores on a fresh
    install / new device / cleared Hive: the deleted log no longer
    reappears.
  - A user who deletes a log and then re-logs the SAME exercise on the SAME
    date landing at the SAME set count: the re-log lands as a fresh row
    (case 3 of the SQL live-verify test) — the no-op trigger branch does not
    silently swallow it.
  - No behavior change for a log that is never deleted, or for a template
    delete (PendingTemplateDeletes/deleteTemplate untouched).
  - workout_log_sets rows for a deleted exercise become permanently orphaned
    (documented residual, not user-visible — see forbidden_patterns_checked).
  - Migrations 150 AND 151 are both LIVE (applied 2026-09-29, founder-
    authorized separately for each per CLAUDE.md §4.3 — plan approval ≠
    deploy approval). backups/applied_migrations.json holds both entries.
  - Tier: platform (supabase/migrations/**, lib/core/services/sync/**).
related_bugs: [OI-218, OI-252, f4a8c2]
recurrence: >-
  Same restore-completeness class as `restore_local_wins_additive_test.dart`
  documents, and the SAME fix shape (soft-delete tombstone + trigger + client
  drain queue) migration 145/OI-252 already applied for workout_templates one
  day earlier (2026-09-27) — the natural-key mechanics differ (composite
  4-column key here vs UNIQUE(user_id,name) there) but the race-safety
  reasoning is identical. OI-218 (filed 2026-09-18, still open) is the
  SIBLING symptom on `moveExerciseLogs`'s from-date row — same missing
  protocol, different call site, NOT fixed by this batch (out of the
  approved OI-245/OI-246 scope; noted as a natural follow-up now that the
  protocol exists). The PendingExlogDeletes const-list bug found during this
  fix's own implementation is filed as its own note (see below) rather than
  silently absorbed, since PendingTemplateDeletes shares the exact defect.

  SECOND, more direct recurrence, corrected 2026-09-29 after adversarial
  review round 1: migration 150's own trigger was `before update` ONLY, the
  EXACT SAME gap diagnose `f4a8c2` (2026-09-27) already found and fixed for
  workout_templates via migration 146 — one day before migration 150 was even
  drafted. This batch's own §4.1.5 bug-history lookup missed the precedent
  (146 postdates 145's own diagnose-doc, and the search that produced this
  doc did not re-check for a same-day-plus-one follow-up migration on the
  sibling table); it was found by an independent reviewer instead, not by
  process. Fixed via migration 151, mirroring 146's fix shape exactly
  (extend the trigger to `before insert or update`). Recorded here as an
  explicit process gap, not smoothed over: a bug-history lookup that checks
  only "has this exact bug happened before" and not "did the LAST fix for
  this exact pattern need a follow-up" will keep missing this class.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "PendingExlogDeletes (new) + deleteLog/resolveSummarySetCount (workout_write_service.dart) + _drainPendingExlogDeletes/_restoreExerciseLogs skip (sync_workout.dart); flutter analyze lib/ — 45 pre-existing infos, 0 new issues." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "test/contracts/exlog_tombstone_delete_writer_to_reader_test.dart WRITER group — real logExercise -> deleteLog round trip via wwsTestSetup, asserts PendingExlogDeletes.read() holds the exact natural key. 16/16 green; full test/sync/ + test/workout_write_service/ suites (156 tests) re-run clean, no regressions." }
  - { tier: 3, name: "Postgres schema", status: fixed_in_this_batch, evidence: "Migration 150 adds workout_log_exercises.deleted_at + the delete-final-rename trigger; migration 151 (2026-09-29, adversarial review round 1 finding P1) extends the trigger to fire on INSERT too. Both mirror migration 145/146's already-applied, already-verified shape for the sibling workout_templates table. Both LIVE — see tier 5." }
  - { tier: 5, name: "Migrations applied", status: fixed_in_this_batch, evidence: "Both 150 and 151 applied live to dedsavbjuwgarrhphgnl. 150: 2026-09-29T05:32:52+05:30, founder-authorized via AskUserQuestion, separate from batch approval per CLAUDE.md §4.3. Post-apply: information_schema confirmed deleted_at; pg_trigger confirmed count 1. 151: 2026-09-29T06:05+05:30, founder-authorized via a second, separate AskUserQuestion after round-1 review surfaced the INSERT-path gap. Verified BEFORE drafting 151 (bug reproduced live in a rollback-wrapped transaction against 150 alone: a tombstone-shaped INSERT left exercise_id unsuffixed, a re-log's data silently dropped) and AFTER applying (same repro succeeds: two rows, re-log data intact). Post-apply: pg_trigger.tgtype=23 (ROW+BEFORE+INSERT+UPDATE) confirms the new firing event. test/sql/workout_log_exercises_delete_final_rename_live_verify.sql's case 4 run live: FAILED against 150 alone (confirmed via the actual raised exception text), PASSED post-151. backups/applied_migrations.json holds both entries with correct sha256 hashes (recomputed programmatically from the files on disk, not hand-typed, after an initial hand-typed hash for 151 was caught truncated by one character during this same batch)." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "The tombstone drain itself is a client-side Supabase call, mirroring the template drain's own shape (no Edge Function involved there). Round-2 review finding P2 required a weekly-recalc/index.ts code fix (excludeDeletedLogs) — type-checked clean, 5/5 Deno tests green, mutation-proven. Round-3 B-pass finding P2 required a pr-detection/index.ts code fix (excludeDeletedPrs, identical shape) — type-checked clean, 11/11 Deno tests green (5 new), mutation-proven. NOT YET DEPLOYED: neither the live weekly-recalc nor pr-detection function runs its fix yet. Deploying either is a separate live action requiring its own explicit founder authorization per CLAUDE.md §4.3." }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "workout_log_exercises' existing wle_update_own/wle_insert_own RLS policies (migration 009) already permit the owning user's UPSERT; migration 150 adds no policy and needs none — the trigger runs SECURITY INVOKER under the same owning-user's write." }
  - { tier: 12, name: "Client → server contract", status: fixed_in_this_batch, evidence: "_drainPendingExlogDeletes' UPSERT payload and onConflict target verified against uniq_wle_user_wlog_ex_set (migration 082) column-for-column in this diagnose-doc's own forbidden_patterns_checked + the SQL live-verify test's case 3." }
---

# Deleted exercise logs reappear after a cloud restore (OI-246)

## Root cause

`WorkoutWriteService.deleteLog` (`workout_write_service.dart:1132`, pre-fix)
called `box.delete(logKey)` and nothing else against the cloud — no tombstone,
no cloud delete. `workout_log_exercises` carried no `deleted_at`/status
column at all (confirmed live 2026-09-28 against
`backups/live_schema_columns.json`), so `SyncService._restoreExerciseLogs`'s
additive/local-wins restore (`sync_workout.dart:916`, pre-fix) had no signal
to distinguish "never synced" from "deliberately deleted" — both look
identical: a cloud row whose Hive key is absent locally. Restore always wins
in favor of "bring it back".

## Fix

Mirrors migration 145's `workout_templates` soft-delete pattern (applied
2026-09-27, one day earlier) exactly: migration 150 adds
`workout_log_exercises.deleted_at` + a BEFORE UPDATE trigger that makes any
further write to an already-deleted row a total no-op, and suffixes
`exercise_id` on the delete transition to free the composite natural key
`uniq_wle_user_wlog_ex_set (user_id, workout_log_id, exercise_id,
set_number)` for a genuine re-log.

Client-side: `PendingExlogDeletes` (new queue class, mirrors
`PendingTemplateDeletes`) is written by `deleteLog` with the row's EXACT
natural key — always fully known at delete time (unlike templates' legacy-id
case, this table's identity needs no resolution step) — and drained by
`_drainPendingExlogDeletes` before every exercise-log push. Restore skips any
`deleted_at`-tombstoned row.

## A bug found and fixed inside this same fix

`PendingExlogDeletes.add`/`.remove` initially mutated `read()`'s return value
directly. `read()` returns the `const []` literal when nothing is queued yet
(a fresh box) — calling `.add()` on it throws `UnsupportedError`. This
batch's own test caught it on the very first run (not review): every
first-ever delete for a user would have failed the whole `deleteLog` call.
Fixed by copying to a growable list first. `PendingTemplateDeletes` shares
the identical `return const []` shape in its own `read()` and is **not**
touched by this fix — out of this batch's approved OI-245/OI-246 scope, filed
as **OI-270** rather than left as prose only.

## Scope note — OI-218

OI-218 (open, filed 2026-09-18) is the sibling symptom on
`moveExerciseLogs`'s from-date row — the exact same missing protocol, a
different call site (`workout_write_service.dart:775`'s own doc comment
already named this residual explicitly: "no cloud exlog tombstone protocol
exists"). This batch does NOT wire `moveExerciseLogs` to the new
`PendingExlogDeletes` infrastructure — that was outside the OI-245/OI-246
scope approved for this batch. OI-218 remains open; a future pickup can now
close its resurrection half cheaply by reusing this exact queue.

## Adversarial review round 1 remediation (2026-09-29)

A dispatched context-blind reviewer found one real defect (P1) and one
internal-consistency defect (P2) in the state this doc originally described.
Both fixed before round 2.

- **P1 (fixed — migration 151, applied live 2026-09-29T06:05+05:30)** —
  migration 150's `workout_log_exercises_delete_final_rename` trigger was
  `before update` ONLY; it never fired when `_drainPendingExlogDeletes`'s
  tombstone UPSERT was the very first cloud write for a natural key (an
  exercise log logged and deleted before its creating push ever synced, a
  realistic sequence since the drain runs before the per-key push loop on
  every sync pass) — that landed as a plain INSERT, the row was created with
  `deleted_at` set but `exercise_id` never suffixed, and
  `uniq_wle_user_wlog_ex_set` still occupied that exact natural key. A later,
  ordinary re-log of the same exercise/date/set-count then hit the
  "already deleted → no-op" branch and was silently dropped — it never
  reached `workout_log_exercises`, and never restores again despite being
  correct and current in the user's local Hive. **This is the identical gap
  OI-252's B-pass Finding 1 found and fixed for the sibling
  `workout_templates` table one day earlier, via migration 146** — a
  precedent this diagnose-doc's own §4.1.5 bug-history lookup should have
  surfaced and did not; see the `recurrence:` field above for the honest
  accounting of that miss.

  Fixed via migration 151 (extends the trigger to `before insert or update`,
  mirroring 146's exact fix shape, suffixing `new.exercise_id` on either
  firing event). Verified live, independently, in both directions before
  requesting authorization: (1) reproduced the bug against migration 150
  alone in a rollback-wrapped transaction — a tombstone-shaped INSERT left
  `exercise_id` unsuffixed, and a subsequent re-log's `reps` value was
  silently dropped (the row's `reps` stayed `null` after the "successful"
  upsert); (2) applied the identical fix logic within a second
  rollback-wrapped transaction (not yet the real migration) and confirmed it
  resolves cleanly: the tombstone row and the re-log now exist as two
  separate rows, the re-log carrying its own data intact. Founder authorized
  the live apply via a dedicated `AskUserQuestion`, separate from both the
  original batch approval and migration 150's own authorization. Post-apply:
  `pg_trigger.tgtype = 23` (ROW+BEFORE+INSERT+UPDATE) confirms the new firing
  event; `test/sql/workout_log_exercises_delete_final_rename_live_verify.sql`
  extended with case 4, run live and confirmed to FAIL with the exact
  expected error text against migration 150 alone (before 151 was applied),
  then re-run and confirmed to PASS (all 4 cases, `[]`/no exception) after.
  Checked the other live trigger on this table
  (`trg_suppress_redundant_updates`, Postgres's built-in
  `suppress_redundant_updates_trigger`, BEFORE UPDATE only) for interaction —
  harmless: it only skips a byte-identical no-op UPDATE, never true for the
  delete transition since `deleted_at` always changes.

- **P2 (fixed — this doc)** — this diagnose-doc's own `touched_layers_checked`
  tier 5 asserted migration 150 was "drafted this commit, NOT applied," while
  `backups/applied_migrations.json` in the same uncommitted batch already
  carried a live-apply entry for it — a stale field left over from an earlier
  draft of this doc, written before the founder-authorized apply happened,
  never updated after. Corrected; tier 5 now reflects both migrations' actual
  live state with full post-apply evidence.

## Adversarial review round 2 remediation (2026-09-29)

A second, independent context-blind reviewer verified the round-1 fixes from
scratch against live code and live Supabase state (not taken on faith) and
found no P1s — migration 151's fix is correct and live-verified, and the
hash-truncation class round 1's own remediation had to watch for was not
repeated. It found one genuine new defect and two trivial citation gaps, all
fixed here; one further gap was judged genuinely out-of-scope and filed as an
OI rather than silently dropped.

- **P2 (fixed)** — `supabase/functions/weekly-recalc/index.ts` computes
  `calculateExperienceLevel`'s exercise-variety and weight-progression scores
  by grouping `workout_log_exercises` rows on `exercise_id ?? exercise_name`,
  with no `deleted_at` filter (it didn't even select the column). Because
  migrations 150/151's trigger mutates `exercise_id` (suffixing it) on the
  delete transition, a log deleted within the trailing 4-week scoring window
  no longer merges into its real exercise's bucket — it creates a **new,
  unique, bogus "exercise"** keyed by the mangled `‹del:xxxxxxxx›` suffix,
  inflating the variety score and adding a spurious single-point entry to the
  weight-progression grouping for every in-window deletion. This is a genuine
  regression introduced specifically by this batch's exercise_id-suffix
  design (pre-fix, the same orphaned row at least had a clean, unmangled
  `exercise_id`, since nothing tombstoned it before OI-246) — not a
  pre-existing gap, and squarely inside the CLAUDE.md §4.1.5 value-semantics
  sweep this batch's own bug-history step should have caught and did not
  (that sweep was run for `lib/` and the client-side tests, not for
  `supabase/functions/`). Fixed by extracting a pure
  `excludeDeletedLogs`/`LiveLogRef` predicate
  (`supabase/functions/weekly-recalc/live_log_filter.ts`, mirroring the
  established `workout-window-closing/deleted_template_filter.ts` shape) and
  filtering `rawLogs` through it before deriving `allLogs`, plus selecting
  `deleted_at` in the fetch. New test:
  `supabase/functions/weekly-recalc/index_test.ts` (5 tests: 4 pure/edge-case
  on `excludeDeletedLogs`, 1 source-grep wiring check that the select list
  includes `deleted_at` and that the filter runs BEFORE `allLogs` is built).
  Type-checked clean (`deno check --node-modules-dir=none`). Mutation-proven:
  reverting `const liveRawLogs = excludeDeletedLogs(rawLogs);` to
  `const liveRawLogs = rawLogs;` reddened exactly the 1 wiring assertion (4/5
  stayed green, confirming the pure-function tests exercise the extracted
  logic independently of the wiring check); restored and re-confirmed 5/5
  green. **Not yet deployed** — this is a code fix in the worktree; the LIVE
  `weekly-recalc` Edge Function does not yet run it. Deploying requires its
  own explicit founder authorization per CLAUDE.md §4.3, separate from both
  migrations' authorizations.

- **P3 (fixed)** — `docs/sot_registry.yaml`'s `deleteLog` writer entry cited
  `line_range: 1101-1175` for a combined label "deleteLog + resolveSummarySetCount",
  but `resolveSummarySetCount` is actually defined at line 1389, well outside
  that range — a citation error from this batch's own earlier edit.
  `check_sot_registry_parity.dart` does not validate that every method named
  in a combined label falls inside its stated range, so it passed anyway.
  Fixed by splitting into two accurate entries (`deleteLog`: 1102-1185,
  `resolveSummarySetCount`: 1389-1401).

- **P3 (fixed)** — `test/contracts/coach_restored_media_mode_writer_to_reader_test.dart`'s
  parity check only string-matched `ai-media-proxy/index.ts`'s successful-
  analysis `[Photo:` insert (line 997, variable `media_type`), missing the
  separate paywall-exhausted insert (line 324, variable `mediaType` —
  different spelling, identical runtime prefix). Harmless today since both
  variants produce the same prefix `isRestoredMediaRow` recognizes, but the
  drift-detector would have missed line 324 diverging in isolation. Fixed by
  adding the missing parity assertion.

- **P3 (partially corrected by round 3 below)** — five OTHER
  `workout_log_exercises` readers across `supabase/functions/`
  (`pr-detection`, `i-see-you-callout`, `future-prediction`, `weekly-report`,
  `_shared/tools/progress/getProgressSummary.ts`) still don't filter
  `deleted_at` at all. This round's own characterization — that all five are
  "not newly broken by 150/151... unchanged" — turned out to be **wrong for
  `pr-detection` specifically**, caught by the round-3 B-pass below: unlike
  the other four, `pr-detection` renders `exercise_id` directly into
  user-facing push-notification text with no `exercise_name` fallback, so
  the suffix design DOES newly corrupt its output. Fixed in round 3, not
  left as OI-269 material. The other four (`i-see-you-callout`,
  `future-prediction`, `weekly-report`, `getProgressSummary.ts`) remain
  correctly filed as OI-269 — each individually verified to prefer/only-use
  `exercise_name` or a numeric aggregate, so their behavior really is
  unchanged by 150/151.

## Self-triggered B-pass code review, round 3 (2026-09-29)

Per CLAUDE.md §4.3, a platform-tier batch self-triggers `/code-review` before
the merge — a separate, mandatory step from the two adversarial plan-review
rounds above. Two fresh context-blind reviewers ran in parallel: reviewer A
(lenses 1/writer_reader_drift, 2/function_exception_swallow,
3/blast_radius_mismatch, 4/secrets_in_tree, 5/unawaited_no_error_sink,
7/missing_input — the latter with live read-only Postgres MCP access, no
writes); reviewer B (lenses 6/guard_without_its_mirror,
8/asserted_fixture_value — mutation testing in the same worktree, all
mutations reverted and confirmed clean before finishing).

**Reviewer B: 0 findings.** Independently re-ran every mutation-proof claim
in both diagnose-docs (the triple-mutation → 5/16 red on
`exlog_tombstone_delete_writer_to_reader_test.dart`; the single-mutation →
1/5 red on `weekly-recalc/index_test.ts`; the marker-collision fix's
grep-count-1 confirmation) and every one reproduced exactly. Live-verified
migration 151's trigger (`tgtype=23`) and `workout_log_exercises.deleted_at`
via read-only `information_schema`/`pg_trigger` queries.

**Reviewer A: 2 findings, both accepted, both resolved.**

- **P2 (fixed)** — `writer_reader_drift` / value-semantics sweep gap. The
  round-2 finding above (and OI-269's original text) characterized all five
  un-patched readers as "unchanged" — false for `pr-detection`: its
  `composeMessage` (`message.ts`) interpolates `exercise_id` directly into
  the push-notification body with **no `exercise_name` fallback** (unlike
  `i-see-you-callout`'s `pr.exercise_name ?? pr.exercise_id`), and the query
  (`index.ts:86`) had no `deleted_at` filter. A PR logged and deleted inside
  the same ~20-minute cron window (a realistic "oops, mis-logged" sequence —
  the drain runs on every sync pass) would send a real push reading e.g.
  `"John — new Bench Press ‹del:a1b2c3d4› 100kg PR. Keep going 💪."` — a
  genuinely new, user-visible regression in the exact class this batch
  already recognized and fixed for weekly-recalc, mischaracterized as
  out-of-scope. Fixed by mirroring the identical
  `excludeDeletedLogs`/`live_log_filter.ts` pattern:
  `supabase/functions/pr-detection/live_pr_filter.ts`'s `excludeDeletedPrs`,
  wired into `index.ts` (select now includes `deleted_at`; `rawRows` filtered
  through `excludeDeletedPrs` before grouping-by-user). Type-checked clean
  (`deno check --node-modules-dir=none`). New tests in
  `supabase/functions/pr-detection/index_test.ts` (5 new: 4 pure/edge-case on
  `excludeDeletedPrs`, 1 source-grep wiring check that the select includes
  `deleted_at` and the filter runs before grouping — 11 total in the file).
  Mutation-proven: reverting `const rows = excludeDeletedPrs(rawRows);` to
  `const rows = rawRows;` reddened exactly the 1 wiring assertion (10/11
  stayed green); restored and re-confirmed 11/11 green. **Not yet
  deployed** — same caveat as the weekly-recalc fix: this is a code fix in
  the worktree, the LIVE `pr-detection` function does not yet run it, and
  deploying needs its own explicit founder authorization per CLAUDE.md §4.3.
  OI-269 corrected (title + body) to move `pr-detection` from "5 remain, all
  unchanged" to "fixed in round 3"; the other 4 readers were each
  individually re-verified (not assumed from the blanket claim) to prefer
  `exercise_name` or read only numeric aggregates, so they genuinely are
  unchanged and correctly remain OI-269 material.

- **P2 (documented, not code-fixed)** — `blast_radius_mismatch`. Platform
  tier's `requires:` list (`docs/blast_radius.yaml`) includes `feature_flag`,
  and nothing in this batch gates `PendingExlogDeletes`'s drain, the
  `_restoreExerciseLogs` `deleted_at` skip, or `isRestoredMediaRow`'s mode
  derivation behind a kill-switch — neither diagnose-doc discussed or
  justified the absence before this finding. Investigated rather than
  reflexively adding a switch: the established, already-shipped sibling
  mechanism this batch's own code comment says it mirrors —
  `_drainPendingTemplateDeletes` (OI-252, `sync_workout.dart:1334`, a
  pending-delete queue drained by an UPSERT tombstone, identical shape) —
  was independently confirmed (`grep -n "disable_\|killSwitch" ... | grep
  -i templ` → zero hits) to carry **no kill-switch either**, and it already
  shipped and has been live for weeks. A kill-switch here would also be the
  WRONG exemption shape in the sense CLAUDE.md's own review-tuning history
  warns about (§4.12/this skill's tuning history, 2026-08-25 P0 entry): both
  the drain and the restore-skip exist specifically to CLOSE the OI-246 data
  corruption (deletes not reaching cloud / reappearing on restore) — a
  switch to disable either would silently re-open the exact bug this batch
  fixes, for the sake of satisfying a checklist item. `isRestoredMediaRow`'s
  mode fix is a pure read-time classification with no analogous "old broken
  path" to fall back to (the old path was the OI-245 bug itself). Resolved
  as a documented exemption rather than a code change: this repo's own
  established precedent (`_drainPendingTemplateDeletes`) already treats a
  pending-delete-drain-of-a-live-authorized-migration as not needing a
  client kill-switch, and this batch's exlog equivalent is not a new
  departure from that norm.

## Corrected full-suite re-run finding (2026-09-29)

Neither review round runs `flutter test` (both reviews read source and
targeted tests; §4.12.5 already documents that gap as a repeating pattern in
this repo). A prior in-session run of the full suite used the wrong
environment (no `TZ=Asia/Kolkata`, no `--exclude-tags golden` — see
`reference_vps_full_suite_needs_ist_tz.md`) and could not be trusted; the
CORRECTED re-run (`TZ=Asia/Kolkata flutter test test/ --exclude-tags golden`)
surfaced one real regression this batch introduced and neither review round
caught, because neither ran the suite this file's own new code could break
outside its own diff:

- **Fixed** — `test/contracts/sync_natural_key_guard_test.dart`'s
  `workout_log_exercises (summary)` guard test failed with a message reading
  as if the null-key guard itself had broken
  (`workout_log_exercises summary upsert must be preceded by a
  'sync_skipped_null_natural_key' telemetry emission`), but the guard was
  untouched. Root cause: `_drainPendingExlogDeletes` (new this batch,
  `sync_workout.dart:196`) issues its own
  `.from('workout_log_exercises').upsert({` call — sharing the EXACT marker
  literal `windowBefore`'s `src.indexOf(marker)` anchors on to find the REAL
  per-row push upsert at `:495`. Because the new call sits earlier in the
  file, `indexOf` (first-match) silently re-anchored onto it instead, putting
  the null-key guard (near `:495`) far outside the window measured from the
  wrong point. This is the recurring "extracting/moving code breaks
  source-grep contracts" class (CLAUDE.md §4.9), but a new variant: nothing
  moved or was renamed — ADDING a new call site that happens to share an
  existing marker's literal text was enough to hijack the anchor. Fixed by
  extending the marker with a trailing newline, exploiting the one stable
  structural difference between the two calls: the drain's is
  `.upsert({` (inline map, brace on the same line), the real one is
  `.upsert(\n  summaryPayload,` (named variable, multi-line). Verified: the
  fix passes (5/5); reverting it alone reproduces the exact original failure
  message (mutation-proven both directions). Added as a fifth documented
  variant of the CLAUDE.md §4.9 pitfall row.

## Verification

`test/contracts/exlog_tombstone_delete_writer_to_reader_test.dart` (16
tests) + `test/sql/workout_log_exercises_delete_final_rename_live_verify.sql`
(4 cases, run live post-apply against both migrations) +
`supabase/functions/weekly-recalc/index_test.ts` (5 tests, round-2 P2 fix,
mutation-proven) + `supabase/functions/pr-detection/index_test.ts` (11 tests
total, 5 new for the round-3 B-pass P2 fix, mutation-proven) +
`test/contracts/sync_natural_key_guard_test.dart` (5 tests, repointed marker,
mutation-proven) + a full corrected suite run (`TZ=Asia/Kolkata flutter test
test/ --exclude-tags golden`) — no regressions. Two-agent self-triggered
B-pass (round 3, CLAUDE.md §4.3): 2 findings, both resolved (see above) — 0
outstanding.
