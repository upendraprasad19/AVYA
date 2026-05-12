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
| **M-2** | `restore_coach_memory` queries wrong column `coaching_notes` (actual: `coach_notes`) — silently drops all notes on every restore | P1 | Codex didn't grep restore code paths |
| **M-3** | `_syncScheduledWorkouts` runs before `_syncWorkoutTemplates` finishes → 48 FK violations in 2 days | P1 | Codex didn't inspect sync ordering |
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
| **P1-A** | `restore_coach_memory` wrong column `coaching_notes` → `coach_notes` | Code (single-line) |
| **P1-B** | `_syncScheduledWorkouts` ordering — `await` template sync first | Code |
| **P1-C** | `compute-coach-signals` upsert silently fails — likely RLS on `coach_memory`; even after Vault fix, plateau-alert + re-engagement stay broken until this is fixed | Edge Fn / RLS investigation |
| **P1-D** | `rolling-context` cron auth — switch from hardcoded anon JWT to Vault service-key pattern | pg_cron + Edge Fn |
| **P1-E** | Register `pg_cron` for `weekly-recap-ready` (Sunday) + `expiry-reminder` | Migration |
| ~~**P1-F**~~ | ~~terms columns missing~~ — **CLOSED 2026-05-12.** Migration targeted `users` (correct); columns present; client reads from `users`. False alarm in Master Audit. | — |
| **P1-G** | `workout_log_sets` realistic-bounds checks (parity with migration 060) — but resolve cardio/bodyweight semantics first (Jump Rope 540 reps may be legitimate seconds, not reps) | Migration after decision |
| **P1-H** | `account_deletion_log` zero-policy RLS — document intent + add guard test | Doc + test |

### P2 — data gaps / analytics blind (7 items)

| # | Item | Type |
|---|---|---|
| **P2-A** | `client_version` read from `PackageInfo.fromPlatform()` not hardcoded | Code |
| **P2-B** | Stop SyncService writing `in_app` duplicate `ai_coach_interactions` rows (Edge Function already authoritative) | Code |
| **P2-C** | Add `paywall_shown` / `paywall_dismissed` / `paywall_upgrade_tapped` events | Code |
| **P2-D** | `daily-snapshot` must call `getEmbedding()` after extracting coaching notes | Edge Fn |
| **P2-E** | `workout_logs` dedupe + UNIQUE constraint + sync fix (27 rows for 8 sessions) | Migration + Code |
| **P2-F** | Add `workout_logs.rpe` to `_syncWorkoutLogs` payload | Code |
| **P2-G** | Widget crash `'String' is not subtype 'int?'` — add `StackTrace.current` to `logEvent` call; investigate | Code |

### P3 — minor / documentation (8 items)

| # | Item | Type |
|---|---|---|
| **P3-A** | CLAUDE.md §7: `referral_redemptions` FK direction (DB correct, doc wrong) | Doc |
| **P3-B** | Drop duplicate UNIQUE on `referral_redemptions.referee_id` | Migration |
| **P3-C** | `workout_templates.last_used_at` — stamp in `WorkoutScheduleService` on template start | Code |
| **P3-D** | `nutrition_logs.source` + `logged_at` migration (if wanted) | Decision + Migration |
| **P3-E** | Redeploy `ai-proxy-pro` as proper 410 stub | Edge Fn |
| **P3-F** | `scheduled_workouts.template_id` — 50/56 NULL non-recoverable; future rows handled by P1-B fix | Accept |
| **P3-G** | `docs/sot_registry.yaml` — remove 9 phantom column claims (`ai_coach_interactions.assistant_response`, `nutrition_logs.logged_at` + `source`, `saved_diet_plans.updated_at`, `sleep_logs.sleep_hours`, `user_daily_snapshots.token_count`, `water_logs.logged_at`, `weight_logs.logged_at`, `workout_log_exercises.volume_kg`) | Doc |
| **P3-H** | Update `supabase/migrations/README_RECONCILIATION_2026-05-11.md` (53 → 55 rows) | Doc |

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
