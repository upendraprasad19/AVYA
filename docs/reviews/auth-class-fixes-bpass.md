---
reviewed_at: 2026-08-17T04:10:00+05:30
staged_against: ab1886b7
branch: auth-class-fixes
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 6
false_alarm_count: 0
verdict: accepted
---

# Code Review (B-pass) — auth-class-fixes @ ab1886b7

Three P0, one P1, two P2. **Zero false alarms.** Every finding was independently
re-verified by me against the repo before acting. All six are fixed in-batch
(§4.2); nothing is carried forward.

**The pass paid for itself on Finding 1**, which is the sharpest possible form of
`guard_without_its_mirror`: the commit fixed "an identity captured before an
await is a snapshot" for `e5c2d1` in the sync layer, and *reproduced the exact
same defect, unmirrored, in the new auth-layer join shipped in the same commit*.
The reviewer did not argue it — they wrote a throwaway test and executed it.

## Finding 1 — P0 — guard_without_its_mirror — **FIXED**
- **file:line:** `lib/core/services/supabase_service.dart:195`, `:209-219`
- **claim:** `_inFlightRefresh` had no identity affinity. A caller acting for a
  different session joined the in-flight future and received the other
  identity's token, never running its own refresher.
- **verification (reviewer's, by execution):** a temporary test calling
  `coalescedRefresh` with a slow identity-A refresher, then a distinct identity-B
  refresher while A was in flight, produced
  `refresherARan=true refresherBRan=false resultB=token-for-USER-A`.
  The existing suite could not see it: all four cases used ONE shared refresher,
  so the mirror case was structurally absent from the file.
- **fix:** `_inFlightRefreshOwner` added; the join now requires
  `_inFlightRefreshOwner == ownerId`, and a **sink-side re-check on resolve**
  (`guarded()`) returns null if the live identity changed while the refresh was
  in flight. `ensureFreshToken` passes `ownerId: session.user.id`.
- **mutation proof:** reverting to the identity-blind join reddens
  `cross-account (B-pass finding 1) a DIFFERENT identity never joins` — and the
  test hangs 30s doing so, because B parks on A's future, which is the bug.
- **status:** fixed

## Finding 2 — P0 — blast_radius_mismatch — **FIXED**
- **file:line:** `lib/core/services/supabase_service.dart:222-230`
- **claim:** the `disableRefreshJoin` kill-switch was decorative. Its doc claimed
  it was "flipped by the same boot code that reads the flag"; no such boot code
  existed. `grep -rn "disable_token_refresh_join"` matched only the doc comment
  itself. Platform tier's `requires: [feature_flag]` was satisfied in appearance
  only. The two switches shipped in one commit were asymmetric — `signInTimeout`'s
  read Hive and worked; this one did not.
- **fix:** now a lazy Hive read (`configBox['disable_token_refresh_join']`)
  mirroring `signInTimeoutDisabled` exactly, with a `disableRefreshJoinForTest`
  override. The false "no Hive import" justification is deleted and the real
  history recorded in its place.
- **status:** fixed

## Finding 3 — P0 — commit-integrity — **FIXED**
- **claim:** `ab1886b7` claimed `closes-diagnose: e5c2d1` and committed that
  doc at `status: fixed`, while the actual guard code existed only as
  uncommitted working-tree edits — in no commit at all.
- **note:** this was true and is mine. I had independently found it minutes
  before the review returned (`git log --all -S "ownerAtStart"` → empty: the
  e5c2d1 fix had never existed in history, in any branch). The reviewer reached
  it from the opposite direction and confirmed it.
- **fix:** the guards, the pure predicates and
  `session_owner_inflight_guard_behavioral_test.dart` are committed in this
  batch. The ledger flip was performed only AFTER verifying each entry's code
  had landed — the discipline `B1` in the post38 ledger exists to enforce
  ("a closure ledger describes GIT, not intent").
- **status:** fixed

## Finding 4 — P1 — writer_reader_drift — **FIXED**
- **file:line:** `docs/sot_registry.yaml` (`notifications_inbox_id_contract`),
  `lib/features/profile/services/notification_inbox_service.dart:136-138`
- **claim:** the registry cited `:136` as writer AND reader — a line this commit
  never touched. The real fix is `newLocalNotificationId()` at `:187`, called
  from `:197`. **Compounding defect:** `:138`'s fallback
  `'os-${DateTime.now().microsecondsSinceEpoch}'` is *not UUID-shaped* and
  carries the identical defect class `a4f1c8` fixes, reachable whenever a real
  OneSignal push arrives with an empty `notificationId`. The diagnose doc's own
  `recurrence:` states the rule it violates: "if the column is uuid, every
  writer that can reach it must mint uuids."
- **fix:** the OneSignal fallback now routes through `newLocalNotificationId()`;
  the registry entry cites all three real writers plus `isUuidShaped` as the
  reader, and records why the original citation was wrong.
- **status:** fixed

## Finding 5 — P2 — guard_without_its_mirror — **FIXED**
- **file:line:** `lib/core/services/supabase_service.dart:260-273`
- **claim:** `_refreshToken`'s `refreshSession()` had no ceiling, in a commit
  whose stated defect class is "an await that can never return". Worse, the join
  made it *strictly worse than before*: pre-fix a stall stranded only the
  concurrent callers, each on an independent connection; post-fix every caller
  for the life of the process joins the same permanently-pending future and no
  independent attempt is ever made again.
- **fix:** `refreshTimeout` (20s) applied to `refreshSession()`. The timeout
  lands in the existing catch, `whenComplete` clears the in-flight field, and
  the next caller starts a genuinely new refresh — retry restored.
- **status:** fixed

## Finding 6 — P2 — informational — **no change needed**
- `signInTimeoutDisabled` reads `... == true`, so a non-bool configBox value
  yields `false` and the timeout stays applied — the safe direction. Correct as
  written; the reviewer flagged only that the real Hive line has no coverage,
  which is inherent to configBox not being open in unit tests (the reason the
  `...ForTest` override exists).
- **status:** no_change_needed

## Lenses that returned clean
- **function_exception_swallow** — the single raw call site `_invokeRaw` routes
  through `retryColdStart`, which catches `FunctionException` and reads
  `e.status`/`e.details`. Clean.
- **secrets_in_tree** — `git show ab1886b7 | grep -nE "sk-|rzp_live_|AKIA…|-----BEGIN|eyJhbGciOiJIUzI1NiIs"` → 0 matches. Clean.
- **unawaited_no_error_sink** — ~16 new `unawaited(` sites, all wrapping
  `ErrorTelemetry.logEvent`/`recordNonFatal`; both method bodies end in a
  swallowing catch, i.e. a declared internal sink. Clean.
- **blast_radius tier** — max across touched paths is `platform`
  (`lib/core/services/sync/**`); the commit's self-declared tier is correct.
  (The `requires: feature_flag` substance gap was Finding 2, kept separate.)

## Tuning
False-alarm rate **0/6** → no lens tuning. Lens 6 (`guard_without_its_mirror`)
produced 3 of the 6 findings including the P0, and its "mutate it and run it"
method is what produced the decisive evidence rather than an argument. It
continues to earn its place.
