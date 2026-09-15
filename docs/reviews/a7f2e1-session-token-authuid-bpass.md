# B-pass — OBS-6 residual: session-token stale-authUid fix (a7f2e1)

reviewed_branch: fix-session-token-stale-authuid
blast_radius: account
date: 2026-07-02
reviewers: 2 context-blind adversarial lenses (correctness + cross-account-safety; test-adequacy + regression)
verdict: accepted

## Scope

The diff of `fix-session-token-stale-authuid` (6 files): the OPT-1 fix to
`lib/features/auth/providers/auth_invalidation_provider.dart` (read the LIVE
authUid, kill-switched), the new regression test, the migrated timing test, and
the diagnose-doc / SoT / auth-CLAUDE.md updates. Reviewers read the final
branch files and verified load-bearing claims against `git show main:`.

## Findings — 0 P0/P1

**Lens 1 — correctness + cross-account safety (accepted):**
1. Token recovers to userB on the owner-edge rebuild via the live authUid read
   (same seam as guarded_box.dart:238) — RED→GREEN case confirms it.
2. Cross-account isolation intact: the `authUid == hiveOwner` equality guard is
   unchanged — a stale/wrong uid still yields `'<anon>'` (verified in both the
   live-read and kill-switch paths). No leak vector.
3. Kill-switch `configBox['disable_live_auth_token_read']` (default OFF = fix ON)
   reverts to the verbatim pre-fix cached read; unopened box → fix stays ON
   (defensive), mirroring the sibling guarded_box pattern.
4. No import cycle (`show debugAuthUidResolverForTests`); `flutter analyze` clean;
   `AUTH_INVALIDATION_EXEMPT` marker preserved.

**Lens 2 — test adequacy + regression (accepted):**
1. `session_token_stale_authuid_recovery_test.dart` is genuine RED→GREEN (case 1
   fails on the pre-fix cached read, passes on the live read) + covers the
   kill-switch revert + cross-account isolation in both states.
2. `auth_invalidation_timing_test.dart` correctly migrated from the now-dead
   `currentUserProvider.overrideWith` to the `debugAuthUidResolverForTests` seam.
3. No other contract test breaks (auth_invalidation_contract, session_teardown_
   skeleton_guard, auth_hive_owner_agreement, wrap_user_scoped_box_disagreement).
   16 tests green across 5 files; analyze clean.

## Verdict

verdict: accepted

No blocking defects. The fix is sound at the code level, the regression test is a
genuine RED→GREEN, both test migrations are correct, cross-account isolation is
preserved, and the documentation set is complete.
