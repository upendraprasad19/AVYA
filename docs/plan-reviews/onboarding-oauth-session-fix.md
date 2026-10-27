---
branch: onboarding-oauth-session-fix
date: 2026-08-04
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/onboarding-oauth-session-fix-bpass.md
---

# Plan review — onboarding-oauth-session-fix (Unit 1, diagnose d4e8a2)

## Why this record exists, and why it is late

This batch was merged into **local** `main` (merge `f0b98c8b`, never pushed)
believing it was `feature`-tier. It was not: `lib/features/onboarding/**` is
pinned `account` at `docs/blast_radius.yaml:185`. §4.12's ×2 independent
review therefore applied and had not been run.

**The tier then escalated again, during the review itself — worth stating
plainly because it is the kind of thing that silently under-gates a batch.**
Closing round-1 finding S3 required a `@visibleForTesting` seam in
`lib/core/services/hive_user_session.dart`, which is pinned **`platform`**.
So the fix for a review finding raised the batch's own review bar. Re-derived
per-file at commit time rather than assumed:

| tier | file |
|---|---|
| **platform** | `lib/core/services/hive_user_session.dart` |
| account | `lib/core/router/app_router.dart`, `lib/features/onboarding/providers/onboarding_provider.dart` |
| feature | the docs, the test, `scripts/cqrs_query_naming_lib.dart` |

`platform` requires `bpass: accepted` in addition to `review_rounds >= 2` —
both are satisfied and were done before this was noticed, not retrofitted to
clear the higher bar. The `blast_radius:` field above records `platform`
accordingly; note the keystone gate recomputes the tier LIVE from the merge
diff and does not trust this field, so the value is documentation rather than
the control.

The gap was independently detected by a **different session** on this machine,
whose unrelated push CI's keystone gate correctly refused — filed as **OI-87**.
That item warns explicitly that the blocked session's fastest unblock would be
to author the missing record itself, which would be a **false attestation**.
This record is not that: the two rounds below were really run, by fresh
context-blind reviewers, and each found real defects. Every finding was
verified against the actual files before being acted on.

## Scope

One idempotent defensive call —
`await HiveUserSession.ensureOpenedForCurrentSession();` — inserted in
`completeOnboarding()` (`onboarding_provider.dart:409`) before its first
user-scoped Hive write (`:414`), so the safety is an invariant of the method
rather than an incidental ordering property of `RestoringScreen`. Plus its
regression test, one new `@visibleForTesting` test seam, a router doc-comment
correction, and citation repairs.

## Review arc

**Round 1 — NOT CONVERGED (2 blocking, 4 should-fix).**
- B1 duplicated comment block; B2 this record absent.
- S1 the diagnose-doc's own `blast_radius:` said `feature`.
- **S2 (material)** — the test pinned a failure branch onboarding cannot
  reach. `wrapUserScopedBox` has two owner-null branches; UNAUTHENTICATED
  throws `'HiveUserSession not opened'`, AUTHENTICATED returns
  `GuardedBox.empty`. An onboarding user is authenticated by definition, but
  the pure-VM harness had no Supabase, so the test silently took the first.
- **S3** — the only assertion that failed when the guard was deleted was a
  source-grep (rule 21: presence-only).
- S4 — `app_router.dart`'s `shouldGateOnSessionOpen` doc claimed onboarding's
  "own writes open/own the boxes via the sign-up bootstrap", the exact claim
  this diagnose disproves, sitting where a refactorer would read it.

**Round 2 — NOT CONVERGED (1 blocking, 3 should-fix). Every finding was
introduced by round 1's own fixes.**
- **B2-1 (blocking)** — fixing S2, round 1 replaced the message matcher with a
  bare `isA<StateError>()`. All three owner-null paths throw `StateError`, so
  it could no longer tell the reachable branch from the unreachable one. The
  reviewer proved it: deleting the seam line left the suite **green** while
  pinning the wrong branch again. Round 1 fixed S2 and removed the only thing
  keeping it fixed.
- B2-2 — the S2 comment named the wrong throw site (`rawBox:172`, not the
  write methods; `HiveService.userBox` unwraps to `.rawBox` first).
- B2-3 — round 1's own edits shifted line numbers and staled citations.
- **B2-4** — round 1's S3 justification was refuted. It had recorded the
  behavioral test as blocked by an undiagnosable `_AssertionError`. False:
  `completeOnboarding`'s catch passes `e.toString()` to
  `ErrorTelemetry.logEvent`, and `debugOnLogEventForTests` exists for exactly
  this. Reading it took one run and produced
  `Unknown fitness goal token "fat_loss"` — round 1's own test data was
  invalid (`'lose_fat'` is the real token). The "blocker" was a typo promoted
  into documented fact. With it corrected the behavioral test works and ships
  as **C1**.

**B-pass — rejected (1 P1, 5 P2), then accepted after fixes.**
- **P1** — the new seam grew `hive_user_session.dart` by 13 lines, silently
  invalidating **six** SoT registry citations that were correct before this
  batch, plus a live gate script's pointer. Round 2's sweep had covered only
  `onboarding_provider.dart` yet the doc said "All corrected" — a false
  attestation, now fixed and re-worded. Note the shift is **not uniform**
  (+6 below line 34, +13 below ~116); the B-pass's own suggested value for one
  range was off for that reason, and each corrected line was verified by
  reading it rather than by arithmetic.
- P2s — stale frontmatter (said 3 tests; forwarded to a withdrawn rationale),
  two more wrong citations, a claim that this record already existed, and
  **C1's own `catch (_) {}`** paired with a confident comment that
  `completeOnboarding` "cannot finish". Removing the catch immediately
  surfaced what it hid (`HiveError: Box not found` — the unseeded exercise
  library). C1 now asserts no swallowed failure is of the session-ordering
  class, tolerating the unrelated harness limitation without going blind.

## Ground-truth verification

- Blast radius re-derived from the real merge diff, every round.
- **Negative control re-run independently in all three passes**: the guard
  line deleted (not commented — a commented line leaves the substring intact
  and keeps a source-pin green), suite re-run, both C1 and C2 fail, file
  restored and verified identical, suite green again. C1's failure carries
  the real production telemetry: `guarded_box_null_owner_authenticated` →
  `GuardedBox.empty: rawBox unavailable`.
- Seam safety traced, not assumed: 3 write sites (all test lifecycle), 1
  same-library read, production leaves it null so behavior is byte-equivalent
  via the `??` fallback. A seam/Supabase uid mismatch cannot silently cross
  accounts — it trips the disagreement guard and `_assertOwnership` (which has
  no seam) → `HiveOwnershipException`.
- Test order-independence verified by execution under a randomized seed.
- Every `file:line` in the diagnose-doc and both changed `line_range` values
  hand-checked (the registry validator only bounds-checks `end <= file
  length`, so wrong-but-in-bounds values pass silently).

## Convergence

Converged. The production change is one idempotent call whose no-op behavior
on the already-safe path was confirmed in every round; all defects found were
in the surrounding test and documentation scaffolding, and each was fixed and
re-verified by execution.

Not fixed here, deliberately, and filed rather than folded in: `GuardedBox.empty`'s
"reads serve empty, writes throw loud" design is bypassed by the seven plain
`Box` getters in `hive_service.dart:225-231`, which call `.rawBox` and so throw
on *reads* too. Pre-existing, unrelated to this batch — folding an unrelated
core-services change into an already-reviewed `account` diff would invalidate
the review it just passed.
