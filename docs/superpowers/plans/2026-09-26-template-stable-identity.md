# Unit 2a — workout templates get ONE stable identity (rev 7)

**Batch:** reuse-audit-fixes, unit 2a. Founder decisions (2026-09-26): **delete wins everywhere**;
**"Stable ID rework"** — one permanent template ID used by sync, restore, schedules and the plan
snapshot so DELETE and RENAME both propagate. Saved meals (2b) reuse the pattern afterwards.

> **Rev 6 (after rev 5 round 1, not converged, 7 material).** Fixed: dropping
> `UNIQUE(user_id,name)` caused 42P10-forever + sweep data loss for old clients (P0) → keep the
> constraint, rename-on-delete instead; drain race → upsert-not-update tombstone; restore-order
> premise was wrong on most paths → thread a `deletedTemplateIds` set through the pass instead of
> relying on ordering; schedule payload dropped stale refs → always send the key; no test seam →
> reuse the existing live-account seam (`test/supabase/supabase_test_helper.dart`).
>
> **Rev 7 (after rev 6 round 2, not converged, 2 material + 2 minor).** Round 2 verified findings
> 1/2/5/9-mechanism/10 as genuinely fixed, then found: **(P1) gating scope unresolved** —
> `_restoreIfNeeded` (`sync_service.dart:1506-1527`) is the SOLE entry point for ALL restore
> domains (templates, nutrition, weight, measurements, profile — confirmed by reading it: no
> domain-specific gate exists there), so rev 6's "gate the restore call" would starve unrelated
> domains for an offline user, not just templates. **(P1) `*ForSyncDomain` gap** — confirmed
> `restoreWorkoutPlanForSyncDomain` (`:2214`) and `restoreScheduledWorkoutsForSyncDomain` (`:2238`)
> are separate single-domain entry points rev 6's threading list never covered. Minor: the "3 of 4
> parallel" claim was wrong (`_attemptSingleCallRestore` is sequential `await`s, not
> `Future.wait` — doesn't affect the fix, corrected below); the EF join mechanism for finding 9
> risked dropping null-`template_id` rows via an `!inner` embed. Rev 7 fixes all four; changes
> from rev 6 marked **[rev7]**.

## Root cause (unchanged from rev 5, still the root)

A template has four identities today: Hive key on create `tmpl_<ms>`
(`template_builder_screen.dart:370`, `train_provider.dart:2177`, AI `workout_repository.dart:1651`);
Hive key on restore `tmpl_<hash(lower(name))>` (`sync_workout.dart:1482-1485`) with a sweep that
deletes every other `tmpl_*` key (`:1544-1554`); cloud identity `(user_id, name)` (push
`onConflict: 'user_id,name'` `:1301-1311`, id lookup by name `:1321-1326`,
`resolveCloudTemplateId` by name `:1637-1677`); schedule `template_id` = the Hive key when
assigned (`template_service.dart:149`) but the CLOUD UUID after a restore (`sync_workout.dart:2101`).
There is no cloud delete anywhere. Consequences: delete resurrects; rename orphans the old-name
row which restores as a second template; restored schedule days survive template delete.

## The one identity

`id` = a UUID minted ON THE CLIENT when a template is created — the cloud primary key. Locally
spelled `tmpl_<uuid>`: the Hive key, the row's `id` field, every schedule/plan_json `template_id`,
the AI snapshot `saved_templates[].id`. Two pure helpers, `lib/core/services/template_identity.dart`:
`templateKeyFor(uuid) => 'tmpl_$uuid'`, `cloudIdFromKey(key)` (null for a non-UUID legacy key). No
lookup, no name. Every `startsWith('tmpl_')` scan keeps working. Rename changes only `name`.

## Cloud — migration 145 (explicit go before live apply)

- `alter table workout_templates add column deleted_at timestamptz;` **[rev6: `UNIQUE(user_id,name)`
  is KEPT — not dropped.** Dropping it was the P0: it made every old-client push fail 42P10
  forever and starved their local sweep into deleting their own unsynced templates. Keeping it
  costs nothing new: old clients keep syncing by name exactly as today, blind to deletes made on
  upgraded devices — a pre-existing limitation (old clients never understood any of this), not a
  regression this batch introduces.)
- Trigger `workout_templates_delete_final_rename` BEFORE UPDATE, SECURITY INVOKER,
  `set search_path = ''`:
  1. **Transition to deleted** (`OLD.deleted_at is null and NEW.deleted_at is not null`):
     `NEW.is_active := false; NEW.name := OLD.name || ' ‹del:' || left(NEW.id::text, 8) || '›'`.
     Renaming frees the original name under `UNIQUE(user_id,name)`, so a re-create (new id, new
     row) or an old client's name-keyed upsert both succeed as plain inserts — neither touches
     the deleted row.
  2. **Any write to an already-deleted row** (`OLD.deleted_at is not null`): `return null;` — the
     UPDATE is silently skipped in full (name, is_active, deleted_at all stay as they are). This
     is what makes the tombstone final regardless of arrival order (see Drain below): a late
     upsert from an in-flight push can never un-delete or rename a tombstoned row.
- FKs unchanged; soft delete keeps `scheduled_workouts.template_id` (NO ACTION) valid.
- Rollback: drop trigger + function + `deleted_at` column. Renamed rows stay renamed (their
  suffix is harmless cosmetic drift, not a correctness issue) — state this in the rollback notes.
- Regenerate `backups/live_schema_columns.json` FROM LIVE. Classify the real file for tier.

## Client

| Area | Change |
|---|---|
| Create (builder `:370`, `saveTemplate:2177`, AI `createTemplate:1651`) | key = `templateKeyFor(Uuid().v4())` via one `WorkoutWriteService.newTemplateKey()`. AI keeps `group_id` as-is. |
| Push `_syncWorkoutTemplates` | skip rows whose key is not UUID-shaped (legacy, awaiting migrator). Upsert `{'id': cloudIdFromKey(key), user_id, name, …}` with `onConflict: 'id'` — first push is an INSERT (fresh id), later pushes are UPDATE. Delete the name→id lookup (`:1321-1326`) — the id is already known. Drain pending deletes (below) BEFORE the loop; a drain exception aborts the template push for this run so a partial drain can't interleave with a stale create. |
| Schedule push `resolveCloudTemplateId` (`:1637`) | becomes `cloudIdFromKey(template_id)` — pure, no lookup; a non-UUID legacy key → null. |
| Schedule payload (`:1712`) **[rev6, finding 5]** | `payload()` now always includes the `template_id` key, sending explicit `null` when the local row has none — clears a stale (deleted) reference in cloud instead of leaving it. Verify in implementation that no server-side check/RLS/`.select()` shape depends on the key's ABSENCE (quick grep before coding; if one does, special-case it). |
| Delete (`TemplatesNotifier.deleteTemplate:2219` → new `WorkoutWriteService.deleteTemplate`) | local delete + `cleanSyncTemplateSchedule(key)` (now matches restored days, since restore also writes the key), skipping terminal/`moved` rows (`tool_dispatcher.dart:764`) not just `completed` + queue `{id: uuid, name: <name at delete time>}` in `PendingCloudDeletes` (userBox direct). **[rev6]** best-effort drain attempted synchronously before logout completes (timeout-bounded); a failed/offline attempt still loses the pending delete on that device — filed as its own OI, since a full "durable delete across sign-out" mechanism is separate scope from this unit. |
| Drain **[rev6, finding 2 — race fix]** | per queued `{id, name}`: `upsert({'id': id, 'user_id': uid, 'name': name, 'deleted_at': now, 'is_active': false}, onConflict: 'id')` — UPSERT, not UPDATE. If the row does not exist yet (the creating push hasn't landed), this INSERTS the tombstone directly; the creating push's later upsert then hits the `OLD.deleted_at is not null → return null` trigger branch and is silently dropped, so the delete wins regardless of arrival order. Any non-exception result ⇒ dequeue. |
| Restore templates (`:1446`, bundle + legacy) | query ALL rows incl. deleted (`limit 500 order by deleted_at nulls first`, `select('*, template_exercises(*)')`). Live row → write at `templateKeyFor(id)`. Deleted row → remove local key + `cleanSyncTemplateSchedule(key)`. Rows whose uuid is pending-delete → skipped. No sweep: local rows absent from the cloud set are unpushed creations and are kept; removal happens only on positive evidence (a row with `deleted_at` set). |
| **Deleted-id set threaded through the WHOLE restore pass [rev7, extends findings 3+4]** | New private helper `Future<Set<String>> _deletedTemplateCloudIds(String userId, {List? preFetchedTemplateRows})` — if `preFetchedTemplateRows` is given (single-call path, already fetched with deleted rows included) it derives the set from those with NO extra query; otherwise it runs one light query `select('id').eq('user_id',userId).not('deleted_at','is',null).limit(1000)`. **[rev7]** Every caller that touches template-derived state gets it by calling this helper itself rather than relying on being fed a value from a sibling `Future` — this covers `_restoreWorkoutTemplates`, `_restoreWorkoutPlan`, `_restoreScheduledWorkouts`, AND the two standalone single-domain entry points **`restoreWorkoutPlanForSyncDomain` (`:2214`) and `restoreScheduledWorkoutsForSyncDomain` (`:2238`)**, which round-2 found rev 6's design never reached. Cheap (indexed, small `limit`) and self-contained per call, so no call site depends on another's completion order. |
| Restore schedules (`_restoreScheduledWorkouts`) | write `template_id: templateKeyFor(cloud template_id)`; a row whose `template_id` maps into `_deletedTemplateCloudIds()` (via the embed OR the resolved cloud id) → skipped/removed locally, regardless of Future ordering. Embed selects `deleted_at`. |
| plan_json restore (`_restoreWorkoutPlan`) + `PlanIntegrityReconciler` | a non-completed `custom_template` entry whose `template_id`'s cloud id is in `_deletedTemplateCloudIds()` OR in the local pending-delete queue → dropped. Positive evidence only (matches the "no sweep" principle) — never keyed on box/ordering state. |
| One-time legacy migration (`TemplateIdentityMigrator`, flag `tmpl_identity_v1_done` in userBox) **[rev7, redesigned scope for finding 2]** | runs after auth. **Gates ONLY the template domain, never `_restoreIfNeeded` as a whole** — `_restoreIfNeeded` (`sync_service.dart:1506-1527`) is the single entry point for EVERY restore domain (templates, nutrition, weight, measurements, profile, customs), confirmed by reading it: no domain-specific gate exists there today, so gating it would starve unrelated domains for an offline user, which round 2 correctly flagged. Instead, the migrator attempt is the FIRST statement inside `_restoreWorkoutTemplates` and `_syncWorkoutTemplates` themselves: online + not yet done ⇒ run it, then proceed; offline + not yet done ⇒ **that function returns early** (skips template restore/push for this pass only) while every other domain in the same `Future.wait` completes normally. Schedule and plan_json restore do NOT block on the migrator — they call `_deletedTemplateCloudIds()` regardless (it degrades gracefully: pre-migration, legacy `template_id` values are non-UUID and simply don't match any id in the set, so the ghost-day filter is a no-op until migration completes, never a false strip). For each non-UUID `tmpl_*` row: query live rows by name (`.limit(1)` not `.maybeSingle()` — never throws even if a transient duplicate exists) → found ⇒ adopt that id; not found ⇒ mint new. Two-or-more local rows sharing a name ⇒ keep the newest by content, drop the rest. Rekey the Hive row; rewrite every `schedule_*`/`displaced_*`/plan_json `template_id` equal to ANY old key (legacy Hive key or a raw cloud UUID with no local match) to the new `tmpl_<uuid>` form. Re-runs every launch (cheap box-keys scan) — idempotent, not strictly one-shot. |
| EFs | `restore-user-snapshot` (`:160-167`) drop `is_active` filter, add `deleted_at` to the select + schedule embed (`:239-247`). `workout-window-closing` (`:175-199`) **[rev7, corrected mechanism for finding 9]** — do NOT join in the query (an `!inner` embed join risks silently dropping schedule rows with a null `template_id`, per round 2). Instead, build `deletedIds` from the EF's OWN existing second `templates` fetch (the `templateNameById`-building step) and filter the schedule rows in application code — exclude any row whose `template_id` is in `deletedIds` — before the "window closing" nudge is composed. AI tools unchanged (already pass the Hive key). |

Apply order: migration 145 → EFs → client merge. New client on the old EF: restore gets live
rows only (old EF filters `is_active`), so remote deletes are not observed until the EF deploys;
nothing resurrects (push is by id + trigger, independent of the EF).

## Filed on the OI board (pre-existing or explicitly out-of-scope; via `mint_oi.sh`)
- AI multi-day `group_id` lost on restore (no cloud column) — pre-existing.
- Migration 067 recorded applied but live still has its "dropped" columns — pre-existing.
- Restore "always refresh" can revert an unpushed offline EDIT — pre-existing.
- A pending delete not drained before logout/offline sign-out is lost on that device (best-effort
  drain added this unit; a durable cross-session delete queue is separate scope).

## Tests (behavioral, mutation-proven)
- `test/core/template_identity_test.dart`: key↔uuid round trip, legacy key → null.
- `test/contracts/template_stable_identity_behavioral_test.dart`, using the EXISTING live-account
  seam `test/supabase/supabase_test_helper.dart` (the pattern already used by other
  Supabase-touching contract tests, no new mock needed): rename keeps one row across
  push+restore; delete → restore removes the local row and its restored schedule days regardless
  of restore-path Future ordering (exercise both a parallel path, e.g. `restoreLightweightAlways`,
  and the sequential `_attemptSingleCallRestore` path); a race where the drain's tombstone-upsert
  runs BEFORE the creating push's upsert lands still ends deleted (the finding-2 case, exercised
  directly); stale device push of a deleted id is a no-op (name reused by a fresh row, not
  revived); unpushed local template survives restore; pending-delete skipped; migration rekeys
  legacy keys AND legacy-key/raw-UUID schedule refs, idempotent across repeated runs; **[rev7]**
  an offline device with pending template work still restores nutrition/weight/measurements
  normally (migrator gate is template-scoped, not global); `restoreWorkoutPlanForSyncDomain` and
  `restoreScheduledWorkoutsForSyncDomain` called standalone also drop ghost days for a deleted
  template; plan_json ghost day dropped using `_deletedTemplateCloudIds()`, not box-read-order.
  Each discriminating case run against the current (pre-fix) code first to confirm it reddens.
- `test/sql/workout_templates_delete_final_rename_live_verify.sql` (BEGIN/ROLLBACK): delete stamps
  the rename + `is_active=false`; a further UPDATE to that row (simulating a stale upsert) is a
  full no-op incl. name; a real `INSERT … ON CONFLICT (user_id,name) DO UPDATE` against the now-
  freed original name succeeds as a fresh row; run once with the trigger disabled to confirm the
  asserts discriminate.
- Repoint (never delete): `restore_keys_deterministic_test` (pin `templateKeyFor`, not
  `tmplName.hashCode`), `templates_unique_constraint_test` (constraint is UNCHANGED in rev 6 — this
  test should still pass as-is; re-verify rather than assume), plus the full rev-2 inventory list
  (`restore_ordering_and_sweep_test`, `restore_local_wins_additive_test`, `template_sync_gap_test`,
  `write_service_bypass_detector_test`, `template_exercises_upsert_test`,
  `sync_template_before_schedule_order_test`, `restore_single_call_bundle_validation_test`,
  `workout_templates_writer_to_reader_test`, `check_writeservice_only.dart:108-109`,
  `test/sql/onconflict_live_arbiter.sql:196,382`).
