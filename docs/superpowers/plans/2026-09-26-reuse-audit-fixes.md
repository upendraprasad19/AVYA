# Reuse-audit fixes (5 bugs) — implementation plan (rev 3, post review round 2)

> **Rev 3 — SPLIT per §4.12.1 (2026-09-26).** Round 2 surfaced NEW material (P1) defects,
> almost all introduced by the round-1 corrections to A and B2: the R1-2 sweep change defeats
> cross-device delete/rename (a second device still holding the template re-pushes it as
> `is_active:true`); an unconditional tombstone plus the sweep can delete a same-named template
> the user kept; `MigratedKey`'s `configBox` fallback can leak a tombstone across accounts in the
> sign-out/sign-in race (`migrated_key.dart:82-100`, `guarded_box.dart:101-104`); and five
> unlisted source-grep tests break. The root problem, multi-device deletion semantics for a
> push-everything-local-as-active sync, needs its own design. Two successive rounds kept
> surfacing new material issues in A/B2, which is the split signal.
> - **This branch ships B1 + C + D.** Round 2 found only P2s there (R2-7, R2-9) and verified
>   C/D's premises (see the round-2 record). The P2 corrections are folded in below.
> - **A + B2 continue as the next unit in this session**, with multi-device semantics brought
>   to the founder as options first. Their sections stay below as design history; they are NOT
>   implemented on this branch.
>
> Round-2 corrections for the shipped scope:
> - **B1 [R2-7]:** `saveMealAsTemplate` re-saving an existing `meal_*` key must PRESERVE
>   `times_used` (it rewrites the payload without it, resetting B1's counter).
> - **D [R2-9]:** `upsertCustomExercise` can return `fail` after a successful put (the sync
>   kick is inside its try). `createCustomExercise` therefore throws `write_failed` only when
>   the row is absent from `customBox` after the call, never on a bare `!success`.
> - **C (residual, verified R2):** `redeem-referral` enforces a 7-day signup window
>   (`redeem-referral/index.ts:32,93-94`), so a user who confirms their email and finishes
>   onboarding more than 7 days after sign-up loses the code; Profile → Apply Referral is the
>   same EF and has the same window. Unchanged by this batch.
> - **Test repoints [R2-4], shipped scope only:** `test/sync/closeout_maintenance_test.dart:40-45`
>   (notifier `syncSavedMealsNow` pin moves to the service's bump). The others in R2-4 belong
>   to A/B2.
> - **C step 4 changed during implementation:** `pending_referral_code` STAYS in
>   `_intentionallyShared` (a documentation-only list, and devices from before c7b4d2 may still
>   hold the key, which must never be migrated into a user box); only its false "read in
>   `_ensureLocalUser`" comment is corrected. So `user_scoped_hive_keys_writer_to_reader_test`
>   and `config_to_user_migration_test` stay valid unchanged, and sync.md / naming_conventions
>   stay accurate.
> - **Bug ids:** D = `d5c2e8`, B1 = `a8e3f1`, C = `c7b4d2`.

**Branch / worktree:** `reuse-audit-fixes` · **Date:** 2026-09-26 · **Tier:** L (touches `sync/`)
**Execution mode (§4.12.7): INLINE**, decided at batch start — units share `sync_*`, the gate
allowlist and nested `CLAUDE.md` files, so a single writer avoids cross-unit edits.

**Origin.** Founder asked for a screen-wise functionality audit plus a check that common
functions are reused. Four parallel surveys produced 9 correctness candidates; each was
re-verified against source by the coordinator. 4 real + a 5th found during design (B2).
Downgraded to duplication-only (consistent logic, not bugs): sign-out guard copies (already
covered by the tree-wide `signout_unbinds_sdk_identity_test.dart`), the "date has logs" scan,
last-weight read, the Nutrition AI-call wrapper, the coach retry-row reset. Founder approved
fixing the real ones; B2 is the same saved-meals feature and a live data-loss path (§4.2).

**Live data (read-only SQL, 2026-09-26):** templates exist only for the founder (5) and
`test2` (1), all `is_active=true`; `user_saved_meals` EMPTY for every user (matches B2);
3 referral redemptions ever. No real users harmed yet.

**Round-1 review** (14 findings: 1 P0, 8 P1, 5 P2) — every finding is addressed below and tagged
`[R1-n]`. Reviewer claims re-verified by the coordinator: `user_saved_meals` has no
carbs/fat/fiber columns (`backups/live_schema_columns.json`), both unique indexes are
case-sensitive (`050b…:107`, `083…:26`), the stale gate allowlist entries exist
(`check_writeservice_only.dart:108-109`), and the D source-grep pins exist.

## Shared helper — `SyncTombstones` (used by A and B2)

New `lib/core/services/sync_tombstones.dart`. A per-user list of names deleted locally whose
cloud row may still exist. Storage: `MigratedKey` under a caller-supplied key, keys added to
`UserConfigMigrator.userScopedKeys` (`deleted_template_names`, `deleted_saved_meal_names`).
`_flagKey` is NOT bumped: neither key has a legacy `configBox` value, and
`user_config_migrator.dart:194-198` records why re-running the copy sweep is wrong. Update the
"31-key" count in `docs/architecture/sync.md:243` and
`user_scoped_hive_keys_writer_to_reader_test.dart:8` [R1-10].
- `add(key, name)` / `remove(key, name)` / `read(key)` — writes are a NO-OP when
  `HiveUserSession.currentOwnerFullId == null`, so a tombstone can never fall back into the
  shared `configBox` (cross-account) [R1-10].
- Pure: `isTombstoned(list, name)` compares `trim()` **case-exact**, the same string the push
  sends and the cloud unique index keys on [R1-11]. `planTombstoneSync(tombstones,
  localNames)` → `{toCloudRemove, toDrop}`: a name that exists locally again is dropped, never
  removed from the cloud.

## A — Deleted workout templates come back after restore

**Writers / readers (verified):** delete `TemplatesNotifier.deleteTemplate`
`train_provider.dart:2219-2235` (raw `workoutBox.delete`; no service method); rename
`TemplatesNotifier.updateTemplate` `:2186-2207` (via `upsertTemplate`); AI create
`WorkoutRepository.createTemplate` `workout_repository.dart:~1606` (raw `box.put`); push
`_syncWorkoutTemplates` `sync_workout.dart:1255-1312` (Hive `tmpl_*` only, upsert
`is_active:true` on `(user_id,name)`); restore `_restoreWorkoutTemplates` `:1446-1561`
(`.eq('is_active',true)`, rewrite + sweep); 5 restore entry points incl.
`restoreWorkoutTemplatesForSyncDomain` `:2226` [R1-14]. Nothing sets `is_active=false`.
RLS `workout_templates_update_own` exists live.

**Fix:**
1. `WorkoutWriteService.deleteTemplate({required String templateId})` → `WriteResult`: resolve
   the push identity name `(name as String?)?.trim() ?? 'Untitled'`,
   `WorkoutScheduleService.instance.cleanSyncTemplateSchedule(templateId)` (the call the notifier
   already makes [R1-14]), delete the row, `SyncTombstones.add('deleted_template_names', name)`,
   fire `syncWorkoutData()` + `pushSnapshot()`, telemetry on catch. Notifier delegates and keeps
   its invalidations.
2. `upsertTemplate`: (a) `SyncTombstones.remove(name)` for the name being saved; (b) if the Hive
   row already at `templateId` has a DIFFERENT trimmed name, `SyncTombstones.add(oldName)` —
   a rename otherwise leaves the old cloud row active and restore adds it back [R1-1].
3. `WorkoutRepository.createTemplate` (AI coach): `SyncTombstones.remove(name)` after its put [R1-1].
4. `_syncWorkoutTemplates`, after the upsert loop: `planTombstoneSync(tombstones, localNames)`;
   for each `toCloudRemove` name, `update({'is_active': false}).eq('user_id',uid).eq('name',name)`
   behind an `ownerChangedSince(userId)` guard [R1-10]; success → `remove`; error → keep +
   `_reportSyncFailure`; `toDrop` → `remove`.
5. Restore, extracted to a pure `planTemplateRestore(cloudRows, localEntries, tombstones)` →
   `{puts, deletes}` that `_restoreWorkoutTemplates` applies:
   - skip cloud rows whose name `isTombstoned` (covers delete-then-relaunch before the update lands);
   - **sweep change [R1-2]:** delete a local `tmpl_*` key only when its trim-lowercased name
     belongs to a restored cloud row (a local duplicate of that row) or is tombstoned. Local-only
     names (created offline, not yet pushed) are KEPT. Today they are swept on every sign-in
     restore — the same data-loss class, closed here. The zero-cloud-rows guard is kept.
6. Test seam: `@visibleForTesting restoreWorkoutTemplatesForTest(userId, {preFetched})`, mirroring
   `restoreScheduledWorkoutsForTest` (`sync_workout.dart:2248`). Add it to
   `sync_service_public_api_snapshot_test.dart`.
7. Gate allowlist: remove the now-dead `TemplatesNotifier:workoutBox.delete` (and `.put` if
   no longer used) from `check_writeservice_only.dart:108-109` [R1-12].

**Tests [R1-9]:**
- `test/contracts/workout_template_delete_tombstone_behavioral_test.dart` (Hive harness):
  delete removes the row and tombstones it; re-save of the same name clears it; rename
  tombstones the old name; `planTombstoneSync` removes absent names and drops recreated ones.
- `test/sync/restore_workout_templates_tombstone_test.dart` (real restore via the seam): a
  tombstoned cloud row is not restored; a local-only offline template survives restore; a local
  duplicate of a restored row is swept.
- Mutations: (m1) no tombstone in `deleteTemplate`; (m2) restore skip removed; (m3) sweep back
  to "delete every non-canonical key"; (m4) rename does not tombstone.

## B1 — Saved-meal use count never increases for modern templates

Writer (bump) `SavedMealsNotifier.relogSavedMeal` `nutrition_provider.dart:1242-1250` (legacy
path only); modern `meal_*` path calls `NutritionWriteService.relogSavedMeal`
`nutrition_write_service.dart:617-638` from `saved_meals_section.dart:216` — no bump. Readers:
sort `nutrition_provider.dart:1182-1186`, display `saved_meals_section.dart:55`, push
`sync_nutrition.dart:695`. No AI-coach caller of relog (verified R1).

**Fix:** bump inside `NutritionWriteService.relogSavedMeal` after a successful `logMeal`:
re-read the row, `times_used += 1`, `await` the put, then `unawaited(syncNutritionData())` —
the coalescer's in-flight + dirty loop guarantees a trailing pass that reads the new count [R1-13].
Remove the notifier's bump. Keep `syncSavedMealsNow` (public, pinned in the API snapshot test) [R1-13].

**Test:** `test/contracts/saved_meal_relog_times_used_behavioral_test.dart` — `meal_*` and legacy
rows each go +1 per relog; a missing key changes nothing. Mutation: delete the service bump.

## B2 — Saved meals never reach the cloud (and follow-on defects once they do)

Writer `NutritionWriteService.saveMealAsTemplate` `:641-708` (`meal_<hash>`, `is_template`,
no `is_saved_meal`) is the only live creator — `saveMealPreset` has no UI caller. Push
`_syncSavedMeals` `sync_nutrition.dart:650-713` requires `saved_meal_*` + `is_saved_meal` → never
pushes templates. Also called from the weekly full sync `sync_service.dart:1373`. Restore
`_restoreSavedMeals` `:953-1010` writes `saved_meal_<nameKey>`. Delete `deleteSavedMeal`
`:785-813` removes the Hive row only.

**Fix** (new pure `lib/core/services/sync/saved_meal_sync_rules.dart`):
1. `selectSavedMealsToPush(entries)` — pushable = legacy (`saved_meal_*` + `is_saved_meal`) OR
   template (`meal_*` + `is_template`); one row per case-exact trimmed name (first by
   `created_at`), with a `saved_meal_push_duplicate_name` telemetry event for the others [R1-4].
   `_syncSavedMeals` iterates its output (source pin that it calls it) [R1-9].
2. Name uniqueness at save: `saveMealAsTemplate` gives the new template a unique name across both
   formats via pure `uniqueSavedMealName(desired, existingNames)` → "Rice", "Rice (2)", … —
   unless the existing same-name row IS this `templateKey` (re-save of the same meal) [R1-4].
3. Delete propagation [R1-3]: `deleteSavedMeal` resolves the row's trimmed name and
   `SyncTombstones.add('deleted_saved_meal_names', name)` unless another local saved meal still has
   that name. `_syncSavedMeals` applies `planTombstoneSync`: cloud delete
   `.delete().eq('user_id',uid).eq('name',name)` (owner DELETE RLS exists) behind
   `ownerChangedSince`; success → remove tombstone.
4. Restore, pure `planSavedMealRestore(cloudRows, localEntries, tombstones)`: skip tombstoned
   names; skip names already present locally in EITHER format (otherwise every restore duplicates
   each local `meal_*` as `saved_meal_*`); fill `total_carbs/fat/fiber` from
   `NutritionReadService.totalMacrosFromItems(items)` when the cloud row lacks them — the cloud
   table has no such columns, so without this a restored meal shows 0 carbs/fat [R1-5]. No
   migration is needed.
5. Test seam `restoreSavedMealsForTest(userId, {preFetched})` + API snapshot entry.

**Tests:** `test/contracts/saved_meal_sync_rules_behavioral_test.dart` (pure: pushable set,
duplicate-name selection, unique naming, tombstone plan, restore plan incl. derived macros) +
`test/sync/restore_saved_meals_dedup_test.dart` (real restore via the seam: a local `meal_*`
blocks a same-name cloud row; a tombstoned name is not restored; carbs/fat derived).
Mutations: drop the `meal_` arm; restore ignores `meal_*` names; drop the derived-macros fill.

## C — Referral code entered at sign-up is usually lost

Writer `sign_in_screen.dart:230-255` redeems on `AuthStatus.success` from `_referralController`.
The field exists only on the sign-up step (`_buildEmailStepSignUp` `:986`, field `:1028-1066`).
With email confirmation on, sign-up yields `AuthStatus.info` (`auth_provider.dart:434-445`), and
the later sign-in is a fresh screen with an empty controller → the code is dropped.
`pending_referral_code` has no reader (`user_config_migrator.dart:101-104` claims one — false).
The correct redeem point is `OnboardingNotifier` (`onboarding_provider.dart:612-617,705-728`,
after the `users` upsert).

**Fix [R1-6] — carry the code in auth user metadata (survives devices and the confirm link):**
1. `AuthNotifier.signUpWithEmail(..., String? referralCode)` passes
   `data: {'referral_code': code}` to `auth.signUp` when non-empty. The sign-up button passes
   the trimmed field value.
2. Remove the success-listener redeem block and its `pending_referral_code` writes.
3. Onboarding: `referralCode = resolveReferralCode(stash, currentUser?.userMetadata)` — the
   stash (Welcome screen) wins, else `userMetadata['referral_code']`. Redeem path unchanged.
   Replay is bounded: `completeOnboarding` already refuses to run twice for an onboarded user,
   and the EF rejects a second redemption per referee.
4. `pending_referral_code` loses its only writer: remove it from `_intentionallyShared`, fix that
   comment block and `docs/naming_conventions.md:75` / `docs/architecture/sync.md:243`.

**Test:** `test/contracts/referral_signup_metadata_behavioral_test.dart` — pure
`resolveReferralCode` (stash wins; metadata fallback; blank/whitespace → empty; non-string
metadata ignored) + source pins: `signUpWithEmail` passes `referral_code` in `data`; the
sign-in listener contains no `redeem-referral`. Mutations: fallback ignores metadata; stash
priority inverted.

## D — Custom-exercise creation bypasses its writer

Bypass `create_custom_exercise_sheet.dart:275-304` (raw `customBox.put` + manual sync, pops and
calls `onCreated` unconditionally). Skips `WorkoutRepository.createCustomExercise`
(`workout_repository.dart:1357-1437`: duplicate-name guard, 60-char cap, equipment normalise,
`created_at`) and `WorkoutWriteService.upsertCustomExercise` (lock, `source`/`updated_at`
stamps, telemetry). The edit path (`:254`) is correct.

**Fix:**
1. The create path calls `WorkoutRepository.instance.createCustomExercise(...)`. Signature: 
   `defaultReps` → `String?` (the sheet accepts "8-12"); `equipment` → optional (`null` ⇒
   `equipment_needed: []`, today's sheet behaviour). Callers updated: `tool_dispatcher.dart:566`
   (`?.toInt().toString()`), `custom_exercises_mutations_behavioral_test.dart:100` (`'8'`) [R1-8].
2. `createCustomExercise` stops ignoring the `WriteResult`: `!success` → throws
   `CreateCustomExerciseException('write_failed', …)` [R1-8].
3. Sheet: on `CreateCustomExerciseException`, show its message and keep the sheet open; on
   success read the row back via `ExerciseRepository.instance.getCustomExercises()` by id and
   pass it to `onCreated` (null ⇒ same error snackbar). Add `maxLength: 60` to the name field [R1-8].
4. Repoint source-grep pins at the repository, never delete them [R1-7]:
   `custom_exercise_writer_to_reader_test.dart:39-90`, `custom_picker_capability_wiring_test.dart:86,106-109`
   (the "`approved_for_library` stamped in exactly ONE place" assertion moves to the repository
   file; the sheet must now contain zero), plus comments in `can_offer_in_picker_behavioral_test.dart:8-18`.

**Test:** extend `custom_exercises_mutations_behavioral_test.dart`: "8-12" round-trips; null
equipment ⇒ `[]`; row carries `source` + `created_at`; a failed write throws. Source pin: the
sheet's create branch calls `createCustomExercise` and has no `customBox.put`. Mutation: restore
the raw put (pin red); drop the `WriteResult` check (throw test red).

---

## Docs + registry (same commits)
- `lib/features/train/CLAUDE.md:60` (`workout_templates` writers: `upsertTemplate` / `deleteTemplate`
  + tombstone) and the `custom_exercises_mutations` row (create via the repository).
- `lib/features/nutrition/CLAUDE.md` `saved_meals` row (both formats, push/restore rules, bump owner,
  delete tombstone).
- `docs/sot_registry.yaml`: extend the EXISTING concepts `workout_templates`, `saved_meals`,
  `custom_exercises_mutations`, `referral_redemption` with the new `behavioral_test_path`s — no
  new concept, so Gate 9's filename rule is unaffected [R1-14].
- 5 diagnose-docs `docs/diagnoses/2026-09-26-*` + `docs/audit/reuse-audit-fixes.closure.yaml`.

## Verification
`flutter analyze lib/`, targeted tests, full pre-commit gate loop, one mutation per protection
(counts recorded in each diagnose-doc), B-pass before merge. Device check owed to founder:
delete a template → relaunch → still gone; save a meal as template → check `user_saved_meals`.

## Residuals (stated, not deferred)
- A cloud pair differing only in case ("Push"/"push") already collides locally (the restore key
  lowercases). The tombstone removes the exact-case row only. No such pair exists live (verified
  2026-09-26); unchanged by this batch.
