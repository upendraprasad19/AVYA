---
review: B-pass (context-blind, adversarial)
branch: workout-adherence-8a3a1
scope: ⑧ Batch 8 · UNIT 3-a1 (REG-1) — PRO stuck-on-free-expired-card fix (always-on)
blast_radius: account
verdict: accepted
---

# B-pass — ⑧ UNIT 3-a1 (REG-1 PRO stuck-card fix)

Self-initiated ≥account B-pass (§4.3) on the implemented, staged diff BEFORE the `--no-ff` merge. A
context-blind adversarial reviewer verified every claim against the actual code (not comments / the
diagnose-doc), diffing the old splash body in `git HEAD` against the extracted shared function.

## Verdict: accepted — no P0, no P1.

## Findings

**P2-1 — concurrent splash+card double-generate (RESOLVED, hardened beyond the review).** The splash
fires `advanceProPhaseIfExpired` unawaited and the card can fire it on tap; the reviewer found the two
could both pass the `isPhaseExpired()` gate in the sub-second window before either writes, and verified
the outcome is BENIGN (both read `current_phase = N` from the same base → both write `N+1`, never `N+2`;
schedule keys are deterministic → last-writer-wins, not an interleaved mix; `pushSnapshot` is coalesced) —
"acceptable as-is; a shared in-flight lock would be over-engineering." I had ALREADY added a single-isolate
in-flight mutex (`_advanceInFlight` in `pro_phase_advance.dart`) after the reviewer's snapshot, which
eliminates the double-generate entirely (the check+set is atomic — no `await` between them — so a
concurrent splash-pass + card-tap can never both proceed to generation). The mutex is covered by the same
"guards keep redundant calls safe" test group.

**P2-2 — Train watches `subscriptionInfoProvider` at build scope (ACCEPTED as-is).** Train reads `isPro`
at the top of `_buildContent` (`screen.dart`), whereas Home scopes it inside the expired branch, so
`_buildContent` rebuilds on a subscription `isVerifying` flip even when the phase is not expired. The
reviewer verified this is HARMLESS (cheap, idempotent) and CONSISTENT with the ~10 other build-scope
`subscriptionInfoProvider` watchers already in the codebase, and marked it "not required." Accepted as-is:
it is a codebase-consistent style choice, not a bug and not a deferral — tightening it would diverge Train
from the established watch convention (and churn the source-anchored test that pins the `final isPro =`
line) for no correctness or measurable-perf gain.

## Classes verified CLEAN (reviewer read the code, did not assume)
- **Free-path / non-expired behavior unchanged** — both `PlanExpiredCard` sites are byte-identical with the
  same `onRedoComplete` invalidation set; the PhaseGeneratingCard `onGenerated` invalidates the SAME
  providers so the card disappears post-generation; the rest-day fall-through stays null-safe.
- **Extraction fidelity** — line-by-line diff of old splash body vs `advanceProPhaseIfExpired`: identical
  profile keys/defaults, identical progress bump, identical `saveProgress` + unawaited `pushSnapshot`; both
  guards preserved (`uid == null`; `isPro()`/`isPhaseExpired()`); only additive `void`→`Future<bool>`.
- **Reactivity correct** (build-scope `ref.watch`; the card uses read-semantics for its action), **null-safe**
  (no force-unwraps; every `context`/`setState` after `await` is `mounted`-guarded), **import layering clean**
  (shared→core+shared only, no cycle; the two removed splash imports have zero remaining code usages),
  **telemetry signature correct** (`recordNonFatal(e, st, reason:)` with the stack captured), and the
  **test is a real pin, not a tautology** (the source-grep assertions vanish on revert; the widget pump
  proves a live `GestureDetector` CTA). Only both `PlanExpiredCard` render sites are PRO-guarded — no third
  expiry surface exists.
