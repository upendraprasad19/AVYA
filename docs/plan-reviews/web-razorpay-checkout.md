# Plan-review record — web-razorpay-checkout

branch: web-razorpay-checkout
spec: docs/superpowers/specs/2026-09-17-web-razorpay-checkout-design.md
plan: docs/superpowers/plans/2026-09-17-web-razorpay-checkout.md
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: pending (run before the --no-ff merge; ≥platform tier — self-initiated per §4.3)
founder_decisions: one-time orders (auto-renew → OI at close) · test keys now, live flip later · no allowlist, test-mode exposure accepted · checkout visible (no feature flag, kill-switch only)

## Round 1 (context-blind qa-agent, on plan @ ca339463)

1 of P0 · 3 of P1 · 3 of P2 · 1 of P3. Verdict: NOT executable as written.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P0 | `operator []=/[]` + `callAsConstructor` live in `dart:js_interop_unsafe`, not `dart:js_interop` — the web bridge as written fails to compile (verified against local SDK: js_interop_unsafe.dart:45,52,114) | FIXED: import added to Task 1 code + plan note |
| 2 | P1 | Spec's paywall dispatch test silently dropped — Task 5 shipped with zero tests; shared-predicate property unpinned | FIXED: `web_checkout_paywall_dispatch_test.dart` restored as Task 5 Steps 1-5 |
| 3 | P1 | Mutation matrix incomplete vs rule 21 — no mutation for the wiring test or paywall test | FIXED: Mutations 4 + 5 added |
| 4 | P1 | Task 3 commit would trip SoT registry staleness (`razorpay_service` entry at sot_registry.yaml:2623-2630, line_range 360-380) — registry update not scheduled into the task | FIXED: registry update is Task 3 Step 4, same commit |
| 5 | P2 | Task 6 test-count arithmetic wrong (said 11; actual 14) | FIXED (superseded: now 17 with the paywall test) |
| 6 | P2 | Synchronous checkout.js in head blocks first paint for all visitors | FIXED: `defer` + rationale (bootstrap is async; guard at call time) |
| 7 | P2 | "Rollback without a redeploy" is false fleet-wide — configBox is device-local (per-browser on web) | FIXED: spec + plan + Task 5 comment corrected to per-browser honesty |
| 8 | P3 | `@visibleForTesting` on handlePaymentConfirmed implies a testing contract that doesn't exist | FIXED: dropped (correctly retained on buildRazorpayCheckoutOptions, whose test imports the symbol) |

## Round 2 (fresh context-blind qa-agent, on the HARDENED plan @ e8a8d822)

0 of P0 · 1 of P1 · 1 of P2 · 4 of P3. Verdict: NOT executable until the P1 fix; all others hardening notes.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | Mutation 4 reddens ZERO tests: a bare `contains('handlePaymentConfirmed(')` is satisfied by the method definition itself, and the comment-form mutation contains the exact grep target — the joint "mutation that reddens nothing" trap (rule 21, diagnose `c5a8f3` class) | FIXED: delegation assertion window-scoped to 400 chars after the `_handlePaymentSuccess` signature; Mutation 4 re-specified as REMOVE the call (replace body with `return;`), expected red 1 of 3 |
| 2 | P2 | Task 3 Step 4's claim "the gate blocks the commit otherwise" is false — `check_sot_registry_parity.dart` keys on the class name (survives inside the debugPrint string), verified PASS even against the drift it was claimed to catch | FIXED: reworded to "manual discipline — the gate cannot catch this entry's drift" |
| 3 | P3 | Mutation 5's applied-confirmation weaker than siblings | FIXED: `git grep -c webCheckoutDisabled` returning 0 (identifier occurs exactly once) |
| 4 | P3 | Paywall test 3 "pop after switch" near-vacuous (the disabled branch contains its own pop) | FIXED: rewritten as in-branch containment pin (pop+snackbar+return between the switch and the `// Web checkout active` fall-through marker) |
| 5 | P3 | Options test is the first VM test ever to import razorpay_service.dart | NOTED in Task 2 (should compile: lazy static + statics-only access); treat a surprise as a real finding |
| 6 | P3 | Deferred-script cold-load race: spurious "Couldn't start payment" possible on an immediate early tap | ACCEPTED: openCheckout's EF round-trip makes it practically unreachable; recoverable by retap; recorded in plan deviation notes |

## Round-2 verified-correct (pinned, do not re-litigate)

Round-1 P0-1 SDK claims; missing-@JS-global getter does not throw until callAsConstructor; every plan line citation vs live worktree files; SoT entry at :2623-2630 real; conditional-import + barrel delegator form; relative-path source-grep convention (no part files in either target); test arithmetic 17; Mutations 1/2/3/5 red-sets; kill-switch byte-exact mirror; web build path healthy; promo flow preserved through the paywall rewrite; verbatim snackbar string.

## Ground-truth verification

Both reviewers verified claims against live worktree source (file:line), the local Dart SDK (js_interop_unsafe.dart), `docs/sot_registry.yaml`, and a LIVE run of `scripts/check_sot_registry_parity.dart` (round 2, P2). Founder decisions quoted from chat 2026-09-17.
