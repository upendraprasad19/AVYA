---
hermes_pass_id: 2026-06-21-hermes-fix-session-open-race
ran_at: 2026-06-21T20:38:00+05:30
batch_scope: fix-session-open-race (b8e3f1) — guarded_box serve-empty + app_router Part B + restoring_screen _onContinueAnyway
lens_set: [cross_account_isolation, routing_loop_correctness, provider_rebuild_race, telemetry_test_sot_completeness]
agents_dispatched: 4
findings_total: 4
findings_by_severity: { P0: 0, P1: 0, P2: 2, false_alarm: 2 }
verdict: accepted
---

# Hermes Pass — fix-session-open-race (b8e3f1)

Four fresh context-blind Opus lenses on FIX-1 (the cross-account session-open
race fix). Platform-tier (the change touches `guarded_box.dart`, the Layer-A
isolation primitive). Run alongside the per-commit B-pass
(`docs/reviews/fix-session-open-race-bpass.md`).

## Summary
- **0 P0, 0 P1.** 2 P2 (both resolved in-batch — telemetry de-overclaim + the
  RangeError guard, which the B-pass already actioned). 2 false_alarm.
- Ship-blockers: none.

## Findings by lens

### L1 — cross_account_isolation — VERIFIED CLEAN (no leak)
The reviewer tried to refute leak-safety and could not. Every `GuardedBox.empty`
surface short-circuits: reads → null-object (`:96/:132/:138/:144/:150/:156/:162`),
writes → `StateError` (`:102/:108/:113/:119/:125`), `rawBox` → throws (`:171`),
`_EmptyBoxStub.noSuchMethod` → throws (`:189`). The stub holds no file binding, so
no write can target the wrong box. The stub is returned **by value, not cached** —
the next call after `openForUser` falls through to the real namespaced box. The
`supabaseAuthUid` served is the live session uid; the test seam is null in prod
(`?? Supabase…` fallback, grep-verified). The disagreement branch (owner≠null)
runs first and is unaffected. **No cross-account read OR write leak.**

### L2 — routing_loop_correctness — VERIFIED CLEAN (no loop, no lost route)
Full `_authRedirect` branch trace: the guard sits after splash/restoring/induction
passthroughs + the `!isAuthenticated` return, and onboarding (all `/onboarding/*`
+ `/plan-generation` sub-routes) is exempt. `/restoring` is exempt BEFORE the
guard, so no self-loop. Every `/restoring` exit either opens the session
(`_goHome`→`openForUser`) or routes to an exempt onboarding route. `_onContinueAnyway`
now opens the session before `/home`, closing the one prior gap (the reinstall
~36s-restore CONTINUE path). 1 LOW (the defensive `catch` in `_onContinueAnyway`)
— actioned as B-pass F1.

### L3 — provider_rebuild_race — VERIFIED CLEAN (heal fires)
`authUserIdTokenProvider` emits `'<anon>'` during the owner-null window; all 8
spot-checked home providers `ref.watch` it in `build()`; `openForUser` drives
`currentOwnerListenable` under `_sessionLock` → `hiveSessionOwnerProvider`
invalidates → providers rebuild with real data. No provider caches the empty
result (grep-enforced by `auth_invalidation_contract_test.dart`). No `build()`
writes, so the throwing empty-stub write is never hit from a rebuild. 1 LOW latent
maintenance-contract note (a future exempt route reading user-scoped Hive
pre-session) — no live bug; no fix required.

### L4 — telemetry_test_sot_completeness — 2 P2 (resolved), rest PASS
- **F1 (P2, resolved by-design):** `guarded_box_null_owner_authenticated` is
  LOW-priority on both client + server while its twin is HIGH. Resolved: LOW is
  correct for a high-volume pre-open timing diagnostic (sibling of the LOW
  `guarded_box_auto_open_fallback`), not a per-instance alarm; comment
  de-overclaimed. No redeploy.
- **F6/RangeError (P2, resolved):** `.substring(0,8)` length-guarded (B-pass F3).
- **PASS:** behavioral test drives the real path + asserts both branches +
  write-throw + resets the seam in tearDown (F2); the auto-open source-grep
  literals (`Supabase…currentUser?.id`, `Hive.isBoxOpen(`, `throw StateError(`)
  are all preserved (F4); the SoT `auth_hive_owner_agreement` reader manifest +
  telemetry list + tests list are complete + consistent (F5); `touched_layers_checked`
  tier coverage correct, Tier 6 correctly N/A — no server change (F7).

## Action items
- [x] F1 (recordNonFatal) — fixed.
- [x] F2 (kill-switch) — fixed.
- [x] F3 (RangeError guard) — fixed.
- [x] L4-F1 (telemetry by-design) — comment de-overclaimed.
- [x] F4 (app_router tier) — false_alarm (already account via catch-all).
- [x] F6 (@visibleForTesting) — false_alarm (matches local testBypassOwnership convention).

## Verdict
No P0/P1. All P2 resolved in-batch. Isolation/routing/race verified clean.
**accepted.**
