---
reviewed_at: 2026-06-21T20:40:00+05:30
staged_against: fix-session-open-race (b8e3f1)
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind) + 4 Hermes Opus lenses
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 6
verdict: accepted
---

# Code Review (B-pass) — fix-session-open-race (b8e3f1)

Fresh context-blind Sonnet B-pass (5 lenses) over the FIX-1 diff
(`guarded_box.dart` serve-empty + `app_router.dart` Part B guard +
`restoring_screen.dart` `_onContinueAnyway`). All findings triaged + resolved
in-batch (no deferrals).

## Findings

### F1 — P1 — function_exception_swallow — ACCEPTED (fixed)
- **file:** `lib/features/auth/screens/restoring_screen.dart` `_onContinueAnyway`
- **claim:** the `catch (_)` around `openForUser` swallowed all failures with no
  telemetry. If `openForUser` is genuinely unrecoverable (corrupt box), the
  user silently loops `/home`→`/restoring`→Continue with zero observability.
- **resolution:** catch now captures `(e, st)` and fires
  `unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: 'restoring_continue_openforuser_failed'))`
  before falling through. Navigation stays non-fatal; the corruption is now visible.
- **status:** fixed.

### F2 — P1 — blast_radius_mismatch — ACCEPTED (fixed)
- **file:** `lib/core/services/guarded_box.dart` (now platform-tier per the
  registry change in this batch)
- **claim:** platform-tier `requires: feature_flag` (`docs/blast_radius.yaml:25`),
  but the new serve-empty path had no kill-switch (§4.6 risky-auth-change protocol).
- **resolution:** added the `configBox['disable_null_owner_serve_empty']`
  kill-switch — read defensively from the GLOBAL `configBox` (try/catch defaults
  the fix ON if unopened); when set, the branch reverts to the old loud-throw
  path verbatim. §4.6 satisfied.
- **status:** fixed.

### F3 — P2 — unawaited_no_error_sink / RangeError — ACCEPTED (fixed)
- **file:** `lib/core/services/guarded_box.dart` (telemetry message)
- **claim:** `pendingAuthUid.substring(0, 8)` would `RangeError` on a sub-8-char
  uid. Production uids are 36-char UUIDs (safe), but the test seam could pass a
  short string. The `unawaited(ErrorTelemetry.logEvent(...))` itself matches the
  two sibling sites + `logEvent`'s internal sink (no error-sink gap).
- **resolution:** length-guarded — `pendingAuthUid.length >= 8 ? substring(0,8) : pendingAuthUid`.
- **status:** fixed.

### F4 — P2 — blast_radius_mismatch — FALSE_ALARM (annotated)
- **claim (Sonnet):** `app_router.dart` is untiered → falls to `feature`.
- **verification:** `app_router.dart` matches the `lib/core/** → account`
  catch-all at `docs/blast_radius.yaml:108` (declared above the `default_tier`).
  It is already **account**-tier. The Sonnet agent missed the catch-all.
- **status:** false_alarm.

### F5 — P2 — telemetry priority (Hermes L4 F1) — ACCEPTED (by-design + de-overclaim)
- **claim:** `guarded_box_null_owner_authenticated` is LOW-priority on client
  (`error_telemetry.dart highPriorityOpTypes`) + server
  (`log-client-error HIGH_PRIORITY_OP_TYPES`), so it can be dropped under a burst,
  while its twin `guarded_box_disagreement` is HIGH.
- **resolution (by-design):** LOW is correct here. This event is a **high-volume
  timing diagnostic** of the pre-open window (fires on every account switch),
  mirroring the existing LOW sibling `guarded_box_auto_open_fallback` — NOT a
  per-instance cross-account ALARM like `guarded_box_disagreement` (which is HIGH
  precisely because every instance is security-relevant and rare). Promoting it
  would flood the HIGH lane with an expected transient. The AGGREGATE count still
  surfaces a persistent ordering bug. The code comment was de-overclaimed to say
  this explicitly (no "keeps masking measurable" overclaim). No allowlist change,
  no server redeploy.
- **status:** false_alarm (by-design), documented.

### F6 — P2 — @visibleForTesting seam (Hermes L4 F3) — FALSE_ALARM (local convention)
- **claim:** `debugAuthUidResolverForTests` is a public mutable top-level var
  with no `@visibleForTesting`.
- **resolution:** matches the immediate local sibling `GuardedBox.testBypassOwnership`
  (also a public mutable static, doc-commented, no annotation) 3 lines away.
  The `?? Supabase…` fallback makes leaving it null fully production-safe; no
  production code assigns it (grep-verified). Consistency with the local pattern
  wins over adding a `meta` import.
- **status:** false_alarm (local convention).

## Cross-account isolation / routing / race (Hermes L1-L3) — VERIFIED CLEAN
- **Isolation (L1):** no leak. Every `GuardedBox.empty` read returns
  null/empty/0/false/true; every write (put/putAll/delete/deleteAll/clear) +
  `rawBox` THROW; `_EmptyBoxStub.noSuchMethod` throws. Empty stub holds no file
  binding (no wrong-box write). The stub is returned by value, never cached —
  the next call after `openForUser` falls through to the real namespaced box.
  Disagreement branch (owner≠null) runs first, unaffected.
- **Routing (L2):** no infinite loop, no lost destination. Guard sits AFTER the
  splash/restoring/induction passthroughs + `!isAuthenticated` return; onboarding
  is exempt (StartMissionBrief/ResumeOnboarding navigate pre-session). Every
  `/restoring` exit path opens the session before a gated nav; `_onContinueAnyway`
  now opens it before `/home`.
- **Race (L3):** heal fires. `authUserIdTokenProvider='<anon>'` during the window;
  all home providers `ref.watch` it; `openForUser` drives `currentOwnerListenable`
  under `_sessionLock` → re-invalidate → rebuild with real data. No provider caches
  the empty result; no build-time write hits the throwing stub.

## Verdict
All 6 findings resolved: 3 fixed in-batch (F1/F2/F3), 3 false_alarm/by-design
(F4/F5/F6). Isolation, routing, and race lenses verified clean. **accepted.**

## Addendum — OBS-4 logout-flash delta (folded into the branch)
A focused fresh Sonnet B-pass over the OBS-4 delta (`HiveTabScaffoldMixin.isSessionTearingDown`
getter + the 4 tab screens' loading-branch guard + `session_teardown_skeleton_guard_test.dart`).
5 lenses, 5 findings, all resolved:
- **F1 (guard re-renders):** FALSE_ALARM — `ref.watch` in the getter registers the dep; the
  screen rebuilds to content once `openForUser` flips the token off `'<anon>'`. No stuck-skeleton.
- **F2 (nutrition app-bar shows during teardown):** by-design — nutrition's *normal* loading
  already renders the app bar + skeleton body (body-ternary), so the teardown guard matches its
  own pattern; the other 3 are pure-skeleton because that's THEIR normal loading shape. No change.
- **F3 (future widget tests auto-skeleton without a token override):** no current breakage — the
  agent found ZERO existing unit tests for the 4 tab screens (they're integration-tested); the new
  `session_teardown_skeleton_guard_test.dart` demonstrates the override pattern for future authors.
  Confirmed by the full suite (green).
- **F4 (import):** FALSE_ALARM — new `auth_invalidation_provider` import is correct + used.
- **F5 (AI-Coach 5th tab):** FALSE_ALARM — `AiCoachScreen` has no `HiveTabScaffoldMixin` and no
  throwing user-scoped Hive read (in-memory chat state), so it correctly needs no guard.
OBS-4 delta verdict: **accepted** (cosmetic, no isolation impact, full suite green).
