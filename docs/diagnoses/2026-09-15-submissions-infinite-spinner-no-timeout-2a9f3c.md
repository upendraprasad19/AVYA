---
bug_id: 2a9f3c
date: 2026-09-15
batch: Internal-testing observation batch, session 2 (Obs 2)
status: fixed
blast_radius: feature
symptom: |
  Founder-reported screenshot from internal testing: Profile > My Submissions
  tab stuck on an infinite loading spinner — "My submissions and added
  exercises not being shown". No error, no retry option, spinner never
  resolves.
concept: submissions_load_resilience
sot_registry_entry: |
  Not applicable — this is a resilience fix (a timeout ceiling on existing
  network calls), not a writer/reader contract change. No field, Hive key, or
  cloud column changed.
writers:
  - { file: lib/shared/repositories/submissions_repository.dart, method_or_widget: "fetchMyFoodSubmissions / fetchMyExerciseSubmissions / fetchPendingFoodReviews / fetchPendingExerciseReviews / fetchAlreadyReviewedKeys (all read-only network calls)", line: 19 }
readers:
  - { file: lib/features/profile/screens/submissions_screen.dart, method_or_widget: "_MySubmissionsBodyState._load", line: 152 }
  - { file: lib/features/profile/screens/submissions_screen.dart, method_or_widget: "_CommunityReviewBodyState._load", line: 331 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/submissions_load_timeout_behavioral_test.dart
ist_handling:
  - "Not applicable — no date keys or counters involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: ["submissions_my_load", "submissions_community_review_load"]
cross_account_guard: "Not applicable — read-only network calls scoped by the caller's own userId, no cross-account surface touched."
forbidden_patterns_checked:
  - { pattern: "an awaited SubmissionsRepository call in submissions_screen.dart with no .timeout()/applySubmissionsLoadTimeout wrapper", absent: true }
proposed_fix: |
  Add a 15s ceiling (applySubmissionsLoadTimeout, extracted as its own
  top-level function for direct fakeAsync testability) around every
  SubmissionsRepository call in BOTH _MySubmissionsBodyState._load (the
  reported tab) and _CommunityReviewBodyState._load (the sibling tab, same
  unbounded-await shape, same silent-hang risk — fixed in the same batch per
  "fix the class, not just the instance").
regression_test_planned:
  - test/contracts/submissions_load_timeout_behavioral_test.dart
impact_analysis: |
  Both `_load` methods already have a correctly-wired catch block that sets
  `_error` and a build() branch that renders `ErrorState(onRetry: _load)` —
  the ONLY thing missing was ever reaching that catch block on a hang. No
  other behavior changes: a healthy request well under 15s is byte-identical
  to before. Bug-history lookup (docs/diagnoses/INDEX.md, grepped for
  "timeout"/"spinner"/"hang") found no prior instance of this exact class in
  this file — not a recurrence, though the repo has the same "no ceiling on
  an awaited network call" shape fixed elsewhere (diagnose b7e4c1, restore
  fan-out) and that file's test (`restore_op_timeout_behavioral_test.dart`)
  is the template this test follows.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "applySubmissionsLoadTimeout wraps all 5 call sites across both tabs; flutter analyze clean." }
---

## Summary

Founder screenshot (internal-testing batch, session 2, 2026-09-15) showed
Profile > My Submissions stuck on an infinite spinner, with the founder
reporting submissions/added exercises not appearing at all.

## Root Cause

`_MySubmissionsBodyState._load` (`lib/features/profile/screens/submissions_screen.dart:152`)
awaits `SubmissionsRepository.fetchMyFoodSubmissions` then
`fetchMyExerciseSubmissions` sequentially inside a `try`/`catch`, with **no
timeout on either call**. If either network request stalls (cold Supabase
connection, dropped packet, backgrounded app resuming with a stale socket),
`_rows` never gets set and `build()` renders `CircularProgressIndicator`
forever. The `catch` block is the ONLY place `_error` is ever set, and a
stalled `await` never reaches `catch` — so the Retry button (`ErrorState`)
that this screen's `build()` already knows how to render never appears. This
violates CLAUDE.md §4.4 rule 13 ("all screens must handle loading / error+retry
/ empty") in the one direction a mandatory error path can silently go missing:
not "no error UI exists" but "the error UI exists and is unreachable".

The sibling tab, `_CommunityReviewBodyState._load` (line 331), has the exact
same shape — three sequential unbounded awaits
(`fetchPendingFoodReviews`, `fetchPendingExerciseReviews`,
`fetchAlreadyReviewedKeys`) with `_loading` playing the same role as `_rows`.
The founder only reported the My Submissions tab, but this is the same
mechanism in the same file — fixed in the same batch rather than left as a
known latent gap (`feedback_mistake_guard_without_its_mirror.md`: fix the
class, not just the reported instance).

## Fix

Added `applySubmissionsLoadTimeout<T>(Future<T> future)` — a small top-level
function wrapping `future.timeout(submissionsLoadTimeout)`
(`submissionsLoadTimeout = Duration(seconds: 15)`) — and routed all 5
`SubmissionsRepository` call sites across both tabs through it. A stalled call
now throws `TimeoutException` at 15s, which the existing `catch` block already
converts into `_error` + the existing `ErrorState(onRetry: _load)` UI.

Extracted as its own function (rather than an inline `.timeout()` at each call
site) specifically so the timeout behavior is directly testable with
`fakeAsync` + a never-completing `Completer`, without needing to fake the
Supabase client — following the precedent in
`test/contracts/restore_op_timeout_behavioral_test.dart` (diagnose `b7e4c1`).

## Verification

`test/contracts/submissions_load_timeout_behavioral_test.dart` — 4 behavioral
tests using `fakeAsync`:
- A never-completing `Completer` future does NOT time out before 14s, and DOES
  throw `TimeoutException` past 15s (the exact founder-reported hang).
- A call finishing inside the ceiling passes through untouched.
- A real error (e.g. a PostgREST 4xx) still propagates — the ceiling swallows
  nothing.
- The ceiling constant is pinned at 15s.

**Mutated and run** (rule 21): changed `applySubmissionsLoadTimeout` to
`(future) => future` (drop the ceiling). 1 of 4 tests reddened — exactly "THE
BUG" test (`Expected: TimeoutException, Actual: <nothing thrown, still
pending>` shape via the `thrown` assertion failing `isA<TimeoutException>()`
after both `async.elapse` calls exhausted). The other 3 tests correctly stayed
green (pass-through, error-propagation, and the constant-value check are all
unaffected by dropping the ceiling — they test properties the mutation doesn't
touch). Restored the fix — all 4 passed again.

## Related

Same "unbounded await on a network call" shape as diagnose `b7e4c1`
(RestoringScreen hang, `SyncService.applyRestoreCeiling`), which is the
direct template for this fix's test structure. Not a recurrence of a named
bug CLASS in `feedback_*.md` — first instance in `submissions_screen.dart`
specifically.
