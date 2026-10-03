---
branch: auth-class-fixes
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/auth-class-fixes-bpass.md
tier: platform
reviewed_at: 2026-08-17T04:20:00+05:30
---

# Plan review — auth-class-fixes (crash-recovery batch)

## What this batch is

The founder's Windows Claude app crashed repeatedly across several concurrent
sessions, each in its own worktree, leaving work at every stage. This batch is
the recovery: preserve everything unrecoverable first, then land the class of
bug the preserved work was about.

## Review rounds

**Three independent context-blind rounds on the PLAN, plus a B-pass on the code.**

| Round | Scope | Result |
|---|---|---|
| 1a — ground truth | re-derive every factual claim from git / filesystem / live prod | 2 P0 + 4 P1 |
| 1b — discipline | CLAUDE.md §4 compliance, deferral audit, gate satisfiability | 3 P0 + 6 P1 |
| 2 — on the HARDENED plan | "the corrections are the most likely source of new defects" | 2 further P0 |
| B-pass — on the code (`ab1886b7`) | 6 lenses, fresh Sonnet | 3 P0, 1 P1, 2 P2, **0 false alarms** |

Every finding was re-verified by me against the repo before acting. §4.12.1's
split rule was applied: after round 2 still surfaced new P0s, the plan was
narrowed to the converged unit rather than reviewed a fifth time.

## What the reviews refuted — corrections that changed the work

- **"P0-1 is self-resolving, cite the Hermes report."** False.
  `check_plan_review_record_exists.dart:860` requires line-anchored
  `verdict: accepted` and says *"Fabricated acceptance is not allowed."* The
  report reads `block_ship`. The proposed 3a/3b/3c ordering was unmergeable at
  3a by construction.
- **"The fix precedent exists in the same file."** True on `main`, false in the
  worktree — which was **92 commits behind** and did not contain
  `signOutTimeout` / `_inFlightSignOut` at all. `auth_provider.dart` was 141
  insertions / **102 deletions** against main, and those 102 were main's own
  shipped sign-out work. Committing the rescued tree as-is would have reverted
  it. The rebase was made mandatory; post-rebase the diff is 1055/65 and the
  sign-out block is verified present.
- **"77 open OIs vs 49 closed."** False — `OPEN_INDEX.md` says **58 open**,
  closed is 68. I had counted headings, not statuses, and the error ran in the
  direction that supported my own argument.
- **"retire_worktree's four-leg predicate prevented data loss here."** False for
  this worktree: `post38-auth-fixes` is in a hardcoded `_protected` set that
  short-circuits *before* the dirty and ignored legs run.
- **"Gate 40 will fail without a closure YAML."** False, and worse —
  `validate_audit_closure.dart:78` validates ledgers it *finds*. A missing one
  is silent.
- **Committing the diagnose-docs would have been BLOCKED** by
  `check_sot_registry_citations.dart`, whose own header names three of these
  exact docs as the false-green it was written to catch.

## Ground-truth verification performed

- `git log --all -S "ownerAtStart"` → **empty**: the e5c2d1 fix had never
  existed in any commit on any branch, despite its doc reading `status: fixed`.
  It was not lost in the crashes; it was never written.
- Migration 120 confirmed applied in prod; migration 119 confirmed hand-applied
  and live (`client_errors.user_id is_nullable = YES`) while absent from
  `schema_migrations` by design.
- `log-client-error` v13 read live via the Management API — carries all SIX
  `PRE_AUTH_OP_TYPES` entries, resolving a ledger entry that was blocked on a
  redeploy which had in fact already happened.
- All three bugs confirmed still live on `main` before any fix was written.
- Every one of the 28 post38 `blocked_on_user` entries checked for landed code
  before its terminal state was flipped.

## Mutation proofs (rule 21)

| Guard | Mutation | Result |
|---|---|---|
| `coalescedRefresh` join | revert to pre-fix racing form | `Expected: <1> / Actual: <15>` — the exact prod signature |
| `coalescedRefresh` identity affinity | revert to identity-blind join | cross-account test reddens, hanging 30s as B parks on A's future |
| `boundSignIn` ceiling | revert to unbounded await | test HANGS, fails on the 30s harness timeout — which IS the bug |
| `ownerChangedSince` sink guards | delete ONE of five | 2 tests redden, naming the exact line and method |
| `ownerChangedFrom` predicate | force `false` | 2 tests redden incl. the fail-safe null case |

All reverted; 20/20 green after revert, 50/50 across the auth contract suite.

## Deliberate decisions worth recording

- **The timeout does NOT sign out.** The session usually exists by the time the
  ceiling fires — it is the post-auth hydration that wedges — and destroying a
  valid session during a backend brown-out makes the user's position worse.
- **COALESCE, never CACHE.** A caller arriving after completion starts a real
  new refresh; a cached token served forever would be a worse bug than the race.
- **The sink guards abort mid-unit and that is correct.** Verified, not assumed:
  `_syncNutritionLogs` has no skip-unchanged optimisation, so it re-walks every
  row each pass and fully repairs an aborted row. Finishing the unit under
  someone else's session is not repairable.
- **`presence_only:` was deliberately not used** for the five new SoT concepts.
  It is the hatch for static/Deno-EF concepts; writing the fixes is what made
  the honest path available.

## Known-open, explicitly stated

- **No APK.** The founder withheld build authorization for this run. These fixes
  are in the repo only — users remain on `1.0.0+38` and keep hitting the Google
  sign-in spinner (`d3a7c9`) until a `+39` is approved. **This is the batch's
  single most important residual.**
- **REC-tooling-gap** (`auth-class-fixes.closure.yaml`) is `blocked_on_user`: an
  old-enough worktree cannot satisfy §4.13 and §4.3 simultaneously without
  hand-copying tooling. Filed with the finding closed and the fix shape open.
- OI-110 (~89 pre-cutoff dangling SoT citations) and OI-111 (~26 sibling sinks
  sharing the stale-userId shape) remain open and are unchanged by this batch.
