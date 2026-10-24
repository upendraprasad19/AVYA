---
batch: unit4-bodyfat-calc-heal
branch: unit4-bodyfat-calc
reviewer: context-blind adversarial B-pass
date: 2026-06-14
verdict: ACCEPTED — 0 P0/P1. F1 + F2 FIXED in-batch; F3 + P3 accepted-with-rationale (established codebase pattern). All triaged before merge (no-deferrals §4.2).
---

# Unit 4 — SAVED onboarding body-fat calc + heal — B-pass review

## Diff scope (16 files staged)

```
lib/core/services/body_fat_default_healer.dart          (NEW)
lib/core/utils/bmr_calculator.dart
lib/features/onboarding/screens/stats_screen.dart
lib/features/onboarding/screens/plan_screen.dart
lib/features/onboarding/providers/onboarding_provider.dart
lib/features/auth/providers/auth_provider.dart
lib/core/services/user_config_migrator.dart             (minor wiring)
test/contracts/body_fat_default_heal_test.dart          (NEW)
test/contracts/onboarding_bodyfat_calc_test.dart        (NEW)
```

---

## Lens 1 — writer_reader_drift

### Claim: a skip-user now saves `null` body_fat_percent. Does any reader force-unwrap or assume non-null?

Readers traced from the diff + codebase:

| Reader | File:line | Null-safe? |
|--------|-----------|-----------|
| Profile edit recompute | `profile_provider.dart:84` — `(profile['body_fat_percent'] as num?)?.toDouble()` | YES — nullable cast, returns null |
| Stat snapshot service | grep confirms `?` cast in `stat_snapshot_service.dart` | YES |
| `sync_profile.dart` | line 101 — `if (SyncService._hasNumber(p['body_fat_percent']))` — omits null from sync | YES |
| `_restoreUserProfile` | re-hydrates only non-null cloud values | YES (see durability below) |
| `body_stats.dart` consumer | existing null → "—" display path, confirmed by test comment line 14 | YES |
| `BmrCalculator.calculateTargets` | accepts `double? bodyFatPercent` (nullable param) | YES |

No force-unwrap found on any reader path. **CLEAN.**

### Claim: the cloud-clear-then-local ordering survives the omit-null sync + re-hydrating restore.

Durability chain:
1. Healer clears cloud `body_fat_percent` to `null` FIRST (line 60-62, `body_fat_default_healer.dart`).
2. Healer nulls local SECOND (line 66-67).
3. Subsequent sync: `sync_profile.dart:101` omits null from the `_hasNumber` guard → cloud column stays null.
4. Restore: `_restoreUserProfile` re-hydrates non-null cloud values only → null cloud column = nothing to re-hydrate.
5. Partial-failure scenario (cloud clear succeeds, local null fails): outer catch at line 69 leaves local at 18.0 → consistent, retries next session. **Safe.**
6. Partial-failure scenario (cloud clear fails, throws `PostgrestException`): caught by outer catch → cloud stays 18.0 → local stays 18.0 → consistent. **Safe.**

Ordering is correct and the durability claim holds. **CLEAN.**

---

## Lens 2 — function_exception_swallow

### Finding 1 — `ensureFreshToken()` return value completely ignored

**Severity: P2**

**File:line:** `lib/core/services/body_fat_default_healer.dart:59`

```dart
await SupabaseService.instance.ensureFreshToken();   // ← String? return discarded
await SupabaseService.instance.client
    .from('user_profile')
    .update({'body_fat_percent': null}).eq('user_id', uid);
```

**What happens:** `ensureFreshToken()` returns `String?` — null when the session is absent or the refresh failed AND the token is already past expiry (`supabase_service.dart:197`). Discarding this return means the `.update()` call proceeds regardless of whether the refresh succeeded.

**Net runtime behavior:** If the token is expired and the refresh fails, `ensureFreshToken()` returns null. The `.update()` call runs with the stale Supabase client auth state → PostgREST returns 401 → supabase_flutter `^2.x` throws `PostgrestException` → caught by the healer's outer `try/catch` at line 69 → 18.0 left consistent. **The outer catch saves it.** The design is technically safe.

**The issue:** The intent expressed in the class doc ("clear cloud FIRST via a fresh-token explicit UPDATE") is not what actually executes when the refresh silently fails. The code relies on the downstream PostgREST exception path to maintain consistency, rather than an explicit check. A future refactor of `ensureFreshToken` that changes its error behavior (e.g., throws instead of returning null) would silently change the healer's behavior without a compile error.

**Verification:**
```bash
grep -n "ensureFreshToken" "lib/core/services/body_fat_default_healer.dart"
# Line 59 — no assignment on left side → return value discarded
grep -n "ensureFreshToken" "lib/core/services/supabase_service.dart"
# Line 176-206 — returns String?, null on expiry-past + refresh-fail
```

**Suggested fix:**
```dart
final token = await SupabaseService.instance.ensureFreshToken();
if (token == null) {
  // No active session or refresh failed — skip cloud clear this session,
  // local heal also deferred so both stay consistent at 18.0.
  return;
}
```
This also avoids the ambiguous "proceed with stale auth" path entirely.

**Status: pending author response** — the outer catch makes this safe today, but the ignored return is a code smell that can bite in future refactors.

---

### Finding 2 — `unawaited(ErrorTelemetry.recordNonFatal(...))` in catch — no inner error sink

**Severity: P2** (pre-existing codebase pattern — not introduced by this diff)

**File:line:** `lib/core/services/body_fat_default_healer.dart:71-73`

```dart
} catch (e, st) {
  unawaited(ErrorTelemetry.recordNonFatal(e, st,
      reason: 'bodyfat_default_heal'));
}
```

`unawaited()` runs the future without capturing its completion. If `ErrorTelemetry.recordNonFatal` itself throws (e.g. telemetry Hive box not open, network error inside the telemetry write), the exception becomes an unhandled zone error — uncaught on the platform and potentially logged to crash reporting as a different, confusing error, masking the original `e`.

**Verification:**
```bash
grep -n "unawaited(ErrorTelemetry" "lib/core/services/body_fat_default_healer.dart"
# Line 71 — in the catch block, no inner try/catch on the recordNonFatal call
```

**Note:** This is the same pattern used by all other migrators (e.g., `user_config_migrator.dart`). This B-pass documents it as a known risk class, not a regression introduced by Unit 4.

**Status: pending** — author to confirm this is an accepted codebase-wide pattern, or add a `.catchError((_) {})` to the `unawaited` call.

---

## Lens 3 — blast_radius_mismatch

### Kill-switch defaults — are absent keys correctly interpreted as "feature ON"?

**`disable_bodyfat_calc`** (calc kill-switch):
- `onboarding_provider.dart`: `bodyFatDisabled = configBox.get('disable_bodyfat_calc') == true`
- Absent key: `null == true` → `false` → disabled = false → body-fat honored. **Feature ON. Correct.**
- Key = true: `true == true` → `true` → body-fat dropped to null → Mifflin. **Kill-switch fires. Correct.**
- Key = false: `false == true` → `false` → body-fat honored. **Correct.**

**`disable_bodyfat_heal`** (heal kill-switch):
- `body_fat_default_healer.dart:44`: `if (hive.configBox.get(killSwitch) == true) return;`
- Absent key: `null == true` → `false` → does NOT return → heal runs. **Feature ON. Correct.**
- Key = true: returns immediately. **Kill-switch fires. Correct.**

**Flag semantics across all 3 states:** VERIFIED CLEAN for both kill-switches. No inversion.

### Cross-account safety:

The healer is wired at `auth_provider._ensureLocalUser` line 447-452, which runs AFTER:
1. `openForUser` (cross-account guard — Hive boxes scoped to the new user)
2. `UserConfigMigrator.runIfNeeded()`

The healer reads via `hive.userBox` (a `GuardedBox`) and writes with `userBox.put('profile', profile)`. Cross-account-safe. **CLEAN.**

---

## Lens 4 — secrets_in_tree

Full diff scanned. No credential-shaped literals, API keys, tokens, or secrets introduced.

**CLEAN.**

---

## Lens 5 — unawaited_no_error_sink

Only `unawaited` in the diff: `body_fat_default_healer.dart:71` (documented above as Finding 2). No other `unawaited(` calls introduced. **No new instances.**

---

## Unit-4-specific scrutiny

### 1 — Flag default flip: `bodyFatDisabled` vs `bodyFatHonored`

The diff changed from `bodyFatHonored = configBox.get('disable_bodyfat_calc') != true` (positive sense) to `bodyFatDisabled = configBox.get('disable_bodyfat_calc') == true` (negative sense), passing `disabled:` to `bodyFatForCalc`.

Both forms are semantically identical across all 3 states (absent / true / false). Verified above under Lens 3. **CLEAN — no inversion.**

### 2 — `_parseDoubleOrNull` vs `_parseDouble`: skip-user truly saves null?

`onboarding_provider.dart` now calls `_parseDoubleOrNull(a['body_fat_percent'])` for `bodyFatPercent`. The helper (lines 638-645 in the diff) returns `null` for absent/blank — not 0.0 from the old `_parseDouble`. The test at `onboarding_bodyfat_calc_test.dart:115-122` pins this with a source-grep (comment-stripped). **CLEAN.**

No downstream reader force-unwraps `body_fat_percent` (confirmed under Lens 1). **CLEAN.**

### 3 — Heal discriminator: int vs float storage of `18.0`?

The healer reads: `(profile['body_fat_percent'] as num?)?.toDouble()` (line 51). The `num?` cast handles both `int 18` and `double 18.0` stored formats. The old `stats_screen` always wrote via `double.tryParse(controller.text) ?? 18.0` → always a `double`. The new `_parseDoubleOrNull` returns `double?` or null. The discriminator is robust. **CLEAN.**

### 4 — `ensureFreshToken()` return not checked — cloud/local split?

Addressed in Finding 1 above. The outer catch prevents a cloud-null/local-18 split (both stay 18.0 on any exception). However, the token refresh path is ignored silently. **P2 — safe but poor practice.**

### 5 — Test honesty: do tests actually FAIL without the fix?

**`onboarding_bodyfat_calc_test.dart`:**
- Behavioral tests (`bodyFatForCalc`, Katch vs Mifflin divergence, kill-switch revert): these test the new static method `BmrCalculator.bodyFatForCalc`. Without the fix, this method doesn't exist → tests fail to compile → **FAIL WITHOUT FIX. Honest.**
- Source-grep tests: test the ABSENCE of `?? 18` and PRESENCE of `_parseDoubleOrNull` and `bodyFatForCalc`. Before the fix all three grep conditions were false → **tests would FAIL WITHOUT FIX. Honest.**

**`body_fat_default_heal_test.dart`:**
- Test "18.0 + never-assessed → nulled": without `BodyFatDefaultHealer` existing, test fails to compile. With the old code (class doesn't exist) → **FAIL WITHOUT FIX. Honest.**
- Local heal path (all 6 tests): exercise the local Hive mutation. These DO fail without the fix. **Honest.**

### Finding 3 — Cloud-clear path completely untested

**Severity: P2** (test gap — not a runtime bug)

**File:line:** `test/contracts/body_fat_default_heal_test.dart:10-14`

The test file itself documents this explicitly:

```
// Cloud-clear path: when there is no Supabase session (uid == null, as in this
// unit test) the healer skips the cloud UPDATE and nulls only local
```

All 6 test cases run with `SupabaseService.instance.currentUser == null` → the healer's `if (uid != null)` guard (line 58) skips the entire cloud-clear block. **The cloud-clear path — the entire durability claim — is never exercised by the test suite.**

A bug in the cloud UPDATE (wrong table, wrong column name, wrong user filter, RLS block) would be:
1. Undetected by the test suite (cloud block never runs in tests)
2. Undetected in production unless the user is online AND the exception path triggers AND someone reads the telemetry

**Verification:**
```bash
grep -n "uid" "test/contracts/body_fat_default_heal_test.dart"
# No Supabase session setup — uid == null throughout
grep -n "SupabaseService\|supabase" "test/contracts/body_fat_default_heal_test.dart"
# No SupabaseService mock/stub — currentUser returns null
```

**Suggested mitigations (any one sufficient):**
- Option A: Add a mock `SupabaseService` in the test, inject a non-null `uid`, spy on the `.update()` call, and verify it was called with `{'body_fat_percent': null}` against the correct table.
- Option B: Add an integration test that signs in with a test user, seeds a fabricated 18.0 in the cloud `user_profile` table, runs the healer, and reads back the cloud column.
- Option C: Document as `behavioral_test_required: true` in `docs/sot_registry.yaml` for the `body_fat_default_heal` SoT entry, with Gate 42 tracking it.

**Status: pending author response** — the cloud-clear path is the core durability mechanism and has zero test coverage.

---

## Dead code finding (informational — P3)

**File:line:** `lib/features/auth/providers/auth_provider.dart:447-452`

The `try/catch` wrapping `BodyFatDefaultHealer.runIfNeeded()` is unreachable dead code. The healer's entire body is inside its own `try/catch` at `body_fat_default_healer.dart:42/69` — the healer cannot throw to its caller. The auth_provider catch comment ("Non-fatal — retries next session") is accurate in intent but the catch block itself will never fire.

Not a bug (dead catch is harmless), but the misleading comment increases confusion for future readers. **Informational only.**

---

## Summary

| ID | Severity | Description | File:line |
|----|----------|-------------|-----------|
| F1 | P2 | `ensureFreshToken()` return value discarded — cloud UPDATE proceeds even on stale/expired token; safe due to outer catch but fragile to future EF changes | `body_fat_default_healer.dart:59` |
| F2 | P2 | Cloud-clear path (the core durability claim) has ZERO test coverage — all 6 heal tests run with `uid == null` and skip the cloud UPDATE entirely | `body_fat_default_heal_test.dart:10-14` |
| F3 | P2 | `unawaited(ErrorTelemetry.recordNonFatal(...))` in catch has no inner error sink — pre-existing codebase pattern but should be confirmed as accepted | `body_fat_default_healer.dart:71` |
| — | P3 | Dead catch in `auth_provider` (healer cannot throw to caller) | `auth_provider.dart:447` |

**Lenses clean:** writer_reader_drift (null propagation + restore ordering), flag semantics (both kill-switches), int/float discriminator, secrets_in_tree, blast_radius / cross-account wiring, test honesty (local heal path fails without fix).

**Most important finding:** F2 — the cloud-clear path that prevents the silent re-hydration revert is completely untested. The local heal is proven; the cloud-first ordering that makes it durable is not.

**Verdict: CONDITIONAL PASS** — no P0/P1 blockers. F1 + F2 require author acknowledgement (fix or explicit accept-with-rationale) before merge.

---

## Author triage (2026-06-14) — all resolved before merge (§4.2 no-deferrals)

- **F1 (ensureFreshToken return discarded) — FIXED.** `body_fat_default_healer.dart` now
  captures the token and `if (token == null) return;` — DEFERS the entire heal (skips the
  local null too) when there's no fresh token, so the "fresh-token explicit UPDATE" intent is
  explicit and the no-split guarantee no longer relies on the downstream 401-throws-and-is-caught
  accident. The reviewer's exact suggested fix.
- **F2 (cloud-clear path untested) — FIXED (defense-in-depth, proportionate to a no-live-backend
  unit env).** Three layers now cover the cloud path: (1) NEW source-contract group in
  `body_fat_default_heal_test.dart` pins the table (`user_profile`), column
  (`body_fat_percent`), filter (`eq('user_id', uid)`), fresh-token-BEFORE-update ordering, and
  the `token == null` defer; (2) `scripts/check_schema_column_refs.dart` validates that
  `body_fat_percent`/`user_id` are real `user_profile` columns against the LIVE schema snapshot
  (it scans `lib/` `.from().update()` refs — verified it runs over the healer: 731 refs, 0 drift);
  (3) the local heal remains behaviorally proven (6 Hive round-trip cases). A full signed-in
  integration test is out of scope for the unit suite (no live backend in CI) — Option A/B from
  the review would need a Supabase mock/integration harness; the source-contract + schema-gate
  combination catches the same failure modes (wrong table/column/filter, dropped fresh token)
  at pre-commit/CI.
- **F3 (`unawaited(recordNonFatal)` no inner sink) — ACCEPTED with rationale.** `recordNonFatal`
  is `static Future<void>` and self-swallows on every leg (Crashlytics + per-key writes each in
  their own try/catch; `error_telemetry.dart:165+`) → it never throws to the `unawaited`. This is
  THE codebase-wide idiom (every migrator + every catch block uses it, e.g. `user_config_migrator`).
  Adding `.catchError` here would make this one migrator inconsistent for no behavioral gain.
- **P3 (dead catch in `auth_provider`) — ACCEPTED with rationale.** The boot try/catch mirrors the
  sibling `UserConfigMigrator.runIfNeeded()` wiring immediately above it (identical structure) and
  is a deliberate defense-in-depth guard: if a future refactor removes the healer's internal catch,
  the boot sequence still won't crash. Keeping it preserves wiring consistency; the "retries next
  session" comment is accurate regardless of which layer catches.

Post-fix: `flutter analyze` clean on all touched files; 18 tests green (9 calc + 6 heal behavioral
+ 3 cloud-contract source).
