---
bug_id: f4a8c2
date: 2026-09-27
batch: reuse-audit-fixes (unit 2a — template stable-ID rework, OI-252)
status: fixed
blast_radius: platform
symptom: |
  Found by the reuse audit. Deleting a workout template on one device, then
  restoring on another (or after a reinstall), could bring the deleted
  template — and any workout day scheduled against it — back to life. Root
  cause was TWO compounding defects: (1) a template's cloud identity was
  derived from `(user_id, lower(name))`, so deleting a template and later
  creating a NEW one under the same name collided on the SAME cloud row —
  restore then had no way to tell "this row is the live replacement" from
  "this row is the deleted original" apart; (2) even with a stable identity,
  none of the three restore paths that can carry a `template_id` reference
  (`_restoreScheduledWorkouts`'s live `scheduled_workouts` embed,
  `_restoreWorkoutPlan`'s frozen `plan_json.schedules` snapshot, and
  `PlanIntegrityReconciler`'s boot-time heal of that same snapshot) had any
  concept of "deleted" — each treated a `template_id` at face value and
  hydrated/wrote the referenced day regardless of whether the template still
  existed. A renamed template's OLD name similarly orphaned: nothing freed
  it for reuse, so a second template created under the same original name
  could not be saved (`UNIQUE(user_id, name)`).
concept: workout_templates
sot_registry_entry: workout_templates
related_bugs:
  - 2026-05-10-restore-overwrite-d9b2c5 — same restore-resurrection SHAPE (a stale cloud row winning over newer local truth), different field (schedule status, not template identity)
  - a7d3f1 — the plan_json restore-skip bug that PlanIntegrityReconciler + _restoreWorkoutPlan's completed-day-preserving merge already exist to fix; this batch adds a second, independent filter (ghost-day) to the SAME merge loop
recurrence: |
  yes — restore-path writer/reader drift class (the same class as d9b2c5 and
  a7d3f1): a piece of local/server state changed meaning (a template can now
  be "soft-deleted") and multiple existing restore readers had to be
  independently taught the new meaning, because each one reads the SAME
  underlying `template_id` field through a DIFFERENT path (live embed vs.
  frozen snapshot vs. boot-heal re-application of that snapshot).
writers:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "WorkoutWriteService.deleteTemplate — local Hive delete + queues PendingTemplateDeletes(id: cloudIdFromKey(key) or null, name:)", line: 1243 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "SyncService._drainPendingTemplateDeletes — drains the queue by UPSERTing a cloud tombstone (deleted_at, is_active:false) per id, resolving a null id by (user_id,name) first", line: 1287 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "SyncService._syncWorkoutTemplates — id-keyed upsert (onConflict:'id'), replacing the old name-based lookup that made a delete+recreate collide on one cloud row", line: 1330 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreScheduledWorkouts — a row whose embedded template carries deleted_at is never hydrated/written; an existing local reference is cleaned via _cleanScheduleReferencesToTemplate", line: 2140 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreWorkoutPlan — a plan_json.schedules entry whose template_id resolves into _deletedTemplateCloudIds() is dropped (ghost-day filter, shared isGhostScheduleEntry predicate)", line: 1248 }
  - { file: lib/core/services/plan_integrity_reconciler.dart, method_or_widget: "PlanIntegrityReconciler.reconcile — same ghost-day filter applied to the boot-time heal of the identical plan_json snapshot", line: 345 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreWorkoutTemplates — rewritten to positive-evidence-only removal (a deleted_at row deletes locally + cleans schedule refs); the old canonicalKeys stale-key SWEEP is gone (it would have deleted every not-yet-pushed local template on a first restore)", line: 1561 }
hive_key_prefix: "tmpl_"
hive_key_formula: "templateKeyFor(const Uuid().v4()) == 'tmpl_<uuid-v4>' — client-minted once at create time (WorkoutWriteService.newTemplateKey()), never re-derived from name/content. Supersedes 'tmpl_<ms>' / 'tmpl_<nameHash>'; TemplateIdentityMigrator rekeys any surviving legacy row."
sync_methods: [_syncWorkoutTemplates, _drainPendingTemplateDeletes]
restore_methods: [_restoreWorkoutTemplates, _restoreScheduledWorkouts, _restoreWorkoutPlan]
cloud_table: workout_templates
cloud_columns: [id, deleted_at, is_active, name]
contract_test_path: test/sync/oi252_deleted_template_restore_behavioral_test.dart
ist_handling: []
provider_invalidations: [currentPlanProvider, calendarWeekProvider, todayWorkoutProvider]
telemetry_op_types:
  success: []
  failure: [sync_deleted_template_cloud_ids, sync_drain_pending_template_deletes, sync_service_if_16, sync_service_if_21]
cross_account_guard: Unchanged — workoutBox / userBox via wrapUserScopedBox; PendingTemplateDeletes lives in userBox (cleared on logout, documented as its own known limit, tracked as OI-253).
forbidden_patterns_checked:
  - "nulling scheduled_workouts.template_id on delete (FK SET NULL) — rejected: migration 145 renames+deactivates instead of dropping the row, so the FK stays valid and downstream readers can still SEE which template a day pointed at (for cleanup) instead of losing that information the instant the delete lands."
  - "gating the WHOLE restore on the template-identity migrator — rejected (round-2 plan review): would starve every OTHER sync domain for an offline user who happens to have legacy template keys. Scoped to _syncWorkoutTemplates only."
  - "resolving the deleted-template cross-check inside WorkoutWriteService.deleteTemplate itself — rejected: that class has zero Supabase access by design (WriteServices are Hive-only); the cloud-side resolution had to move into SyncService, which already owns cloud I/O."
proposed_fix: |
  One stable, client-minted UUID identity per template (create-time only,
  never re-derived), a rename-on-delete tombstone trigger that keeps
  UNIQUE(user_id, name) satisfiable without dropping the row, and a
  ghost-day filter applied independently to every restore path that can
  carry a stale template_id reference (live embed, frozen plan_json
  snapshot, and the boot-time heal of that same snapshot) — each path
  resolves the deleted set on its own (no dependency on restore-Future
  ordering) via the shared _deletedTemplateCloudIds / isGhostScheduleEntry
  helpers.
regression_test_planned:
  - test/sync/oi252_deleted_template_restore_behavioral_test.dart (new, 10) — deleted-embed row never written; deleted-embed row cleans an existing local schedule reference; live-embed row writes template_id in the stable Hive-key form (not the raw cloud uuid); plan_json ghost day dropped; plan_json live day written normally; a plain rest day (no template_id) unaffected; isGhostScheduleEntry pure-predicate cases (no template_id / legacy key / not-deleted / deleted).
mutation_proven: |
  Three independent mutations, each run against the full 10-test file:
  (1) `if (tmpl['deleted_at'] != null)` → `if (false && ...)` in
  `_restoreScheduledWorkouts` reddened exactly the 2 tests that exercise the
  embed-based deleted-template detection (8/10 stayed green). (2)
  `isGhostScheduleEntry`'s body replaced with a bare `return false;`
  reddened exactly the 2 tests that depend on it (the plan_json ghost-day
  drop + the predicate's own "cloud id IS in the deleted set → true" case;
  8/10 stayed green). (3) the merged-row `template_id` write reverted from
  `hiveTemplateKey` back to the raw `map['template_id']` reddened exactly
  the 1 test asserting the Hive-key-form write (9/10 stayed green). All
  three mutations compiled; each was restored from a pre-mutation backup
  and the full 10/10 green re-confirmed before proceeding.
impact_analysis: |
  A deleted template — and any schedule day/plan_json entry that pointed at
  it — no longer resurrects on restore, on any device, regardless of which
  of the three restore paths runs or in what order. A renamed-away original
  name is freed for reuse by a new template. Live (non-deleted) templates
  and their schedule days are written exactly as before — every mutation
  above left the "live" arm green throughout. Migration 145 was applied to
  the live database 2026-09-27 (founder-authorized, separate from plan
  approval per CLAUDE.md 4.3) and both Edge Function changes
  (restore-user-snapshot, workout-window-closing) are deployed — see
  touched_layers_checked tiers 3 and 6 for the live verification.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/ clean (45 pre-existing infos, 0 errors/warnings) across every file this unit touched." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "test/sync/oi252_deleted_template_restore_behavioral_test.dart — real workoutBox write -> restore -> read, mutation-proven on 3 independent legs." }
  - { tier: 3, name: "Postgres schema", status: fixed_in_this_batch, evidence: "Migration 145 applied live to dedsavbjuwgarrhphgnl 2026-09-27T06:44:46+05:30 (cloud_version 20260927011446), founder-authorized in chat separately from plan approval. Post-apply live verification: pg_trigger shows workout_templates_delete_final_rename (count 1) on public.workout_templates; information_schema.columns confirms deleted_at exists (ordinal position 11). backups/applied_migrations.json + backups/live_schema_columns.json updated same batch; check_migrations_applied + check_schema_column_refs gates both PASS." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "restore-user-snapshot deployed to dedsavbjuwgarrhphgnl as v7 (HTTP 201) and workout-window-closing as v15 (HTTP 201), both founder-authorized. Both Deno type-checked (deno check --node-modules-dir=none) clean pre-deploy; workout-window-closing's 8-test Deno suite (index_test.ts) green pre-deploy. Both functions' post-deploy smoke probes returned 401/Unauthorized as expected (restore-user-snapshot is verify_jwt:true rejecting an unauthenticated probe; workout-window-closing's isAuthorizedCronCall guard rejecting a probe with no cron secret) -- neither is a regression." }
---

## Summary

A deleted workout template could resurrect via restore because (a) its cloud
identity was name-derived, so a delete-then-recreate under the same name
collided on one row, and (b) no restore path treated a deleted template's
downstream references (schedule days, plan_json entries) as gone. Fixed with
a stable client-minted identity, a rename-on-delete tombstone (migration 145,
applied live 2026-09-27), and an independent ghost-day filter on every
restore path that can carry a stale reference.

## B-pass remediation (2026-09-27, `docs/reviews/template-stable-identity-bpass.md`)

A self-triggered B-pass on this unit found 7 real defects (0 false alarms,
independently re-verified against live code/cloud state before any fix
landed). Findings 3-7 (documentation/citation drift) are fixed and verified —
see the review file's per-finding `status:` fields. The two P1s:

- **Finding 2 (fixed)** — `TemplateIdentityMigrator.runIfNeeded` was wired
  into `_syncWorkoutTemplates` only, never into `_restoreWorkoutTemplates` —
  the path `restoreLightweightAlways` calls on every normal sign-in once
  Hive already has local data (the common returning-user case). A device
  holding a pre-rework legacy-keyed template never got it rekeyed on this
  path, rendering as a duplicate until `weeklyFullSync` happened to fire.
  Fixed by adding the identical gate to `_restoreWorkoutTemplates` itself
  (`sync/sync_workout.dart`), covering every caller of that method in one
  place. Regression test: `test/sync/oi252_template_restore_migrator_wiring_test.dart`
  (2 tests) — a test-only invocation counter on the migrator
  (`TemplateIdentityMigrator.invocationCountForTest`) proves the gate is
  reached, since this repo has no Supabase-mocking seam to exercise the
  migrator's own live-network legacy-key-resolve branch (verified: zero
  existing tests reference `TemplateIdentityMigrator`, zero mock-http/mock-
  Supabase packages in `pubspec.yaml` — building one is disproportionate to
  this fix). Mutation-proven: deleting the gate call reddened exactly the
  invocation-count test (1 of 2) and left the functional pass-through test
  green, as expected — restored from a pre-mutation backup, both green
  re-confirmed after.

- **Finding 1 (drafted, NOT yet applied — blocked)** — migration 145's
  `workout_templates_delete_final_rename` trigger is `before update` ONLY;
  it never fires when `_drainPendingTemplateDeletes`'s tombstone UPSERT is
  the very first cloud write for a template's id (created and deleted in
  the same offline session, so no prior "creating push" ran) — that lands
  as a plain INSERT, the row is created with `deleted_at` set but the name
  is never suffixed, and `UNIQUE(user_id, name)` still occupies that name,
  so a later ordinary re-create under the identical name hits a live
  `23505` — reopening the "42P10 forever" class 145 itself exists to avoid,
  through the one path its header comment didn't cover. Does NOT reopen the
  resurrection bug this diagnose-doc's own fix closes (restore still
  filters purely on `deleted_at`, untouched by this gap) — a distinct,
  narrower regression in the rename/name-freeing guarantee only, and it
  requires a specific offline create-then-delete-before-first-sync sequence
  to trigger, which is uncommon but real.

  Fix drafted as follow-up migration 146 (extends the trigger to
  `before insert or update`, suffixing on `new.name` when fired by INSERT
  since `OLD` doesn't exist there) — SQL content is final and was NOT saved
  under `supabase/migrations/` in this commit specifically to avoid failing
  Gate 14 (`check_migrations_applied.dart`) for the rest of this batch,
  since it is drafted but unapplied. **Two live-apply attempts via
  `apply_migration` were both denied by the Claude Code auto-mode
  classifier** (attempt 1: "Production Deploy"; attempt 2: "Protected-Scope
  IaC Apply") — per CLAUDE.md §4.3 ("A classifier block on a live apply is
  CORRECT; get the explicit ok, never work around it"), this was not
  retried a third time or worked around. **Founder action needed**: either
  grant the permission so a future attempt can land, or apply the drafted
  SQL manually via the Supabase dashboard SQL editor and have a future
  session update `backups/applied_migrations.json` + this doc's
  `touched_layers_checked` tier 3 to match. The full drafted migration file
  (header, function body, trigger, live BEGIN/ROLLBACK verification
  snippet, inline rollback block) is preserved and ready to commit as-is
  once applied — see the branch's follow-up commit / OI board for its
  current location if this doc is read after that lands.
