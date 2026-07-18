---
branch: auth-test-seam
scope: Testable seam for AuthNotifier.checkEmailRegistered (follow-up from sign-in-simplify B-pass Finding 3) — extract-and-override so the AuthStatus.success invariant is exercised at runtime, not just source-grepped for absence
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/da4a7129-review.md
---

# Plan-review record — auth-test-seam

## Ground-truth verified (against live repo, pre-implementation)
`SupabaseService` (`lib/core/services/supabase_service.dart`) is a hard singleton with no
interface — `AuthNotifier` reaches it via `SupabaseService get _supabase => SupabaseService.instance`.
No mocking library exists in `pubspec.yaml`. The two existing tests for `checkEmailRegistered`
(`test/contracts/email_registration_gate_state_machine_test.dart`,
`test/auth/sign_in_screen_email_gate_test.dart`) are source-grep or whole-method-override —
neither exercises the real state-machine logic with a fake network response. Confirmed this
codebase's established test-seam convention is "swappable function/closure" or "global mutable
test hook" (precedents: `SupabaseService.retryColdStart`, `guarded_box.dart`'s
`debugAuthUidResolverForTests`, `error_telemetry.dart`'s existing 3 `@visibleForTesting` statics) —
NOT constructor injection (zero notifiers in `lib/` take a service via constructor param).

## Implementation
- `lib/features/auth/providers/auth_provider.dart`: extracted the RPC call out of
  `checkEmailRegistered` into `@visibleForTesting Future<bool> rpcEmailIsRegistered(String
  trimmedEmail)`; renamed private `_ensureSupabaseReady()` to `@visibleForTesting
  Future<bool> ensureSupabaseReady()` (body unchanged) so a test subclass can override both leaves
  while inheriting the real loading/try-catch/telemetry state machine.
- `lib/core/services/error_telemetry.dart`: added `@visibleForTesting static void
  Function(String, {String? message})? debugOnLogEventForTests`, checked at the top of `logEvent`.
- New `test/contracts/check_email_registered_behavioral_test.dart`: two `AuthNotifier` subclasses
  (`_FakeRpcSuccessNotifier`, `_FakeRpcErrorNotifier`) via `ProviderContainer`, asserting the real
  `checkEmailRegistered` never reaches `AuthStatus.success` and that telemetry fires on error.
- `test/contracts/email_registration_gate_state_machine_test.dart` updated for the rename.

## Round 1 (×2 context-blind — fresh agents, independently re-derived every claim against the
live repo, ran `flutter analyze`/`flutter test` themselves rather than trusting prior output)
- Confirmed: zero behavior drift from the extraction (same params/return/exception propagation);
  the new test genuinely exercises real logic (not vacuous — hand-traced that a future regression
  reintroducing `AuthStatus.success` would be caught); no stale `_ensureSupabaseReady` references
  left anywhere in the repo; `@visibleForTesting` usage matches established precedent; blast radius
  confirmed `account` tier via `docs/blast_radius.yaml`.
- 4 P2 findings, all fixed same-session: (1) the new `debugOnLogEventForTests` doc comment was
  inserted with no blank line before it, merging into and orphaning the preceding
  `highPriorityOpTypes` docstring — fixed by relocating; (2) a test-boundary anchor
  (`email_registration_gate_state_machine_test.dart`) sliced up to `signInWithEmail(`, which now
  also (harmlessly) captured the new `rpcEmailIsRegistered` method — tightened to anchor on
  `rpcEmailIsRegistered(` instead; (3) no test pinned that `checkEmailRegistered`'s body literally
  calls `rpcEmailIsRegistered(` — added an explicit assertion; (4) the new test hook reset only in
  `tearDown`, inconsistent with sibling statics' `setUp`+`tearDown` pattern — added `setUp` reset.

## Round 2 (×2 — on the Round-1-hardened diff) — findings, fixed
- Re-verified every Round-1 fix fresh (not trusting round-1's own claims): doc comments correctly
  attached, test-boundary slice hand-computed to be unambiguous and correct, `setUp`+`tearDown`
  reset confirmed order-safe, `flutter test test/contracts/` (whole directory, 2178 tests) green,
  no orphaned artifacts from the multi-pass edit history, no scope creep, RPC's SECURITY DEFINER
  trust boundary unaffected by the Dart-level visibility change.
- 1 new P2 found: `debugOnLogEventForTests`'s doc comment said "Reset to null in `tearDown`" but
  the actual test resets it in both `setUp` and `tearDown` — stale wording, could mislead a future
  test author into omitting the `setUp` half. Fixed.
- I independently re-verified both rounds' load-bearing claims myself (read the exact lines,
  re-ran analyze/tests) before accepting them.

## Verdict: converged
Core design (extract-and-override, matching this codebase's established seam idiom) validated
across 2 independent rounds; every finding across both rounds was a real, fixable P2 (no P0/P1);
`flutter analyze` clean and `flutter test test/contracts/` green (2178 passed, 1 pre-existing
unrelated skip, 0 failed) after all fixes. Self-initiated B-pass to run before merge per §4.3.
