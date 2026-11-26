# Target history: cloud backup (Nutrition History, Landing B)

Status: plan, revision 1 (2026-11-25). Parent: `docs/plans/nutrition-history.md` section 9.
Landing A (PR #346, main `25526bd3`) keeps the list only on the phone.

## 1. Goal

`userBox['target_history']` (which nutrition targets were in force from which day) survives a
reinstall and reaches a second device. Nothing else changes for the user: no new screen, no copy.

## 2. Ground truth (verified 2026-11-25 on main `25526bd3`)

- Writer: `lib/core/services/target_history_service.dart` `TargetHistoryService.reconcile`
  (the ONE writer of `userBox['target_history']`; list oldest first of
  `{from, calories, protein, carbs, fat, strategy, at_ms}`; cap 400; kill switch
  `configBox['disable_target_history']`). Pure step `reconciled(entries, today)`: a same-day entry
  is replaced; **when the replacement equals the entry before it, the same-day entry is REMOVED**;
  entries dated after today are dropped.
- Readers: `TargetHistoryService.read` / `targetFor` -> `nutritionHistoryProvider`.
- Profile push: `lib/core/services/sync/sync_profile.dart` `_syncUserProfile` (line 160): a
  WHITELISTED payload upserted into `user_profile`; callers `syncProfileNow` (line 29), the queue
  drain (`sync_service.dart:899`), the sweep (`sync_service.dart:1423`), the SyncDomain forwarder.
- Profile restore: `_restoreUserProfile` (line 773): `select()` with no column list (the
  single-call Edge Function reads `select("*")`, `restore-user-snapshot/restore_reads.ts:51`),
  then merges EVERY non-null cloud key into `userBox['profile']` and writes through
  `ProfileWriteService.updateProfile(merged, skipSync: true)`, whose `_afterPut` calls `reconcile`.
  Consequence: once the column exists, a client WITHOUT this landing copies the cloud list into
  the profile map as a key `target_history` (harmless, never pushed back: the payload is a
  whitelist; healed in 4.3).
- Precedents: migration 123 `merge_notification_preferences` (jsonb merge RPC, SECURITY INVOKER,
  both revokes), migration 177 `raise_coach_chat_cleared_at` + `pushCoachChatClearedAt`
  (`sync_profile.dart:1211`: owner checks, pushed-memory key, failure op type), local rehearsal
  `test/sql/coach_chat_cleared_at_local.sh` (throwaway `supabase/postgres:17.6.1.084` container).
- Class to avoid: a list written wholesale into a jsonb column lets a device with a SHORT list
  delete a longer cloud one (diagnose `e4a1b7`).
- Next migration number: 190 (`sh scripts/mint_migration.sh --next`, read 2026-11-25); it is
  reserved with `--stub` at build time.

## 3. One merge rule, used in three places

`merge(a, b)`: the union of both lists keyed by `from`; for the same `from` the entry with the
greater `at_ms` wins (a tie keeps `a`'s); sorted by `from`; the last 400 kept. There is NO delete
in the rule, so it is commutative up to ties and safe to apply in any order on any device.

Used by: the SQL function (stored = `a`, supplied = `b`), the Dart restore merge (local = `a`,
cloud = `b`), and nothing else (the test stub records calls; it does not re-implement the rule).

Because the rule cannot delete, the two local deletes of Landing A are changed or bounded:

- **U1 Same-day revert no longer removes the entry.** Today: targets A, changed to X at 10:00
  (entry `D:X`, pushed), changed back to A at 11:00 (entry removed locally). The cloud would keep
  `D:X` forever and a restore would bring it back, judging every day from D against X.
  Change in `reconciled`: the same-day entry is REPLACED by `D:A` with the newer `at_ms` even when
  it equals the entry before it. Readers are unaffected (`targetFor` returns equal numbers); the
  list may hold an entry equal to its predecessor. The no-same-day branch is unchanged (an equal
  target on a new day still writes nothing).
- **U2 Future-dated entries.** Dart: the restore merge drops entries with `from` after IST today
  (same rule `reconciled` already applies). SQL: entries with `from` after IST today + 1 day are
  not stored (one day of clock tolerance).

Stated limit: `at_ms` is a device clock. Two devices changing targets on the SAME IST day resolve
by clock, so a device whose clock runs ahead wins that day. Different days never conflict.

## 4. Changes

### 4.1 Migration 190 (additive, not destructive)

```sql
ALTER TABLE public.user_profile ADD COLUMN IF NOT EXISTS target_history jsonb NULL;

CREATE OR REPLACE FUNCTION public.merge_target_history(p_entries jsonb) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp
```

Body, in order:
1. `auth.uid() IS NULL` -> raise. `p_entries` null or not a jsonb array -> raise. More than 400
   elements -> raise. An empty array -> return.
2. `SELECT target_history INTO v_stored FROM user_profile WHERE user_id = auth.uid() FOR UPDATE`;
   no row -> return (the profile upsert that runs just before creates the row; the function never
   inserts a `user_profile` row, so no NOT NULL / default question arises). A stored value that
   is not an array counts as empty.
3. Candidates = stored elements then supplied elements, each kept only if it is an object whose
   `from` matches `^\d{4}-\d{2}-\d{2}$`, is a real date, is not after
   `(now() AT TIME ZONE 'Asia/Kolkata')::date + 1`, and whose `calories`, `protein`, `carbs`,
   `fat`, `at_ms` are jsonb numbers. A malformed element is SKIPPED, never an error (one bad entry
   must not block every later push).
4. Each kept element is rebuilt with exactly the seven keys (`strategy` = the text value cut to
   32 characters, `'balanced'` when absent or not a string), so the column cannot carry anything
   else.
5. Per `from`: greatest `at_ms`, a tie keeps the stored element. Ordered by `from`, last 400.
6. `UPDATE user_profile SET target_history = <result> WHERE user_id = auth.uid()`.

`REVOKE ALL ... FROM PUBLIC; REVOKE EXECUTE ... FROM anon; GRANT EXECUTE ... TO authenticated;`
column and function comments; four-tag header; inline rollback
(`DROP FUNCTION`, `ALTER TABLE ... DROP COLUMN`).

Not an integrity boundary: RLS lets a user UPDATE their own `user_profile` row directly, so the
validation binds the RPC only (self-harm only). Stated in the function comment.

No Edge Function changes and no deploy: `restore-user-snapshot` reads `select("*")`.

### 4.2 Client push (`sync_profile.dart`)

`Future<void> pushTargetHistory(String userId)`, modelled on `pushCoachChatClearedAt`:
- returns when `configBox['disable_target_history_cloud'] == true`, when
  `ownerChangedSince(userId)`, or when the local list is empty;
- memory `userBox['target_history_pushed']` = `SyncFingerprint.canonicalJson` of the list about
  to be sent: equal -> no request;
- `ensureFreshToken`, owner re-check, `rpc('merge_target_history', params: {'p_entries': list})`,
  owner re-check, then the memory is written;
- never throws; a failure is reported with op type `merge_target_history` (swept: the sweep
  re-runs `_syncUserProfile`), the memory is NOT written, the error text goes through
  `ErrorTelemetry.redactRowValues` via `_reportSyncFailure`.

Called as the last step of `_syncUserProfile` on every path where the profile upsert did not
throw (direct, reliability-queue success, queue drain), never before the upsert (step 2 of the
function needs the row). A failed or enqueued profile upsert skips it; the next profile sync or
sweep sends it.

Triggers that write the list without a profile sync (day rollover, post-restore heal, History
screen open; in practice a PRO flip or a birthday): the entry stays on the phone and reaches the
cloud with the next profile sync or sweep. A lag, never a loss. No new sync trigger is added.

### 4.3 Client restore (`_restoreUserProfile` + `TargetHistoryService`)

- Right after `cloud.remove('user_id')`: `final cloudHistory = cloud.remove('target_history');`
  ALWAYS (kill switch or not), and the merged map drops a stale `target_history` key an earlier
  client may have copied into `userBox['profile']`. The profile map never holds the list.
- When the cloud switch is not set and the owner is unchanged:
  `TargetHistoryService.adoptFromCloud(cloudHistory, now:)` BEFORE the profile write, so the
  `_afterPut` reconcile of that write sees the merged list (an unchanged target adds no entry).
  It also runs on the paths that return before the write (no change to the profile): it sits
  before the write-if-changed early return. `rows.isEmpty` -> nothing to adopt.
- `adoptFromCloud` (same file as `reconcile`; the file stays the only writer of the key):
  synchronous, never throws, same session / `disable_target_history` guards as `reconcile`;
  `parse` both sides, pure `mergedHistories(local, cloud, today)` (section 3 + U2), write only
  when the result differs from local. It does not touch `target_history_pushed`: a merged list
  that differs from what was last sent is pushed by the next profile sync (that is how a device
  uploads entries the cloud lacks).
- The existing post-restore `reconcile` (T3) is unchanged.

Stated limit carried over from Landing A: on a fresh install the profile write lands before PRO
state is known, so today's entry can record Balanced carbs / fat for a Keto user until the next
trigger the same day replaces it; that entry can now also reach the cloud for those minutes.
Calories and protein never depend on the strategy.

### 4.4 Flags

`configBox['disable_target_history_cloud']`: push and adopt off, the strip of 4.3 stays on.
Default ON behind this kill switch (the pattern of every recent sync landing). With the switch
set the client is byte-identical to Landing A except U1 and the strip. `disable_target_history`
(Landing A) still stops every local write.

## 5. Tests

- `test/sql/target_history_merge_local.sh` (local docker, migration applied VERBATIM, calls made
  as `authenticated` / `anon` with `request.jwt.claims`): anon refused; null / object / 401
  elements raise; empty array no-op; no row no-op and no row created; union by `from`; greater
  `at_ms` wins in BOTH directions (stored newer, supplied newer); tie keeps stored; malformed
  elements skipped while the valid ones land; extra keys dropped; long strategy cut; future
  entry dropped, tomorrow kept; cap keeps the newest 400; a stored non-array is treated as empty;
  another user's row is untouched; two concurrent sessions both land (row lock);
  `has_function_privilege` false for anon, true for authenticated; `prosecdef` false.
- `test/sync/target_history_cloud_sync_test.dart` (`SyncHarness`, stub RPC): push after the
  profile upsert carries the local list; no request when the memory matches; memory not written
  and op type reported on a 503; nothing sent under the switch, with an empty list, after an
  owner change; no push when the profile upsert failed; restore adopts BEFORE the profile write
  (the write's reconcile adds no duplicate); adopt on the unchanged-profile path; the profile map
  never holds `target_history` (cloud key and a pre-seeded stale key); switch on -> no adopt but
  still stripped; a merged list that differs from the memory is pushed on the next sync.
- Pure `mergedHistories` cases in `test/contracts/nutrition_target_history_writer_to_reader_test.dart`
  plus the U1 case (same-day revert keeps a newer entry), replacing the removal case.
- `sync_retry_controller_test.dart` forcing function: the new op type gets its swept decision.
- Mutation pass (rule 21): per clause of the merge rule (both comparison directions, tie side,
  cap side, future bound), each guard of push and adopt, the call order (adopt before write, push
  after upsert), the strip, the memory write. SQL mutants run through the local script.

## 6. Docs and records

SoT `nutrition_target_history` (cloud block, second writer `adoptFromCloud`, push, readers),
`lib/core/services/CLAUDE.md` row, `lib/features/nutrition/CLAUDE.md`, `docs/naming_conventions.md`
(`merge_target_history`, `target_history_pushed`, `disable_target_history_cloud`),
`backups/live_schema_columns.json` and `backups/applied_migrations.json` in the commit of the
apply, plan-review record, closure ledger, diagnose doc not required (feature, no bug).

## 7. Order and tier

Tier `platform` (`sync_profile.dart`): plan x2 review, gate loop, CI, B-pass.
1. Build + local rehearsal + tests on the branch; PR; CI green; B-pass.
2. **Founder go for the production apply of migration 190** (additive; per-action go, root
   CLAUDE.md 4.3). Nothing is applied before it.
3. Apply through MCP `apply_migration` on `dedsavbjuwgarrhphgnl`; verify live (`pg_get_functiondef`
   equals the file body, both privilege checks, column present); ledger + schema snapshot commit.
4. Land the PR (the client must not reach `main` before the function exists: a push would report
   a missing-function failure on every profile sync).

## 8. Risks

- A client without this landing copying the cloud list into its profile map between the apply
  and the merge: harmless, healed by the strip (4.3).
- The list grows by one redundant entry per same-day revert (U1): bounded by the 400 cap.
- Pre-launch: every account is a test account; no backfill, no existing-user path.

## 9. Revision 2: changes from review round 1 (this section wins over 3 to 8)

R1 **Order (finding 1).** A migration file cannot sit under `supabase/migrations/` before it is
applied (Gate 14 `check_migrations_applied.dart` and `check_migration_ledger_paired.dart` need a
ledger entry, and a ledger entry before the apply would claim an apply that has not happened).
So:
1. The SQL is written and reviewed as `test/sql/target_history_merge_draft.sql` (a path no
   migration gate reads). The rehearsal script takes its file from `F190`, defaulting to the
   draft. Client, tests, docs, PR, CI green and the B-pass all happen on that state; the B-pass
   reviews the SQL BEFORE the apply because an applied migration is immutable.
2. Founder go. `sh scripts/mint_migration.sh --stub` reserves 190; the draft body is moved
   byte-for-byte to `supabase/migrations/190_target_history.sql` (four-tag header added by the
   stub, body unchanged); applied through MCP; verified live.
   **Done 2026-11-26** (cloud version 20261126012225; the draft file is gone, the rehearsal
   script now defaults to the migration file; record: `backups/applied_migrations.json` 190).
3. ONE commit: the migration file, the ledger entry (hash from
   `dart run scripts/migration_ledger_hash.dart 190`), `backups/live_schema_columns.json`, the
   draft deleted, the script default repointed. Push, CI, then `land_pr`. The delta since the
   B-pass is a file move plus records; it is listed in the plan-review record as such.
The CI run before the apply is a real gate for the client (its tests use the stub server); the
live `Supabase Integration Tests` job references neither the column nor the function.

R2 **Second merge path (finding 2).** `AuthSessionBootstrapper` hydrates the profile through
`mergeCloudProfileWithTargets` (`lib/features/profile/services/profile_cloud_merge.dart:36`),
which also spreads every non-null cloud key. The strip moves into ONE pure helper
`stripCloudOnlyProfileKeys(map)` (removes `target_history`) called by both
`mergeCloudProfileWithTargets` and `_restoreUserProfile` on the merged map, so
`userBox['profile']` never holds the list on either path. Adoption stays in `_restoreUserProfile`
only (it runs on every sign-in through `restoreLightweightAlways`); the bootstrapper path only
strips. Test for the bootstrapper path added.

R3 **Push gating and the no-row case (finding 3).** Exit paths of `_syncUserProfile`:
(a) no local profile: no push. (b) reliability branch, `result.isOk`: push. (c) reliability
branch, `result.isErr` (reported, marker enqueued, returns normally): NO push. (d) legacy /
queue-drain path after the awaited upsert returned: push; a throw skips it. The function
`merge_target_history` RETURNS boolean: `true` only when a `user_profile` row was updated,
`false` when no row exists or the supplied array is empty. The client writes the pushed-memory
ONLY on `true`; `false` writes nothing and logs one `target_history_push_no_row` event.

R4 **Op type (finding 4).** `upsert_target_history` (armed by the `upsert_` prefix in
`isPushFailureOpType`, re-sent by the sweep through `_syncUserProfile`); added to the `armed`
list of the forcing-function test in `test/contracts/sync_retry_controller_test.dart`.

R5 **Owner (finding 5).** `adoptFromCloud(cloud, {required String ownerId, DateTime? now})`
returns unless the open Hive session belongs to `ownerId` (the comparison `HiveUserSession`
offers for a user id, as `ownerChangedSince` does), and `_restoreUserProfile` checks
`ownerChangedSince(userId)` immediately before the call. Test: an owner swap between the fetch
and the adopt writes nothing.

R6 **U1 touches two existing cases (finding 6).** In
`test/contracts/nutrition_target_history_writer_to_reader_test.dart`: the pure "changing back
removes the entry" case and the behavioural "changing back removes it" case both become "keeps
the day's entry with the reverted numbers and the newer `at_ms`".

R7 **Fresh install, PRO not yet known (finding 7): accepted limit, stated exactly.** The restore
profile write can replace today's cloud entry with Balanced carbs / fat for a Keto or Low carb
PRO user. It is pushed only if a profile sync runs before the post-restore heal
(`reckonAndNotifyAfterRestore`, which runs after the subscription refresh inside the restore and
re-records today with the newer `at_ms`); the restore write itself is `skipSync`. If that push
happens and no trigger runs again that day (heal, a profile edit, History opened), that ONE day
keeps Balanced carbs / fat targets in the macro-split view. Calories, protein, day statuses and
hit-rates are unaffected. No gate on a "restore settled" marker is added: that marker is not set
on a launch without a full restore, so gating the push on it could stop pushes for good.

R8 **Pushed-memory has a day bound (finding 8).** `target_history_pushed` =
`'<canonicalJson fingerprint>|<IST day>'`, as `pushCoachChatClearedAt` does: a cloud value lost
out of band (the bootstrapper deletes an empty `user_profile` row at
`auth_session_bootstrapper.dart:1079`) is re-sent within a day.

R9 **SQL validation, concrete (finding 9).** An element is kept only when: it is an object;
`from` is a string matching `^\d{4}-\d{2}-\d{2}$` AND `pg_input_is_valid(from, 'date')` (no
raise on `2026-02-31`; Postgres 16+, live is 17.6) AND not after IST today + 1;
`jsonb_typeof = 'number'` for the five numbers with `calories` in 1..20000, `protein`, `carbs`,
`fat` in 0..2000, `at_ms` in 0..4102444800000. The stored element holds the numbers rounded to
integers. The SQL is the stricter side (Dart `tryParse` only checks the length of `from`); Dart
never sends what SQL refuses because `reconcile` records only resolved, positive targets.

R10 **Flag rationale (finding 10).** Root CLAUDE.md 4.6 asks for a gate with the old path
reachable; 4.12.4's ship-dark tier (default OFF, one review round) is NOT used. This batch takes
the full tier (plan x2, B-pass) and ships default ON behind `disable_target_history_cloud`, as
the unit-preference sync did (`disable_unit_pref_sync`, migration 185). With the switch set the
old path (no push, no adopt) is what runs. Acceptance step: founder device check (change a
target, reinstall, History shows the earlier target for earlier days).

R11 **Ties converge (finding 12).** The rule is made fully commutative: for the same `from`,
order by `at_ms`, then `calories`, `protein`, `carbs`, `fat`, `strategy`, greatest wins. SQL and
Dart use the same order, so two sides holding different entries with an equal `at_ms` (the
`at_ms: 0` default of `tryParse`) converge on the same one. Clock limit, named: a device whose
clock is a day ahead can store a tomorrow-dated entry (SQL tolerance) whose `at_ms` also beats
the correct device's entry for that day.

R12 **Local wipes (finding 13).** The cloud list is never trimmed by a local wipe: sign-out,
`clearAllData` and the debug-only journey reset clear or keep the local list and the next
restore brings the cloud list back. Intended. Account deletion removes it with the
`user_profile` row (cascade).

R13 **Wording (finding 14).** "A lag, never a loss" becomes: an entry written by the rollover,
the heal or the History screen reaches the cloud at the next profile edit or the next launch
sweep (`checkAndSync` runs the sweep when 24 h have passed or one is owed). A device wiped
before either loses that entry only; the profile's CURRENT targets are still in the cloud, so a
restore records them from the restore day.

R14 **Tests added (finding 11).** Bootstrapper strip; reliability-branch Err -> no push; RPC
`false` -> memory unwritten; wrong-owner adopt; the R7 sequence (documents the limit and the
heal); memory re-sends on a new IST day. Local fixture: `user_profile` with RLS, the four own-row
policies and `trg_onboarding_required_fields` as live (read from `pg_policies` / `pg_trigger` on
2026-11-25). Named mutants: SQL and Dart tie order; future bound `<=` vs `<`; strategy cut 32;
which 400 are kept; owner re-check between RPC and memory; `ensureFreshToken` removed; push on
path (c); memory written on `false`.

R15 **Records (finding 15).** SoT entry carries
`behavioral_test_path: test/sync/target_history_cloud_sync_test.dart`; `docs/architecture/sync.md`
(restore) and `lib/features/profile/CLAUDE.md` (the strip in the cloud merge) join the docs
list; plan-review record at `platform` with `bpass: accepted`; closure ledger
`docs/audit/target-history-cloud.closure.yaml` (units: migration, push, restore adopt, strip,
U1, tie order).

## 10. Revision 3: changes from review round 2 (converged; this section wins)

V1 The SQL tie-break on `strategy` is `COLLATE "C"` (code-point order, what Dart's
`String.compareTo` gives for these ASCII tokens); a rehearsal case orders `low_carb` against
`lowcarb`.
V2 `pushTargetHistory(userId, {bool fromSignOut = false})` copies the precedent's catch branch:
a failure after an owner change or during sign-out logs `target_history_push_failed` (text
through `redactRowValues`) and returns without `_reportSyncFailure` (which would arm the retry
for the NEXT user); the memory is not written after the RPC when `fromSignOut` or the owner
changed.
V3 Sign-out: one best-effort `pushTargetHistory(uid, fromSignOut: true)` beside the coach
marker push in `auth_provider.dart` (before `clearAllData`), so entries written by the rollover,
the heal or the History screen are not lost to a sign-out. An uninstall before the next profile
sync still loses them (R13).
V4 Structure of `_syncUserProfile`: the reliability branch's `isOk` path must reach the push
before its `return`; the legacy / drain path pushes after the awaited upsert. The push never
throws, so it cannot fail a queue drain. Callers: `syncProfileNow`, the drain
(`sync_service.dart:899`), the sweep (`sync_service.dart:1423`), `pushUserProfileForSyncDomain`.
V5 U1 wording: the header and the `reconciled` doc comment of `target_history_service.dart`,
the rows in `lib/core/services/CLAUDE.md` and `lib/features/nutrition/CLAUDE.md`, and the SoT
entry all say "replaced" (grep `removed when` before the edit).
V6 The onboarding upsert in `user_repository.dart` (a spread of `profileData`) also removes
`target_history`, beside its existing `coach_extraction_locked_fields` removal.
V7 The pushed-memory holds a short hash of the canonical JSON plus the IST day, not the ~45 KB
text.
V8 Stated limits added: an entry for a `from` already trimmed by the 400 cap can reappear from
a device that still holds it (only beyond-cap entries); the bootstrapper's delete of an empty
`user_profile` row (neither side has data) is the one other way the cloud list goes away.
V9 The ledger entry of the apply commit copies the shape of entry 189 (hash, MCP version, pre-
and post-apply verification, rollback).
