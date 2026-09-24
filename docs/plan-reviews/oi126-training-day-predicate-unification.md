---
plan: docs/superpowers/plans/2026-09-24-oi126-training-day-predicate-unification.md
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: pending
---

# Plan review — OI-126 training-day predicate unification

**Blast radius:** platform/account — touches `WorkoutScheduleReadService.currentPhaseCompletionRate`,
the direct input to the PRO phase-advance gate, plus 7 other display surfaces. Ships ship-dark
(kill-switch default OFF); the flip-on commit is explicitly out of scope and needs its own full
×2 review.

## Round 1 (context-blind, general-purpose subagent)

Reviewed v1 (5 call sites). Found 2 Critical + several Important issues:
- Only 5 of the real 11 inline call sites were in scope — 6 more found by an independent live grep
  (`plan_integrity_reconciler.dart:97`, `home_provider.dart:103/375/678`,
  `day_detail_sheet.dart:46/104`).
- The regression test suite only exercised the two pure predicate functions in isolation — no test
  observed any real call site's actual output, so a wiring bug at any of the 5 sites would have
  been undetectable (debugging skill §2.37 class).
- Test file imports used the wrong package name (`fitness_app` vs. the real `icanbefitter`).
- The proposed `docs/sot_registry.yaml` entry didn't match the file's real schema.
- One factually wrong doc-comment-correction claim (conflated two different call-site populations).
- `home_screen.dart`'s import status was hedged rather than stated as fact (verified: needs both
  imports, unlike the other 4 files).

All fixed in v2: scope expanded to all 11 sites; a single shared wrapper
(`PlanEngineFlags.isRestDayConsideringLogged`) extracted so every site delegates to one tested
function instead of duplicating the ternary; package name corrected; SoT schema corrected against
a real entry; doc-comment fix narrowed to the actually-stale sentence; import hedges resolved to
verified fact.

## Round 2 (context-blind, general-purpose subagent, on the hardened v2 plan)

Confirmed all 6 of round 1's specific findings were genuinely fixed (re-verified independently, not
taken on the plan's word) and found the structural design sound (no circular import, no further
missed call sites, all 11 citations accurate, the flag-off/flag-on ternary logic correct at every
site including a hand-traced `'none'`-sentinel edge case). But found 3 NEW Critical issues, all
inside the v2 test task written to close round 1's coverage gap:
- The new `phase_adherence_rate_test.dart` case seeded two already-100%-complete days, so the
  asserted rate change could never occur regardless of the flag — broken arithmetic, test cannot
  pass as written.
- The streak-warning "wiring test" never called any production code — it hand-duplicated the
  predicate in a local closure and tested that instead, reintroducing the exact gap the task
  existed to close, just in a more disguised form (real Hive plumbing made it look load-bearing).
- Consequently, real call-through coverage of Task 4's 6 newly-discovered sites was 0 of 6, not the
  "1 of 6" the plan's narrative implied.
- Additionally: the negative-regression grep only checked the exclusion-shaped phrasing (used at
  the 5 original sites), silently blind to the inclusion-shaped phrasing (used at all 6 new sites).

All fixed in v3: phase-adherence test re-seeded with an incomplete `'logged'` day so the ratio
genuinely moves (1.0 → 0.5, hand-verified against the real function); streak-warning test rewritten
to drive `StreakWarningEligibilityNotifier` through a genuine `ProviderContainer` with real
`Notifier` subclass overrides (verified subclassable — no `final`/`sealed`/unusual constructors);
added a third genuine call-through test at `PlanIntegrityReconciler.needsHeal` (pure `@visibleForTesting
static`, cheapest real site to cover); negative-regression grep extended to both phrasings. Plan
now states explicitly (not implicitly) that 3 of 11 sites get real call-through coverage and the
other 8 rely on source-grep + `flutter analyze` + existing-test re-runs — an honest, bounded gap
rather than an overclaimed one.

## Scoped re-review (v3 → v4, targeted at round 2's 5 specific findings)

Dispatched a scoped re-review (not a full third round) to verify each of round 2's findings was
actually fixed, per this repo's established scoped-re-review convention for fix loops. Result: all
5 confirmed FIXED, arithmetic hand-verified independently against the real function, provider
subclassability independently confirmed against the real class declarations. One NEW issue found
while verifying: both new Hive-backed test files' `setUp` called `HiveService.instance.init()`,
which calls `Hive.initFlutter()` → `path_provider`, throwing `MissingPluginException` in a pure-VM
test with no mocked channel — a documented repo pitfall (`lib/core/services/CLAUDE.md`'s pitfalls
table) that every other `HiveService.instance.init()`-calling test in the repo already works around,
and that the plan's own sibling fixture (`phase_adherence_rate_test.dart`) already avoids by using
the same pattern applied here: mock `path_provider`, raw `Hive.init`, open only the needed boxes,
`markInitializedForTests()` instead of `init()`. Fixed in v4 by copying that exact proven pattern
into both new files (the streak-warning test additionally needs `workoutBox` +
`HiveUserSession.openForUser`, since the real, un-mocked
`WorkoutRepository.getRecentWorkoutCompletionHours` reads a user-scoped box).

## Convergence note

Two full review rounds plus one scoped re-review, each round's findings genuinely distinct from
the prior round's (not the same issue recurring) and each fixed with verification, not asserted.
Per CLAUDE.md §4.12.5, repeated *new* material findings across rounds would be the signal to split
the unit — here they narrowed each round (structural → test-design → test-setup-mechanics),
consistent with convergence rather than an oversized unit. Declaring converged.

## Outstanding, stated rather than hidden

- 8 of 11 call sites (the 4 UI-layer sites in `home_screen.dart`/`day_detail_sheet.dart` plus 4
  others) rely on source-grep + `flutter analyze` + existing-test re-runs, not a genuine
  call-through test. Deliberate scope boundary for this ship-dark batch, not a deferred bug — the
  flip-on commit (separately reviewed, out of scope here) is the point real user risk begins.
- `bpass: pending` — the self-triggered `/code-review` B-pass (§4.3) runs before the `--no-ff`
  merge, after implementation, per the standard sequence; not run yet since no code exists yet.
