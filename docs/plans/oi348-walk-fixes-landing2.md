# OI-348 walk fixes — Landing 2: B8 rank floor, B9 unit sync, B10 restore speed, B2 referral codes

Status: v4 CONVERGED (2026-11-23). B8 and B2 converged at round 3; B9 at round 5; B10 at round 6
(its last finding, a missing `.eq("id", vUid)` shape, was mechanical: `mechanical_only: true`).
Rounds 4-6 moved only test wiring, rollout order and spec precision. Round 1 folded (B8 2×P1, B9 2×P1, B10 1×P0 + 3×P1, B2 2×P1; the B10
subscription-refresh overlap DROPPED: it races restore on `progress`). Round 2 folded (B8 2×P1
test seams + pinned literals; B9 1×P1 toggle snap-back; B10 1×P0 source-grep repoints + 1×P1
golden parity; B2 1×P0 M2 → its own PR C + 1×P1 web-deploy check). No design changed in round 2.
B2 now lands as PR B (M1 + client) then PR C (M2). Branch `oi348-landing2`, base `main` `e28cdab8`.
Founder decisions locked 2026-11-23 (AskUserQuestion): B2 server mints codes; B9 sync BOTH the
profile metric/imperial switch and the measurement sheet's cm/in, per user; B8 the starting rank is
never announced. Execution mode (§4.12.7): **inline, three PRs**: PR A = B8 + B9 + B10 (`platform`,
branch `oi348-landing2`); PR B = B2 M1 + client; PR C = B2 M2 after the web deploy. PR B = B2 (`catastrophic`: a `SECURITY DEFINER` function; branch
`oi348-landing2-referral`, its own worktree, staged B-pass + Hermes + local full suite before its
commit). Tiers from `scripts/blast_radius_from_diff.dart` on the real paths (2026-11-23):
rank_service / supabase_service `account`; the three EFs, `_shared/rank_engine.ts`, `sync_profile.dart`,
`sync_service.dart`, `user_repository.dart`, migrations `platform`; Home / sheet / provider `feature`.
Every migration apply and every EF deploy needs its own founder go (§4.3).

---

## Unit B8 — a new account is "promoted" to the starting rank (walk, 2026-11-22)

### Symptom and evidence
A brand-new account got a coach "Promotion Day" chat message, a push and the full-screen
celebration for Seaman 2 (SD2), the floor rung, after 0 sessions. Live (2026-11-23, read-only):
`rank_promotions` holds 48 SD2 rows (29 `signup` from the client, 19 `combined` from the cron) and 2
higher rows; `ai_coach_interactions` holds 27 `tool_calls.kind='proactive_promotion'` rows, ALL for
SD2; 18 of the 48 users also have a cron `promotion_ceremony` row.

### Writers and readers (verified by reading)
- The floor is always "qualified": `_shared/rank_engine.ts:32` (SD2 ordinal 0), `:46` empty gate,
  `highestQualified` starts at `kRankLadder[0]`; client mirror `rank_ladder_data.dart`.
- A null current rank is ordinal −1: `RankService.shouldPromote` (`rank_service.dart:63-68`), so
  `shouldPromote(null, SD2)` is true.
- Writer 1, client: `evaluateAndPromote` inserts every rung up to `qualified` not on file, floor
  included (`rank_service.dart:105-120`, upsert `:122-125`), then on `shouldPromote` writes
  `current_rank_code` and stamps the pending celebration (`:159-204`, stamp `:196-197`).
- Writer 2, cron: `evaluate-rank-promotions/index.ts:295-312` (`ranksUpTo(winner)` minus existing,
  floor included); ceremony rows per new code (`:316-350`, `prevCode` falls back to `"SD2"`).
- Dispatch: live trigger `trg_dispatch_proactive_coach_promotion AFTER INSERT ON rank_promotions FOR
  EACH ROW`, function `private.dispatch_proactive_coach_promotion()` (live `pg_get_functiondef`,
  SECURITY DEFINER, `search_path=public`): no rank filter, posts every row to the EF.
- Sink: `proactive-coach-promotion/index.ts:82-86` accepts any `rank_code`; writes the chat row
  (`:125-136`) and the push (`:146-147`).
- Reader: Home `_maybeShowPendingPromotion` (`home_screen.dart:~221-237`) opens
  `PromotionCelebrationScreen` for any stamped code.

### Fix (founder: the floor is never announced; rows stay as history)
1. One floor predicate per language: Dart `isFloorRank(String? code)` in `rank_ladder_data.dart`
   (`code == kRankLadder.first.code`), TS `isFloorRank(code)` in `_shared/rank_engine.ts`
   (`code === kRankLadder[0].code`). No literal `'SD2'` at the new call sites.
2. Client: rows are still written (history, deployments count, restore of the last 20, migration 075
   heal) — unchanged. `shouldPromote` stays (the denormalised `current_rank_code` must still move
   null → SD2). The pending-celebration stamp is skipped when `isFloorRank(qualified.code)`.
   The `isFloorRank` check wraps the stamp ONLY — never the `current_rank_code` update, the Hive
   write or `onStateChanged` (`rank_service.dart:159-204`). Seam: pure
   `shouldStampPromotionCelebration(String code)` (= `!isFloorRank(code)`) in `rank_ladder_data.dart`;
   the stamp stays after `if (shouldPromote(currentCode, qualified))`
   (`promotion_celebration_wiring_test.dart:124-135` keeps passing). `evaluateAndPromote` uses
   singletons and has no test seam; it is not run in tests.
3. Home reader mirror (`home_screen.dart:221-240`): pure `pendingPromotionAction(String? code)` →
   `none` (null) / `clearOnly` (floor) / `clearAndCelebrate`. Order in `_maybeShowPendingPromotion`:
   read → `clearPendingPromotionRankCode` → `if (action == clearOnly) return;` → the
   `rank_promotion_celebration_shown` event (`:229`, so it never logs a celebration that did not
   happen) → push. Clear-before-push within 1500 chars stays (`promotion_celebration_wiring_test
   .dart:203-212`). The only other stamp consumer is `user_repository.dart:961-972` (storage);
   only Home opens `PromotionCelebrationScreen` (`home_screen.dart:236`); `RankService
   .onStateChanged` is wired only in `lib/app.dart:75-93` (invalidates `userProfileProvider`).
4. Cron: no ceremony row for a floor code (`sortedNew` filters `isFloorRank`); rows still written.
   The `prevCode` fallback literal `"SD2"` (`evaluate-rank-promotions/index.ts:341`) becomes
   `LADDER[0].code` (the file imports `LADDER`, `:21`; `isFloorRank` added to that import). A first run inserting SD2 + SD1 together gives exactly one ceremony,
   SD2 → SD1.
5. EF sink guard: `proactive-coach-promotion` returns `200 {skipped: "floor"}` after the
   `!user_id || !rank_code` check (`:82-85`) and before `createClient` (`:87`). NEW seam (today a bare
   module-scope `serve(async (req) => …)` at `:50` with `!` env reads at `:31-34`): `export async
   function handler(req, deps = realDeps())`, deps = `{createAdmin, fetchPrefs, sendPush}` ONLY.
   Auth stays a direct literal call `if (!await isAuthorizedCronCall(req))` (pinned:
   `cron_auth_adoption_test.dart:132-143`, `audit_2026_06_07_batch6_server_test.dart:112`; the
   sibling keeps auth direct for the same reason, `evaluate-rank-promotions/index.ts:108-111`), so
   the Deno test sets `CRON_SECRET`. Literals other contract tests grep stay verbatim in the file:
   `createClient(SUPABASE_URL, SERVICE_ROLE_KEY)` inside `realDeps()`
   (`proactive_coach_promotion_test.dart:127`), `onesignal.com/api/v1/notifications`,
   `include_external_user_ids`, `deep_link` (`:228-250`), `model_used: "congrats_template"`,
   `isNotificationEnabled(prefs, user_id, "rank_promotion")` in the handler body
   (`notification_prefs_server_guard_test.dart:144`; `notification_prefs_parity_test.dart:73` forbids
   `markProactiveSent`). Env read inside `realDeps()` into `SUPABASE_URL` / `SERVICE_ROLE_KEY` BEFORE
   the `createClient(SUPABASE_URL, SERVICE_ROLE_KEY)` line, and `realDeps` defined BELOW `handler`:
   `cron_auth_adoption_test.dart:150-175` requires the auth call to precede any
   `createClient(…{0,240}SUPABASE_SERVICE_ROLE_KEY` match; `if (import.meta.main) serve((req) => handler(req))` (NOT
   `serve(handler)`: connInfo would land in `deps`, `supabase/functions/CLAUDE.md`). Pattern copied
   from `evaluate-rank-promotions/index.ts:116` / `:433`.
6. Trigger: a new migration (number from `sh scripts/mint_migration.sh`), one file, applied in one
   transaction: `DROP TRIGGER IF EXISTS trg_dispatch_proactive_coach_promotion ON
   public.rank_promotions; CREATE TRIGGER trg_dispatch_proactive_coach_promotion AFTER INSERT ON
   public.rank_promotions FOR EACH ROW WHEN (NEW.rank_code <> 'SD2') EXECUTE FUNCTION
   private.dispatch_proactive_coach_promotion();` — no `CREATE OR REPLACE FUNCTION`. The file's text,
   comments included, must not match `security\s+definer` (`blast_radius_content_rules_lib.dart:37`
   escalates ANY migration whose text matches to catastrophic); its header calls it "the dispatch
   function" and says a floor change needs a new trigger migration. Live today (2026-11-23,
   `pg_get_triggerdef`): `AFTER INSERT … FOR EACH ROW EXECUTE FUNCTION
   private.dispatch_proactive_coach_promotion()`, no WHEN. Ledger pair
   `backups/applied_migrations.json` in the same commit as the apply.
7. Existing rows and the 27 messages: left as they are (history; every account is a testing account,
   CLAUDE.md §1).
8. Announcer sweep (done during implementation, each recorded in the diagnose-doc as "reads rank
   state only" or fixed): `weekly-report/index.ts`, `daily-snapshot/index.ts`,
   `future-prediction/index.ts`, `_shared/captain_manual.ts`,
   `_shared/tools/progress/getPromotionStatus.ts`, `ai_snapshot_builder.dart` (`eta_next_promotion`),
   `rank_ladder_screen.dart`, `progress_comparison_screen.dart`, `rank_service_record_sheet.dart`,
   `stat_snapshot_service.dart` `snapshotOnPromotion`, `simulation_service.dart:~284`,
   `_shared/ceremony_text.ts`, `restore-user-snapshot/index.ts:~250`,
   `coach_interaction_repository.dart:~388`, `sync_restore_completeness.dart:592-616`,
   `promotion_history_provider.dart`, `rank_promotion_repository.dart`,
   `notification_settings_screen.dart`. Intended behaviour change recorded: `weekly-report/index.ts:
   ~443` — a new account's first weekly report no longer takes the CEREMONIAL tone from a floor
   ceremony row.
9. Deploy smoke (after each founder-approved EF deploy): POST an SD2 payload with the service token →
   `200 {skipped:"floor"}`; SD1 for a test user → chat row + push attempt (a LIVE write
   to a testing account; proves `import.meta.main` holds in the hosted runtime). Deploys: only
   `proactive-coach-promotion` and `evaluate-rank-promotions`; `isFloorRank` is additive in
   `_shared/rank_engine.ts`, so other importers need no redeploy.

### Tests
- `test/contracts/rank_floor_never_announced_test.dart`: behavioural on the pure seams —
  `shouldStampPromotionCelebration`: SD2 false, SD1 true, every higher rung true (mirror: an
  "always skip" mutant fails SD1); `pendingPromotionAction`: null → none, SD2 → clearOnly, SD1 →
  clearAndCelebrate. Source pins on the call sites: the stamp sits inside the
  `shouldPromote` block behind `shouldStampPromotionCelebration` and the `current_rank_code` /
  Hive writes are NOT behind it; in Home the clear precedes the `clearOnly` return, which precedes
  the telemetry event and the push.
- `test/contracts/rank_floor_trigger_migration_test.dart` (presence pins, `presence_only` with
  reason: SQL runs only live): the migration has the `WHEN (NEW.rank_code <> '<floor>')` with the
  floor equal to Dart `kRankLadder.first.code` and the TS ladder's first code; no `CREATE OR
  REPLACE FUNCTION`; text does not match `security\s+definer`.
- Deno: EXTEND the existing `proactive-coach-promotion/index_test.ts` (8 tests today, all kept;
  request builder and fake from
  `evaluate-rank-promotions/index_test.ts`, `CRON_SECRET` set): floor → 200 skipped, fake records no
  insert, no push, `createAdmin` never called; SD1 → one insert + one push.
  `evaluate-rank-promotions/index_test.ts`: empty `rank_promotions`, state qualifying SD2 only → SD2
  row, no ceremony; state qualifying SD1 → SD2 + SD1 rows, one ceremony SD2 → SD1.
- Live verify `test/sql/rank_floor_trigger_live_verify.sql` (BEGIN…ROLLBACK, real user id for the
  FK): an SD2 insert queues no `net.http_request_queue` row, an SD1 insert queues one; run first
  against the OLD trigger (SD2 queues one = the bug).
- Mutations: drop the stamp skip (contract red), `shouldStamp…` returns false always (SD1 case red),
  stamp skip widened over `current_rank_code` (pin red), Home return-before-clear (pin red),
  telemetry before the floor return (pin red), cron filter dropped (Deno red), EF guard dropped (Deno red), WHEN
  clause dropped (presence pin red; live verify red).

---

## Unit B9 — the measurement unit is not shared across devices (walk A3)

### Symptom and evidence
Phone set to inches; the web sheet showed cm. Values are stored in cm (correct). Live: no unit
column anywhere (`information_schema`, 2026-11-23).

### Writers and readers (verified by reading)
- Sheet unit: writer `MeasurementWriteNotifier.save` → `MigratedKey.write('body_measurement_sheet_
  unit', 'in'|'cm')` (`body_measurements_provider.dart:122-128`, per-user userBox, listed in
  `UserConfigMigrator.userScopedKeys` `user_config_migrator.dart:104`); readers `lastUnitInches`
  (`:143-148`), `preferredInches` (`:157-165`) used by the sheet and the Progress card.
- Profile unit: `units_metric` in the SHARED `configBox` (`user_repository.dart:1085-1093`), so it
  leaks between accounts on one device; writer the Profile Units row (`profile_content.dart:409-418`);
  readers `edit_profile_screen.dart:228`, `profile/screen.dart:99`, `preferredInches`, and
  `switch_goal_diff.dart:76` (reads `configBox` directly).
- Neither is pushed or restored (grep of `lib/core/services/sync/` and `supabase/`).
- Precedent: the profile map (`userBox['profile']`) is pushed with conditional entries
  (`sync_profile.dart:~200-260`, e.g. `diet_supplements`, migration 180) and restored on every launch
  by `_restoreUserProfile` (`sync_profile.dart:768-`), cloud non-null wins per key, cloud null never
  wipes.

### Fix
1. Migration: `ALTER TABLE public.user_profile ADD COLUMN units_system text CHECK (units_system IN
   ('metric','imperial')), ADD COLUMN measurement_unit text CHECK (measurement_unit IN ('cm','in'));`
   nullable, no default. Regenerate `backups/live_schema_columns.json` in the same commit; ledger
   pair. MUST be applied before any build carrying the push keys ships (an unknown column makes
   PostgREST reject the WHOLE profile row: `sync_profile.dart` comment at the `equipment_owned`
   entry).
2. Both settings become profile-map fields: `units_system` ('metric'|'imperial'),
   `measurement_unit` ('cm'|'in'), values normalised by one pure helper before any write (a CHECK
   violation would reject the whole profile row).
   - Writers go through `ProfileWriteService.patchProfileWith(build, stillOwner:)` (owner check
     inside the lock; `build` returns null → no write when NO profile exists yet: `patchProfile` on a
     missing profile would create a stub `{units_system, updated_at}` that makes `userBox['profile']`
     non-null before onboarding and pushes a near-empty row, `profile_write_service.dart:~95-110`).
     `setUnitsMetric` (already `Future<void>`, `user_repository.dart:1090`) now writes the profile and
     is a no-op with no profile. Callers: `profile_content.dart:416` and
     `body_measurements_sheet_test.dart:787-805` only.
     `MeasurementWriteNotifier.save` writes `measurement_unit` under the same `shouldRememberUnit`
     gate (it no longer writes the legacy key).
   - Readers treat any value other than `'imperial'` / `'in'` as the default (a bad cloud value is
     merged verbatim by restore, `sync_profile.dart:822-843`; the CHECKs guard only pushes).
     `getUnitsMetric()` becomes TOTAL: reads `profile['units_system']`; absent → the legacy
     `configBox['units_metric']` (so an imperial device shows imperial before the adopter has run,
     offline or after a failed restore; the adopter deletes that key, after which absent → metric);
     a throw (`userBox` is guarded: owner mismatch / no session throws `StateError`) → metric + event
     `units_pref_read_failed`. Callers with no try today: `profile/screen.dart:99`,
     `edit_profile_screen.dart:228`, `switch_goal_diff.dart:76` (switches from the raw configBox
     read to `getUnitsMetric()`). `lastUnitInches()` reads `profile['measurement_unit']`, falling
     back to the legacy per-user userBox key (no adopter needed for it).
   - Profile screen: `_isMetric` (`profile/screen.dart:99`, seeded once) stays the screen's source of
     truth; it is NEVER re-read in `build` (a `build` re-read would run before the queued locked
     write lands and snap the toggle back; `userProfileProvider` is not invalidated by
     `patchProfileWith` nor by restore, `profile_provider.dart:83`). The Units row sets `_isMetric`
     at once, then `await setUnitsMetric(…)` inside a try that logs, then `if (!mounted) return;`
     and `ref.invalidate(userProfileProvider)`. A restore-driven change: a NEW Profile-screen override of
     `invalidateOnBackgroundRestore` (calls the default first; the `HiveTabScaffoldMixin` hook every tab gets on
     `restoreCompletedTick`, `lib/features/home/CLAUDE.md` `cold_start_restore_refresh`) re-seeds
     `_isMetric` from `getUnitsMetric()` — a tick, not a build, so no snap-back. `setUnitsMetric`
     captures `HiveUserSession.currentOwnerFullId` at call start (null → return, no write: `null ==
     null` would otherwise pass) and passes `stillOwner: () => HiveUserSession.currentOwnerFullId ==
     owner` (the `home_provider.dart:947/994` pattern). The adopter does the same. The
     measurement sheet reads its unit when opened: an already-open sheet does not flip.
   - Onboarding's full replace (`updateProfile`) cannot wipe these keys: the Units row and the sheet
     exist only after onboarding. The onboarding upsert door (`user_repository.dart:1321`) never
     carries them (onboarding `profileData` has no unit keys; pinned).
3. Push: one pure helper `unitPrefsPushEntries(profile, enabled)` (the `dietSupplementsPushEntry`
   shape, `diet_supplements_rule.dart:86`) returns the present keys or `{}`; switch
   `disable_unit_pref_sync` (configBox, `DietSupplementsFlags` pattern) → `{}`, payload
   byte-identical to today. Restore still merges cloud values with the switch on (stated).
4. Restore: automatic (cloud non-null wins, cloud null never wipes, `sync_profile.dart:822-843`).
   Conflict rule: the last PUSHED change wins at every device's next restore. Same-device risk
   accepted explicitly (the posture of every profile field): a toggle made offline and followed by
   a relaunch before it pushes is reverted by the launch restore.
5. One-time device adopter `UnitsPrefAdopter.runIfNeeded()`, its own flag
   `units_metric_to_profile_v1_done` in `migrationBox` (the `_purgeFlagKey` precedent,
   `user_config_migrator.dart:215-246`: the main v2 flag is already true on every device), called
   from BOTH post-restore heal sequences, after the restore so the profile exists:
   `_healAfterRestoreInBackground` (`restoring/heal_after_restore.dart`, the background-restore
   path, already gated on `result.succeeded`; placed BEFORE `DayRolloverObserver
   .reckonAndNotifyAfterRestore()` (`:~87`), which bumps `restoreCompletedTick` last, so the
   Profile re-seed sees the adopted value) and its foreground twin `_ensureOwnershipBeforeHome` in
   `restoring_screen.dart` (`:~343-344` calls it WITHOUT checking the restore's result, so the
   adopter itself first requires `SyncService.instance.restoreSettledForCurrentUser` (deliberately
   over-strict: a persistently failing streak-critical restore op also holds the adoption back until
   it clears; the legacy fallback keeps the device's own display right meanwhile), else returns
   with no write and no flag: a failed restore leaves the profile without the cloud's value and
   the adopter would push the device value over another device's). Each call in its own try with a
   distinct `recordNonFatal` reason. Splash sends every authenticated launch (persisted session and
   Google OAuth included) to `/restoring` (`splash_screen.dart:307-312`). NOT `_ensureLocalUser`: it runs only on explicit sign-in /
   sign-up (`auth_provider.dart:323,457,470,692,912`), never at a launch with a persisted session and
   never for Google OAuth, so the founder's phone would never adopt. Inside
   `patchProfileWith(stillOwner:)`: if a profile exists and has no `units_system`, copy
   `configBox['units_metric']` into it; then delete the configBox key and set the flag. Key absent
   (never toggled; the default is metric) → no write, set the flag (no re-run, no push every
   session). Profile already has `units_system` → no write, delete the key, set the flag. No profile
   (restore failed / empty account) → do nothing, set no flag (the next successful restore's heal
   retries). Because it runs AFTER the restore merge, a value already in the cloud (another device
   synced first) is in the profile and wins over the device value ("only if absent"). Two
   accounts on one device: the shared value goes to whichever account first runs it with a profile
   (it was one device-wide value; stated). After it, nothing reads `configBox['units_metric']`.
6. Registry and docs: `docs/sot_registry.yaml` entries citing `units_metric` /
   `body_measurement_sheet_unit` (`:~18488-18541`) repointed with `behavioral_test_path`; a new
   `unit_preference_sync` concept; `lib/features/profile/CLAUDE.md` row; `docs/naming_conventions.md`
   (both columns, both keys, switch, flag, event). `measurement_sign_out_lifecycle_test.dart:34`
   re-checked (the legacy key is still cleared on sign-out; the profile key goes with the profile).
7. Existing tests that seed `configBox['units_metric']` are repointed to the profile key, never
   loosened (a `false` seed would otherwise test metric and stay green):
   `body_measurements_sheet_test.dart`, `measurement_prompt_state_behavioral_test.dart`,
   `measurement_card_end_to_end_test.dart`, `edit_profile_goal_target_test.dart`,
   `edit_profile_target_impact_test.dart` (seed a profile; `body_measurements_sheet_test.dart:787-805`
   also asserts the stored `units_system` is imperial). NOT `config_to_user_migration_test.dart`
   (`:73,100,155,183` use `units_metric` only as a "device key the migrator leaves alone" probe,
   still true). `grep -rn units_metric test/` = 13 hits in 6 files (2026-11-23); re-grep after.

### Tests
- `test/contracts/unit_preference_sync_writer_to_reader_test.dart`: writers put the profile keys;
  `getUnitsMetric` / `preferredInches` read them; a reader whose box throws returns metric and logs;
  no profile → setter writes nothing (no stub); two users on one device see only their own
  profile value; AFTER the adopter has run, a second account reads metric (the configBox key is
  gone); BEFORE it, a second account reads the device-wide legacy value (the bounded pre-adopter
  window: offline launch / failed or unsettled restore; stated).
- `test/sync/unit_preference_push_restore_test.dart`: `unitPrefsPushEntries` both / neither /
  switch-on byte-identical; restore through the REAL `_restoreUserProfile` merge: cloud imperial +
  `in` into a local profile → readers say imperial / inches; cloud null keeps the local value.
- Adopter call sites: source pins that `UnitsPrefAdopter.runIfNeeded()` is called in both
  `_healAfterRestoreInBackground` (before `reckonAndNotifyAfterRestore`) and
  `_ensureOwnershipBeforeHome`, each inside its own try with a distinct `recordNonFatal` reason, and
  NOT in `_ensureLocalUser`. Behavioural: restore not settled → no write, no flag; owner null →
  no write.
- `getUnitsMetric` legacy fallback: profile without `units_system` + configBox `false` → imperial;
  profile `metric` + configBox `false` → metric (profile wins).
- Profile restore tick: the screen's `invalidateOnBackgroundRestore` re-seeds `_isMetric` (widget
  test: profile changed to imperial behind the screen + a tick → row shows imperial).
- Adopter test with a PRE-SEEDED profile `units_system`: not overwritten; without it: copied once,
  configBox key gone, flag set; key absent: no write, flag set; no profile: nothing written, no
  flag; second user: nothing.
- Readers: cloud value `'feet'` / `'xx'` → default (metric / cm).
- Profile Units row widget test: toggle to imperial with the write delayed → the row shows imperial
  throughout (no snap-back); after the write, the profile holds `imperial`.
- Mutations: drop each push entry, the reader try (throwing box), the reader value check, the
  "no profile → no write" guard, the adopter's "only if absent", "no profile → no flag", "absent
  key → flag", a `build` re-read of `_isMetric` (widget test red), the switch.

---

## Unit B10 — restore takes 5 to 79 s (walk A8)

### Symptom and evidence
Live 24 h (2026-11-22/23): `restore-user-snapshot` `execution_time_ms` 4.8 to 97.5 s, not tracking
body size (3.7 KB took 34.5 s, 328 KB took 4.8 s). `client_errors`: for the 97 s case the client
apply steps took A 1 ms, B 333 ms, C 5 ms, sub 254 ms; in the walk's case readiness took 2.8 s and
the subscription refresh 8.6 s. The EF issues ~33 requests strictly one after another
(`index.ts:153-268`, no `Promise.all`), each 150 to 650 ms on a slow backend. Not a recurrence of
e4c1d7 (it fixed paging correctness; OI text at `open_issues.md:~5387` asks for this re-measure).

Round-1 caveat (accepted): serial round-trips alone (33 × 150-650 ms ≈ 5-21 s) do not explain 97 s,
so cold start, `getUser` and DB/PostgREST queuing are part of it. Live 2026-11-23: `max_connections`
60 (small compute tier), 3 PostgREST connections at rest, `statement_timeout` 2 min. Hence: a
conservative default cap, per-step timings in the same deploy, and the cap tunable live by env.

### Fix — EF (`supabase/functions/restore-user-snapshot/`)
1. Seam: the table assembly moves out of `index.ts` (module-scope env reads + `serve()`,
   `:80-102`, cannot be imported) into `restore_reads.ts`:
   `assembleTables(db, vUid, budget, limit, clock)` returns `{tables, timings}`. `index.ts` keeps
   auth, the UUID check, the response and the fail-closed catch.
   Source-grep tests and registry rows that read `index.ts` today are REPOINTED to
   `restore_reads.ts` in the same commit, never loosened (§4.9):
   `test/contracts/restore_user_snapshot_paged_reads_wiring_test.dart` (`:65-153`: the
   `tables["X"] = … readPaged(db, vUid, "X", budget)` pattern, `readCoachNewest(db, vUid)`, the
   budget-before-reads order, `vUid` per slice, the key set = `SyncService.singleCallBundleKeys`),
   `restore_user_snapshot_freezes_projection_parity_test.dart:42-55` (re-anchored on the signature-independent tuple
   head `["freezes",`, then the next `.select(`),
   `user_preferences_coaching_notes_writer_to_reader_test.dart:34-36,103-106` (path change only;
   its two `contains` checks are layout-agnostic);
   `docs/sot_registry.yaml` rows at `:3728`, `:3807`, `:7977`, `:18336`. New mirror pin: `index.ts`
   creates the budget per request and calls `assembleTables` (the wiring test's budget check
   otherwise reads `indexOf == -1`). Re-run `grep -rn "restore-user-snapshot" test/ docs/` after.
2. `runLimited<T>(thunks, limit)`: thunks are LAZY (a builder is a thenable that fetches on `then`;
   none is built before its slot); at most `limit` in flight; results in INPUT order; on the first
   rejection it starts nothing new, waits for the in-flight ones to settle, then rejects with that
   first error. In-flight reads after a rejection run to completion (no deadline; bounded by the
   EF wall clock). `limit` from env `RESTORE_READ_CONCURRENCY`, read PER REQUEST (so a dashboard
   change applies on the next call) by a pure `parseReadConcurrency(raw)`: absent or empty/blank → 3
   (checked BEFORE parsing: `Number(undefined)` is NaN); otherwise `n = Number(raw.trim())`; not
   `Number.isInteger(n)` (NaN, "3abc", "2.5") → 1; clamped to 1..8 (0, negative → 1; > 8 → 8). Not
   `parseInt` ("3abc" would read 3). `1` = today's serial order, the rollback lever without a redeploy.
3. Page budget charged PER PAGE inside the page factory (`restore-user-snapshot/paged_reads.ts:
   284-291`; `_shared/paged_fetch.ts` calls it once per page at `:225` and is NOT edited):
   `if (budget.remaining <= 0) throw new Error("paged_reads: page budget exhausted at '<name>'")`
   then `budget.remaining--`. In `restore-user-snapshot/paged_reads.ts` the `finally` charge
   (`:311`) and the `maxPages = min(MAX_PAGES, budget.remaining)` coupling (`:280`) go; the `catch`
   rewrite keyed on `maxPages < MAX_PAGES` (`:304`) is replaced by the factory's own message.
   Per-table `MAX_PAGES` and the entry guard (`remaining < 1`) stay; the existing assertions in
   `paged_reads_test.ts:389-391` (trip at 'weight_logs', remaining 0) and `:430` (remaining 8)
   still hold. Pass/fail is order-independent (fails iff total demand > budget or a table > 51);
   which table trips, and whether the entry-guard or the factory message fires, can differ under
   concurrency: tests accept either message. `readPaged`, `createPageBudget`, `readCoachNewest`
   have no caller outside this EF (grep 2026-11-23).
4. Layout (one source of order AND key set): `const READS: ReadonlyArray<readonly [string,
   "paged" | "query", (db, vUid, budget) => PromiseLike<unknown>]>` — an ordered array of
   `["<name>", "<kind>", (db, vUid, budget) => <today's chain verbatim, with vUid>]` tuples in
   today's exact key order. The KIND says how the result is read: `"query"` = a PostgREST builder,
   wrapped by `q(name, …)` (destructures `{data, error}`); `"paged"` = `readPaged(…)` or
   `readCoachNewest(…)`, which return plain arrays and are NOT wrapped (wrapping them would yield
   `undefined`). Paged entries are `["X", "paged", (db, vUid, budget) => readPaged(db, vUid, "X",
   budget)]`; the bundle key
   `ai_coach_interactions` (`index.ts:218`, `_kSingleCallBundleKeys` `sync_service.dart:2631`; NOT
   the client op label `coach_interactions`) is `readCoachNewest(db, vUid)`. Today's handler-local
   `q("label", builder)` (`index.ts:139`) moves into `restore_reads.ts` and takes the TUPLE NAME:
   `assembleTables` wraps each `"query"` read as `q(name, f(…))` itself, so no tuple body repeats
   its name and a label cannot drift (all 15 of today's `q` labels equal their bundle keys and no
   reader parses `query_failed:` text, round 5); `"paged"` reads keep their own errors, unwrapped,
   as today. `assembleTables` runs `runLimited(READS.map(([name, kind, f]) => () => run(name, kind,
   f)), limit)`
   and builds `tables` by INPUT index, so the bundle is byte-identical. No separate key-list
   constant. The three `user_progress` reads stay three.
   Wiring-test rewrite (`restore_user_snapshot_paged_reads_wiring_test.dart`), none loosened: each
   paged tuple's body is exactly `readPaged(db, vUid, "X", budget)` (`:65-88`); `readCoachNewest(db,
   vUid)` present (`:90-97`); the no-`.range(` / no-`SINCE` scan (`:99-105`) covers `index.ts` AND
   `restore_reads.ts`; the budget-order check (`:107-120`) becomes: `index.ts` creates the budget per
   request inside `serve(async`, calls `assembleTables`, and contains no `readPaged(`; the per-slice
   `vUid` check (`:131-144`) slices each tuple's BODY (from after its `=>` to the next tuple head or
   the close of `READS`; the parameter list is excluded, since every head names `vUid`) and requires
   `vUid` in a call position (`.eq(<any column>, vUid)` — 15 reads use `"user_id"`, `users` uses
   `"id"` (`index.ts:157-160`) —, the `referral_redemptions` `.or(` template containing `${vUid}`,
   `readPaged(db, vUid,` ×13, `readCoachNewest(db, vUid)`; all 29 enumerated in round 6); every `"paged"` tuple's body is a
   `readPaged`/`readCoachNewest` call and every `"query"` tuple's body is not; tuple count = 29
   (`starts.length`, `:135`; `grep -c 'tables\["' index.ts` = 29 today); names unique; names equal
   `SyncService.singleCallBundleKeys` (`:146-153`). The "13 paged keys" assertion (`:81`)
   becomes: tuple names of kind `"paged"` other than `ai_coach_interactions` equal
   `_manifestNames(paged)`, count 13; `:122` (`UUID_RE.test(vUid)` in `index.ts`) unchanged; `:155`'s
   import assertion is repointed to `restore_reads.ts` importing `readPaged` and `readCoachNewest`
   from `./paged_reads.ts` (and `paged_reads.ts` still imports only `../_shared/paged_fetch.ts`).
   All 9 `test(` blocks accounted for.
5. Timing: a SEPARATE log line from `restore_reads.ts`, `restore_timings request_id=<id> auth_ms= reads_ms=
   limit= ok=<true|false> <table>_ms=<n> …` (names and numbers only; reads not finished are omitted),
   emitted in a `finally` inside `assembleTables` so a failed or slow restore — the case to
   diagnose — still logs it. `index.ts` measures the auth step and passes it in:
   `assembleTables(db, vUid, budget, limit, {authMs, requestId, clock})`. `rowCountLogLine` is untouched
   (`paged_reads_test.ts:570-575` pins its shape and that it never names `user_profile`).
6. Fail-closed unchanged: any rejection → the same 500 `restore_snapshot_failed`.

### Fix — client (`sync_service.dart` `_attemptSingleCallRestore`)
7. Readiness prefetch: the `readiness_daily` network read starts concurrently with the EF call,
   wrapped at creation so it can never reject unobserved (`.then((r) => _Prefetch.ok(r),
   onError: (e, st) => _Prefetch.failed(e, st))`). At step B: ok → `_restoreReadiness(…,
   preFetched: rows)`; failed → `_reportSyncFailure('restore_readiness', …)` then
   `_restoreReadiness(…)` with NO argument (the `_kNoInject` sentinel = its own read;
   `sync_health.dart:122-130`; passing `null` would mean "empty", the silent-drop trap). On every
   other exit (legacy fallback, cancelled, owner changed) the prefetch is ignored, never awaited for
   its value; it cannot throw.
8. Subscription refresh: NOT overlapped. `refreshFromSupabase` → `writeSubscriptionState` →
   `grantFirstProFreezes` / `_downgradeLocally` → `resetToFreeCapOnLapse` read-modify-write the
   `progress` map and fire `syncFreezes()` (`subscription_service.dart:~323-340, ~1182-1228`,
   `streak_progress_service.dart:308-361`), the same key restore steps A and C merge; it stays the
   deliberate last step (`sync_service.dart:2537`). Its 0.3-8.6 s is one network select on the
   slow backend.
9. Kill switch `disable_restore_overlap` (configBox, the `disable_single_call_restore` pattern
   `sync_service.dart:411`, cleared by `clearAllData()`, named in `docs/naming_conventions.md`) →
   today's serial readiness read. Both switches are default-ON behaviour changes, so the full ×2
   review applies (not the ship-dark tier).

### Tests
- Deno `restore_reads_test.ts`, fake DB supporting the non-paged chains (`select/eq/limit/order/
  maybeSingle/gt/or`) and paged reads, with DIFFERENT per-table latencies: `runLimited` (max
  in-flight counter never exceeds `limit`; input order; first error rejects only after in-flight
  settle; lazy thunks: no builder's `then` runs before its slot is free); budget: 13 concurrent full
  tables with a page-yielding gate still throw `page budget exhausted at`; parity against a GOLDEN,
  not against itself: a fixture recorded by running the ORIGIN/MAIN serial assembly
  (`git show e28cdab8:…/index.ts` body, harnessed once with the same fake) — `JSON.stringify` of the
  new bundle at `limit=1` and `limit=3` equals the golden byte for byte; each non-paged chain's
  exact `.select/.eq/.order/.limit/.maybeSingle` call sequence recorded by the fake equals the
  golden's (the `old_chains.fixture.json` pattern, `paged_reads_test.ts:576+`); one rejected read →
  reject (index maps it to 500). Existing `paged_reads_test.ts` stays green, its `:389-391` substring assertions included.
- Env clamp table (absent → 3, "" → 3, "  " → 3, "abc" → 1, "3abc" → 1, "2.5" → 1, "1e1" → 8,
  "0" → 1, "-1" → 1, "2" → 2, "99" → 8, "Infinity" → 1, "0x10" → 8).
- Golden recording: the e28cdab8 `index.ts` read body is copied once into a throwaway harness
  (scratch, not committed) run against the fake; the committed fixture is its static output.
  The recorded call sequences are keyed by READ (tuple) name, not by table (`user_progress` is read
  three times and a global sequence interleaves at limit 3); the `.gt("expires_at", <now ISO>)`
  argument is normalised to a placeholder (`generated_at` is outside `tables`, so not compared). The golden proves only what the fake can
  see (stated in the diagnose-doc).
- Dart: prefetch ok → `_restoreReadiness` gets the rows and does not read; prefetch failed → telemetry
  + own read (not empty); switch on → no prefetch, own read; legacy fallback after a started
  prefetch → no unhandled error (zone guard).
- Mutations: per-page charge removed (budget test red), order by completion (golden parity red),
  two tuples swapped / keys assigned as reads finish (golden parity red), a tuple body
  loses `vUid` (wiring pin red), a `"query"` tuple marked `"paged"` (golden parity red: the
  builder's result object lands unwrapped), eager thunks (lazy test
  red), limit ignored (in-flight counter red), clamp or empty-check removed (env table red), failed
  prefetch passed as `null` (Dart red), switch inverted (Dart red).
- Live: before/after `execution_time_ms` plus the new timing line on the founder's account; the
  cap is raised by env only if the timings show reads (not auth / cold start) dominate.

---

## Unit B2 — REGENERATE on an expired referral code does nothing (walk A10) — PR B

### Symptom and evidence
The sheet's REGENERATE button does nothing, no error; telemetry 42501 on `referral_codes`. Live:
RLS policies SELECT own + INSERT own only (no UPDATE, no DELETE, since migration 035); 3 rows, 2
expired; UNIQUE(user_id), UNIQUE(code); no triggers.

### Writers and readers (verified by reading)
- Writer: `SupabaseService._generateNewCode` upserts `{user_id, code, expires_at}` onConflict
  `user_id` (`supabase_service.dart:149-172`) — an UPDATE when the row exists → 42501, swallowed
  4 times, then telemetry and `null`. Callers `getOrCreateReferralCode` (`:112-139`) and
  `regenerateReferralCode` (`:141-146`).
- Sheet: `_regenerate` (`invite_friends_sheet.dart:96-109`) ignores a null result: the silent no-op.
- Readers: `redeem-referral/index.ts:~82-96` (service role, code lookup, expiry check), the restore
  (`sync_restore_completeness.dart:~646`, `restore-user-snapshot` `referral_codes` read).
- Second gap: the INSERT policy lets a user's first row carry any `code` text and any `expires_at`.

### Fix (founder: the server makes codes)
1. Migration M1 (catastrophic): `public.issue_referral_code()` RETURNS TABLE `(out_code text,
   out_expires_at timestamptz)` (OUT names differ from the columns: same names make plpgsql raise
   "column reference is ambiguous"), SECURITY DEFINER, `SET search_path = ''`, every name
   schema-qualified, every column table-qualified. Body:
   - `uid := auth.uid()`; null → `RAISE EXCEPTION` (no anonymous path).
   - `PERFORM pg_advisory_xact_lock(hashtextextended('issue_referral_code:' || uid::text, 0))` —
     two devices tapping at once serialise here (without it, B passes its expiry pre-check, blocks
     on A's row lock, then OVERWRITES A's fresh code: A shows a code no longer in the table). Held
     across the collision retries.
   - If a row with `expires_at > now()` exists → return it unchanged.
   - Else up to 5 attempts: mint `'AVYA-' || 8 chars` from `extensions.gen_random_bytes`, each byte
     `>= 252` discarded (no modulo bias; draw more bytes as needed); `INSERT … ON CONFLICT (user_id)
     DO UPDATE SET code = EXCLUDED.code, expires_at = now() + interval '7 days', created_at = now()`
     inside `BEGIN … EXCEPTION WHEN unique_violation` — `GET STACKED DIAGNOSTICS` constraint name
     `referral_codes_code_key` → retry; any other constraint → re-raise. 5 failures → raise.
   - End with a plain `SELECT … WHERE user_id = uid`; nothing → raise. Never returns zero rows.
   - `REVOKE EXECUTE … FROM PUBLIC, anon; GRANT EXECUTE … TO authenticated;` (anon revoke is required:
     platform default grants, `supabase/migrations/CLAUDE.md`).
   Live columns (2026-11-23): `id`, `user_id`, `code`, `created_at` (default now()), `expires_at`
   (NOT NULL, default now()+7d); no `uses` column; `redeem-referral` reads `user_id`, `expires_at`.
2. Migration M2, in its OWN PR C (`scripts/check_migration_ledger_paired.dart` blocks any commit
   that ADDS a migration file without its ledger row, and a row is written only at apply, so an
   unapplied M2 cannot ride in PR B). M2 is applied only AFTER the web build carrying the RPC is
   live, because the live web app still ships the old first-code INSERT:
   `DROP POLICY "Users can insert own referral code"`; `REVOKE ALL ON public.referral_codes FROM
   anon, authenticated; GRANT SELECT ON public.referral_codes TO authenticated;` (live today both
   hold DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE; anon needs no SELECT: its RLS
   policy is own-row only). Writers after M2 checked: the only client writer is the upsert being
   replaced (`supabase_service.dart:156`); `redeem-referral` and `restore-user-snapshot` read with a
   service-role client; the FK `ON DELETE CASCADE` runs as owner; no test/script/integration file
   writes the table. The function keeps working: owner `postgres`, `relforcerowsecurity` false
   (live), so it bypasses RLS and keeps table privileges.
   Sequence: PR B merged (M1 applied before its merge, founder go) → Vercel builds `main` on push
   (`vercel.json` `ignoreCommand` builds only `main`; `scripts/vercel_build.sh` = plain
   `flutter build web --release`, dart2js keeps string literals) → confirm the Vercel deployment for
   the merge SHA is READY → `curl --compressed "https://app.icanbefitter.com/main.dart.js?v=<sha>"`
   and grep `issue_referral_code` → founder go → apply M2 (with a self-check `DO` block that aborts
   if `authenticated` or `anon` still holds INSERT/UPDATE/DELETE, the migration 160 pattern), commit
   M2 + ledger row as PR C → CI → merge. Tabs or service-worker-cached web clients still on the old
   build fail their first-code INSERT after M2 (testing accounts, accepted).
   M1 is applied only AFTER the staged B-pass and Hermes pass accept it; its bytes are then frozen
   (Gate 39 hashes the applied file). A post-apply change is a NEW migration, never an edit.
3. Client: `getOrCreateReferralCode` and `regenerateReferralCode` both call
   `client.rpc('issue_referral_code')` with the token handling of the neighbouring
   `referrer_summary` call (`referral_repository.dart:126`); the result is a `List`: take `first`,
   map `out_code` / `out_expires_at`; empty list or exception → null + telemetry.
   `_generateNewCode` and `_buildReferralCode` are deleted. The Hive `referral_code` key is written
   only by the restore and read by nothing else in `lib/` (verified), so regenerate needs no cache
   write.
4. Sheet: `_regenerate` and `_load` show an error line with Retry on a null result (Wardroom copy),
   re-enable the button; success replaces the code and expiry.
5. Old shared codes: REGENERATE is offered only after expiry and `redeem-referral` refuses an
   expired code, so nothing redeemable is lost.
6. Old builds (AAB +50): after M2 their first-code INSERT fails (testing accounts only, CLAUDE.md §1;
   existing codes unaffected; REGENERATE was already broken there).

### Tests
- Live verify `test/sql/referral_code_issue_live_verify.sql` (BEGIN…ROLLBACK, real `auth.users`
  ids for the FK, `SET LOCAL ROLE authenticated` + `set_config('request.jwt.claims', …, true)`):
  expired → new code `^AVYA-[A-Z0-9]{8}$`, +7 d, one row; expiry exactly `now()` → treated as
  expired; valid → unchanged; none → created; claims with no `sub` → raises; `SET LOCAL ROLE anon`
  → permission denied; `has_function_privilege('anon', …)` false; user A's call never touches B's
  row; PRE-M2 ONLY: the old upsert as `authenticated` → 42501 (the bug, run against the OLD state
  first);
  `prosecdef`, `proconfig = {search_path=""}`, `proacl`, `proowner = 'postgres'::regrole` pinned;
  after M2: authenticated INSERT / UPDATE / DELETE denied AND a real `authenticated` call to the
  function on an expired row still returns a new code.
- Concurrency `test/sql/referral_code_issue_concurrency_local.sh` (two sessions, the
  `referral_pay_on_conversion_concurrency_local.sh` docker-replica pattern): two simultaneous calls
  on an expired row both return the SAME non-null code. Its replica schema
  (`test/sql/referral_code_issue_replica_schema.sql`, own marker and container name) carries
  `auth.users`, an `auth.uid()` that reads `request.jwt.claims`, the `extensions` schema with
  pgcrypto, `public.referral_codes` with the live constraints, and M1 verbatim (the existing replica
  has no `referral_codes`). The advisory lock is held across the code-collision retries (stated).
- Dart: rpc result parsing with a fake returning a `List` (and an empty list → null); sheet error +
  retry (seam); source pin that no client code writes `referral_codes` (`.upsert`/`.insert`/
  `.update`/`.delete` on it), allowing the restore SELECT (`auth_invalidation_contract_test.dart:30`
  keeps its `.from('referral_codes')` pin).
- Mutations: expiry guard, advisory lock (concurrency red), final re-select (function pin only: the
  upsert always returns a row while the lock exists, so no runtime test can see it),
  `user_id = uid` scoping, REVOKE, null-uid raise, `proconfig`, retry constraint-name check, byte
  rejection, client `first`/empty parsing, sheet error branch. A whole-function text pin
  (`test/contracts/issue_referral_code_function_pin_test.dart`: the migration's function body,
  whitespace- and comment-insensitive, plus every GRANT/REVOKE whatever the spelling) catches the
  body mutations a single-session SQL run cannot (byte rejection, retry check).

---

## Ledger and docs (same batches)
Diagnose-docs: B8 `8b1f3d`, B9 `e9a6c1`, B10 `a0d5f7` (PR A); B2 `c2e8a4` (PR B). SoT registry
entries (`rank_monotonic_current_code` reopened; new `rank_floor_never_announced`,
`unit_preference_sync`, `restore_snapshot_concurrency`, `referral_code_issue`). Naming. Kill
switches: one OI minted (`mint_oi.sh`) for removing `disable_unit_pref_sync` and
`disable_restore_overlap` after the device re-check (`RESTORE_READ_CONCURRENCY` stays: it is the
tuning knob, not a rollback switch). `backups/applied_migrations.json` per applied
migration; `backups/live_schema_columns.json` for B9. Closure ledgers per PR. OI-348 rows A3, A8, A10
and the rank row: "fix landed, re-check".
