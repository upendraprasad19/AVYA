---
review_type: b-pass (code-review)
batch: restore-single-call (C3 single-call restore)
reviewed: 2026-06-30
findings: { P0: 0, P1: 0, P2: 1, nit: 2 }
verdict: accepted
---

# B-pass: restore-single-call (C3 single-call restore)

**Reviewer:** Context-blind adversarial reviewer (§4.3 ≥account gate — CATASTROPHIC tier)
**Branch:** `restore-single-call` (worktree `C:\Upendra\Claude Code\Fitness App\.claude\worktrees\restore-single-call`)
**Staged diff:** 16 files — `supabase/functions/restore-user-snapshot/index.ts`, `lib/core/services/sync_service.dart`, `lib/core/services/sync/sync_*.dart` (6 files), `test/sync/`, `test/contracts/` (5 files), `test/safety/`

> This is a `service_role` Edge Function that bypasses RLS — the EF body is the only scope guard. Catastrophic tier.

---

## Findings

### P2 — Misleading docstring on `RestoreResult.cancelled()` (non-fatal, but will mislead)

**File:** `lib/core/services/sync_service.dart` — docstring at line 1464 inside `_attemptSingleCallRestore`

**The docstring says:**
> `RestoreResult.cancelled` — a cancel / owner-swap landed before/while writing (H-7); **the snapshot is discarded without a Hive write.**

**What actually happens:**

The pre-write cancel/owner-assert block at lines 1495–1500 guards entry into Step A, Step B, Step C. However, the three inter-step cancel checks are at:

- Line 1535: `if (_restoreCancelled) return RestoreResult.cancelled();` — fires **after Step A completes** (profile, plan, templates, preferences, workout_plan writes are already written to Hive).
- Line 1586: `if (_restoreCancelled) return RestoreResult.cancelled();` — fires **after Step B completes** (all bulk history writes — workout_logs, weight_logs, nutrition_logs, streaks, coach_memory, etc. — are already written).
- Line 1615: `if (_restoreCancelled) return RestoreResult.cancelled();` — fires **after Step C completes** (freezes, saved_diet_plan, referral_codes, etc. are already written).

If `_restoreCancelled` is set mid-restore (e.g., a `StartMissionBrief` cancel arriving during Step B), the `cancelled` result is returned but Step A's Hive writes are already on disk.

**Why this matters:**

The cancelled path is NOT data-loss — writes are additive/local-wins, and the next login heals any gaps. But the docstring's "snapshot is discarded without a Hive write" claim is flat-out wrong for mid-batch cancels, and will mislead the next developer who:

- Investigates a bug where "restore was cancelled" but Hive contains partial data.
- Tries to add post-cancel cleanup code based on the false "no writes happened" premise.

**Concrete fix:**

Replace the docstring (line 1464) with the accurate description:

```dart
///   • [RestoreResult.cancelled] — a cancel / owner-swap was detected. The
///     pre-write check (H-7) at the top of the method prevents any write if
///     cancel arrives before Step A. If cancel arrives between steps (post-A,
///     post-B), the already-applied step's additive Hive writes are NOT
///     rolled back — they are safe (local-wins, next login fills gaps). The
///     remaining steps are skipped.
```

---

### nit-1 — `workout_schedule_completions` inherits 1000-row PostgREST cap (pre-existing; not a C3 regression)

**File:** `supabase/functions/restore-user-snapshot/index.ts` and confirmed by `supabase/config.toml` (`max_rows = 1000`)

The EF query for `workout_schedule_completions` has no `.range()`, inheriting the PostgREST `max_rows = 1000` default. The legacy client (`_restoreScheduleCompletions` in `lib/core/services/sync/sync_workout.dart`) also uses no `.range()` — confirmed by reading the pre-C3 HEAD of that file. This is H-9 intentional parity. At real user volumes this is far from a data-loss risk. Noted for awareness since `PAGINATED_CEILING = 50000` is used for the other large tables but not here.

No action required for this batch; mention in the diagnose-doc if one is written.

---

### nit-2 — Source-grep test signatures widened to tolerate `{Object? preFetched}` param

**Files:** `test/contracts/restore_completeness_writes_test.dart`, `test/contracts/restore_plan_json_authoritative_test.dart`, `test/contracts/restore_round_trip_field_coverage_test.dart`, `test/contracts/restore_template_schedule_test.dart`, `test/safety/restore_after_session_open_test.dart`, `test/sync/restore_ordering_and_sweep_test.dart`

The test signatures were widened (e.g. `'Future<void> _restoreReferralCodes('` instead of `'Future<void> _restoreReferralCodes(String userId)'`) to tolerate the new optional `{Object? preFetched}` params. The `_methodSlice`/`_extractMethod` helpers were also updated to skip the param-list group before finding the method body brace.

These are correct adaptations — the tests still pin method presence and body content. The trade-off is that a future rename of the method signature away from the partial prefix would no longer be caught. The behavioral test (`restore_single_call_bundle_validation_test.dart`) and the `validatedSnapshotTables` static helper cover the fail-closed contract more robustly anyway.

No action required.

---

## What I verified

### EF security (catastrophic scope guard — this body is the only scope check)

- **Auth contract (e8a1c3):** `createClient(SUPABASE_URL, SERVICE_ROLE)` + `db.auth.getUser(token)` — correct. Token is NOT used as the supabase key. Verified at lines 97–100 of `index.ts`.
- **UUID H-4 guard:** `UUID_RE = /^[0-9a-f]{8}-...$/i` tested against `vUid` before any query is built. A null / empty / non-UUID `vUid` returns 401 at line 107–111. No query path exists that skips this guard.
- **Every table scoped to `vUid`:** All 29 table reads are scoped. The three user_id-less tables are handled correctly:
  - `nutrition_log_items` — embedded under `nutrition_logs` which IS `.eq('user_id', vUid)`.
  - `template_exercises` — embedded under `workout_templates` + `scheduled_workouts`, both user-scoped.
  - `referral_redemptions` — `.or('referrer_id.eq.${vUid},referee_id.eq.${vUid}')` dual-FK. Because `vUid` is UUID-validated before this point, string interpolation into the `.or()` is injection-safe (a non-UUID value would have 401'd at H-4).
- **No client-supplied user-id parameter:** The EF body has no `req.json()` call for a user-id param. `vUid` is derived solely from the validated token. Verified by reading the full 318 lines.
- **Fail-closed (H-2):** The `q()` helper throws on any PostgREST error. The outer `try/catch` at the `serve()` level catches the throw and returns 500 (non-200). No per-table `try/catch` that could swallow an error and return a partial 200 exists.
- **`coach_memory` 10-col projection:** Explicit column list in the EF matches the `_restoreCoachMemory` select string in `sync_coach.dart`. Not `SELECT *`.
- **Embed shapes:** `nutrition_logs` → `nutrition_log_items(*)`, `workout_templates` → `template_exercises(*)`, `scheduled_workouts` → `template:template_id(id, name, workout_type, template_exercises(*))`. All match what the respective `_restoreX` parsers read.
- **`referral_codes` shape:** `.limit(1).maybeSingle()` → supabase-js returns object|null (not array). Client treats injected value as `rawRes as Map` after null check. Correct.
- **`workout_plan` shape:** EF returns array of objects with `plan_json` field. Client reads `(rows.first as Map)['plan_json']`. Shapes match.
- **`saved_diet_plan` key vs `saved_diet_plans` table:** Intentional aliasing — Hive/bundle key is singular; cloud table name is plural. The EF sets `tables["saved_diet_plan"]` from `.from("saved_diet_plans")`. Client reads `row('saved_diet_plan')` (line 1598–1599). No mismatch.
- **29-key parity:** Diffed EF `tables[...]` keys against `_kSingleCallBundleKeys`. Empty output — exact match in both directions.
- **Missing await / exception swallowing:** No `await`-less promise in the EF that would silently miss a query error. All `q()` calls are properly awaited. The outer catch correctly returns 500.
- **Error response shape:** `jsonError()` returns `{error, request_id}` — no stack trace leakage. Correct (§4.4 rule 17).

### Client orchestrator

- **`_kNoInject` sentinel:** `const Object _kNoInject = Object()` top-level constant. Every `_restoreX` default is `_kNoInject`, checked via `identical(preFetched, _kNoInject)` (not `==`). No equality-operator bypass possible.
- **`validatedSnapshotTables` fail-closed logic (line 1661–1671):**
  - Non-200 → null. ✓
  - `data` not a Map → null. ✓
  - `schema_version != 1` → null. ✓
  - `tables` not a Map → null. ✓
  - ANY key from `_kSingleCallBundleKeys` absent → null. ✓
  - Present key with null or `[]` value — NOT a fault (correct — legitimately empty table). ✓
  - Behavioral test pins all these paths: `test/sync/restore_single_call_bundle_validation_test.dart`.
- **Kill-switch:** `_singleCallKillSwitch` reads `configBox.get('disable_single_call_restore') == true`. Gated before the EF call. Legacy path is verbatim.
- **Owner re-assert before first Hive write (line 1495–1500):** `_restoreCancelled` check + `_supabase.currentUser?.id != userId` check, both before `row()` or any `_safeRestoreOp` call. A fast account-switch mid-EF-call is blocked here.
- **A→B→C apply order:** Verified sequential `await` chains — Step A (profile/plan/templates) → cancel check → Step B (bulk history, scheduled_workouts before schedule_completions) → cancel check → Step C (restore-completeness surfaces, freezes after user_progress) → cancel check → subscription refresh.
- **`preFetched` shape for every `_restoreX`:**
  - List-valued reads: `preFetched as List? ?? const []`. ✓ for all 20 list-type tables.
  - Object|null reads (`coach_memory`, `freezes`, `users`, `saved_diet_plan`, `referral_codes`): `rawRow as Map` / `rawRes as Map` after null guard. ✓
  - Two-param reads (`_restoreExerciseLogs`: `preFetchedExercises` + `preFetchedSets`; `_restoreUserProfile`: `preFetched` + `preFetchedUsers`): each param checked independently with `identical()`. ✓
- **Legacy path byte-identical when preFetched omitted:** All `_restoreX` methods default to `_kNoInject` and follow the `identical()` guard — the original network query path is taken verbatim when the param is absent. No behavior change to the legacy fan-out.

### Cross-account / concurrency

- **Fast account-switch mid-EF-call:** Owner re-assert at lines 1495–1500 (pre-write) + at lines 1535, 1586, 1615 (inter-step) — catches a switch that arrives at any step boundary.
- **Slow-boot window:** `restoreFromCloud` (background path for returning users) reads from Hive only; it does not call the new EF. The C3 path lives exclusively in `restoreFromCloudForUser` (the fresh-install / new-login path). No interference.
- **`restoreLightweightAlways`:** Confirmed unchanged. Reads `_supabase.callFunction` only for `restore-user-snapshot`; `restoreLightweightAlways` uses a separate flow. No conflict.
- **`restoreFromCloud`:** Line numbers confirmed unchanged vs the HEAD commit. C3 code is inserted in `restoreFromCloudForUser` only; `restoreFromCloud` delegates to per-domain `_restoreX` methods directly without the new EF path.

### Tests

- **`restore_single_call_bundle_validation_test.dart`:** Behavioral. Covers non-200, absent key, bad schema_version, non-Map data → null; present null/`[]` → NOT fault. Uses `SyncService.singleCallBundleKeys` getter (exposes `_kSingleCallBundleKeys` as unmodifiable) so test and EF can never drift silently.
- **Source-grep tests (widened signatures):** Correct adaptations. No test now vacuously passes — the `_methodSlice`/`_extractMethod` fixes correctly skip the param-list group before scanning for the body brace, so the body content assertions are still live.
- **`restore_marker_wiring_test.dart` + `restore_marker_writer_to_reader_test.dart`:** Staged but from the OPT-H marker batch, not C3. Pinning unrelated contracts; not relevant to this review.
- **`restore_marker_test.dart`:** Same — OPT-H artifact, not C3.

---

## Summary

Zero P0/P1 findings. The EF body is sound as the sole RLS substitute — UUID guard, dual-FK `.or()`, no client-supplied user param, fail-closed `q()` + outer catch, correct auth contract. The client orchestrator correctly implements kill-switch, pre-write owner re-assert, `_kNoInject` sentinel, `validatedSnapshotTables` fail-closed logic, and A→B→C apply order.

The single P2 is a docstring inaccuracy about partial writes on inter-step cancel — not a data-loss bug, but will mislead future maintainers. Fix the docstring before or in the merge commit.
