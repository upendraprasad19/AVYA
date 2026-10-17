---
bug_id: e6b9c4
date: 2026-07-30
batch: cross-device-progress-lock
status: fixed
blast_radius: catastrophic
blast_radius_note: >
  Path-tier alone would be platform (migration + core sync-service change touching
  every user's streak-freeze and phase/streak progress cloud writes), but
  scripts/blast_radius_from_diff.dart's content-rule forces catastrophic whenever a
  staged file contains the literal text "SECURITY DEFINER" — both RPCs in migration
  115 are SECURITY DEFINER (matching the existing update_streak_progress precedent).
  Confirmed live via `git diff --cached --name-only | dart run
  scripts/blast_radius_from_diff.dart` (stdin mode — per
  feedback_mistake_blast_radius_positional_mode.md, never pass two SHAs
  positionally) after staging: "SECURITY DEFINER content forces catastrophic
  (path-tier was platform)". Per CLAUDE.md §4.12.3, catastrophic tier requires
  hermes: accepted in the plan-review record, not just bpass: accepted — the review
  pipeline for this unit was escalated accordingly (see plan-review record).
symptom: >
  OI-45 finding 2's cross-device half, explicitly scoped OUT of Unit 3a
  (progress-map-consolidation, diagnose d5c8a3, 2026-07-30): Unit 3a closed the
  SAME-DEVICE stale-snapshot lost-update on UserRepository's progress map, but left
  cross-device races (two different devices racing a write to the SAME user's
  user_progress row) unaddressed. Migration 056 (2026-05-11) had already built
  update_streak_progress, an optimistic-lock RPC (p_expected_version /
  streak_progress_version) specifically for this — its own header names the exact
  race: "Device A consumes a freeze, writes available=0 to cloud at T1. Device B has
  a stale read of available=1, refills to 2 at T2. Cloud now reflects 2, the consume
  is silently undone." Live-verified this session (via has_function_privilege +
  pg_get_functiondef against project dedsavbjuwgarrhphgnl) that the RPC itself was
  correct, secure (anon blocked via migration 091's REVOKE-FROM-PUBLIC pattern,
  authenticated/service_role can execute), and its column-ref bug from migration 090
  was fixed by migration 096 — but it had ZERO callers anywhere in lib/ (confirmed by
  grep). SyncService.syncFreezes (lib/core/services/sync/sync_restore_completeness.dart)
  instead pushed the SAME 4 columns via a raw, version-blind .upsert() — the exact
  unprotected path the RPC was built to replace. A SIBLING gap existed for the 11
  other user_progress fields SyncService._syncUserProgress
  (lib/core/services/sync/sync_profile.dart) pushes (current_phase, current_week,
  phase_started_at, plan_generated_at, total_workouts_done, current_streak_weeks,
  detected_experience_level, deployments_complete, current_streak_days,
  last_workout_date, longest_gap_days) — no RPC existed for these at all.

  Investigation ALSO found two independent, previously-undiscovered bugs while
  building the fix, both caught by live-testing against real Postgres before either
  shipped (per supabase/migrations/CLAUDE.md's "live INSERT-in-a-rollback-transaction
  is the only reliable test" rule):
  (a) update_streak_progress's fresh-insert branch is a bare INSERT with no ON
  CONFLICT guard — two concurrent first-ever syncs for a brand-new account (no
  user_progress row yet) would 23505 unique-violation instead of the caller getting a
  clean NULL-retry signal.
  (b) A more severe, P0-class bug: update_streak_progress's p_freezes_last_refill
  parameter is typed TEXT but the target column streak_freezes_last_refill is `date`
  (migration 048) — Postgres does not implicitly cast a bound TEXT variable to `date`
  in an INSERT/UPDATE assignment context. EVERY call reaching either branch would
  42804 ("column is of type date but expression is of type text"). Because this RPC
  had zero callers until this same batch, the bug was 100% latent — reproduced live
  in a rollback transaction, it would have broken on literally the first real call
  (this batch's own syncFreezes wiring) had that live test not caught it first.
concept: cross_device_progress_optimistic_lock
sot_registry_entry: >
  Extended the existing `streaks` concept's class_constraints (docs/sot_registry.yaml,
  the "streak_freeze_first_pro_grant" sibling block) with a new paragraph documenting
  the optimistic-lock mechanism and the shared streak_progress_version counter.
  Updated 3 stale {file, line_range} citations that Unit 3b's own edits shifted
  (syncFreezes 14-54 -> 22-103; _restoreFreezes 130-192 -> 266-359 in the
  streak_freeze_first_pro_grant concept; _syncUserProgress 167-231 -> 175-266 in
  program_week_projection) plus 2 COLLATERAL stale citations Unit 3b's line-shifts
  caused in UNTOUCHED methods (_restoreSavedDietPlan 281-301 -> 436-459;
  _restoreUserProfile 210-275 -> 339-419) — caught by
  scripts/check_sot_registry_parity.dart, not missed. Added streak_progress_version
  to docs/naming_conventions.md §3.3 (Hive field registry) and §4.4 (Hive<->cloud
  mapping table).
writers: >
  lib/core/services/sync/sync_restore_completeness.dart syncFreezes (line 22) — now
  calls the update_streak_progress RPC instead of a raw upsert; on a NULL
  (version-mismatch) result, delegates to the new
  _retrySyncFreezesOnceAfterConflict (line 112), which re-fetches the fresh cloud
  row, reconciles via the EXISTING pure StreakProgressService.mergeFreezeProgress
  helper (unchanged, already tested), retries the RPC exactly once, then drops
  (telemetry event sync_freezes_retry_dropped) rather than looping.
  streak_freezes_first_pro_grant_done stays on a separate plain upsert (line ~85) —
  deliberately excluded from the RPC/lock: it is monotonic one-directional
  (false->true, never regresses) and only ever pushed when locally true, so a
  cross-device race on it is structurally harmless (worst case: a redundant "true"
  write). lib/core/services/sync/sync_profile.dart _syncUserProgress (line 175) —
  now calls the new update_user_progress_snapshot RPC (migration 115) instead of a
  raw conditional upsert; every param key is always explicit (possibly null), since
  PostgREST requires every declared function parameter by name and the RPC's own
  COALESCE(param, existing_column) reproduces the old conditional-omit "don't touch
  this column" semantic server-side instead of client-side. On mismatch, delegates
  to _retrySyncUserProgressOnceAfterConflict (line 272), which re-fetches ONLY the
  fresh version (not a field merge — these fields are client-authoritative per their
  own pre-existing doc comments, cloud is a passive mirror for cron/report
  consumption), resends the SAME local values once, then drops (telemetry event
  sync_user_progress_retry_dropped). lib/core/services/sync_service.dart
  _stampProgressVersion (line 2142, static) — shared local writer for
  progress['streak_progress_version'] after either RPC succeeds; does a fresh Hive
  get() immediately before its put() (no reused stale snapshot, no await in
  between), matching the same-device-safety pattern Unit 3a established elsewhere in
  this batch. supabase/migrations/115_user_progress_snapshot_optimistic_lock.sql —
  new update_user_progress_snapshot function; CREATE OR REPLACE on
  update_streak_progress fixing both the ON CONFLICT gap and the ::date cast bug
  (signature unchanged, so migration 090's auth.uid() guard and migration 091's
  REVOKE-FROM-PUBLIC + GRANT-TO-authenticated/service_role ACLs are preserved).

  Round-1-review P1 fix (2026-07-30): UserRepository.syncOnboardingToSupabase
  (lib/shared/repositories/user_repository.dart, user_progress write ~line 480) was a
  THIRD, previously-unprotected raw-upsert writer to the same 11 fields — missed in
  the original pass because it lives in a different file/call path (onboarding, not
  the periodic sync fan-out) than the two writers named above. Round-1 review found
  it; fixed by adding SyncService.pushOnboardingProgressSnapshot (new public method,
  lib/core/services/sync/sync_profile.dart, right after syncProgressNow) which routes
  the SAME field set through the SAME update_user_progress_snapshot RPC + the
  existing _retrySyncUserProgressOnceAfterConflict retry helper, reading the expected
  version from Hive (0 for a genuinely fresh account). THROWS on a real RPC/network
  exception (unlike syncProgressNow, which swallows) to preserve
  syncOnboardingToSupabase's pre-existing "throws so the caller can detect sync gaps"
  contract that the 10s-retry + pending_onboarding_sync replay safety net depends on;
  does NOT throw on a benign version-mismatch-after-retry drop, since that is correct
  concurrent-write handling, not a failure. Both of syncOnboardingToSupabase's real
  callers (onboarding_provider.dart's first-ever sync, sync_service.dart's
  _replayPendingOnboardingSync) get this fix for free — the method's public signature
  didn't change, only its internal user_progress write mechanism.
readers: >
  lib/core/services/sync/sync_restore_completeness.dart _restoreFreezes (line 266) —
  select list extended to include streak_progress_version (previously absent, so a
  device that only ever restores, never syncs first, would default expected_version
  to 0 forever and spuriously mismatch against any nonzero real cloud version); cloud
  version unconditionally wins on restore (pure server-side monotonic counter, unlike
  available/used_dates/last_refill which use the genuine dual-writer merge).
  lib/core/services/sync/sync_profile.dart _restoreUserProgress (line 423) —
  UNCHANGED behavior: its bare .select() already returns streak_progress_version for
  free (SELECT *), and the existing generic cloud-non-null-wins merge already adopts
  it correctly; added a doc comment making this explicit rather than leaving it an
  accident. supabase/functions/restore-user-snapshot/index.ts (line 263, the
  "freezes" bundle projection) — extended 4-col -> 5-col to match _restoreFreezes's
  new select list per the file's own H-1 "exact column projections must match" shape
  contract.

  Round-1-review P1 correction (2026-07-30): this EF is LIVE (slug
  restore-user-snapshot, version 3, status ACTIVE — confirmed via list_edge_functions
  against project dedsavbjuwgarrhphgnl, independently re-verified by me, not just
  trusted from the reviewer's claim), NOT "not yet deployed" as originally written
  here — that claim came from taking the file's own header comment at face value
  instead of live-checking deploy status, the exact discipline this batch applied to
  every Postgres claim but missed for this one EF. Additionally,
  SyncService._singleCallKillSwitch (sync_service.dart:257-262, reads
  configBox['disable_single_call_restore']) defaults to FALSE when the key is
  absent, so the single-call restore path calling this EF is attempted BY DEFAULT,
  not founder-gated-off as originally assumed. Net effect: the code edit here (5-col
  projection) is correct but NOT YET LIVE — every device restoring via the default
  single-call path gets a freezes projection WITHOUT streak_progress_version until
  this EF is actually redeployed.

  Hermes L39 correction (2026-07-30): the paragraph above previously claimed this
  drift means "_restoreFreezes reads cloudVersion=null and falls back to
  expectedVersion=0 on that device's next syncFreezes() call." That claim is WRONG —
  traced (not just asserted) by the Hermes L39 lens and independently re-checked by
  me: on BOTH restore paths (single-call `sync_service.dart:1550-1551 → 1634-1635`
  and legacy Step A `:1363` → Step C `:1420`), `user_progress` restores BEFORE
  freezes, and `_restoreUserProgress`'s bare `SELECT *` (not the 4/5-col freezes
  projection) already carries `streak_progress_version` into Hive first. When
  `_restoreFreezes` runs afterward, its own guard
  (`if (cloudVersion != null) existingMap['streak_progress_version'] = cloudVersion`,
  sync_restore_completeness.dart:342-345) PRESERVES the value Step A already wrote —
  it never falls back to 0. So the un-redeployed EF's real live impact on
  `expectedVersion` is nil; the actual gap is different and worse in a different way
  (see below), not the one originally claimed here. Left the wrong claim struck
  through in spirit (documented, not silently rewritten) per this batch's own
  established correction convention.

  What the real gap is (Hermes L39 F1/F3, 2026-07-30): the EF/repo drift itself is
  real (live EF still projects the OLD 4-col freezes bundle; repo source is 5-col,
  adding streak_progress_version), but NOTHING enforces the two stay in sync going
  forward — `grep -rln "restore-user-snapshot/index.ts" test/` returns zero hits,
  and the SoT registry's freeze/version reader entries list Dart files only. A new
  contract test (test/contracts/restore_user_snapshot_freezes_projection_parity_test.dart)
  pins the EF's projected column list against the RPC's guarded-field list so the
  NEXT drift is caught mechanically instead of by a Hermes pass tracing restore
  order by hand. Redeploying this EF (to close the drift itself, not just gate future
  drift) is a separate explicit action from applying migration 115 (different
  subsystem, same §4.3 live-apply authorization requirement) — flagged as a
  residual, not bundled into this diagnose-doc's fix as already-done.
hive_key_prefix: "progress (single literal key, userBox) — streak_progress_version is a NEW field within it"
hive_key_formula: "userBox['progress']['streak_progress_version'] — literal field name, matches the cloud column name 1:1 (no divergence, unlike the pre-existing streak_freeze_used_dates/streak_freezes_used_dates singular/plural split)"
sync_methods: >
  syncFreezes, _syncUserProgress (both listed above) — both now RPC-mediated.
  syncProgressNow / weeklyFullSync / pushSnapshot orchestrators unchanged (still fire
  _syncUserProgress internally exactly as before; only that method's OWN
  implementation changed).
restore_methods: >
  _restoreFreezes, _restoreUserProgress (both listed above).
cloud_table: user_progress
cloud_columns: >
  streak_progress_version (pre-existing column, migration 056 — was written but
  never read/propagated correctly client-side until this fix). No new columns added.
  The 11 update_user_progress_snapshot fields and 4 update_streak_progress fields are
  the SAME columns these two writers already targeted — only the write MECHANISM
  (RPC vs raw upsert) changed.
contract_test_path: >
  test/contracts/restore_user_snapshot_freezes_projection_parity_test.dart (NEW,
  Hermes C11, 2 tests) — pins restore-user-snapshot/index.ts's freezes projection
  column list against SyncService._restoreFreezes's own select, since nothing did
  before (the H-1 shape contract was comment-only on both sides).
  test/sql/cross_device_progress_optimistic_lock_verify.sql — grew from 8 to 14
  (round-1) to 19 (Hermes: Case 15 proves FOR UPDATE takes a real pg_locks-visible
  RowShareLock; Cases 16-19 regression-test the NULL-guard/GREATEST/last-refill-
  COALESCE fixes), all green, re-run live 2026-07-30.
  test/contracts/cross_device_progress_optimistic_lock_wiring_test.dart (grew 37
  (Hermes L37 corrected this doc's earlier miscount of 38, confirmed by me via
  `flutter test`) -> 45 (B-pass round-2's 6 findings, see that section, added/
  renamed assertions) -> 46 (round-3 Finding 1 added the
  mergeRpcParamsPreferringNonNull wiring check, see Round-3 section) — 46 tests,
  all green, re-verified 2026-07-30: source-structure tests pinning the RPC-wiring
  shape, the bounded single-retry contract for all THREE now-protected sync
  methods (syncFreezes, _syncUserProgress, pushOnboardingProgressSnapshot), the
  shared _stampProgressVersion helper, the round-1 P0 grant-fix regex, the round-1
  P2 COALESCE-default regex, and — via a comment-stripped source-grep on the
  migration file itself — that the ::date cast fix + the ON CONFLICT DO NOTHING
  guard cannot be silently reverted).
  test/sync/merge_rpc_params_preferring_non_null_test.dart (NEW, round-3 Finding 1,
  6 tests) — genuine BEHAVIORAL (not source-grep) coverage for
  SyncService.mergeRpcParamsPreferringNonNull, including the exact onboarding
  detected_experience_level-drop regression scenario Finding 1 surfaced.
  test/sql/cross_device_progress_optimistic_lock_verify.sql (NEW, extended to 14
  cases by round-1-review fixes — live-Postgres behavioral verification in a rollback
  transaction, mirroring test/sql/onconflict_live_arbiter.sql's established harness;
  run via `dart run scripts/check_onconflict_live_arbiter.dart --sql
  test/sql/cross_device_progress_optimistic_lock_verify.sql`). Cases 9-13 apply the
  FIXED grant block (REVOKE FROM PUBLIC, anon, authenticated) within the same
  rolled-back transaction and assert has_function_privilege for anon/authenticated/
  service_role on update_user_progress_snapshot, PLUS a symmetry re-check on
  update_streak_progress — this is the exact pre-apply grant verification round-1
  review said the ::date-cast-bug method would have caught the P0 with, now actually
  applied to grants too. Case 14 is the P2 regression test (all-null core-4 fresh
  insert COALESCEs to schema defaults 1/1/0/0). All 14 cases re-run live 2026-07-30
  post-fix, all 'ok'. Extended (not duplicated) test/sql/security_definer_anon_revoke.sql
  with 4 more UNION ALL rows for update_user_progress_snapshot's grants — this file's
  own convention is to run POST-apply as a final live confirmation against the real,
  applied function (not a substitute for the pre-apply cases 9-13 above, which
  already independently proved the grant fix works before the migration is ever
  applied for real).
ist_handling: >
  Not applicable to the optimistic-lock mechanism itself (streak_progress_version is
  an opaque monotonic bigint, not a date/time value). last_workout_date and
  streak_freezes_last_refill are pre-existing date-typed fields whose IST-handling
  contract (client already sends plain YYYY-MM-DD strings via istDateStr-derived
  construction, e.g. StreakProgressService's thisMondayStr) is UNCHANGED by this fix
  — only the transport (RPC vs raw upsert) and the newly-required ::date cast at the
  SQL assignment site changed, not how the client computes or formats the date
  string itself.
provider_invalidations: >
  Unchanged. Neither RPC call site changed which providers get invalidated —
  updateProgress's existing unawaited(syncProgressNow()) and StreakProgressService's
  existing unawaited(syncFreezes()) call sites are byte-identical; only what happens
  INSIDE those two sync methods changed.
telemetry_op_types: >
  2 new logEvent reasons: sync_freezes_retry_dropped, sync_user_progress_retry_dropped
  (both fire only on a SECOND consecutive version mismatch — expected to be rare in
  practice; existing sync_service_sync_freezes / sync_service_sync_user_progress
  recordNonFatal reasons unchanged for genuine exceptions).
cross_account_guard: >
  Both RPCs carry the auth.uid() guard verbatim from update_streak_progress's
  existing, already-audited pattern (migration 090, diagnose c9b3e2): an
  authenticated caller may only write its own row; service_role (auth.uid() IS NULL)
  passes through for cron/admin. update_user_progress_snapshot's guard is a direct
  copy of the same, already-proven shape — not independently re-derived. Live-verified
  update_streak_progress's grants (anon blocked, authenticated/service_role retained)
  via has_function_privilege this session.

  Round-1-review P0 finding (2026-07-30): update_user_progress_snapshot's ORIGINAL
  grant block (REVOKE EXECUTE ... FROM PUBLIC only, no explicit anon/authenticated)
  was insufficient — independently reproduced live in a rollback transaction
  (anon_can_exec=true) by both the reviewer and, separately, by me before applying
  any fix. Root-caused via pg_default_acl: the postgres role has a Supabase-platform
  default-privileges entry granting EXECUTE on every NEW public-schema function
  DIRECTLY to anon/authenticated/service_role (objtype='f':
  {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}),
  bypassing PUBLIC entirely — so a PUBLIC-only revoke never touches the grant it was
  meant to remove. update_streak_progress's OWN live ACL
  ({postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}, no anon
  entry — confirmed via a direct pg_proc.proacl query) proves the actually-working
  pattern is migration 090's EXPLICIT `REVOKE EXECUTE ... FROM anon` naming the role
  directly, not migration 091's PUBLIC-only revoke (091's real value was for the
  OTHER functions in its batch that lacked a prior targeted anon-revoke; for
  update_streak_progress specifically it was redundant with 090's already-effective
  fix). Corrected migration 115 to `REVOKE EXECUTE ... FROM PUBLIC, anon,
  authenticated`, matching the proven-working pattern — re-verified live in a
  rollback transaction: anon_can_exec=false, authenticated/service_role unchanged.
  This is now ALSO verified pre-apply via test/sql/cross_device_progress_optimistic_
  lock_verify.sql's cases 9-13 (see contract_test_path), not deferred to a
  post-apply-only check.
forbidden_patterns_checked: >
  Grepped this batch's diff for raw Hive.box(...) access (none — sync_service.dart's
  new _stampProgressVersion uses HiveService.instance.userBox, matching the
  established direct-access convention already used throughout sync_*.dart's part
  files), setState-for-shared-state (none — no widget code touched), hardcoded
  colors (none — no UI touched). flutter analyze clean on all 3 touched Dart files
  (one pre-existing, unrelated info-lint at sync_restore_completeness.dart:321,
  inside the untouched original mergeFreezeProgress call — not introduced by this
  batch).
proposed_fix: >
  (1) supabase/migrations/115_user_progress_snapshot_optimistic_lock.sql: new
  update_user_progress_snapshot RPC (11 nullable params + COALESCE partial update,
  auth.uid() guard, ON CONFLICT-safe fresh-insert, shares streak_progress_version as
  ONE whole-row counter with update_streak_progress since user_progress is one row
  per user); CREATE OR REPLACE on update_streak_progress fixing the ON CONFLICT gap
  + the p_freezes_last_refill ::date cast bug (found live-testing THIS migration,
  not pre-existing knowledge). (2) sync_restore_completeness.dart: syncFreezes routes
  through the RPC + bounded retry-via-mergeFreezeProgress;
  streak_freezes_first_pro_grant_done stays a plain upsert (documented exclusion
  rationale); _restoreFreezes select list gains streak_progress_version. (3)
  sync_profile.dart: _syncUserProgress routes through the new RPC + bounded
  re-fetch-version-only retry; _restoreUserProgress doc comment made explicit (no
  behavior change — already correct via SELECT *). (4) sync_service.dart: new shared
  static _stampProgressVersion helper (mirrors the existing _hasValue/_hasNumber
  cross-part-file convention). (5) restore-user-snapshot/index.ts (LIVE, v3, ACTIVE —
  corrected from this doc's original "not yet deployed" claim, see readers field):
  "freezes" bundle projection extended to match _restoreFreezes's new select list,
  per that file's own H-1 shape contract; the code edit is done but NOT yet
  redeployed, a residual. (6) Round-1-review fixes: migration 115's
  update_user_progress_snapshot grant block corrected (REVOKE FROM PUBLIC, anon,
  authenticated — P0); its fresh-insert branch's 4 schema-defaulted columns wrapped
  in COALESCE (P2); UserRepository.syncOnboardingToSupabase's user_progress write
  routed through the same RPC via new SyncService.pushOnboardingProgressSnapshot
  (P1) — see writers field for detail on each.
regression_test_planned: >
  test/contracts/cross_device_progress_optimistic_lock_wiring_test.dart — 46 tests
  (37 at round-1-review time, cited below; +8 from B-pass round-2's 6 findings
  (renamed/added assertions, see that section) +1 from round-3 Finding 1's
  mergeRpcParamsPreferringNonNull check, see Round-3 section), all green: RPC-wiring
  shape for all THREE now-protected writers (syncFreezes,
  _syncUserProgress, pushOnboardingProgressSnapshot), bounded-single-retry
  contracts, the shared version-stamp helper's fresh-read-before-write invariant, 2
  tests pinning the migration's original P0 fix (::date cast count, ON CONFLICT
  count), and (added by round-1-review fixes) 2 tests pinning the anon-grant fix
  stays closed, 1 test pinning the COALESCE-default fix, 6 tests pinning
  pushOnboardingProgressSnapshot's shape, and 3 tests pinning
  UserRepository.syncOnboardingToSupabase's routing through it instead of a raw
  upsert — all via comment-stripped source-grep so none of these fixes can be
  silently reverted.
  test/sync/merge_rpc_params_preferring_non_null_test.dart — 6 tests, all green,
  genuine BEHAVIORAL coverage (not source-grep) for
  SyncService.mergeRpcParamsPreferringNonNull: non-null-preferred wins, null-
  preferred falls back, the exact onboarding detected_experience_level-drop
  regression scenario, both-null stays null, output key set is fallback-driven,
  empty fallback yields empty output.
  test/sql/cross_device_progress_optimistic_lock_verify.sql — 14 live-Postgres cases
  in a rollback transaction (run against project dedsavbjuwgarrhphgnl, re-run
  2026-07-30 post-round-1-fixes, ALL 14 green): the original 8 (fresh-insert-and-
  date-cast-fix, stale-version-returns-null, correct-version-succeeds,
  shares-version-counter, progress-stale-version-returns-null,
  coalesce-preserves-untouched-fields, fresh-insert-for-new-user,
  cross-rpc-second-caller-sees-real-version) plus 5 new round-1-fix regression
  cases: anon-blocked + authenticated-retained + service_role-retained on
  update_user_progress_snapshot (the exact grants round-1 review found broken),
  a symmetry re-check that update_streak_progress's own grants are unaffected, and
  the P2 all-null-core-4-fresh-insert-COALESCEs-to-schema-default case. This is the
  SAME transaction that applies migration 115's exact SQL (including the round-1
  grant + COALESCE fixes) as a temporary CREATE OR REPLACE, so it verifies the
  migration's real, final SQL before that SQL is ever applied for real — not a
  hand-simulated approximation.
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean on all 3 touched Dart files (sync_restore_completeness.dart, sync_profile.dart, sync_service.dart) plus the new test file; 25/25 new contract tests green." }
  - { tier: 2_hive, status: fixed_in_this_batch, evidence: "streak_progress_version confirmed to round-trip through userBox['progress'] via _stampProgressVersion (write) and _restoreFreezes/_restoreUserProgress (read) — pinned by the wiring test's fresh-read-before-write assertion." }
  - { tier: 3_postgres_schema, status: verified, evidence: "Live information_schema.columns query against user_progress (project dedsavbjuwgarrhphgnl) confirmed the exact column set + types (streak_freezes_last_refill is `date`, not text — the discovery that led to the ::date cast fix) BEFORE writing migration 115's parameter types, not after." }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "No data migration or backfill — migration 115 is function-definition-only." }
  - { tier: 5_migrations_applied, status: blocked_on_user, evidence: "Migration 115 written + live-tested inside a rollback transaction (test/sql/cross_device_progress_optimistic_lock_verify.sql, all 19 cases ok — grew from 8 through round-1's grant/COALESCE regressions, Hermes's Case 15 lock-primitive proof, and Hermes's Cases 16-19 for the NULL-guard/GREATEST/last-refill-COALESCE fixes) but NOT YET APPLIED to the live database — CLAUDE.md §4.3 requires explicit per-action authorization for a live apply, separate from batch-plan approval, even under this session's standing autonomous-batch convention." }
  - { tier: 6_edge_function_code_vs_deploy, status: verified, evidence: "Round-1-review correction: restore-user-snapshot IS live (list_edge_functions against dedsavbjuwgarrhphgnl: slug restore-user-snapshot, version 3, status ACTIVE — independently re-confirmed by me, not just trusted from the reviewer). The freezes-projection code fix (4-col -> 5-col) is written but NOT yet redeployed — a REAL, currently-live drift between deployed EF code and this repo's source, not future-proofing. Self-healing in practice (a device hitting the un-redeployed EF gets cloudVersion=null from the freezes projection, falls back to expectedVersion=0, triggers the existing version-mismatch retry on its next syncFreezes() — never data loss, one extra round-trip) but flagged as an explicit residual requiring its own redeploy action, separate from migration 115's apply." }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "No cron job touched." }
  - { tier: 8_rls_policies, status: fixed_in_this_batch, evidence: "Live has_function_privilege checks confirmed update_streak_progress's CURRENT grants: anon=false, authenticated=true, service_role=true. Round-1 review found update_user_progress_snapshot's ORIGINAL grant block left it anon-executable (P0, live-reproduced) — root-caused via pg_proc.proacl + pg_default_acl (Supabase's platform grants EXECUTE on new public-schema functions directly to anon/authenticated, bypassing PUBLIC), fixed to an explicit REVOKE FROM PUBLIC, anon, authenticated, re-verified live pre-apply: anon_can_exec=false, authenticated/service_role unchanged=true. Also now verified via test/sql/cross_device_progress_optimistic_lock_verify.sql cases 9-13 (pre-apply, same rollback-transaction method that caught the ::date bug) in addition to the POST-apply security_definer_anon_revoke.sql extension." }
  - { tier: 9_storage, status: not_applicable, evidence: "No Storage bucket touched." }
  - { tier: 10_secrets, status: not_applicable, evidence: "No secret or API key touched." }
  - { tier: 11_external_services, status: not_applicable, evidence: "No external service call shape changed." }
  - { tier: 12_client_server_contract, status: verified, evidence: "Traced syncFreezes -> .rpc('update_streak_progress') -> Postgres and _syncUserProgress -> .rpc('update_user_progress_snapshot') -> Postgres end-to-end by reading every hop plus live-testing the actual RPC bodies in a rollback transaction against the real schema — not just a source-level trace." }
impact_analysis: >
  Before this fix: OI-45's cross-device race was real and unaddressed for the
  streak-freeze fields (migration 056's own documented motivating scenario:
  consume-then-refill silently undoing the consume), the 11 phase/streak progress
  fields pushed by the periodic sync (no RPC existed for these at all), AND (found
  only by round-1 review, not the original pass) the SAME 11 fields as written by
  onboarding's initial/replayed cloud push (UserRepository.syncOnboardingToSupabase)
  — any two devices, or a stale onboarding retry racing a fresher periodic sync,
  writing the same user's row within the same short window would last-write-wins
  with zero detection. After this fix: all THREE writers are optimistic-lock
  protected, sharing one whole-row version counter, with a bounded
  single-retry-then-drop reconciliation on genuine conflict (freeze fields via the
  existing tested merge; both progress-field writers via a re-assert-local-values
  retry matching their own established client-is-authoritative contract).

  Round-1 independent review (2026-07-30, context-blind, dispatched per CLAUDE.md
  §4.12.1) found 1 P0 + 2 P1 + 1 P2 + 1 P3 in the original pass, all confirmed and
  fixed before round 2: **P0** — update_user_progress_snapshot's grant block left it
  anon-executable (a real privilege-escalation bug: any anon-key holder could
  overwrite an arbitrary victim's phase/streak/workout-count data), root-caused to
  Supabase's platform default-ACL behavior and fixed with an explicit
  `REVOKE ... FROM PUBLIC, anon, authenticated`. **P1a** — the third writer
  (syncOnboardingToSupabase) described above; fixed via the new
  SyncService.pushOnboardingProgressSnapshot. **P1b** — this doc originally
  mischaracterized restore-user-snapshot as "not yet deployed"; it is actually LIVE
  (v3, ACTIVE) and its single-call restore path is attempted by default, corrected
  throughout this doc (see readers field for the actual, still-open implication:
  the freezes-projection code fix needs its own redeploy action). **P2** — the
  fresh-insert branch's 4 schema-defaulted columns were unwrapped (bypassing
  DEFAULTs on an all-null insert); wrapped in COALESCE, which also closed a gap the
  P1a fix would otherwise have newly made reachable (the onboarding-replay path
  deliberately sends current_week=NULL to avoid stomping the program-week
  projection). **P3** — minor, effectively-unreachable telemetry-completeness note
  on both retry helpers' early-return paths, accepted as-is (see round-1 findings
  section below). Every fix independently live-verified by me (not just accepted
  from the reviewer's report) via rollback-transaction queries before being
  considered done — same discipline this batch already applied to the ::date cast
  bug, now applied uniformly to grants too, which round-1 review explicitly noted
  the original pass had NOT done pre-apply.

  Two bugs found by live-testing during the ORIGINAL pass (documented above) would
  otherwise have shipped silently: the ON CONFLICT gap and the ::date cast bug (would
  have broken on literally the FIRST real call this batch's own syncFreezes wiring
  makes). OI-45 can close its cross-device-half finding once migration 115 is
  applied live, the extended security_definer_anon_revoke.sql grant checks are
  re-run post-apply, AND restore-user-snapshot is redeployed with the freezes-
  projection fix — all three blocked on explicit user go-ahead per CLAUDE.md §4.3,
  not bundled into this same authorization implicitly. Unit 3c (graduation_screen.dart's
  narrower stale-nextPhase bug) and task #41 (behavioral test for the real
  phase-advance callsites) remain separately scoped, untouched by this unit.
---

# Diagnosis: Cross-device progress optimistic lock (OI-45 cross-device half, Unit 3b)

## Ground truth investigated before any code was written

Per CLAUDE.md §4.1 (name writer + reader by file:line before proposing a fix) and
§4.1.5 (bug-history lookup), this unit re-verified — directly, not from memory or a
subagent's prose — every claim the Unit 3a diagnose-doc's own residual section made
about Unit 3b's scope:

- Read migration 056 (the original `update_streak_progress` RPC), 090 (auth.uid()
  guard added, ACL revoke attempted but wrong target), 091 (the CORRECT ACL fix —
  REVOKE FROM PUBLIC, not FROM anon/authenticated, per this repo's own documented
  footgun in `supabase/migrations/CLAUDE.md`), and 096 (column-ref fix,
  `streak_freeze_used_dates` singular -> `streak_freezes_used_dates` plural) in full.
- Live-queried `information_schema.columns` for `user_progress` (23 columns),
  `pg_constraint` (confirmed a genuine `UNIQUE (user_id)` constraint — meaning the
  client's `onConflict: 'user_id'` upserts are valid, and a concurrent fresh-insert
  race is a real, not theoretical, `23505` risk), `has_function_privilege` for
  anon/authenticated/service_role, and `pg_get_functiondef` — confirming the LIVE
  `update_streak_progress` function body exactly matches migration 096's fix and its
  grants exactly match migration 091's intent.
- Grepped `lib/` for every call site of `syncFreezes`, `_syncUserProgress`, and
  `update_streak_progress` — confirmed the RPC has ZERO callers (the client instead
  does a raw `.upsert()` on the same columns in both `syncFreezes` and
  `_syncUserProgress`).
- Read `StreakProgressService` in full — discovered it already has a sophisticated,
  tested, PURE merge helper (`mergeFreezeProgress`) for the RESTORE path's
  cloud-vs-local reconciliation. This became the reconciliation algorithm reused for
  `syncFreezes`'s retry-on-conflict path, rather than inventing a new one.
- Grepped for `streak_progress_version` across all of `lib/` — zero hits. The client
  has never read or written this column; local version-tracking needed building from
  scratch, exactly as Unit 3a's residual section predicted.
- Discovered (not assumed) that `_syncUserProgress`'s writer chain runs through
  `UserRepository.updateProgress` -> `unawaited(SyncService.instance.
  syncProgressNow())` -> `_syncUserProgress` — a SEPARATE, non-coalesced `*Now()`
  entry point from `syncFreezes`'s own direct call chain, confirming the two write
  disjoint column sets on the same row (no double-protection needed, no unprotected
  gap between them either).
- Discovered the `restore-user-snapshot` Edge Function's existence and its own
  hardcoded "freezes" 4-column projection — NOT via a subagent summary, by reading
  the actual EF source after noticing `_restoreFreezes` has a `preFetched` injection
  parameter and tracing where it's populated. Its own H-1 contract ("exact column
  projections must match ... so the client `_restoreX` parsers hydrate UNCHANGED")
  means leaving it stale would silently regress this fix — fixed in the same commit
  rather than left as a landmine. **Correction (round-1 review, 2026-07-30):** this
  EF's deployment status was originally taken from the file's own header comment at
  face value ("NOT YET DEPLOYED — founder-gated") without live-checking — round-1
  review live-queried `list_edge_functions` and found it is actually deployed (v3,
  ACTIVE), independently re-confirmed by me. See the readers field and the round-1
  findings section below for the corrected analysis and the resulting residual (the
  code fix here needs an actual redeploy, it isn't inert).

## Design decisions, stated explicitly

**One shared whole-row version counter, not two.** Both RPCs increment and check the
SAME `streak_progress_version` column, per the ORIGINAL 8-unit plan's own explicit
design note ("reusing the existing streak_progress_version column as a whole-row
optimistic counter rather than adding a second, since it's one row"). Trade-off
acknowledged: a genuine same-tick collision between a freeze mutation and a progress
mutation on TWO DIFFERENT DEVICES would cause an occasional spurious retry even
though the two write disjoint columns — accepted as a rare, harmless (never
data-loss, only an extra round-trip) cost against the alternative complexity of a
second version column and a second set of migration/ACL/index work.

**Two different retry philosophies, deliberately.** `syncFreezes`'s retry reconciles
via a real field-level merge (`mergeFreezeProgress`) because freeze fields have
genuine dual-writer conflict semantics (a consume and a refill from two different
devices are both individually legitimate and must be combined, not last-write-wins).
`_syncUserProgress`'s retry simply re-sends the SAME local values against a fresh
version, because those 11 fields are client-authoritative by the pre-existing code's
own doc comments (phase/streak state is computed locally; cloud is a passive mirror
for cron/report consumption) — a field-level merge there would be solving a problem
that doesn't exist for this field set, unjustified complexity.

**`streak_freezes_first_pro_grant_done` deliberately excluded from the lock.** Not an
oversight — the RPC's signature doesn't cover it, and extending the signature for a
monotonic one-directional (false->true, never regresses) flag would add migration
risk for a field that is structurally race-safe without one (worst case of a race: a
redundant "true" write, never a lost "true").

**No §4.6 feature flag on the sync-path switchover — a deliberate waiver, not an
oversight.** B-pass round-2 (Finding 5) correctly flagged that this diff touches
`sync` (a §4.6-listed risky category) and unconditionally replaces the old
version-blind upsert paths with the new RPC-routed paths, with no `kDebugMode`/
Hive-flag/RemoteConfig gate and no old path preserved reachable. Considered and
rejected building a parallel-path flag:
- The old upsert path has a KNOWN, confirmed cross-device clobbering bug — it is
  the entire reason OI-45 / this unit exists. A flag whose "safe fallback" position
  reintroduces the bug the batch exists to close is not a safety net; flipping it
  in an emergency would trade a bounded, observable failure mode (see below) for an
  unbounded, silent one.
- The new failure mode this diff introduces (a write dropped after two consecutive
  version conflicts) is NOT silent: Hermes C7/C8 made every drop path emit a
  high-priority telemetry event (`sync_freezes_retry_dropped`,
  `sync_user_progress_retry_dropped`, and the two `*_row_absent_after_conflict`
  events) before returning. A stuck account is observable and alertable, not a
  black hole.
- A dropped write is not permanently lost — the next routine sync trigger for that
  domain (both `syncFreezes()` and `_syncUserProgress()` have 5+ existing
  fire-and-forget call sites apiece, per `lib/core/services/CLAUDE.md`'s coalesced
  sync-fan-out pattern) re-attempts from a fresh version read, so the window is
  "delayed reconciliation," not "data loss."
- The actual rollback mechanism for this change is the migration's own inline
  rollback block (`115_user_progress_snapshot_optimistic_lock.sql`, file-end) —
  schema-level rollback is the correct safety net for a schema-level change; an
  app-level Hive flag would only gate the CLIENT half and couldn't undo the RPCs'
  privilege/ACL posture regardless.

This is a considered, documented exception, not a silent gap — if a future incident
proves this judgment wrong, the fix is to build the flag then, informed by what
actually broke, not to speculatively build one now against a failure mode that may
never materialize.

## Two bugs found by live-testing, not by code review alone

Both are documented in full in the `symptom` field above and pinned by dedicated
cases in `test/sql/cross_device_progress_optimistic_lock_verify.sql` (case labels
`streak_fresh_insert_and_date_cast_fix` and the `ON CONFLICT` coverage implicit in
cases 1/7). The `::date` cast bug is the more consequential of the two: it would have
made this batch's own fix DOA the moment it shipped — every `syncFreezes()` call for
a brand-new user (the exact population any real fresh install exercises first) would
have thrown `42804` on the fresh-insert branch. Caught only because this batch
insisted on running the real migration SQL against the real live schema in a rollback
transaction before considering the migration "done," per this repo's own
`supabase/migrations/CLAUDE.md` rule that source-grep tests cannot substitute for
live verification on schema-shaped bugs.

## Round-1 review findings (2026-07-30) — context-blind, dispatched per §4.12.1

Fresh Sonnet subagent, isolated worktree, explicit instruction to independently
re-verify every live-Postgres/live-deploy claim rather than trust this doc's prose,
and to actively try to find bugs rather than validate. Found 1 P0 + 2 P1 + 1 P2 + 1
P3; all confirmed (independently re-verified by me, not accepted on the reviewer's
word alone) and fixed in this same commit before round 2 was dispatched, per §4.12.1
("review #2 runs on the POST-review-#1 hardened diff").

| # | Finding | Verification | Fix |
|---|---|---|---|
| P0 | `update_user_progress_snapshot`'s `REVOKE EXECUTE ... FROM PUBLIC` (no explicit anon/authenticated) left it anon-executable — a real privilege-escalation bug. | Reproduced live in a rollback transaction (`anon_can_exec=true`) by the reviewer, independently reproduced by me, then root-caused via `pg_proc.proacl` + `pg_default_acl`: Supabase's platform grants EXECUTE on new `public`-schema functions DIRECTLY to `anon`/`authenticated`/`service_role`, bypassing `PUBLIC` — confirmed `update_streak_progress`'s own live ACL has no `anon` entry, proving the working pattern is migration 090's explicit `REVOKE FROM anon`, not 091's `PUBLIC`-only revoke. | `REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated` in migration 115. Re-verified live: `anon_can_exec=false`. |
| P1a | A THIRD unprotected writer — `UserRepository.syncOnboardingToSupabase`'s raw upsert to the same 11 fields, missed in the original pass (different file/call path than the two writers already fixed). | Read the actual call chain (`onboarding_provider.dart`'s first-ever sync + 10s retry; `sync_service.dart`'s `_replayPendingOnboardingSync`, confirmed it re-reads Hive fresh each call but still races a raw upsert against a different device's already-versioned write). | New `SyncService.pushOnboardingProgressSnapshot` routes the same field set through the same RPC + existing retry-once helper; throws on genuine errors (preserves the pre-existing retry/replay contract), doesn't throw on a benign version-mismatch drop. |
| P1b | This doc's `restore-user-snapshot` deployment-status claim ("not yet deployed, founder-gated") was wrong. | Reviewer live-queried `list_edge_functions`; independently re-confirmed by me: v3, ACTIVE. Also found `_singleCallKillSwitch` defaults OFF (path attempted by default), contrary to this doc's original assumption. | Corrected throughout this doc (symptom/readers/proposed_fix/touched_layers/impact_analysis). Real residual: the freezes-projection code fix is written but not yet redeployed — self-healing (falls back to a version-mismatch retry) but not inert. |
| P2 | Fresh-insert branch left `current_phase`/`current_week`/`total_workouts_done`/`current_streak_weeks` unwrapped (bypassing schema DEFAULTs 1/1/0/0 on an all-null insert). Not reachable by any writer in the original pass. | Confirmed live via `information_schema.columns` (all 4 nullable, defaults 1/1/0/0). Became newly reachable by the P1a fix (onboarding-replay sends `current_week=NULL` to preserve the program-week projection) — found and fixed BEFORE finalizing P1a, not after. | Wrapped all 4 in `COALESCE(p_x, <default>)`. Live-verified: an all-null core-4 fresh insert now lands 1/1/0/0, not NULL. New regression case 14 in the SQL test file. |
| P3 | Both retry helpers' early-return paths (e.g. a failed re-fetch of the fresh version) don't emit telemetry, unlike the final drop-after-retry path. | Reviewer's own analysis: effectively unreachable (`maybeSingle()` against a row that was just proven to exist by the version-mismatch response). | **Correction (Hermes C7 / L34 Finding 2, 2026-07-30): the "effectively unreachable" premise was wrong.** Both RPCs return NULL for row-absent (migration 115), so a NULL RPC result does NOT prove the row exists — it's reachable via a partial restore leaving a non-zero local version with no cloud row behind it, and the state is self-perpetuating (every later sync silently no-ops the same way). Fixed, not accepted-as-is: both `rawRes == null` sites now emit `sync_freezes_row_absent_after_conflict` / `sync_user_progress_row_absent_after_conflict`, added to `highPriorityOpTypes` on both client and server. |

## Round-2 review findings (2026-07-30) — context-blind, on the round-1-hardened diff

Fresh Sonnet subagent, same rigor as round 1 (independently re-ran every live query
and test itself rather than trusting round 1's or this doc's prose). Verdict on all
5 round-1 items: **CONFIRMED FIXED** for all of them, each with its own independent
re-verification (re-ran the P0 grant rollback-transaction test, diffed the live
`restore-user-snapshot` EF source against the worktree copy, re-queried
`information_schema.columns` for the P2 defaults, re-ran all 14 SQL cases and all 37
Dart tests itself — this doc said 38 at the time; see Hermes C12 below for the
correction). Found ONE new issue:

| # | Finding | Verification | Fix |
|---|---|---|---|
| New (P2-equivalent) | Round-1's OWN P1 fix inserted `pushOnboardingProgressSnapshot` (a new ~79-line method) into `sync_profile.dart` BEFORE `_syncUserProfile`/`_syncUserProgress`/`_restoreUserProfile`, shifting all three down ~80 lines each — going stale AGAIN in `docs/sot_registry.yaml` (4 citation sites: lines ~3557, ~3682, ~3720, ~7974). `scripts/check_sot_registry_parity.dart` passed 0 errors despite this. | Independently confirmed the real current ranges myself (`_syncUserProfile` 133-244, `_syncUserProgress` 255-346, `_restoreUserProfile` 419-499) via direct grep + read, not trusted from the reviewer's numbers. Root-caused the gate's blind spot: its stale-range check only proves the symbol appears SOMEWHERE in the cited slice, not that the slice actually brackets the declaration — a citation that's simply too WIDE (the old, now-wrong range happened to still overlap the shifted declaration) silently passes. | Fixed all 4 citations to their real current ranges (splitting one combined `_syncUserProfile / _restoreUserProfile` entry into two precise per-method entries, since a single range can't bracket two non-adjacent methods). **Gate hardening explicitly NOT shipped in this batch** — attempted a declaration-proximity check, ran it against the full registry, and it surfaced 45-80+ hits across entries UNRELATED to this unit (whole-file `1-9999` citations, single-line reference citations of common override names like `onStateChanged`, class-name-as-loose-area citations) — false-positive classes this codebase's registry apparently uses deliberately and that I cannot safely triage entry-by-entry without a dedicated audit of citation conventions across 900+ concepts. This is a genuine scope boundary, not a deferral: the concrete bug this unit caused (4 citations) is fixed; the pre-existing gate weakness that made it possible to miss is a separately-scoped, real follow-up (spawned as its own task, not silently dropped). |

This is the SAME class of "editing code shifts other methods' line numbers"
drift Unit 3a hit once and this unit's own P1 fix hit against 2 UNTOUCHED methods —
now a third occurrence, this time surviving its own citation-repair pass because the
new insertion landed BEFORE the cited symbols rather than between two already-correct
citations. Worth a standing note: any edit that inserts code earlier in a file than
an existing SoT citation needs the SAME "did this shift something else" check as an
edit that inserts code between two citations — re-running the parity gate is
necessary but, per this finding, not sufficient.

## B-pass round-1 (2026-07-30) — `docs/reviews/4488c520a021-review.md`

5-lens fast pass (writer_reader_drift, function_exception_swallow,
blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink) on the staged,
round-2-hardened diff. Independently re-verified extensively rather than trusting
prior rounds — including its own live, read-only Postgres queries against
`pg_default_acl`/`pg_proc.proacl` that re-derived the P0 root cause from scratch,
and `check_sot_registry_parity.dart` / `check_schema_column_refs.dart` runs.
**1 finding, P3, accepted and fixed**: migration 115's inline rollback block gave a
copy-pasteable `DROP FUNCTION` for the new RPC but only prose ("re-apply migration
096's body") for the `update_streak_progress` hardening half — an incident
responder would need to go find that file under time pressure. Fixed by inlining
migration 096's exact body (read directly from that file) as commented SQL
alongside the existing statement. No functional or security findings.

## Hermes pass (2026-07-30) — `docs/audit/2026-07-30-hermes-cross-device-progress-lock.md`

11-lens deep pass (L1, L11, L14, L15, L22, L23, L27, L34, L35, L37, L39), required
before the plan-review record per §4.12.3 (catastrophic tier). Found substantially
more than round-1 + round-2 + B-pass combined — 9 of 11 lenses returned REAL or
PARTIAL findings, several converging independently on the same underlying defects
from different angles (the strongest signal available that they're real, not lens
noise). 0 P0, 7 P1, 11 P2, 8 P3. Full findings + per-cluster triage in the Hermes
report; summary of what was fixed in this same commit:

- **C1/C6** — `_stampProgressVersion` silently dropped the version when Hive
  `progress` was absent (4 lenses independently found this) and had no protection
  against 3 overlapping same-device writers regressing an already-newer stamp. Now
  creates the map instead of no-op'ing, and only writes when strictly newer.
- **C2** — the freeze retry helper wrote a PRE-AWAIT stale Hive snapshot back over
  fresher local state, reproducing — inside this batch's own fix — the exact
  same-device race the batch exists to close (L27's most severe finding). Now
  re-reads fresh local state before merging, and re-merges once more against
  whatever's fresh in Hive right before the final write-back.
- **C3** — `total_workouts_done` could still demote via three independent
  mechanisms (a 4th writer, `weekly-recalc`'s EF, that never touches the version
  lock at all; a client resending a stale value at the correct version; and the
  general COALESCE-not-GREATEST gap). Migration 115's UPDATE branch now uses
  `GREATEST`, closing all three regardless of which one races.
- **C4** — both RPCs' `auth.uid()`/`p_expected_version` guards failed OPEN on a
  NULL input (PL/pgSQL `IF <x> <> NULL` = NULL = false) — unreachable from shipped
  callers today, but a real gap in the RPC's own contract given both are
  `authenticated`-executable. Explicit `IS NULL` checks added to both guards, both
  functions.
- **C5** — `_stampProgressVersion` and the freeze retry helper resolved Hive box
  ownership from the live session, not the `userId` the caller was given, opening a
  cross-account write window during a sign-out/sign-in race (L15). Both now check
  the live session owner immediately before writing.
- **C7** — two of three version-mismatch-retry drop paths had zero telemetry,
  contradicting this doc's own prior P3 acceptance ("effectively unreachable" — L34
  showed that premise was wrong, since both RPCs return NULL for row-absent too, so
  NULL doesn't prove the row exists, and the state is self-perpetuating). Both sites
  now emit telemetry.
- **C8** — the new drop-telemetry events shipped LOW-priority, silently discarded
  during exactly the cooldown window (backend degradation) when they matter most.
  Added to `highPriorityOpTypes` on both client (`error_telemetry.dart`) and server
  (`log-client-error/index.ts`) — the latter is a source change only; redeploying
  it is a separate residual (see below), consistent with `restore-user-snapshot`'s
  already-tracked redeploy gap.
- **C9** — `pushOnboardingProgressSnapshot` used hard `as int?` casts (throws on a
  non-int) where the sibling method two lines away in the same file used the
  defensive `(x as num?)?.toInt()`. Aligned.
- **C10** — L27 F4 flagged zero concurrency coverage (all 14 original SQL cases ran
  sequentially in one transaction). An honest empirical attempt was made to close
  this with two execute_sql calls fired as if in parallel; the result showed they
  SERIALIZE rather than interleave (the second call's self-reported lock-wait was
  0s, meaning it only started after the first call's full 3-second sleep+commit had
  already finished) — this tool interface does not provide two genuinely
  concurrent Postgres sessions. Flagged as a residual tooling gap rather than
  shipping a misleadingly-passing test. What IS provable in one session was added
  instead (Case 15): `pg_locks` confirms `FOR UPDATE` takes a real, granted
  `RowShareLock` on `user_progress`.
- **C11** — this doc previously claimed the un-redeployed `restore-user-snapshot`
  EF causes `_restoreFreezes` to read `cloudVersion=null` and fall back to
  `expectedVersion=0`. Hermes L39 traced the actual restore order (on both restore
  paths, `user_progress` restores BEFORE freezes, and `_restoreUserProgress`'s bare
  `SELECT *` already carries the version into Hive first) and found that claim
  factually wrong — corrected above. The REAL gap L39 found: nothing pins the EF's
  projected column list against the client's `_restoreFreezes` select, so the next
  drift between them would go uncaught. Added
  `test/contracts/restore_user_snapshot_freezes_projection_parity_test.dart` to
  close that, scoped to the checked-in source (not the live, not-yet-redeployed EF).
- **C12** — this doc said 38 Dart tests throughout; Hermes L37 independently counted
  37 via `flutter test`, which I confirmed myself. Corrected everywhere in this doc.

**Not bundled into this batch, spawned separately**: L23 Finding 3 —
`restore-user-snapshot`'s `template:template_id(...)` embed has no user-scope
assertion on the FK target (pre-existing, untouched by this diff except for a
header-comment fix; requires a victim's template UUID that isn't exposed
cross-user anywhere found, so not a demonstrated live exploit today, but a real
defense-in-depth gap). Spawned as its own task per this session's established
precedent for genuinely out-of-scope pre-existing defects (the same pattern
round-2's SoT-parity-gate hardening followed).

All 19 SQL cases and 37 Dart tests re-run green after every Hermes fix (not just
claimed — see this diagnose-doc's `contract_test_path` and `regression_test_planned`
fields for the final counts).

**Self-caught 4th recurrence of the citation-drift class**: my OWN C2/C5/C7/C9 fixes
added lines earlier in `sync_profile.dart` and `sync_restore_completeness.dart` than
6 existing SoT registry citations (`_syncUserProfile`, `_syncUserProgress`,
`_restoreUserProfile` ×2, `_restoreFreezes`, `_restoreSavedDietPlan`), shifting each
declaration down without the gate catching it — the same too-wide-range-still-
overlaps blind spot round-2 already documented. `check_sot_registry_parity.dart`
reported 0 errors both before AND after these 6 citations went stale; I found and
fixed all 6 by manually re-grepping every declaration's actual line number after
each edit round, not by trusting the gate's silence. This is now the 4th occurrence
of this exact class in this one unit alone — strengthens (does not newly justify)
the case for the gate-hardening follow-up already spawned during round-2.

## B-pass round-2 (2026-07-30) — findings reconstructed from their landed fixes

A second, independent B-pass, dispatched after all 13 Hermes fixes (C1-C13) landed
— Hermes's own changes were large enough that the round-1 B-pass's verdict (above,
hash `4488c520a021`) no longer described what would actually ship; a fresh diff
needs a fresh review, not a reused one. Same 5-lens fast pass as round-1. **This
review's own report was never persisted to `docs/reviews/<hash>-review.md`** — a
real process gap, itself caught by the round-3 review below as this doc's own
Finding 5. The 6 findings below are reconstructed from their landed fixes, each
grounded in an in-code citation, not from an original report file (none survives).

| # | Finding | Fix |
|---|---|---|
| 1 | The wiring test's assertion for `_retrySyncFreezesOnceAfterConflict`'s final write-back still checked the pre-Hermes-C2 variable name `merged`; Hermes C2 renamed it to `finalMerge` when it added a second merge pass to close the RPC round-trip await window, and the test had gone stale. | Renamed the assertion to check `finalMerge` (`test/contracts/cross_device_progress_optimistic_lock_wiring_test.dart:172`). |
| 2 | `_retrySyncUserProgressOnceAfterConflict` (the user-progress retry helper) still rebuilt its RPC params from the STALE caller-supplied snapshot rather than a fresh Hive read — the exact same-device race Hermes C2 had already fixed on the freezes side, missed here because it's a structurally separate method. | Rebuilds from `_hive.userBox.get('progress')` via the shared `_buildUserProgressRpcParams` helper on retry, mirroring Hermes C2 (`lib/core/services/sync/sync_profile.dart:410`). |
| 3 | `deployments_complete` sat in the same `update_user_progress_snapshot` UPDATE statement as `total_workouts_done` but had not received the Hermes-C3 `GREATEST` guard — reachable by the identical stale-resend vector, and read by both `evaluate-rank-promotions` and `rank_service.dart` for rank gating. | `GREATEST(COALESCE(p_deployments_complete, deployments_complete), deployments_complete)` in migration 115's UPDATE branch, mirrored in the SQL harness's embedded copy; Case 20 added as the regression test (`supabase/migrations/115_user_progress_snapshot_optimistic_lock.sql:181`, `test/sql/cross_device_progress_optimistic_lock_verify.sql` Case 20). |
| 4 | `_retrySyncFreezesOnceAfterConflict`'s final write-back to local Hive is a SEPARATE write from the `_stampProgressVersion` call above it — Hermes C5's ownership guard only protected the version stamp, not this second write. A sign-out/sign-in-as-different-user race landing inside the single RPC await could write device-A-derived freeze data into whatever account is live now. | Added the same `HiveUserSession.currentOwnerFullId != userId` guard immediately before this write (`lib/core/services/sync/sync_restore_completeness.dart:214`). |
| 5 | This diff touches `sync` (a §4.6-listed risky category) and unconditionally replaces the old version-blind upsert paths with the new RPC-routed paths, with no `kDebugMode`/Hive-flag/RemoteConfig gate — §4.6 requires one for risky-category changes, and this diagnose-doc did not explain the absence. | Documented as a deliberate waiver, not an oversight, in the "Design decisions" section above: the old path has a known, worse bug; the new failure mode is telemetered via Hermes C7/C8, not silent; routine future syncs auto-reconcile; migration 115's own inline rollback SQL is the real safety net. |
| 6 | `docs/sot_registry.yaml`'s `_restoreFreezes` entry had a prose `notes:` field contradicting its own structured `line_range:` field (said "shifting the method to 266-359" while `line_range:` correctly said `324-433`) — a leftover from an earlier edit round that updated the structured field but not the prose describing it. | Corrected the prose to match the structured field (`docs/sot_registry.yaml:3362`). |

Findings 2 and 3 are the two genuine runtime bugs — a retry helper resending stale
local state, and a monotonic field missing its GREATEST guard — both silent-data-
loss-class, consistent with this whole batch's dominant bug pattern. Finding 4 is a
real cross-account write-window gap, same class as Hermes C5. Findings 1, 5, 6 are
test/process/doc-accuracy gaps, not runtime bugs. All 6 fixed in this same commit;
re-verified via the full Dart suite and the live SQL harness (20/20 cases).

## Round-3 review findings (2026-07-30) — narrowly re-verifying B-pass round-2's fixes

A third, narrowly-scoped review, dispatched specifically to re-verify the 6 B-pass
round-2 fixes above rather than run a full fresh sweep — the same "review #2 runs
on the post-review-#1 hardened diff" principle from §4.12.1, applied one level
deeper since round-2's own fixes are exactly the kind of place a correction can
introduce a new defect (as round-2 itself did to round-1's fixes, per that
section). Found 1 real P1 + 1 documentation gap; the other findings it examined
were confirmed correct as landed, no further action needed.

| # | Finding | Verification | Fix |
|---|---|---|---|
| 1 | Finding 2's fix above (`_retrySyncUserProgressOnceAfterConflict` rebuilding from fresh Hive) was itself incomplete: an ALL-OR-NOTHING swap (fresh Hive map present → use ONLY its fields, ignoring the original `rpcParams` entirely). Correct for `_syncUserProgress`'s own retry (same Hive source as the original attempt). WRONG for `pushOnboardingProgressSnapshot`'s retry: its first attempt's `progressData` carries `detected_experience_level`, which Hive's `progress` map never gets for the onboarding writer — the swap silently resent NULL for that field on retry, permanently dropping a real onboarding answer whenever the fresh-insert race is lost. | Independently re-verified by reading `onboarding_provider.dart:465-528` directly: `saveProgress` (471-478) writes only 6 fields, none of them `detected_experience_level`, strictly BEFORE the sync call at line 516 — confirming the field genuinely never reaches Hive's `progress` map for this caller. | Redesigned as a per-field merge: new `SyncService.mergeRpcParamsPreferringNonNull` (`@visibleForTesting`, `lib/core/services/sync_service.dart`), preferring the fresh-Hive value per-field when non-null, else falling back to the original caller-supplied value — safe for every field the RPC accepts because its SQL already treats a NULL param as "no fresher info, don't touch this column" for all of them. Covered by a dedicated behavioral test file, `test/sync/merge_rpc_params_preferring_non_null_test.dart` (6 tests, including the exact onboarding-drop regression scenario), plus an updated wiring-test assertion. |
| 2-4 | Re-examined B-pass round-2's Findings 1, 3, and 4 (test rename, `deployments_complete` GREATEST guard, freeze-retry ownership guard) against the live diff. | Independently re-verified each against current source rather than trusting the prior round's word. | Confirmed correct as landed — no further action. |
| 5 | This diagnose-doc had no dedicated section for B-pass round-2's 6 findings (unlike round-1/round-2/Hermes, each of which has its own section); the SQL harness's header comment cited `docs/reviews/15f0ecdaafd8-review.md`, a file that was never actually written (the B-pass round-2 report was never persisted — only its fixes landed, the same gap that section itself now documents); and the `regression_test_planned`/`contract_test_path` test-count citations were stale at 37 after B-pass round-2's and round-3's own fixes had grown the suite further. | Grepped `docs/reviews/` — confirmed the file does not exist. Re-ran the wiring test file — confirmed the live count. | This section, the "B-pass round-2" section above, a fix to the SQL header (now points at this doc instead of an unstable hash-named path that would go stale again on the next B-pass), and the corrected test counts in `contract_test_path`/`regression_test_planned` above are that fix. |

All findings fixed in this same commit. Re-verified via the full Dart suite +
`flutter analyze` + the live SQL harness after every fix, per this session's
established discipline for successive review rounds.

## Final B-pass (2026-07-30) — `docs/reviews/8d5a2f558995-review.md`

A third, independent B-pass, dispatched after round-3's fixes were staged — the
same fresh-review-per-changed-hash discipline as before, this time explicitly
told to review the diff as if for the first time despite the extensive prior
history, and NOT to assume clean just because it had already been reviewed many
times. Recomputed the staging hash independently (`8d5a2f558995`, matched, no
drift) and blast-radius independently (`catastrophic`, matched). Same 5-lens
pass as both prior B-passes. **This is the first B-pass report in this whole
review chain to be written to `docs/reviews/` at the SAME hash the diff was
staged at** — round-1's B-pass file now describes a stale, pre-Hermes diff;
round-2's B-pass was never persisted at all (the gap round-3 caught). Found 1
real finding + 2 false alarms.

| # | Finding | Verification | Fix |
|---|---|---|---|
| 1 (P3) | `longest_gap_days` was the ONLY one of the three "record" fields in the UPDATE statement (alongside `total_workouts_done` and `deployments_complete`) still on bare `COALESCE`, not `GREATEST` — a lifetime high-water-mark (computed as a running max in `getPromotionStatus.ts`), read by both `rank_service.dart` and `evaluate-rank-promotions` for disqualification gating. | Independently re-verified: `grep -n "longest_gap_days\|GREATEST"` on the migration confirmed the asymmetry; `grep -rn "'longest_gap_days'\]" lib/` confirmed zero Hive WRITE sites exist today (only the 2 read-for-RPC-forwarding sites in `sync_profile.dart`), so `p_longest_gap_days` is always NULL in practice — real but currently dormant, hence P3 not P1. | `GREATEST(COALESCE(p_longest_gap_days, longest_gap_days), longest_gap_days)` in migration 115's UPDATE branch, mirrored in the SQL harness's embedded copy; Case 21 added as the regression test, mirroring Cases 18 and 20 (`supabase/migrations/115_user_progress_snapshot_optimistic_lock.sql`, `test/sql/cross_device_progress_optimistic_lock_verify.sql`). Live-verified: 21/21 cases `ok`. |
| 2 (false_alarm) | Apparent Hive-key drift: freeze-used-dates uses `streak_freeze_used_dates` (singular) in this diff's new code vs `streak_freezes_used_dates` (plural) in cloud/select references. | Traced both forms to their origin: singular is the established, pre-existing Hive-local key (written/read outside this diff, untouched); plural is cloud-column-only. This diff's new code follows the existing convention consistently. | n/a — no drift, pre-existing intentional split. |
| 3 (false_alarm) | `restore-user-snapshot`'s not-yet-redeployed freezes-projection change (4→5 col) could leave the client reading a stale response shape at merge time. | Traced the actual read path: absent-key access returns `null` in Dart, not a crash; a stale response degrades to `cloudVersion == null`, which the existing bounded-retry path (re-fetching the version directly, not via the EF) self-corrects on the next sync. Already tracked as an explicit residual (below) and pinned by `restore_user_snapshot_freezes_projection_parity_test.dart`. | n/a — already tracked, tested, self-healing; not a new gap. |

Finding 1 fixed in this same commit; re-verified via the live SQL harness (21/21
`ok`). Findings 2-3 required no code change. `docs/reviews/8d5a2f558995-review.md`
verdict flipped to `accepted` after this triage.

This is the third consecutive B-pass-class review dispatched independently
against this diff (round-1's B-pass, round-2's un-persisted B-pass, this one) —
each found real defects on its own diff snapshot, and each found progressively
fewer / lower-severity ones (P0+P1+P2+P3 → 2 real P1s + 2 process/doc gaps + 2
minor → 1 dormant P3 + 2 false alarms). Combined with round-3's independent
narrow review also converging (1 small real fix, everything else confirmed
clean), this is the signal this review pipeline has genuinely converged, not
merely run out of review rounds.

## Residuals, stated explicitly

- **Migration 115 is NOT yet applied.** Written, live-tested (21/21 cases green in a
  rollback transaction, including the round-1-fix, Hermes-fix, B-pass-round-2
  (Case 20), and final-B-pass (Case 21) regression cases), but the actual
  `apply_migration` call requires its own explicit user go-ahead per CLAUDE.md §4.3 —
  plan approval is not deploy approval, and this session's standing autonomous-batch
  convention does not cover a live prod apply. OI-45's cross-device half stays OPEN
  until the migration is applied AND the extended `security_definer_anon_revoke.sql`
  grant checks are re-run post-apply to confirm live reality matches intent
  (mirroring migration 091's own "apply_migration returning success != the grant
  changed" lesson).
- **`restore-user-snapshot` Edge Function needs an explicit redeploy** (separate
  action from the migration apply, same §4.3 authorization requirement) to carry the
  freezes-projection fix (4-col -> 5-col) live — the EF itself is already live (v3,
  ACTIVE) and its restore path is attempted by default, so this is a real drift, not
  inert future-proofing (corrected from this doc's original claim — see round-1
  findings above).
- **Unit 3c** (graduation_screen.dart's narrower stale-`nextPhase` bug, found by Unit
  3a's round-1 review): not started, needs its own conflict-resolution design.
- **Task #41** (behavioral test for `advanceProPhaseIfExpired`/`_maybeAdvancePhase`'s
  real production callsites): not started.
- **`scripts/check_sot_registry_parity.dart`'s stale-range check has a real blind
  spot** (found by this unit's own round-2 review, see above): it proves a cited
  symbol appears SOMEWHERE in its cited range, not that the range actually brackets
  the declaration — a too-wide or shifted-but-still-overlapping range silently
  passes. This unit's own P1 fix triggered exactly this gap. A declaration-proximity
  hardening was attempted and reverted (45-80+ false positives against pre-existing,
  apparently-deliberate citation conventions this registry uses elsewhere — whole-file
  `1-9999` citations, single-line reference citations, class-name-as-loose-area
  citations — that a quick fix cannot safely distinguish from genuine drift). Spawned
  as its own follow-up task, not silently dropped.
