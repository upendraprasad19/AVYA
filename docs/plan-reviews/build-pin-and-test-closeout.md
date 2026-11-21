---
branch: build-pin-and-test-closeout
date: 2026-10-21
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
---

# Plan-review record — Razorpay SDK pin + test close-out (`build-pin-and-test-closeout`)

Founder request (chat 2026-10-21, after PR #140): "fix all three": pin the Razorpay Android
dependency that failed `main` CI, write the missing diagnose-doc for the three Windows path test
fixes, and deal with the load-sensitive restore test. Plan: `docs/plans/build-pin-and-test-closeout.md`.

## Rounds

Both rounds were fresh, context-blind Sonnet reviewers that verified claims against code, the pub
and Gradle caches, and Maven Central.

- **R1:** NOT converged.
  - P1: checkout's own POM declares `standard-core` at `LATEST`. Pinning only `checkout` leaves the
    same failure mode, and the shipped SDK had silently moved to standard-core 1.7.20
    (published 2026-10-14).
  - P1: the planned verification could not discriminate. It now counts every `com/razorpay/**`
    listing fetch (79 → 0 measured).
  - P2s: an unimplementable test mirror (replaced by a plugin-lock re-audit check); validator
    realities for the docs; the stub's re-sort cost behind U3 (memoisation rejected, with the
    reason); an honest U3 claim.
  - P3s: the full `sync_nutrition.dart` path; the ambiguous id `d4e7c2` (cite by filename); the
    SKILL.md index row; the reproducible gate-measurement command; the cold CI Gradle cache;
    softened `force` wording.
- **R2:** CONVERGED (P3 only), on the v2 plan.
  - A fixed Kotlin shape and pin-map test.
  - A re-audit recipe in the failure message.
  - OI-383 for the frozen-SDK intention.
  - "All built AABs +46..+48" wording.
  - A whole-app listing measurement.
  - In-repo anchors for the docs.
  - Backfilled index rows for 2.109/2.110.
  - The retirement cleanup list.
  - All folded in as v3.

## Changed during execution (recorded in plan v3)
- **One `fix(build)` commit with three `closes-diagnose:` trailers instead of three commits.**
  Bug classes 2.111 and 2.112 share two files, so a split would need partial staging.
- **Whole-app measurement** (`prodDebugRuntimeClasspath`; the release configuration needs the
  signing key). The only remaining dynamic selectors are ranges with a preferred version
  (androidx, firebase-messaging), which do not float the shipped bytes. They are deliberately not
  pinned; the reason is in diagnose a6c3e9.
