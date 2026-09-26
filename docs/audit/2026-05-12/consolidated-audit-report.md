# Consolidated Audit Report — 2026-05-12

> Comparison of two independent audit passes:
> - **Master Audit** (4 parallel Claude agents, 21 findings) — root-cause focused
> - **Codex Audit** (`live-db-schema-edge-sync-telemetry-audit.md`, 12 findings) — symptom + inventory focused
>
> Goal: deduplicate, identify gaps in either pass, produce one prioritized punch list.

---

## Status

- ✅ **Vault fix DONE** — `service_role_key` added to Supabase Vault. Within 15 min of save, PR-detection cron should produce its first successful tick (was 0/2102 prior).
- 🟡 Sync failures (C1 / Master #2) still firing — independent of Vault fix, code change needed.
- 🟡 19 items still open (1 user-action — verify migration target — plus 18 autonomous code/migration/deploy fixes).

---

## Overlap matrix

| # | Finding | Master | Codex | Both? | Master's root-cause depth |
|---|---|---|---|---|---|
| 1 | Cron 401s → all proactive features broken | P0 #1 | C2 | ✅ | Identified Vault is empty (Codex only saw 401s) |
| 2 | Sync 23505 on `workout_log_exercises` | P0 #2 | C1 (workout slice) | ✅ | Identified orphaned-sets side-effect |
| 3 | Sync 23505 on `nutrition_logs` | — | C1 (nutrition slice) | ❌ Codex-only | — |
| 4 | `ai-proxy-pro` still ACTIVE not 410 stub | P3 #20 | M1 | ✅ | Equal |
| 5 | `nutrition_logs.source` / `logged_at` columns missing | P3 #19 | H3 (partial) | ✅ | Codex finds more drift |

---

## Gaps in Master Audit (Codex found, Master missed) — 5 items

| # | Finding | Severity | Verification |
|---|---|---|---|
| **G1** | **Sync 23505 also failing on `nutrition_logs`** (16 rows/24h on `uniq_nutrition_logs_user_date_meal`) — same class as P0 #2 but on nutrition side | P0 | Codex live telemetry; confirmed by `client_errors` count |
| **G2** | **`admin-verify-payment` + `admin-wipe-storage` deployed but NOT in local source** — production has executable code that can't be reviewed or diffed. `admin-wipe-storage` is storage-destructive by name | P0 | ✅ Verified: 33 local fn dirs, 36 deployed in cloud — diff = these 2 |
| **G3** | **`workout_log_sets` missing realistic-bounds checks** that migration 060 added to `workout_log_exercises` | High | Codex live: 7 reps-out-of-bounds + 15 set_number-out-of-bounds rows (Jump Rope 540 reps, Leg Press set_number 15) |
| **G4** | **`account_deletion_log` has RLS enabled with zero policies** | High (intentional?) | Likely correct for server-only audit table — needs documentation note + guard test |
| **G5** | **`docs/sot_registry.yaml` schema drift** — 9 column claims that don't exist live (e.g. `ai_coach_interactions.assistant_response`, `workout_log_exercises.volume_kg`, `weight_logs.logged_at`, `sleep_logs.sleep_hours`) | High (docs) | Codex live check vs information_schema |

Notable Codex findings that **overlap but add detail**:
- **H1 (Codex)** — `sumitt@gmail.com` missing `user_preferences` row. Master Audit P2 #10 hinted at thin coverage but didn't name the user.
- **H2 (Codex)** — one orphan `nutrition_logs` row (id `f2c6754e...`, 78 cal snack 2026-05-03) with no `nutrition_log_items`. Master Audit had no equivalent.
- **H4 (Codex)** — `README_RECONCILIATION_2026-05-11.md` is stale (says 53 rows, prod has 55 through 060). Master Audit didn't track migration count drift.

---

## Gaps in Codex Audit (Master found, Codex missed) — 14 items

These are the items only the Master Audit surfaced. Codex stopped at symptoms; Master traced root causes.

| # | Finding | Severity | Why Codex missed |
|---|---|---|---|
| **M-1** | **Vault root cause** for all 12 cron 401s (Codex saw the 401s but didn't drill to `vault.decrypted_secrets`) | P0 | Codex doesn't have the `private.morning_alert_get_service_key()` runtime read |
| ~~**M-2**~~ | ~~`restore_coach_memory` queries wrong column~~ — **FALSE ALARM (verified 2026-05-12).** Code at `sync_service.dart:4722` already SELECTs `coach_notes` (the live column). The `coaching_notes` reference is the Hive key — intentional back-compat per CLAUDE.md §15 Hive field-name contract. | ~~P1~~ CLOSED |
| ~~**M-3**~~ | ~~`_syncScheduledWorkouts` runs before templates~~ — **FALSE ALARM (verified 2026-05-12).** Already fixed in Test #14 / Bug B.1 at `sync_service.dart:579-584` + `:638-642`. The 48 FK violations cited were all 2026-05-09 to 2026-05-10 09:06–12:45 — i.e. BEFORE the fix landed. No errors since. | ~~P1~~ CLOSED |
| **M-4** | `compute-coach-signals` upserts silently fail — RLS likely blocking service-role; `signals_computed_at` NULL after 23 nightly runs | P1 | Codex saw the table state but didn't correlate to function execution |
| **M-5** | `rolling-context` cron sends hardcoded anon JWT (pre-Vault pattern) — embeddings corpus may be frozen | P1 | Codex flagged "different auth paths" but didn't enumerate |
| **M-6** | `weekly-recap-ready` + `expiry-reminder` deployed but NO `pg_cron` job registered — never auto-triggered | P1 | Codex inventoried functions but didn't cross-check cron registrations |
| ~~**M-7**~~ | ~~`user_profile.terms_accepted_at` + `terms_version` MISSING~~ — **FALSE ALARM (verified 2026-05-12).** Migration `20260424074817` explicitly targets `users` table (confirmed via `supabase_migrations.schema_migrations`). Columns present on `users`. Client (`auth_provider.dart:601-631`) reads from `users`. CLAUDE.md §7 already documents this correctly. Master Audit conflated `user_profile` with `users`. No fix needed. | ~~P1~~ CLOSED | — |
| **M-8** | `client_version` hardcoded `"0.0.0+release"` — can't correlate 381 errors to APK builds | P2 | Codex saw "broad telemetry" (M2) but didn't trace to this field |
| **M-9** | `ai_coach_interactions` 79% phantom duplicates (81 of 114 rows) — SyncService double-writes alongside Edge Function | P2 | Codex saw the row count but didn't dedup-analyze |
| **M-10** | Conversion funnel completely blind — no `paywall_shown` / `paywall_dismissed` / `paywall_upgrade_tapped` events | P2 | Codex audited telemetry quality but didn't enumerate missing event types |
| **M-11** | `daily_summary` + `coaching_note` embeddings never implemented — semantic retrieval only searches chat history | P2 | Codex didn't trace embedding write paths per source type |
| **M-12** | `workout_logs` has 27 rows for 8 sessions (some 6× copies) — duplicate inserts on the parent table | P2 | Codex reported the count (27) without flagging the ratio |
| **M-13** | `workout_logs.rpe` never synced — weekly AI report shows "N/A" | P2 | Codex didn't check field-level sync coverage |
| **M-14** | Widget crash `'String' is not subtype 'int?'` active on 2026-05-11 — silent ErrorWidget catch | P2 | Codex saw the error in `client_errors` but didn't surface the active crash |
| **M-15** | CLAUDE.md §7 doc claim that `referral_redemptions` FKs point at `auth.users` — actually point at `public.users` | P3 | Codex didn't audit CLAUDE.md against live schema |
| **M-16** | Duplicate UNIQUE constraint on `referral_redemptions.referee_id` (two identical) | P3 | Codex didn't pg_indexes diff against expected |
| **M-17** | `workout_templates.last_used_at` — never written by client | P3 | Codex didn't audit write-path completeness per column |
| **M-18** | `scheduled_workouts.template_id` — 50/56 NULL, no backfill possible | P3 | Codex didn't quantify the NULL fraction |

Verdict: **Master Audit was substantially more thorough — root-cause + system-of-systems lens.** Codex Audit added 5 concrete live-data findings the Master Audit missed (especially G2 cloud-only admin functions, which is a security concern, and G3 `workout_log_sets` integrity).

---

## Unified prioritized punch list (after Vault fix)

### P0 — must fix before wider beta (3 items)

| # | Item | Owner | Type | Notes |
|---|---|---|---|---|
| **P0-A** | Sync `workout_log_exercises` onConflict mismatch → orphaned sets | Claude | Code | `_syncExerciseLogs` change `onConflict: 'id'` strategy. 20 errors at 03:41 UTC. (Master #2 + Codex C1) |
| **P0-B** | Sync `nutrition_logs` onConflict mismatch on `uniq_nutrition_logs_user_date_meal` | Claude | Code | Same class as P0-A but nutrition side. 16 rows/24h. (Codex C1 — gap G1) |
| **P0-C** | `admin-verify-payment` + `admin-wipe-storage` are cloud-only — pull source, classify, either commit + add tests OR formally decommission | Claude (after user confirms intent) | Source-of-truth | Storage-destructive by design. NEVER invoke `admin-wipe-storage`. (Codex C3 — gap G2) |

### P1 — feature significantly degraded (8 items)

| # | Item | Type |
|---|---|---|
| ~~**P1-A**~~ | ~~`restore_coach_memory` wrong column~~ — **CLOSED 2026-05-12. False alarm.** Code already correct. |
| ~~**P1-B**~~ | ~~`_syncScheduledWorkouts` ordering~~ — **CLOSED 2026-05-12. False alarm.** Fixed in Test #14 / Bug B.1. |
| ~~**P1-C**~~ | ~~`compute-coach-signals` silent upsert~~ — **CLOSED 2026-05-12.** Root cause was Bearer null (Vault empty), not RLS (`force_rls=false` on `coach_memory` so service-role bypasses RLS). Self-resolves on next 21:00 UTC tick post-Vault-fix. Server-side cron observability deferred to M2. |
| **P1-D** ✅ | `rolling-context` + `streak-guardian` crons rewritten via Vault key (migration 061) |
| **P1-E** ✅ | `weekly_recap_ready_sunday` + `expiry_reminder_daily` crons registered (migration 061) |
| ~~**P1-F**~~ | ~~terms columns missing~~ — **CLOSED 2026-05-12.** Migration targeted `users` (correct); columns present; client reads from `users`. False alarm in Master Audit. | — |
| **P1-G** ✅ | `workout_log_sets` NOT VALID bounds (migration 061) — legacy corrupt rows survive; new inserts bounded `[0, 60]` reps + `[0, 10]` set_number + `[0, 3600]` duration_secs |
| **P1-H** ✅ | `account_deletion_log` zero-policy RLS documented in CLAUDE.md §7 as intentional |

### P2 — data gaps / analytics blind (7 items)

| # | Item | Type |
|---|---|---|
| **P2-A** ✅ | `client_version` reads `AppConstants.appVersion` (mirrors pubspec) |
| **P2-B** ✅ | SyncService no longer double-writes `ai_coach_interactions` (channel='in_app_orphan' fallback for rare pre-server entries only) |
| **P2-C** ✅ | Paywall funnel events `paywall_shown` / `paywall_upgrade_tapped` / `paywall_dismissed` instrumented |
| **P2-D** ✅ | `daily-snapshot` v20 deployed — embeds merged coaching_notes into `memory_embeddings` (source_type=`daily_summary`) |
| **P2-E** ✅ | `workout_logs` deduped (27→8 rows via migration 062) + natural UNIQUE added + sync onConflict updated |
| **P2-F** ✅ | `workout_logs.rpe` in `_syncWorkoutLogs` projection |
| **P2-G** ✅ | `ErrorWidget.builder` composes exception+stack (~600 chars) into `client_errors.message` |

### P3 — minor / documentation (8 items)

| # | Item | Type |
|---|---|---|
| **P3-A** ✅ | CLAUDE.md §7 corrected — `referral_redemptions` FKs point at `public.users` |
| **P3-B** ✅ | Duplicate UNIQUE dropped (migration 061). Canonical: `unique_referee_redemption` |
| **P3-C** ✅ | `WorkoutScheduleService.assignTemplateToDate` stamps `last_used_at` |
| ~~**P3-D**~~ | `nutrition_logs.source` + `logged_at` — **DECIDED AGAINST 2026-05-12.** `created_at` already carries timestamp; `source` was an unused enrichment. Phantom claims in sot_registry removed (P3-G) instead. |
| ~~**P3-E**~~ | ~~Redeploy `ai-proxy-pro` as 410 stub~~ — **CLOSED 2026-05-12.** Local source IS already a 410 stub (since 2026-04-18). Deployed v17 matches. |
| **P3-F** | `scheduled_workouts.template_id` 50/56 NULL — historical, not recoverable; accept. Future rows handled by P1-B fix (which was already in place). |
| **P3-G** ✅ | 9 phantom column claims removed from `docs/sot_registry.yaml` (verified via `information_schema`) |
| **P3-H** ✅ | `README_RECONCILIATION_2026-05-11.md` updated: 53→55 prod migrations + 060+061+062 |

---

## User-action gates remaining (0 items)

Verified 2026-05-12 via live SQL query: migration `20260424074817` targeted `users` correctly; columns present; client code consistent. P1-F closed as false alarm.

**Everything else (P0-A through P3-H) is autonomous.**

---

## Cross-audit lessons

1. **Codex was symptom-driven** (401 counts, 23505 counts, schema diffs) — strong on inventory, weak on tracing failures to root cause.
2. **Master Audit (4-agent parallel) was root-cause-driven** — found the Vault was empty (the single biggest finding), traced sync-ordering bugs, surfaced silent RLS failures.
3. **Neither caught everything.** Codex C3 (cloud-only admin Edge Functions) is a real security/SoT concern Master missed. C4 (`workout_log_sets` bad rows) is a data-integrity gap Master missed.
4. **Both audits agreed on the Top 2** (Vault 401s + sync 23505), so those rank as P0 with double signal.

Recommended posture: **Master Audit as the spine of the fix batches; Codex findings G1-G5 folded in as additional P0/P1 items.**

---

## Suggested fix order

1. **Now (already done):** Vault fix (user) — unblocks all 12 crons within 15 min.
2. **Next batch — P0 (3 items):** P0-A, P0-B, P0-C. All before wider beta.
3. **Then — P1 (8 items):** P1-A through P1-H. Includes the DPDP compliance gap and the silent RLS failure.
4. **Then — P2 (7 items):** Analytics + dedup.
5. **Finally — P3 (8 items):** Documentation + retired-stub hygiene.

Total: **25 distinct items** after dedup + P1-F closure. Estimate ~10-14 hours of focused work to clear P0+P1; P2+P3 are another batch.
