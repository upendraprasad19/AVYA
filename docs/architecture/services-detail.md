# Core Services - moved-out detail

On-demand detail for `lib/core/services/CLAUDE.md`. Everything here was moved VERBATIM out of the nested file, except sections marked "Added" (written for this file) (dated incident narratives, `Corrected <date>` histories, per-batch provenance, long pitfall bodies, audit results) to keep the auto-loaded file lean. The nested file keeps the current rule for each item and points here.

## subscription_service.dart bullet (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 31-42, context-lean batch 2026-09-29)._

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

## Migrators bullet (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 45-45, context-lean batch 2026-09-29)._

- Migrators: `exlog_key_migrator.dart`, `nlog_key_migrator.dart`, `hive_field_rename_migrator.dart`, `user_config_migrator.dart`, `body_fat_default_healer.dart` (Unit 4 c3f2d8 — nulls a legacy fabricated onboarding body-fat `18.0` where `body_fat_percent==18.0 && body_fat_assessed_at==null`; clears the CLOUD column FIRST under a fresh token, THEN local, so the omit-null profile sync + re-hydrating restore can't silently revert it; idempotent, kill-switch `disable_bodyfat_heal`; wired in `auth_provider._ensureLocalUser` after the cross-account guard), etc.

## SoT row: exercise_logs_read_path / workout_receipt_rendering (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 54-54, context-lean batch 2026-09-29)._

| Concept | Writer (this dir) | Reader entry point |
|---|---|---|

| `exercise_logs_read_path` / `workout_receipt_rendering` | `workout_write_service.dart` `logExercise` — the top-level `reps_completed`/`weight_kg`/`volume_kg` aggregate fields MUST be computed from `cleanedSets` (post logging-type normalization), never `mergedSets` (raw pre-normalization input) — fixed 2026-09-28 (bug e8f95e) after a phantom pre-strip value leaked into the aggregate while `sets[]` itself already correctly showed the normalized (stripped) values, producing a "reps_completed == duration_seconds" duplication visible in the cloud table | `workout_read_service.dart` `exerciseLogsForIstDate` |

## SoT row: day_rollover_provider_invalidation (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 66-66, context-lean batch 2026-09-29)._

| Concept | Writer (this dir) | Reader entry point |
|---|---|---|

| `day_rollover_provider_invalidation` | `day_rollover_service.dart` — three triggers: cold-launch (`runRolloverNow`), resume (`didChangeAppLifecycleState`), and (since 2026-09-28) a foreground midnight `Timer` backstop (`_scheduleMidnightTimer`/`_onMidnightTimerFired`) for a session that never backgrounds across midnight | `splash_screen` + `home_screen` mount. The ~27-provider invalidation list itself is a common miss-site for a NEW daily-scoped provider — `streakFreezeProvider`, `weeklyNutritionProvider`, `weeklyReportDataProvider`, `referralEligibilityProvider` and `usageWeeksProvider` were ALL absent entirely until bugs 9c8958/bae4dd/b1bfea/4018b3/ff3131 (2026-09-28, the last two found by an independent plan-review round's own audit from a different starting angle — every `DateTime.now()`-computing provider under `lib/features/*/providers/`). `weeklyReportDataProvider`'s case is worse than the other four: it had NO invalidation anywhere at all (not just here) before the fix — its write-time leg (invalidate on a new weight/meal/workout log, across 3 domains' 15+ raw call sites) remains open on OI-267. `referralEligibilityProvider`/`usageWeeksProvider` are `presence_only: true` in their diagnose-docs — both derive from `SupabaseService.instance.currentUser.createdAt` (real auth, no Hive-mutable proxy, no test seam), so only a mutation-proven source-grep protects them, not a behavioral test. |

## SoT row: rank_monotonic_current_code (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 68-68, context-lean batch 2026-09-29)._

| Concept | Writer (this dir) | Reader entry point |
|---|---|---|

| `rank_monotonic_current_code` | `rank_service.dart` `evaluateAndPromote` (guarded by `shouldPromote(currentCode, qualified)` helper — monotonic-only writer; same pattern mirrored in `evaluate-rank-promotions` Edge Function cron) | `rank_service.dart` `getCurrentRank` (Hive `userBox['profile']`) → Profile rank chip + Home pending promotion. Also `ai_snapshot_builder.dart` `_getCurrentRankFromLadder`/`_getNextRankFromLadder` (OI-230/231, 2026-09-22 — now routes through `getCurrentRank()` instead of duplicating its Hive read) → AI coach snapshot `current_rank`/`next_rank`. |

## SoT row: day_swap_engine (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 69-69, context-lean batch 2026-09-29)._

| Concept | Writer (this dir) | Reader entry point |
|---|---|---|

| `day_swap_engine` | `swap_service.dart` `SwapService.swapDays` — the ONE entry point for Train drag, Train ⇅, Home long-press and the coach; every check re-runs at confirm time under `WorkoutWriteService.swapScheduledDays`'s two-date lock, and the whole swap (allowance check → write → `recordSwap`) runs under `SwapService._withWeekLock`, one lock per IST Mon–Sun week, so two concurrent swaps on DIFFERENT pairs of one week cannot both pass "not spent" (B-pass R2-F2, diagnose `e2b9d4`). A swap is counted only after its write succeeds. | `day_swap_provider.dart` (`daySwapWeekProvider`, `daySwapAllowanceProvider`), `SwapPickerSheet`, `DaySwapRowTrailing`. |

## Sync fan-out is COALESCED (Unit H) (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 85-107, context-lean batch 2026-09-29)._

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
  behavior. `_syncScheduledWorkouts` additionally skips an unchanged row via the
  shared `SyncSkipIndex` (domain `sched`, day-swapper + sync-load Task 15). ⚠ Since
  Task 15 that includes `completed` rows — the d9b2c5 "never skip a completed row"
  carve-out (A-fix-1) is deliberately SUPERSEDED, because the server-side
  completed-day guard (migration 149) now refuses a stale overwrite of a completed
  row. That makes migration 149 a HARD prerequisite: it must be applied live
  before any build carrying Task 15 ships.

## SyncSkipIndex paragraph (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 109-120, context-lean batch 2026-09-29)._

**`SyncSkipIndex` is the ONLY way a sync history step may skip a push** — Gate G1
(`scripts/check_sync_hash_skip_atomicity.dart`) statically fails any `.upsert(`/`.insert(`
inside a Hive-row loop in `lib/core/services/sync/**`/`sync_service.dart` that does not sit
inside a `pushIfChanged(` closure, and fails any `*_payload_hash_index` literal written outside
`sync_skip_index.dart` itself. `SyncSkipIndex` reports a push failure to `ErrorTelemetry` once
per DISTINCT `opType` per pass (Task 17 fix, F1 round 2) — a shared index like `customItem`
(one index, two underlying tables) can see two different `opType` overrides fail in one pass and
both surface, while a single-opType domain still reports exactly once. `SyncSkipIndex.clearAll`
(the `sync_epoch` repair lever, sync.md's 'Sync skip pattern' point 5) returns a `ClearAllResult`, not a bare count —
`allSucceeded` (`failed == 0`) is the ONLY field `_applySyncEpochFromRestoreRow` checks before
advancing `workoutBox['sync_epoch_seen']` (diagnose `a9d3f6`): a bare `cleared` count cannot tell
"nothing to clear" from "clearing failed" apart, since both leave a domain out of `cleared`.

## Re-audited clean 2026-09-21 (A3-follow) (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 131-142, context-lean batch 2026-09-29)._

**Re-audited clean 2026-09-21 (A3-follow, observation-batch-and-digest-redesign).**
Grepped every `unawaited(SyncService.instance.<sync|push>...)`-shaped call site
across the whole `lib/` tree (~50+, spanning every WriteService plus screens/
providers added after Unit H landed — e.g. `deload_evaluator.dart`, 2026-07-17):
100% call the coalesced entry (`syncWorkoutData()` / `syncNutritionData()` /
`pushSnapshot()`), none call a raw `*Now()` directly. The 5 raw `*Now()` call
sites found match this doc's documented exception list exactly — resync
migrator, sim harness (×2), onboarding first-context (`pushSnapshotNow()`,
`onboarding_provider.dart:701`, fires once per completion not in a loop),
`coach_memory_service`, and `checkAndSync` (`pushSnapshotNow()`,
`sync_service.dart:1110`) — no undocumented bypass reintroduced the pre-Unit-H
flood. No fix needed; no diagnose-doc per rule 22 (nothing was broken).

## Pitfall: Hive file bloat (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 150-150, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| Hive file bloat over time | `HiveService` implements `WidgetsBindingObserver` and runs `box.compact()` on **8** mutation-heavy boxes (user / workout / nutrition / health / custom / coach / sync / notifications) every 7 days on `AppLifecycleState.paused`. Gated via `configBox['last_compact_at']`. Per-box + global telemetry via `ErrorTelemetry.recordNonFatal` (reasons `hive_service_maybe_compact_box` / `hive_service_maybe_compact`). User-scoped box switch is race-safe via `HiveUserSession._sessionLock` + `Hive.isBoxOpen()` guard. Verified GREEN by audit 2026-05-17 / OI-17. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Pitfall: force-unwrap on map keys (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 151-151, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| Force-unwrap `!` on map keys or `.first` on possibly-empty lists | Null-safe the map read (`(m['k'] as num?)?.toDouble() ?? 0.0`) and always guard `.first` with `isNotEmpty`. Closed 2026-04-24 (PR-FIX-2) in macros maps (home_provider + nutrition_provider), `exercise_type.first` (3 files), `sentences.last`, `options.keys.first`, `diet_plan_screen` shuffle result, `todayDay!` in train_screen. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Pitfall: Hive path_provider MissingPluginException (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 152-152, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| Hive `path_provider` MissingPluginException in unit tests | `HiveService.init()` calls `Hive.initFlutter()` which uses `getApplicationDocumentsDirectory` from path_provider — fails in pure unit tests with `MissingPluginException(No implementation found for method getApplicationDocumentsDirectory on channel plugins.flutter.io/path_provider)`. Fix in tests that need Hive boxes (e.g., `test/ai_coach/meals_today_snapshot_test.dart`): add `TestWidgetsFlutterBinding.ensureInitialized()` + mock the channel via `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel('plugins.flutter.io/path_provider'), (call) async => tempDir.path)` BEFORE calling `Hive.init(tempDir.path)` and `HiveService.instance.init()`. Required pattern for any Hive-touching unit test. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Pitfall: restore merge lowers a monotonic field (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 155-155, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| Cloud→Hive restore merge lowers a monotonic field | A `progress`/profile-map restore that spreads the cloud row over the local one (`{...local, for (e in cloud.entries) if (e.value != null) e.key: e.value}`) is cloud-wins for EVERY key — it silently demotes any field the local device advanced and has not yet pushed. Route the `progress` map through `UserRepository.mergeCloudProgress`, which is local-max-wins on exactly `current_phase` / `deployments_complete` / `total_workouts_done` and cloud-non-null-wins on the rest, and emit the refusal via `reportProgressDemotionsDeclined`. ⚠ Pick the set by asking *which direction is bad*, not by whether it sounds like a lifetime counter: `longest_gap_days` was on this list until round-1 review caught that higher is WORSE for it and it gates a rank, so max-wins could only refuse a server correction. Kill-switch `disable_progress_restore_monotonic_merge`. ⚠ The guard belongs to the field, not to the operation: `commitPhaseAdvance` had guarded the ADVANCE path since `c8f3d1` and the RESTORE path still demoted, because no restore writer calls it. Diagnose `d1f6b3` / OI-83. | `feedback_monotonic_field_recompute_demotion.md` |

## Pitfall: overwrite of a lifetime/peak field (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 156-156, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| Writer unconditionally overwrites a "lifetime / peak / earned" field with a recomputed current-state value | Lifetime monotonic fields (rank, lifetime workout count, longest streak, peak weight, deployments_complete, badge unlock state) MUST have an only-increment writer guard. Pattern: extract pure helper (`shouldPromote(...)`-style) for behavioral test coverage; mirror to every parallel writer (client + every server cron). Diagnose 3a7b9f (2026-05-27): rank demoted SD1 → SD2 after streak loss + weekly-recalc total_workouts_done overwrite. Debugging skill section 2.19. | `feedback_monotonic_field_recompute_demotion.md` |

## Pitfall: restore skips plan_json (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 157-157, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| Restore skips `plan_json` when a local plan already exists | `_restoreWorkoutPlan` must NOT early-return on `current_plan != null`. Apply the cloud `plan_json` snapshot (plan_start_date + date-keyed schedules WITH exercises) authoritatively via the shared `PlanIntegrityReconciler.mergeScheduleEntry` (completed-day-preserving). A reinstall regenerates a plan locally before/around restore → the skip dropped every planned day's exercises (cloud `scheduled_workouts` has NO exercises/name column to rehydrate from) + left plan_start stale → "REST DAY / No exercises scheduled" everywhere + an inflated week number. Boot heal `PlanIntegrityReconciler` (symptom-gated via `needsHeal`, kill-switch `disable_plan_integrity_reconciler`) re-applies on next sign-in for already-broken installs. Diagnose a7d3f1. | `feedback_writer_reader_field_drift_recurring.md` |

## Pitfall: sparse map into a jsonb column (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 158-158, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| A sparse map is written into a jsonb COLUMN with a plain upsert | A partial upsert protects sibling COLUMNS; it does nothing for the contents of one jsonb column — PostgREST emits `SET col = EXCLUDED.col`, which is assignment, not a merge. If the writer can ever hold FEWER keys than the store, a wholesale write is a DELETION. `notification_preferences` hit this twice: once inside `snapshot_json`, then again in the dedicated column it was moved to as the fix. The stored map is legitimately sparse — the settings screen seeds from `read()` (`{}` on a fresh device) and each toggle adds ONE key — so device A storing `{streak_alerts:false}` and device B storing `{weekly_recap:false}` each deleted the other's key. Write per-key additively instead: migration 123's `merge_notification_preferences` RPC (`jsonb ||`, SECURITY INVOKER, keyed on `auth.uid()`). Do NOT pad the client map to the full key set — that fabricates values the user never chose, the same bug pointing the other way. Diagnose `e4a1b7` / OI-98. **3rd instance (2026-09-21), on a DIFFERENT column with MULTIPLE independent writer processes rather than one client with two code paths:** `user_daily_snapshots.snapshot_json` is written by both the client's `daily-snapshot` Edge Function push AND several cron EFs that each own specific keys (e.g. rolling-context owns `fitness_summary`) — the client's wholesale-replace upsert clobbered whichever cron-owned key had most recently written. Fixed with a shared `mergeSnapshotJson` helper (`supabase/functions/_shared/snapshot_merge.ts`, read-modify-write against the existing row, kill-switched) applied inside `daily-snapshot/index.ts` — the RPC-merge pattern above doesn't generalize here because there is no single client-owned key to move to a dedicated column; the column is inherently multi-writer. A code-review pass on the fix then caught that the CLIENT's own push payload independently re-asserted `fitness_summary` too (via `AiSnapshotBuilder.buildAiContext()`, shared with the live chat request body), which would have kept winning the now-safe merge on a stale mirror — stripped in `SyncService.compileDailySnapshot()`. Diagnose `d8a2f6`, debugging skill 2.71. | `feedback_mistake_guard_without_its_mirror.md` (#17), debugging skill 2.51, 2.71 |

## Pitfall: restore overwrites a just-logged local row (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 159-159, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| Restore overwrites a local row the user just logged | A loss-sensitive `_restoreXxx` that writes a LOG row (exlog/wlog/nutrition log/saved meal) MUST be **additive / local-wins**: `if (box.get(key) != null) continue;` — only fill gaps, never overwrite. Once the **background restore** runs concurrently with the user logging on /home (slow-boot guard, `disable_bg_restore` opt-out, c5a1f2), an unconditional `put` of the stale cloud row over a just-logged local row is a data-loss (TRUE loss if the local write hadn't synced — a network blip). Reference pattern: weight (`sync_health.dart:300`). `_restoreScheduledWorkouts` instead **timestamp-merges** (schedule status needs cloud↔local reconciliation, d9b2c5) — additive vs merge is per-writer. ADR: offline-first local-wins (a 2nd-device edit won't overwrite the local copy). | `restore_local_wins_additive_test.dart`, diagnose c5a1f2 |

## Pitfall: restore SELECT with no retry (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 160-160, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| A restore-path Supabase SELECT with no retry silently drops a field on a stale post-redirect token | A query returning empty (HTTP 200, `null`) is indistinguishable from "no such row" — the SAME ambiguity diagnose `c2e9f4` fixed for `resolveDestination`'s `user_profile` SELECT, recurring in `_restoreUserProfile`'s `users` SELECT (full_name/email) because the fix was never generalized past its first call site. Confirmed live on 2 accounts via the `profile_full_name_empty_at_read` probe: `hasProfile=true`, `rawName=<null>` — the rest of the restore succeeds, only the ambiguous field vanishes. Fix pattern: `ensureFreshToken()` proactively, then on a `null`/empty result retry ONCE behind a hard `auth.refreshSession()` before accepting it as genuinely absent — never accept the first empty result as authoritative for a query this early in the session. ⚠ **The retry only protects the code path that actually RUNS the query.** If the same read can also arrive PRE-FETCHED (e.g. `_restoreUserProfile`'s `preFetchedUsers` param, fed by the C3 single-call restore's bundle), a null pre-fetched value bypasses the retry helper entirely — check whether the pre-fetch source shares the same stale-token exposure (an EF using a service-role client does not) before assuming the fix's coverage is universal; if it doesn't, at minimum log the injected-null case distinctly (B-pass finding 1) so a real gap isn't silent. Diagnose `d4e9a2`. | `test/contracts/restore_users_row_retry_test.dart` |

## Pitfall: rest row refilled with stale content, L1 (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 161-161, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| Restore/reconcile merge refills a local rest row with stale workout content (L1) | `PlanIntegrityReconciler.mergeScheduleEntry` never refills a local row whose `type` is a rest type or whose `status` is `'rest'` from the downloaded snapshot's content — kill switch `disable_rest_row_refill_guard` restores the old unconditional-refill behaviour. NOT a verbatim revert even with the switch on: the merge-output normalizer (`_normalizeHybrid`) stays live regardless and still corrects a no-exercises refill to `type: 'rest'` — only a refill whose snapshot row carries exercises reproduces the pre-fix hybrid. Diagnose `b6e1c8`. | `docs/architecture/sync.md`'s 'Sync skip pattern' point 6, `test/contracts/plan_integrity_reconciler_*_test.dart` |

## Pitfall: restore rewrites an unchanged plan bundle, L2 (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 163-163, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| Restore re-downloads and re-writes an unchanged plan bundle on every launch (L2) | Two independent skips, ONE kill switch (`disable_plan_merge_skip_when_known`): `_restoreWorkoutPlan` skips the WHOLE bundle merge only when the fingerprint matches AND every bundled `schedule_<date>` key still exists locally (a locally-deleted row defeats the skip — commit `18183762`, fingerprint match proves the CLOUD is unchanged, not that local still holds it). ⚠ An OI-252 ghost day (template deleted) is filtered out of every merge and never written, so an absent row whose `tmpl_<uuid>` template key is ALSO absent locally counts as present, or the skip could never fire again for that account (diagnose `a3e7d9`); `mergeScheduleBundleIntoHive` additionally writes a row only when its merged, canonicalized result differs from the existing one. | `docs/architecture/sync.md`'s 'Sync skip pattern' point 6 |

## Tests pinning the rules here (full, incl. path-correction note)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 169-185, context-lean batch 2026-09-29)._

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
- `test/contracts/sync_fanout_workout_domain_behavioral_test.dart` (+ `sync_fanout_nutrition_domain_behavioral_test.dart`).
- `test/contracts/error_telemetry_helper_writer_to_reader_test.dart`.
- `test/contracts/health_write_service_writer_to_reader_test.dart`.
- `test/contracts/workout_write_service_*_test.dart` (multiple — exercise log, schedule, templates).
- `test/contracts/nutrition_write_service_*_test.dart`.
- `test/contracts/subscription_state_*_test.dart`.

## SoT row: schedule_arrangement_stamp (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 60-60, context-lean batch 2026-09-29)._

| Concept | Writer (this dir) | Reader entry point |
|---|---|---|

| `schedule_arrangement_stamp` | `day_swap/day_swap_rules.dart` `buildSwap`/`landed` set `arranged_at_ms` (one `nowMs`, both rows) inside the build function `SwapService.swapDays` passes to `workout_write_service.dart` `swapScheduledDays`, which only writes it; `upsertScheduled`'s `carriesArrangement` carries it forward on a non-swap, non-restore rewrite of an already-arranged row | `plan_integrity_reconciler.dart` `snapshotArrangementWinsKeys` (restore-merge L3, `docs/architecture/sync.md`). |

## swapScheduledDays / ScheduleHybridRepairMigrator paragraph (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 80-84, context-lean batch 2026-09-29)._

`swapScheduledDays` (`workout_write_service.dart`) is the day-swap engine's one atomic write
(`WriteSource.daySwap`, two-date lock, all-four-keys-or-none) — see `day_swap_engine` above. Its
`carriesArrangement` helper is the sole decider of when `upsertScheduled` carries an
`arranged_at_ms` stamp forward onto a non-swap rewrite (`schedule_arrangement_stamp` above).
`ScheduleHybridRepairMigrator` (`schedule_hybrid_repair_migrator.dart`) is a ONE-TIME PER-USER

## Pitfall: older arrangement overwrites newer swap, L3 (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 109-109, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| An older arrangement from another device overwrites a newer local swap on restore (L3) | `PlanIntegrityReconciler.snapshotArrangementWinsKeys` compares MAX `arranged_at_ms` per Mon–Sun IST week between local and downloaded rows and only lets the snapshot win on a STRICT `>` (a tie keeps local). Kill switch `disable_swap_arrangement_merge`. A completed row is never a candidate — the completed-row guard runs before L3 is ever consulted. One `swap_merge_conflict` telemetry event per merge CALL, never per row. | `docs/architecture/sync.md`'s 'Sync skip pattern' point 6 |

## Pitfall: per-launch restore writer rewrites unchanged row (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 111-111, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| A per-launch restore writer rewrites an unchanged row every launch | `_restoreWorkoutTemplates`, `_restoreUserProgress` and `_restoreUserProfile` run on EVERY launch (`restoreLightweightAlways`). Each compares the value it would write with the stored one via `SyncFingerprint.canonicalJson` and skips an identical write (kill switch `disable_restore_write_if_changed`). ⚠ If the write path STAMPS a field (here `ProfileWriteService.updateProfile` sets `updated_at = istNow()`), drop that field from BOTH sides of the comparison, or the skip can never fire. Any new per-launch restore writer takes the same guard. Diagnose `f1c6b4`. | `test/sync/restore_write_if_changed_test.dart` |

## Pitfall: error text reaches telemetry with row data (full)

_Moved verbatim from `lib/core/services/CLAUDE.md` (original lines 112-112, context-lean batch 2026-09-29)._

| Pitfall | How to avoid | Source |
|---|---|---|

| An error's text reaches telemetry with the user's row data in it | Postgres echoes the rejected row into its error (`Failing row contains (...)`, `Key (cols)=(values)`, `invalid input syntax ... "value"`), and `PostgrestException.toString()` carries it. Every sink that ships error text off the device calls `ErrorTelemetry.redactRowValues` first: both `recordNonFatal` legs, `_reportSyncFailure`, the retry queue, the dead-letter post and `_logRefreshFailure`. A NEW direct `log-client-error` post owes the same call. Diagnose `e8c3a1`. | `test/core/error_telemetry_redact_row_values_test.dart`, `test/sync/sync_error_row_values_redacted_test.dart` |


## Pitfall: caller-level `recordNonFatal` + `_reportSyncFailure` double-post (full)

_Added 2026-09-30 to accompany the condensed row in `lib/core/services/CLAUDE.md` (fix `b2baab45`, diagnose `f7b2c9`). Written for this file, not moved from it._

| Pitfall | How to avoid | Source |
|---|---|---|

| A caller's own `ErrorTelemetry.recordNonFatal` call sits earlier in the same catch block as a call to the canonical funnel (`_reportSyncFailure`), so the SAME failure posts to `client_errors` TWICE | This is the "audit-2026-05-11 H-42 — telemetry pair" idiom: a catch block calls `recordNonFatal` for a broad Crashlytics-only signal, then separately calls `_reportSyncFailure(opType:, error:)` for the canonical, retry-queue-integrated write. Left at `recordNonFatal`'s default `skipServerPost: false`, BOTH calls independently POST to `log-client-error`, doubling the row count per failure. Fixing `_reportSyncFailure`'s own INTERNAL double-write (its own `recordNonFatal` call vs. its own direct `functions.invoke`) is NOT sufficient — a `grep "H-42" sync_service.dart` alone saw only ~13 `H-42` hits (of the real caller-level pairs) (87 existed at fix time; `sync_telemetry_test.dart` pins 75 today) because at fix time 8 of the 9 affected files were `part of sync_service.dart` under `lib/core/services/sync/`, invisible to a single-file grep. Fix: every caller-level `recordNonFatal` call earlier in the same enclosing block as a `_reportSyncFailure` call for the SAME caught error (the sweep test pairs to the end of the brace-matched block, because a ~570-580-char comment once separated a pair in `sync_nutrition.dart`) must pass `skipServerPost: true` — this preserves the caller's real stack trace for Crashlytics while leaving `_reportSyncFailure`'s own retry-queue-integrated write as the sole `client_errors` writer. Regression test must concatenate ALL `part of` files (`test/contracts/_sync_service_source.dart`'s `loadSyncServiceSource()`), not just the root file, or it will undercount exactly like the first fix attempt did. Diagnose `f7b2c9`, B2a-2b. | `test/sync/sync_telemetry_test.dart` |
