---
reviewed_at: 2026-09-27T00:00:00+05:30
staged_against: 034d8100..c9e60838
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 7
verdict: accepted
---

# Code Review — template-stable-identity (OI-252)

Reviewed post-commit (nothing staged; branch `template-stable-identity`, 2 commits since
merge-base `034d8100`, HEAD `c9e60838`). Read `docs/agent_brief_preamble.md` and
`.claude/skills/code-review/SKILL.md` §§1,2,4,6 first per the dispatch brief. Independently
re-derived every claim below against the live worktree — nothing here is taken from the
diagnose-doc or plan-review record's own prose without a direct check.

## Finding 1 — P1 — guard_without_its_mirror (migration 145 trigger, LIVE/IMMUTABLE)

- **file:line:** `supabase/migrations/145_workout_templates_stable_delete.sql:56-93` (function
  `workout_templates_delete_final_rename`, `before update` trigger only) + the writer that can
  defeat it: `lib/core/services/sync/sync_workout.dart:1313-1319` (`_drainPendingTemplateDeletes`'s
  tombstone UPSERT).
- **claim:** The trigger's rename-on-delete logic (`new.name := old.name || ' ‹del:...›'`,
  `new.is_active := false`) is declared `before update` ONLY. The migration's own header comment
  (lines 22-26) explicitly describes the race it is designed to survive: "whichever of {creating
  push, deleting drain} reaches Postgres first via an INSERT wins the row's existence." If the
  **deleting drain** is the side that performs the INSERT (i.e. the template was created and
  deleted in the same offline session, so no separate "creating push" for that id ever runs —
  confirmed: `WorkoutWriteService.deleteTemplate` at `workout_write_service.dart:1249`
  unconditionally does `await box.delete(templateId)`, so a template that never synced before
  deletion leaves nothing else to push), then `_drainPendingTemplateDeletes`'s own UPSERT payload
  (`'name': name` — the ORIGINAL, un-suffixed name, `'deleted_at': ...`, `'is_active': false`) is
  what actually creates the cloud row, via a plain INSERT. **The `before update` trigger never
  fires on an INSERT**, so the row is created directly with `deleted_at` set but the name NOT
  renamed. The `UNIQUE(user_id, name)` constraint — which this migration's own header explains was
  deliberately KEPT (not dropped, per round-1 plan review) specifically so "a genuine re-create...
  succeed[s] as a plain insert" — is never freed for that name. A later, legitimate re-create of a
  template under the identical name (a very ordinary user action — delete "Leg Day", make a new
  "Leg Day") then hits a live `23505 duplicate key value violates unique constraint` on
  `(user_id, name)`, because the tombstoned row still silently occupies that name. This is exactly
  the "42P10 forever" failure class the migration's own comment cites as the reason rev 5 (drop
  the constraint) was rejected — reopened here through the one path the header text didn't cover.
  Does **not** reopen the resurrection bug this unit exists to fix (restore still filters purely
  on `deleted_at`, which IS set correctly on both the INSERT and UPDATE paths) — this is a
  distinct, newly-introduced regression in the rename/name-freeing guarantee, not a resurrection.
- **verification:**
  ```sql
  -- Reproduces the gap directly against the live trigger (read-only until the final INSERT,
  -- wrap in BEGIN/ROLLBACK before running against prod per CLAUDE.md's migration-comment rule):
  BEGIN;
  INSERT INTO workout_templates (id, user_id, name, workout_type, source, is_active, deleted_at)
    VALUES (gen_random_uuid(), '<real-user-id>', 'Leg Day Repro', 'custom', 'user', false, now());
  SELECT name, is_active FROM workout_templates WHERE name = 'Leg Day Repro';
  -- expect: name is STILL 'Leg Day Repro' (not renamed), is_active=false -- the trigger never ran.
  INSERT INTO workout_templates (id, user_id, name, workout_type, source, is_active)
    VALUES (gen_random_uuid(), '<real-user-id>', 'Leg Day Repro', 'custom', 'user', true);
  -- expect: ERROR 23505 duplicate key value violates unique constraint "workout_templates_user_id_name_key" (or equivalent)
  ROLLBACK;
  ```
  Client-side: `grep -n "'name': name," lib/core/services/sync/sync_workout.dart` at the drain's
  UPSERT (line 1316) shows the un-suffixed `name` is what's sent — there is no suffix applied
  client-side either, so neither side of the write path frees the name on the INSERT-wins branch.
- **suggested-fix:** Migration 145 is live and immutable (CLAUDE.md's migrations rule) — this
  cannot be patched in place. A follow-up migration is needed that either (a) extends the trigger
  to `before insert or update` and applies the same rename/deactivate transform whenever
  `new.deleted_at is not null` regardless of `TG_OP`, or (b) makes `_drainPendingTemplateDeletes`'s
  own UPSERT payload apply the identical `' ‹del:<id prefix>›'` suffix client-side so the row is
  correctly named however it lands (defense in depth: do both, since an unmigrated legacy client
  or a future direct-INSERT caller would still bypass a client-only fix). Add a regression test
  that inserts a tombstone via a bare `INSERT ... ON CONFLICT (id) DO UPDATE` (the same shape
  PostgREST's `upsert(..., onConflict:'id')` emits) against a row that does not yet exist, and
  asserts the resulting name is suffixed.
- **status:** accepted, fixed and applied — migration 146 (option (a): extends the trigger to
  `before insert or update`; option (b)'s client-side duplication was considered and rejected as
  unnecessary once (a) covers every writer unconditionally) applied live 2026-09-27T10:22:49+05:30
  after founder granted explicit permission (two earlier attempts were denied by the Claude Code
  auto-mode classifier: "Production Deploy", then "Protected-Scope IaC Apply" — not retried a
  third time or worked around, per CLAUDE.md §4.3). Post-apply live verification:
  `pg_trigger.tgtype=23` confirms BEFORE INSERT OR UPDATE; a functional repro run live inside
  BEGIN/ROLLBACK reproduced the exact pre-fix failure shape and confirmed it now succeeds (a
  tombstone-shaped INSERT came back suffixed + is_active=false; a second INSERT under the
  original name then succeeded with no 23505), rolled back with 0 leftover rows confirmed. Full
  detail: diagnose-doc's "B-pass remediation" section, `backups/applied_migrations.json` entry
  for migration 146.

## Finding 2 — P1 — guard_without_its_mirror / plan-vs-implementation drift (legacy-key migrator never reached by the most common restore path)

- **file:line:** `lib/core/services/template_identity_migrator.dart:17-21` (class doc, and the
  ONLY real call site: `lib/core/services/sync/sync_workout.dart:1338`, inside
  `_syncWorkoutTemplates`) vs. `lib/core/services/sync_service.dart:1539-1568`
  (`restoreLightweightAlways`, which calls `_restoreWorkoutTemplates(userId)` at line 1547 and
  never calls `_syncWorkoutTemplates` or the migrator anywhere in that method).
- **claim:** `TemplateIdentityMigrator`'s own class doc says: "Called from
  `_syncWorkoutTemplates` / `_restoreWorkoutTemplates` themselves." The converged plan-review
  record (`docs/plan-reviews/template-stable-identity.md`, Round 2→3) makes the same claim about
  the AGREED design: "the migrator now gates only `_restoreWorkoutTemplates`/
  `_syncWorkoutTemplates` themselves (early-return offline)." **Neither is true of the code as
  drafted.** `grep -rn "runIfNeeded" lib/` shows exactly one call site for
  `TemplateIdentityMigrator.runIfNeeded` in the whole tree:
  `sync_workout.dart:1338`, inside `_syncWorkoutTemplates`. `_restoreWorkoutTemplates`
  (`sync_workout.dart:1561-1669`, read in full) never calls it.
  `restoreLightweightAlways` — which fires on **every normal sign-in once Hive already has local
  data** (`sync_service.dart:1523` `else { await restoreLightweightAlways(userId); }`, the common
  case for a returning user) — calls `_restoreWorkoutTemplates(userId)` directly and does **not**
  call `_syncWorkoutTemplates` anywhere in its body, so on this path the migrator never runs this
  session. `_syncWorkoutTemplates` only runs from `weeklyFullSync` ("Triggered on app launch if
  >1 day since last full sync" — `sync_service.dart:1346`), which is NOT guaranteed to coincide
  with a given sign-in. **Impact:** a device holding a pre-existing legacy-keyed template
  (`tmpl_<ms>` or `tmpl_<namehash>`, from before this rework shipped) that signs in normally gets
  the cloud-authoritative copy written under a NEW key (`tmpl_<cloud-uuid>`, since
  `_restoreWorkoutTemplates` keys purely off the cloud row's `id`) while the OLD legacy-keyed row
  is left untouched — `TemplatesNotifier.build` (the canonical UI reader, per
  `docs/sot_registry.yaml`'s `workout_templates` reader list) filters by `type == 'template'`, not
  key prefix, so **both rows render as separate templates in the Train tab** until
  `weeklyFullSync` happens to fire (potentially days later for an active user). This is exactly
  the "ambiguous identity between devices" symptom class OI-252 exists to close, reopened on the
  single most common restore path.
- **verification:**
  ```bash
  grep -rn "runIfNeeded" lib/core/services/sync/sync_workout.dart   # only 1 hit, inside _syncWorkoutTemplates
  sed -n '1561,1669p' lib/core/services/sync/sync_workout.dart | grep -c "TemplateIdentityMigrator"   # 0
  sed -n '1539,1568p' lib/core/services/sync_service.dart | grep -c "_syncWorkoutTemplates\|TemplateIdentityMigrator"   # 0
  ```
- **suggested-fix:** Either call `TemplateIdentityMigrator.runIfNeeded(userId)` from
  `_restoreWorkoutTemplates` too (matching what the class doc and the plan-review record both
  already claim is the design), or — if the round-2 "never gate `_restoreIfNeeded` as a whole"
  concern extends to this call site too — call it from `restoreLightweightAlways` right before the
  `workout_templates` entry in its `Future.wait` list, scoped to that one Future exactly as
  `_syncWorkoutTemplates` already does it. Add a behavioral test that seeds a legacy `tmpl_<ms>`
  row, drives `restoreLightweightAlways` alone (no `weeklyFullSync`), and asserts only one
  `type=='template'` row survives.
- **status:** accepted — added the identical gate to `_restoreWorkoutTemplates` itself (covers
  all of its callers, including `restoreLightweightAlways`, in one place, rather than only the
  one call site). Full legacy-key-seeded behavioral coverage was not feasible (no Supabase-mock
  seam exists anywhere in this repo, and the migrator's legacy-key-resolve branch always makes a
  live query once any legacy key is found); instead added
  `test/sync/oi252_template_restore_migrator_wiring_test.dart` (2 tests) using a test-only
  invocation counter (`TemplateIdentityMigrator.invocationCountForTest`, incremented as the
  first statement of `runIfNeeded`) to prove the gate is reached, plus a functional
  pass-through test proving the gate doesn't wrongly block the common (no-legacy-keys) case.
  Mutation-proven: removing the added gate call reddened exactly the invocation-count test
  (1 of 2), left the pass-through test green — matches the intended coverage split exactly.

## Finding 3 — P2 — asserted_fixture_value (OI board: wrong migration number on 3 unrelated citations)

- **file:line:** `docs/audit/open_issues.md:6014` (OI-247) and `docs/audit/open_issues.md:3632`
  (the R2-11 `alert_cron_function_dead` entry, same hunk) + `docs/audit/OPEN_INDEX.md:145`
  (OI-247's index row).
- **claim:** All three now read "migration 145" for the `db_maintenance_nightly` VACUUM-split fix
  (diagnose `d6b2f9`, `ops-alerting-batch-b`) — but that fix is migration **144**
  (`144_split_vacuum_out_of_db_maintenance_nightly.sql`), not 145. Migration 145 is THIS batch's
  own `145_workout_templates_stable_delete.sql`, entirely unrelated to VACUUM/cron. Confirmed
  against the authoritative source: `backups/applied_migrations.json` has two separate, correctly
  distinguished entries — `"migration": "144"` / `slug: split_vacuum_out_of_db_maintenance_nightly`
  applied `20260926065733`, and `"migration": "145"` / `slug: workout_templates_stable_delete`
  applied `20260927011446` — and the migration filenames on disk match that exactly
  (`ls supabase/migrations/ | grep -E '^14[45]'` → `144_split_vacuum...sql`,
  `145_workout_templates...sql`). `git diff 034d8100 HEAD -- docs/audit/open_issues.md` shows the
  ONLY change to these two entries is `144`→`145` in the "Verified" line — nothing else about
  either entry changed, consistent with an inadvertent global find/replace of "144"→"145" run
  while stamping this batch's own new migration number into the OI-252 entry, that also swept two
  unrelated pre-existing citations.
- **verification:**
  ```bash
  grep -n "migration 14[45]" docs/audit/open_issues.md docs/audit/OPEN_INDEX.md
  cat backups/applied_migrations.json | grep -A2 '"migration": "14[45]"'
  ls supabase/migrations/ | grep -E '^14[45]_'
  ```
- **suggested-fix:** Revert the 3 stray "145" back to "144" in the OI-247 and R2-11 entries
  (`open_issues.md:3632,6014`, `OPEN_INDEX.md`'s OI-247 row) — these describe migration 144, and
  the wrong number will mislead anyone auditing OI-247 later into reading the wrong migration
  file. Re-run `dart run scripts/build_oi_index.dart` after, since `OPEN_INDEX.md` is generated.
- **status:** accepted — reverted both stray "145"→"144" citations in `open_issues.md` (OI-247
  line, R2-11 line); this batch's own OI-252 entry (correctly "145") left untouched; regenerated
  `OPEN_INDEX.md`.

## Finding 4 — P2 — asserted_fixture_value (diagnose-doc self-contradicts on migration's live status)

- **file:line:**
  `docs/diagnoses/2026-09-27-deleted-workout-template-resurrects-via-restore-f4a8c2.md:94-98`
  (frontmatter `impact_analysis`) and `:102` (`touched_layers_checked` tier 3) vs. `:112-113`
  (prose `## Summary` at the bottom of the SAME file).
- **claim:** The structured frontmatter states migration 145 "was applied to the live database
  2026-09-27" and tier 3's evidence gives a precise timestamp
  (`2026-09-27T06:44:46+05:30`, `cloud_version 20260927011446`) plus a live `pg_trigger` /
  `information_schema.columns` verification. The prose Summary at the very end of the identical
  file instead says: "a rename-on-delete tombstone (migration 145, **not yet live**)". These
  directly contradict each other about the single most operationally important fact in the
  document (whether a live-prod schema change actually happened) — one of them is stale.
  `backups/applied_migrations.json`'s own entry (confirmed above) agrees with the frontmatter,
  which means the prose Summary is the stale one — but a reader of the doc has no way to know that
  without cross-checking a THIRD file, which is exactly the failure mode
  `docs/diagnoses/2026-09-27-...` itself exists to prevent for other readers.
- **verification:** `grep -n "not yet live" docs/diagnoses/2026-09-27-deleted-workout-template-resurrects-via-restore-f4a8c2.md`
- **suggested-fix:** Fix the Summary's last sentence to say "migration 145 (applied live
  2026-09-27)" to match the frontmatter and `backups/applied_migrations.json`.
- **status:** accepted — Summary's last sentence corrected to "applied live 2026-09-27",
  matching the frontmatter.

## Finding 5 — P3 — writer_reader_drift (SoT registry line_range wrong for one of two named methods)

- **file:line:** `docs/sot_registry.yaml` — the `workout_templates` concept's reader entry for
  `_restoreScheduledWorkouts / _restoreWorkoutPlan` (added/edited in this diff, per
  `git diff 034d8100 HEAD -- docs/sot_registry.yaml`), citing a single `line_range: 1990-2320`.
- **claim:** That range correctly bounds `_restoreScheduledWorkouts` (actual body
  `sync_workout.dart:2000-2296`, confirmed by reading it in full) but is **wrong** for
  `_restoreWorkoutPlan`, whose actual declaration and body are at
  `sync_workout.dart:1177` through `:1274` (confirmed: `grep -n "Future<void> _restoreWorkoutPlan"
  lib/core/services/sync/sync_workout.dart` → `1177:`, and the method's closing catch block ends
  at line 1274, ~800 lines before the cited range even starts). `check_sot_registry_parity.dart`
  (per `lib/CLAUDE.md`) validates that a `line_range` is in-bounds of the FILE and that some named
  symbol exists somewhere in it — it does not check that every method named in a combined
  `method:` string actually falls inside the cited range, so this passes the gate silently.
- **verification:**
  ```bash
  grep -n "Future<void> _restoreWorkoutPlan" lib/core/services/sync/sync_workout.dart   # 1177
  grep -n "Future<void> _restoreScheduledWorkouts" lib/core/services/sync/sync_workout.dart   # 2000
  ```
- **suggested-fix:** Split into two separate reader entries with their own accurate
  `line_range`s (`_restoreWorkoutPlan` ~1177-1274, `_restoreScheduledWorkouts` ~2000-2296), or at
  minimum widen the shared range to cover both (not recommended — it would then span ~1150 lines
  and stop meaning anything as a citation).
- **status:** accepted — split into two separate `docs/sot_registry.yaml` entries with accurate
  own `line_range`s, re-verified via `check_sot_registry_parity.dart` (PASS, 0 errors).

## Finding 6 — P3 — writer_reader_drift (diagnose-doc citation points at the wrong function)

- **file:line:**
  `docs/diagnoses/2026-09-27-deleted-workout-template-resurrects-via-restore-f4a8c2.md:44`
  (`readers:` entry for `PlanIntegrityReconciler.reconcile`, cited `line: 64`) vs.
  `lib/core/services/plan_integrity_reconciler.dart:64` (actual content) and `:345` (actual call
  site inside `reconcile`).
- **claim:** Line 64 of `plan_integrity_reconciler.dart` is the top-level, standalone
  `bool isGhostScheduleEntry(` function declaration (confirmed by reading it) — a shared helper,
  not part of the `PlanIntegrityReconciler` class (declared separately at line 74) and not inside
  `reconcile` at all. The `reconcile` method's actual call to the ghost-day filter is at line 345
  (confirmed: `grep -n "isGhostScheduleEntry" lib/core/services/plan_integrity_reconciler.dart` →
  hits at both 64 and 345). The diagnose-doc's structured `readers:` citation for this concept
  therefore points a reader at the wrong function.
- **verification:** `sed -n '60,66p;340,348p' lib/core/services/plan_integrity_reconciler.dart`
- **suggested-fix:** Change the cited `line:` for the `PlanIntegrityReconciler.reconcile` reader
  entry from 64 to 345 (or a small range around it, e.g. 320-350, to survive minor future shifts).
- **status:** accepted — diagnose-doc's `readers:` citation for `PlanIntegrityReconciler.reconcile`
  changed from `line: 64` to `line: 345`, re-validated via `validate_diagnose_doc.dart` (OK).

## Finding 7 — P2 — asserted_fixture_value (the "filed as its own OI" claim for the logout gap is unverified/false)

- **file:line:** `lib/core/services/pending_template_deletes.dart:12-15` (class doc) and
  `docs/diagnoses/2026-09-27-deleted-workout-template-resurrects-via-restore-f4a8c2.md:58`
  (`cross_account_guard` field).
- **claim:** Both say the known limit ("a queued [template] delete does NOT survive logout —
  `userBox` is cleared on sign-out, so an undrained delete is lost on that device") is "filed as
  its own OI" / "tracked separately on the OI board." **No such OI entry exists.** Searched the
  entire board (`docs/audit/open_issues.md`, 159 `## OI-` sections) for `PendingTemplateDeletes`,
  "survive logout", "cross-session delete queue", any phrasing of this gap — zero hits. The gap
  IS genuinely disclosed (in the class doc comment, and in the diagnose-doc's field) so this is
  not a silently-unmentioned limitation per the review brief's framing — but the specific,
  checkable claim "filed as its own OI" is false as written, which matters because the next person
  who greps the OI board for this class of gap (exactly the workflow `docs/audit/OPEN_INDEX.md`'s
  own header prescribes — "read the index FIRST") will find nothing and may wrongly conclude no
  one has looked at it, rather than that it's a known, accepted, intentionally-scoped-out limit.
- **verification:**
  ```bash
  grep -c "^## OI-" docs/audit/open_issues.md   # 159 total entries
  grep -in "PendingTemplateDeletes\|survive logout\|cross-session delete queue" docs/audit/open_issues.md   # 0 hits
  ```
- **suggested-fix:** Either file the OI now (cheap — one `mint_oi.sh` call, matching what both
  comments already claim happened) or correct both comments to say the limit is documented here
  and in the diagnose-doc only, not on the OI board.
- **status:** accepted — filed OI-253 via `sh scripts/mint_oi.sh`, wrote a full board entry
  (`docs/audit/open_issues.md`), regenerated `OPEN_INDEX.md`, and updated both citing comments
  (`pending_template_deletes.dart` class doc, diagnose-doc `cross_account_guard`) from "filed as
  its own OI" / "tracked separately on the OI board" to "tracked as OI-253".

## Lenses checked clean (with method)

- **function_exception_swallow:** `git diff 034d8100 HEAD | grep -n "functions.invoke("` → 0
  hits. This diff touches no client-side `.functions.invoke(` call sites at all (it changes two
  Edge Functions' server-side logic and the client's Hive/Supabase-table sync/restore code, not
  any AI-proxy-style client invocation) — lens not applicable to this diff.
- **secrets_in_tree:** `git diff 034d8100 HEAD | grep -nE "sk-|rzp_live_|AKIA|-----BEGIN|service_role|SUPABASE_SERVICE_ROLE"`
  → the one hit is unrelated prose inside `docs/diagnoses/INDEX.md` (an existing index line about
  a different, older bug) containing neither a real secret nor new content from this diff. No
  credential-shaped literal anywhere in the added/changed lines.
- **unawaited_no_error_sink:** every new `unawaited(` in the diff (`git diff | grep -n "^\+.*unawaited("`,
  9 hits) wraps either `ErrorTelemetry.recordNonFatal(...)` / `ErrorTelemetry.logEvent(...)`
  directly (inline error sink) or `SyncService.instance.syncWorkoutData()` /
  `.pushSnapshot()` — the standing coalesced fire-and-forget sync entries used identically
  throughout this file and documented as the established pattern in
  `lib/core/services/CLAUDE.md` (each has its own internal try/catch + telemetry). No bare
  unguarded `unawaited(` introduced.
- **blast_radius_mismatch:** independently re-derived (not trusted from the brief) via
  `DART_BIN=$(sh -c '. scripts/_dart_bin.sh && resolve_dart_bin'); "$DART_BIN" run
  scripts/blast_radius_from_diff.dart - < <(git diff --name-only 034d8100 HEAD)` → prints
  `Blast-radius: platform`, matching the self-declared tier in both the plan-review record and
  this review's own frontmatter. Also confirmed migration 145's trigger function is declared
  `security invoker` (not `security definer`), so the classifier's SECURITY DEFINER content-rule
  that forces `catastrophic` correctly does not fire — `platform` is the right tier, not an
  under-classification.
- **missing_input:** `docs/plan-reviews/template-stable-identity.md` and
  `docs/superpowers/plans/2026-09-26-template-stable-identity.md`, both cited repeatedly from the
  diagnose-doc and the class docs, are present in this diff's own file list (confirmed via
  `git diff --name-only`) — not phantom references. Both Edge Functions type-check clean:
  `deno check --node-modules-dir=none supabase/functions/workout-window-closing/index.ts` and
  the same for `restore-user-snapshot/index.ts` (Deno 2.9.6 at
  `%LOCALAPPDATA%/Microsoft/WinGet/Links/deno.exe`) — zero output, zero errors, on both. The
  8-test Deno suite (`workout-window-closing/index_test.ts`, includes the new
  `deleted_template_filter.ts` tests) was run directly:
  `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/workout-window-closing/`
  → **8 passed | 0 failed**, matching the diagnose-doc's claim exactly.
- **asserted_fixture_value — mutation-proof re-verification (required by the dispatch brief):**
  re-ran mutation (1) of the diagnose-doc's `mutation_proven` claim myself, live, against the
  real test file (not just re-reading the prose). Backed up
  `lib/core/services/sync/sync_workout.dart` first, confirmed baseline
  `flutter test test/sync/oi252_deleted_template_restore_behavioral_test.dart` → **10/10 green**,
  then applied the exact claimed mutation (`if (tmpl['deleted_at'] != null)` →
  `if (false && tmpl['deleted_at'] != null)` at line 2150) and re-ran: result was **exactly 2
  failed / 8 passed** (`_restoreScheduledWorkouts — deleted-template embed (OI-252) deleted-embed
  row is never written...` and `...cleans an existing local reference (today)` both reddened,
  every other test stayed green) — matching the diagnose-doc's claim precisely (8/10 stayed
  green). Restored the file from the pre-mutation backup and confirmed `git status --porcelain`
  and `git diff --stat` on the file are both empty before finishing. Mutations (2) and (3) were
  not independently re-run (time-boxed to one, per the brief's "at least one") but mutation (1)'s
  exact match to the claimed count is a real, positive signal for the other two, not just an
  assumption.

## Founder triage notes
<filled in by founder during triage>
