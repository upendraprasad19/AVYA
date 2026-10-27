# Sync Reliability — Design Spec

**Status:** Draft · **Author:** Claude + Upendra · **Date:** 2026-04-17
**Target implementation session:** TBD · **Implementation scope:** ~1-2 days engineering

---

## 1. Problem

`SyncService` is structurally unable to surface sync failures. Every failed Supabase write is swallowed into `debugPrint` and lost. A user whose onboarding-sync fails silently has:

- An incomplete cloud profile (no backup)
- No UI feedback that anything is wrong
- No persistent retry — next daily sync may or may not happen, may or may not succeed, may or may not be noticed
- No server-side signal we could use to diagnose the failure post-hoc

### Concrete evidence

The `icanbefitter@gmail.com` test account has an all-null `user_profile` row in Supabase despite its Hive profile being fully populated. Reconstructed failure path:

1. Onboarding completes → Hive gets full profile → `_syncOnboardingToSupabase` fires
2. That sync fails (network / JWT / schema-mismatch — unknown, because nothing was logged)
3. The single 10-s retry at `onboarding_provider.dart:381` also fails
4. Falls through to `debugPrint('[Onboarding] Retry also failed: $e — will sync on next daily sync')`
5. User never sees an error. Next `checkAndSync()` either never runs or also fails. Stays all-null for weeks until manual SQL inspection surfaces it.

This is a **class of bug**, not a one-off — it applies to every `unawaited(SyncService.instance.pushSnapshot())` call site (9+ in nutrition/train providers), every `weeklyFullSync`, every `syncWorkoutData`. Any user with flaky connectivity during a sync window is a potential silent data-loss victim.

### Current code map

| File | Lines | Role | Error handling |
|---|---|---|---|
| `lib/core/services/sync_service.dart` | 100-132 | `checkAndSync()` — daily sync entry | try/catch → debugPrint |
| `lib/core/services/sync_service.dart` | 147-166 | `pushSnapshot()` — AI-context push | try/catch → debugPrint |
| `lib/core/services/sync_service.dart` | 172-203 | `weeklyFullSync()` — bulk push all mutations | try/catch → debugPrint |
| `lib/core/services/sync_service.dart` | 783-816 | `_syncUserProfile()` — profile upsert | **no try/catch** — uncaught exception bubbles up |
| `lib/core/services/sync_service.dart` | 814-... | `_syncCustomItems()`, `_syncWeightLogs()`, etc. | try/catch → debugPrint each |
| `lib/features/onboarding/providers/onboarding_provider.dart` | 375-390 | Onboarding first-sync + 10-s retry | try/catch → debugPrint, then falls through |
| `lib/features/auth/providers/auth_provider.dart` | 500-512 | Login gap-fill (if cloud profile missing, fill it) | try/catch → debugPrint |
| Call sites (9+) | various | `unawaited(SyncService.instance.pushSnapshot())` etc. | **no error propagation by design** |

No `pending_sync_queue` Hive box exists despite CLAUDE.md §4 listing it. No Sentry/Crashlytics. No Supabase `client_errors` table.

---

## 2. Goals

1. Every sync failure is **captured** (in a structured form), **retried** (with backoff), and **observable** (to both the user and to us via server telemetry).
2. Zero new user-facing friction when sync succeeds (the 99% path). Success stays invisible.
3. Existing fire-and-forget call pattern at 9+ sites doesn't need to change shape — the queue layer wraps it transparently.
4. Backwards-compatible with current Hive data — no forced migration.

## 3. Non-goals

- Real-time two-way sync (CRDT, live subscriptions) — remains out of scope
- Conflict resolution beyond "last write wins with deterministic UUIDs" (current behavior preserved)
- Replacing Supabase — still the backing store
- Offline-first already works; this spec only hardens the Hive→Supabase push leg

---

## 4. Design — 4 pillars

### Pillar A — Typed error shape

**File (new):** `lib/core/services/sync_error.dart`

```dart
sealed class SyncError {
  final String code;
  final String? message;
  final DateTime at;
  const SyncError({required this.code, this.message, required this.at});
}

class NetworkError extends SyncError { /* no route to host, DNS, socket timeout */ }
class AuthError extends SyncError { /* 401/403 — JWT expired, RLS denied */ }
class ValidationError extends SyncError { /* 400 — payload rejected */ }
class SchemaError extends SyncError { /* 42703 unknown column, 42P01 table missing */ }
class RateLimitError extends SyncError { /* 429 */ }
class UnknownError extends SyncError { /* anything else; preserves raw body */ }
```

**Helper:** `lib/core/services/result.dart` — discriminated `Result<T, E>` with `.isOk`, `.value`, `.error`, `.map`, `.flatMap`.

Every `SyncService` method's signature changes from `Future<void>` to `Future<Result<void, SyncError>>`. Callers that currently `unawaited` continue to, but the enqueue layer (Pillar B) now wraps them.

### Pillar B — Persistent retry queue

**File (new):** `lib/core/services/sync_queue.dart`
**Hive box:** `syncBox` (already exists) → new key prefix `pending_sync_<uuid>`

```dart
class PendingSyncOp {
  final String id;             // uuid
  final String opType;         // 'upsert_user_profile' | 'upsert_water_log' | ...
  final Map<String, dynamic> payload;
  final int retryCount;
  final DateTime firstAttemptAt;
  final DateTime? lastAttemptAt;
  final SyncError? lastError;
}

class SyncQueue {
  Future<Result<void, SyncError>> enqueue(PendingSyncOp op);
  Future<void> drain();        // fires every op that's due; respects backoff
  Stream<int> get pendingCount; // for UI banner
  void scheduleRetry(PendingSyncOp failed);
}
```

**Backoff schedule:** 1s → 5s → 30s → 5min → 30min → 2h → 24h → dead-letter (user-visible "couldn't save" + server telemetry).

**Drain triggers:**
- `main()` — on app launch after Hive opens, before `runApp`
- `connectivity_plus` listener — on transition offline→online
- Manual: user taps sync banner "Retry now"
- Periodic: 5-min timer while app foregrounded

### Pillar C — User-visible sync state

**File (new):** `lib/shared/providers/sync_state_provider.dart`

```dart
sealed class SyncState { const SyncState(); }
class SyncIdle extends SyncState {}
class SyncInFlight extends SyncState { final int inFlightCount; }
class SyncQueued extends SyncState { final int queuedCount; }
class SyncFailed extends SyncState { final SyncError lastError; final int failedCount; }

final syncStateProvider = StateNotifierProvider<SyncStateNotifier, SyncState>(...);
```

**File (new):** `lib/shared/widgets/sync_banner.dart` — a slim 32-px banner shown above the tab bar when state ≠ `SyncIdle`. Copy (per CLAUDE.md error-copy rule — never "restart the app"):

- `SyncInFlight` → "Saving changes…" (spinner, auto-dismisses)
- `SyncQueued(n)` → "`$n` changes waiting for connection" (passive, no action)
- `SyncFailed` → "Couldn't save — tap to retry" (tap fires `SyncQueue.drain()`)

**Mounted at:** `lib/features/home/screens/home_screen.dart` + `lib/features/profile/screens/profile_screen.dart` (the two tabs where users are most likely to notice and care).

### Pillar D — Server telemetry

**Migration (new):** `supabase/migrations/018_client_errors.sql`

```sql
CREATE TABLE public.client_errors (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  error_code      text NOT NULL,       -- 'NetworkError' | 'AuthError' | ...
  error_message   text,
  op_type         text,                -- 'upsert_user_profile' | ...
  retry_count     int DEFAULT 0,
  client_version  text NOT NULL,       -- from package_info_plus
  platform        text NOT NULL,       -- 'android' | 'ios' | 'web'
  created_at      timestamptz DEFAULT now()
);

CREATE INDEX idx_client_errors_user_created ON public.client_errors(user_id, created_at DESC);
CREATE INDEX idx_client_errors_code_created ON public.client_errors(error_code, created_at DESC);

ALTER TABLE public.client_errors ENABLE ROW LEVEL SECURITY;

CREATE POLICY "client_errors_insert_own" ON public.client_errors
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- No SELECT policy for regular users; admin reads via service_role key.
```

**Edge Function (new):** `supabase/functions/log-client-error/index.ts`
- `verify_jwt: true` + manual `auth.getUser()` per CLAUDE.md §11
- Accepts `{error_code, error_message, op_type, retry_count, client_version, platform}`
- Input validation: error_code IN enum, error_message ≤ 2K chars, op_type ≤ 64 chars
- Writes to `client_errors` table with `user_id = auth.uid()`
- Per-user rate limit: 100 errors / 24h (prevents a sync loop from spamming)
- Standard error-sanitization pattern (request_id, generic 500 body per CLAUDE.md §11)

**Client integration:** `SyncQueue` calls `log-client-error` ONLY on dead-letter (after all retries exhausted) to minimize cost. Success and transient failures stay local.

---

## 5. Migration & backwards-compatibility

- **Existing Hive data:** untouched. `syncBox` already exists; new `pending_sync_*` keys coexist with existing keys.
- **Existing call sites:** no change required. `unawaited(SyncService.instance.pushSnapshot())` continues to work — internally the service hands the op to `SyncQueue.enqueue`. The only change is that failures are now persisted + retried instead of vanishing.
- **Bundled app behavior:** users who update to the new version immediately start queuing failed syncs. First successful drain of pre-existing backlog may take minutes if they've been offline.
- **Feature flag:** `configBox.get('sync_reliability_v1', default: false)` — allows dark-launch. Gate the queue integration behind this flag for the first release; flip to `true` after a week of server-side metrics look clean.

---

## 6. Rollout — implementation checklist for follow-up session

1. [ ] Migration `018_client_errors.sql` + RLS + apply via MCP
2. [ ] Edge Function `log-client-error` + deploy via MCP
3. [ ] `sync_error.dart` + `result.dart` (types only, no tests needed beyond compile)
4. [ ] Refactor `sync_service.dart` public methods: return `Result<void, SyncError>` — mechanical conversion of existing try/catch blocks
5. [ ] `sync_queue.dart` — Hive-backed queue + backoff scheduler
6. [ ] Connectivity listener wire-up in `main.dart` after `HiveService.init()`
7. [ ] `sync_state_provider.dart` + `sync_banner.dart`
8. [ ] Mount banner in `home_screen.dart` and `profile_screen.dart`
9. [ ] Feature-flag gate (`sync_reliability_v1`)
10. [ ] Integration test (`integration_test/flows/sync_reliability_flow_test.dart`):
    - Turn on airplane mode
    - Edit profile (writes to Hive, enqueues sync op)
    - Assert `SyncQueued(1)` appears in banner
    - Turn off airplane mode
    - Assert queue drains, Supabase row updates, banner returns to `SyncIdle`
11. [ ] Dark-launch: ship with flag `false`. Manually enable for `myfitnessjourney1988@gmail.com` → monitor `client_errors` for 1 week
12. [ ] Flip flag to `true` for all users
13. [ ] Remove CLAUDE.md §4 claim about `pending_sync_queue` being in `syncBox` (until this ships) — or update it to reference this spec

---

## 7. Testing strategy

| Layer | Test | Method |
|---|---|---|
| Unit | `SyncError` discrimination, `Result` monad laws | `flutter test` |
| Unit | `SyncQueue.enqueue` + `.drain` happy path | mock Supabase, in-memory Hive |
| Unit | Backoff schedule math | `flutter test` with fake clock |
| Integration | Offline → edit → reconnect → drain | real Hive + real Supabase (staging branch), real airplane-mode toggle |
| Integration | Auth expiry during queue drain | force JWT expiry mid-drain, assert retry with fresh token |
| Manual | Banner visual — all 4 states | device test, screenshot diff |
| Canary | `client_errors` rate in staging | Supabase dashboard query |

---

## 8. Open questions

- **Do we dead-letter or retry forever?** Proposal: dead-letter after 24h of failures. User can manually re-trigger via "Retry now" in banner. Alternative: infinite retry with exponential cap at 24h between attempts. Decision: **dead-letter** (avoids infinite battery drain on hopeless ops like a validation error that will never succeed).
- **Should `pushSnapshot` be queued?** It's the AI-context push, ~once per app launch. Probably yes — AI gives worse advice with stale context. But its payload is larger (may hit queue-size limits). Decision: **queue it with special handling** — overwrite any queued `pushSnapshot` op with the latest (no need to push 5 snapshots if 4 are stale).
- **Crashlytics too?** Supabase `client_errors` covers this need at zero extra cost, but Crashlytics gives stack traces. Decision for now: **skip Crashlytics, add later if `client_errors` proves insufficient.**
- **How do we surface auth errors to the user?** Auth failure (401) means JWT expired mid-session — app should force re-login. Current handling is ad-hoc. Proposal: `SyncQueue` detects `AuthError` and emits `AuthExpiredEvent` → router redirects to login. Out of scope for this spec — flag for follow-up.

---

## 9. Related work / references

- Validation doc at `C:\Users\upend\.claude\plans\merry-sauteeing-tome.md` — full field inventory and finding verdicts
- Migration 017 (just shipped) — closed the data-layer gap; this spec closes the reliability gap
- CLAUDE.md §4 — currently lies about `pending_sync_queue` existing; correct this after ship
- CLAUDE.md §11 — Edge Function error-sanitization rule (applied to `log-client-error`)
- CLAUDE.md §15 — fire-and-forget sync pattern (preserved; this spec wraps failures in queue transparently)
