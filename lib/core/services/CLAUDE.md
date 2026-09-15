---
scope: core_services
parent: ../../../CLAUDE.md
created: 2026-05-18
updated: 2026-08-30
status: active
---

# Core Services — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/core/services/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

## What lives here

`lib/core/services/` is the **service layer between widgets and storage**. Every
write to Hive that participates in cloud sync goes through a *WriteService*
class (`WorkoutWriteService`, `NutritionWriteService`, `HealthWriteService`,
`ProfileWriteService`, `WaterTargetService`, etc.). Every read with a public
domain contract goes through a *ReadService* (`WorkoutReadService`,
`NutritionReadService`, `HealthReadService`). Widgets and Riverpod providers
**must never call `Hive.box(...)` directly** — the WriteService wires
provider invalidation + sync fan-out + telemetry as one atomic unit.

Also in this directory:

- `sync_service.dart` + `sync/sync_*.dart` — orchestrator + per-domain sync extensions.
- `hive_service.dart` — boot, lifecycle compaction, user-session swap.
- `hive_user_session.dart` — cross-account ownership lock (`auth_hive_owner_agreement`).
- `auth_session_bootstrapper.dart` — post-auth decision tree owner.
- `subscription_service.dart` — entitlement. **Three entry points, and the difference matters
  (OI-44 Unit 6, diagnose `a9c4e1`):** `isPro()` is the DECISION path — it enforces the
  invariants (cross-account guard + expiry downgrade) and then reports, so it may WRITE;
  `proStateSnapshot()` is the PURE read and is **required in every Riverpod build method**;
  `evaluateEntitlement()` enforces without asking, and is called at boot
  (`splash_screen.dart:220`) and on account swap (`_onUserChanged`). Calling `isPro()` from a
  provider build made that provider invalidate ITSELF (build → `isPro` → `_downgradeLocally` →
  `onStateChanged` → `app.dart:47` `ref.invalidate(subscriptionInfoProvider)`). Gating goes
  through `gateAndVerify()` (returns `Future<void>` so the decision is awaitable — `gate()`
  survives as a `@Deprecated` shim). Kill-switch `disable_cqrs_pure_pro_read`; gate
  `scripts/check_cqrs_query_naming.dart` blocks a `get*`/`is*`/`has*`/`calculate*` member that
  mutates.
- `error_telemetry.dart` — `recordNonFatal` (the helper every catch block must use).
- `usage_counter_service.dart` — increment-at-API-call counters (post Test #11).
- Migrators: `exlog_key_migrator.dart`, `nlog_key_migrator.dart`, `hive_field_rename_migrator.dart`, `user_config_migrator.dart`, `body_fat_default_healer.dart` (Unit 4 c3f2d8 — nulls a legacy fabricated onboarding body-fat `18.0` where `body_fat_percent==18.0 && body_fat_assessed_at==null`; clears the CLOUD column FIRST under a fresh token, THEN local, so the omit-null profile sync + re-hydrating restore can't silently revert it; idempotent, kill-switch `disable_bodyfat_heal`; wired in `auth_provider._ensureLocalUser` after the cross-account guard), etc.

## Single-source-of-truth contracts

Every WriteService here is the canonical writer for at least one SoT-registry
concept. Selected mappings (full list in `docs/sot_registry.yaml`):

| Concept | Writer (this dir) | Reader entry point |
|---|---|---|
| `exercise_logs_read_path` / `workout_receipt_rendering` | `workout_write_service.dart` `logExercise` | `workout_read_service.dart` `exerciseLogsForIstDate` |
| `nutrition_total_calories` / `food_log_delete_with_undo` | `nutrition_write_service.dart` `logMeal` / `deleteLog(allowUndo:)` (audit-fixwave F12 — was mis-named `deleteWithUndo`) | `nutrition_read_service.dart` |
| `health_write_service` | `health_write_service.dart` (6 methods — water / weight / sleep / steps / mood / energy) | `health_read_service.dart` |
| `subscription_state` / `subscription_payment_grace_window` | `subscription_service.dart` `setPro` + Razorpay webhook handlers | `subscriptionInfoProvider`, `gate()` |
| `water_target` | `water_target_service.dart` | `waterTargetProvider` |
| `error_telemetry_helper` | `error_telemetry.dart` `recordNonFatal` | every catch block app-wide |
| `sync_fanout_workout_domain` / `sync_fanout_nutrition_domain` | `sync/sync_workout.dart` / `sync/sync_nutrition.dart` | callers fire `unawaited(syncWorkoutData())` after a mutation |
| `restore_completeness` | `sync_service.dart` `restoreFromCloud` | `restoring_screen.dart` |
| `user_scoped_hive_keys` / `hive_deletion_and_session_helpers` | `hive_user_session.dart` + `hive_service.dart` | `wrapUserScopedBox` (helper used everywhere) |
| `auth_hive_owner_agreement` | `hive_user_session.dart` + `wrapUserScopedBox` | every WriteService + every Hive-touching Riverpod provider |
| `day_rollover_provider_invalidation` | `day_rollover_service.dart` | `splash_screen` + `home_screen` mount |
| `singleton_lifecycle_registry` | `singleton_lifecycle_registry.dart` | hot-restart cleanup |
| `rank_monotonic_current_code` | `rank_service.dart` `evaluateAndPromote` (guarded by `shouldPromote(currentCode, qualified)` helper — monotonic-only writer; same pattern mirrored in `evaluate-rank-promotions` Edge Function cron) | `rank_service.dart` `getCurrentRank` (Hive `userBox['profile']`) → Profile rank chip + Home pending promotion |

The WriteService pattern enforces three steps every write:

1. **Write to Hive first** (via `wrapUserScopedBox`).
2. **Invalidate the registered provider set** (see `provider_invalidation_set` in `docs/sot_registry.yaml`).
3. **Fire-and-forget `unawaited(syncDomain())`** — never block the UI on cloud.

Failures from step 3 are captured by `ErrorTelemetry.recordNonFatal` with an
`op_type` from `op_types_canonical.dart`; the catch block never bubbles up to
the user. Every WriteService method returns a `WriteResult` so the caller can
distinguish "Hive succeeded" from "cloud succeeded".

**Sync fan-out is COALESCED (Unit H, 2026-06-27).** `syncWorkoutData()` /
`syncNutritionData()` / `pushSnapshot()` are fire-and-forget *coalesced* entries
(in-flight + dirty do-while via `SyncCoalescer`): a burst of per-write calls
collapses to 1–2 cloud passes (a fresh signup was ~90 cloud calls; a returning
login ~190 → a handful — the free-tier-collapse fix, diagnoses c4f8d2 / b4f7e2 /
e7c1a9). Two rules this imposes on callers:
- **Awaited / durability-critical callers MUST call the non-coalesced `*Now()`
  variant** (`syncWorkoutDataNow` / `syncNutritionDataNow` / `pushSnapshotNow`) —
  a coalesced call may only set `_dirty` and return, so awaiting it does NOT
  guarantee the cloud write happened this tick. Current `*Now()` callers: the
  resync migrator, the sim harness, `checkAndSync` (next-login backstop),
  onboarding first-context, `coach_memory_service` (freshly-extracted notes).
- **All three coalescers are reassigned in `_onUserChanged`** — an owed trailing
  pass under a new owner would cross accounts (esp. `pushSnapshot`'s `coach_memory`
  mirror into `coachBox`). Each path is kill-switched (`disable_sync_debounce` /
  `disable_sched_hash_skip` / `disable_snapshot_debounce`) to verbatim pre-Unit-H
  behavior. `_syncScheduledWorkouts` additionally skips an unchanged *planned*
  row via a sync-owned fingerprint index — but NEVER a `completed` row (d9b2c5).

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Hive box not open | Open ALL boxes in main.dart before runApp(). | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Adapter not registered | Register ALL Hive adapters before openBox(). | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Hive file bloat over time | `HiveService` implements `WidgetsBindingObserver` and runs `box.compact()` on **8** mutation-heavy boxes (user / workout / nutrition / health / custom / coach / sync / notifications) every 7 days on `AppLifecycleState.paused`. Gated via `configBox['last_compact_at']`. Per-box + global telemetry via `ErrorTelemetry.recordNonFatal` (reasons `hive_service_maybe_compact_box` / `hive_service_maybe_compact`). User-scoped box switch is race-safe via `HiveUserSession._sessionLock` + `Hive.isBoxOpen()` guard. Verified GREEN by audit 2026-05-17 / OI-17. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Force-unwrap `!` on map keys or `.first` on possibly-empty lists | Null-safe the map read (`(m['k'] as num?)?.toDouble() ?? 0.0`) and always guard `.first` with `isNotEmpty`. Closed 2026-04-24 (PR-FIX-2) in macros maps (home_provider + nutrition_provider), `exercise_type.first` (3 files), `sentences.last`, `options.keys.first`, `diet_plan_screen` shuffle result, `todayDay!` in train_screen. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Hive `path_provider` MissingPluginException in unit tests | `HiveService.init()` calls `Hive.initFlutter()` which uses `getApplicationDocumentsDirectory` from path_provider — fails in pure unit tests with `MissingPluginException(No implementation found for method getApplicationDocumentsDirectory on channel plugins.flutter.io/path_provider)`. Fix in tests that need Hive boxes (e.g., `test/ai_coach/meals_today_snapshot_test.dart`): add `TestWidgetsFlutterBinding.ensureInitialized()` + mock the channel via `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel('plugins.flutter.io/path_provider'), (call) async => tempDir.path)` BEFORE calling `Hive.init(tempDir.path)` and `HiveService.instance.init()`. Required pattern for any Hive-touching unit test. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Increment a usage counter at save time | Counters MUST increment at the API-call site, not at the save site. Pre-Test-#11 free-tier users saw "50 remaining" while the Postgres trigger had counted every Edge Function call. Counter callsites: `food_logger_section._analyse`, `ScanMealNotifier.scanImage`, `cart_auditor_section.analyseCart`, `tool_dispatcher._executeLogMealByText`. | (relocated 2026-05-18 — see `lib/features/nutrition/CLAUDE.md`) |
| Restore writer keyed differently from production writer | Test #12.8 root cause — 6 of 16 `_restoreXxx` methods used legacy keys. Always test restore→read round-trip in `test/sync/restore_completeness_test.dart`. | `feedback_writer_reader_field_drift_recurring.md` |
| Cloud→Hive restore merge lowers a monotonic field | A `progress`/profile-map restore that spreads the cloud row over the local one (`{...local, for (e in cloud.entries) if (e.value != null) e.key: e.value}`) is cloud-wins for EVERY key — it silently demotes any field the local device advanced and has not yet pushed. Route the `progress` map through `UserRepository.mergeCloudProgress`, which is local-max-wins on exactly `current_phase` / `deployments_complete` / `total_workouts_done` and cloud-non-null-wins on the rest, and emit the refusal via `reportProgressDemotionsDeclined`. ⚠ Pick the set by asking *which direction is bad*, not by whether it sounds like a lifetime counter: `longest_gap_days` was on this list until round-1 review caught that higher is WORSE for it and it gates a rank, so max-wins could only refuse a server correction. Kill-switch `disable_progress_restore_monotonic_merge`. ⚠ The guard belongs to the field, not to the operation: `commitPhaseAdvance` had guarded the ADVANCE path since `c8f3d1` and the RESTORE path still demoted, because no restore writer calls it. Diagnose `d1f6b3` / OI-83. | `feedback_monotonic_field_recompute_demotion.md` |
| Writer unconditionally overwrites a "lifetime / peak / earned" field with a recomputed current-state value | Lifetime monotonic fields (rank, lifetime workout count, longest streak, peak weight, deployments_complete, badge unlock state) MUST have an only-increment writer guard. Pattern: extract pure helper (`shouldPromote(...)`-style) for behavioral test coverage; mirror to every parallel writer (client + every server cron). Diagnose 3a7b9f (2026-05-27): rank demoted SD1 → SD2 after streak loss + weekly-recalc total_workouts_done overwrite. Debugging skill section 2.19. | `feedback_monotonic_field_recompute_demotion.md` |
| Restore skips `plan_json` when a local plan already exists | `_restoreWorkoutPlan` must NOT early-return on `current_plan != null`. Apply the cloud `plan_json` snapshot (plan_start_date + date-keyed schedules WITH exercises) authoritatively via the shared `PlanIntegrityReconciler.mergeScheduleEntry` (completed-day-preserving). A reinstall regenerates a plan locally before/around restore → the skip dropped every planned day's exercises (cloud `scheduled_workouts` has NO exercises/name column to rehydrate from) + left plan_start stale → "REST DAY / No exercises scheduled" everywhere + an inflated week number. Boot heal `PlanIntegrityReconciler` (symptom-gated via `needsHeal`, kill-switch `disable_plan_integrity_reconciler`) re-applies on next sign-in for already-broken installs. Diagnose a7d3f1. | `feedback_writer_reader_field_drift_recurring.md` |
| A sparse map is written into a jsonb COLUMN with a plain upsert | A partial upsert protects sibling COLUMNS; it does nothing for the contents of one jsonb column — PostgREST emits `SET col = EXCLUDED.col`, which is assignment, not a merge. If the writer can ever hold FEWER keys than the store, a wholesale write is a DELETION. `notification_preferences` hit this twice: once inside `snapshot_json`, then again in the dedicated column it was moved to as the fix. The stored map is legitimately sparse — the settings screen seeds from `read()` (`{}` on a fresh device) and each toggle adds ONE key — so device A storing `{streak_alerts:false}` and device B storing `{weekly_recap:false}` each deleted the other's key. Write per-key additively instead: migration 123's `merge_notification_preferences` RPC (`jsonb ||`, SECURITY INVOKER, keyed on `auth.uid()`). Do NOT pad the client map to the full key set — that fabricates values the user never chose, the same bug pointing the other way. Diagnose `e4a1b7` / OI-98. | `feedback_mistake_guard_without_its_mirror.md` (#17), debugging skill 2.51 |
| Restore overwrites a local row the user just logged | A loss-sensitive `_restoreXxx` that writes a LOG row (exlog/wlog/nutrition log/saved meal) MUST be **additive / local-wins**: `if (box.get(key) != null) continue;` — only fill gaps, never overwrite. Once the **background restore** runs concurrently with the user logging on /home (slow-boot guard, `disable_bg_restore` opt-out, c5a1f2), an unconditional `put` of the stale cloud row over a just-logged local row is a data-loss (TRUE loss if the local write hadn't synced — a network blip). Reference pattern: weight (`sync_health.dart:300`). `_restoreScheduledWorkouts` instead **timestamp-merges** (schedule status needs cloud↔local reconciliation, d9b2c5) — additive vs merge is per-writer. ADR: offline-first local-wins (a 2nd-device edit won't overwrite the local copy). | `restore_local_wins_additive_test.dart`, diagnose c5a1f2 |
| A restore-path Supabase SELECT with no retry silently drops a field on a stale post-redirect token | A query returning empty (HTTP 200, `null`) is indistinguishable from "no such row" — the SAME ambiguity diagnose `c2e9f4` fixed for `resolveDestination`'s `user_profile` SELECT, recurring in `_restoreUserProfile`'s `users` SELECT (full_name/email) because the fix was never generalized past its first call site. Confirmed live on 2 accounts via the `profile_full_name_empty_at_read` probe: `hasProfile=true`, `rawName=<null>` — the rest of the restore succeeds, only the ambiguous field vanishes. Fix pattern: `ensureFreshToken()` proactively, then on a `null`/empty result retry ONCE behind a hard `auth.refreshSession()` before accepting it as genuinely absent — never accept the first empty result as authoritative for a query this early in the session. ⚠ **The retry only protects the code path that actually RUNS the query.** If the same read can also arrive PRE-FETCHED (e.g. `_restoreUserProfile`'s `preFetchedUsers` param, fed by the C3 single-call restore's bundle), a null pre-fetched value bypasses the retry helper entirely — check whether the pre-fetch source shares the same stale-token exposure (an EF using a service-role client does not) before assuming the fix's coverage is universal; if it doesn't, at minimum log the injected-null case distinctly (B-pass finding 1) so a real gap isn't silent. Diagnose `d4e9a2`. | `test/contracts/restore_users_row_retry_test.dart` |

## Tests pinning the rules here

- `test/contracts/auth_hive_owner_agreement_behavioral_test.dart` — Layer A+B cross-account guard.
- `test/sync/restore_completeness_test.dart` — every `_restoreXxx` round-trips.
  > ⚠ **Path corrected 2026-08-03 (Unit A).** This line read
  > `test/contracts/restore_completeness_test.dart`, which does not exist — same
  > phantom-citation class as the `check_writer_reader_drift.dart` entry
  > `lib/CLAUDE.md` corrected in Unit 6. The real files are
  > `test/sync/restore_completeness_test.dart`,
  > `test/contracts/restore_completeness_writes_test.dart` and
  > `test/contracts/restore_local_wins_additive_test.dart`.
- `test/contracts/progress_restore_monotonic_behavioral_test.dart` — the cloud→Hive
  `progress` merge is local-max-wins on the 3 monotonic fields (d1f6b3 / OI-83).
- `test/contracts/sync_fanout_workout_domain_writer_to_reader_test.dart` (+ nutrition).
- `test/contracts/error_telemetry_helper_writer_to_reader_test.dart`.
- `test/contracts/health_write_service_writer_to_reader_test.dart`.
- `test/contracts/workout_write_service_*_test.dart` (multiple — exercise log, schedule, templates).
- `test/contracts/nutrition_write_service_*_test.dart`.
- `test/contracts/subscription_state_*_test.dart`.

## See also

- `lib/CLAUDE.md` — cross-feature rules.
- `docs/architecture/sync.md` — sync schedule + restore-completeness + Hive field-name contracts.
- `docs/sot_registry.yaml` — full SoT registry.
