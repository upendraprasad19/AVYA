---
branch: spawn-tests-env-and-stderr
date: 2026-10-06
blast_radius: feature
review_rounds: 2
ground_truth_verified: true
verdict: converged
---

# Plan-review record — every spawned-process test gets one control-variable-clean environment and one failure report (`spawn-tests-env-and-stderr`, PR 1 of 2)

Founder decisions 2026-10-06 (items 1-3 of the six-item recommendation, "lets go ahead with them", then "follow discipline"); the scope question (item 3 is not a small change) was answered "Shared helper, 2 PRs (Recommended)": PR 1 = the helper, the derived guard, the sweep-test fix and the issue-board entry; PR 2 = the other 50 spawn files with strict site guards. **The batch closes only when PR 2 merges.**
Plan: `docs/plans/spawn-tests-env-and-stderr.md` (v3, after both rounds). Fix tier M (`scripts/` and `test/`, well over 100 lines, §4.12.6). Blast radius `feature` (re-derived by reading `docs/blast_radius.yaml:404-406,417`; no path of this PR is in the platform overrides, and PR 1 does not edit `docs/architecture/hooks.md` or `process-invariants-detail.md`, which would lift it to `platform`).

## Review rounds
- **R1**: a fresh, context-blind reviewer, read-only, on the v1 plan. Verdict **harden**. 14 findings (R1-01 to R1-14): a helper that could not remove a kept variable, an env-reader census that was a lookup and not a derivation, a derived test that could pass vacuously, absorbed mutants, a default reporter that throws outside a test zone, the missing d9e4b1 history, the `CONTRACT_SWEEP_NESTED` recursion-guard trade-off, a merge walk that may never run, nothing durable carrying PR 2, a raw-bytes site, start sites, number drift, `SUPABASE_` not being a repo-owned prefix, two assertions that change.
- **R2**: a different reviewer who had not seen R1's report, read-only, on the post-R1 plan. Verdict **harden**. 13 findings (R2-01 to R2-13); the single P1 was in my PROTOTYPE of the derived scan (it missed `ANDROID_DEVICE_ID`, `scripts/run-device-tests.sh:28`, because an `echo` line looked like an assignment), not in the design principle. Also: four more scan holes (alias receivers and quote styles, wrapper callers, shell computed reads, a hidden 25-name builtin list), a census that undercounted PR 2 (lexer re-derivation: 126 sites, 52 files), five or more changed assertions in the SoT test (not two), a fallback that would print on every load-time spawn, a whole-parent map that can re-inject the whole environment through `extra`, a `DART_BIN_OVERRIDE` removal that stayed hand-remembered, the Windows `env` binary, the second OI mint needing a go, an unspecified recursion-pin detector.
- Every finding was re-verified against the code before folding; none was rejected. Section 9 of the plan lists each finding, my check and where it landed.
- **Converged-after-fold is a SELF-ATTESTATION, not a third review.** Two rounds are done and R2's only P1 was in a prototype, which v3 replaced by a measured scan with a synthetic mutant per hole. The implementation checkpoint (plan section 6) re-checked the points against the code; the diagnose-doc answers each.

## Ground truth
- Code read at the base `f749cda3` by both reviewers and the main thread: the sweep runner and its test, the canonical scrub and its callers, the 52 spawn test files (lexer census, reproduced exactly by an independent reviewer), the scripts' environment reads (the derived scan, now the real manifest test).
- Run, not just read: the sweep test with `CONTRACT_SWEEP_NESTED=1` exported (2 passed / 5 failed before; 9 passed after: the 7 existing tests, the poisoned-parent regression and a seam pin, the plan having counted 8); the manifest scan on the real tree reproduces the plan's classification plus one name the plan missed (`USDA_API_KEY`, read in `.claude/build_food_db_v2.js`, which `git grep` prints only as `Binary file ... matches` with no lines, so the plan's reading of `git grep -n process.env` was incomplete: found by the scan, classified STRIPPED).
- Not verifiable here: Windows (the founder also runs these tests there). The helper keeps case-insensitive matching, removes only named control variables and `DART_BIN_OVERRIDE`, and its environment-equality test spawns Dart, not the MSYS `env`; stated in the PR body.

## §4.6 disposition (CLAUDE.md feature-flag protocol)
**Not applicable.** Test-support code and one pure function in `scripts/regression_catalog_lib.dart`; not payment, sync, auth, an AI prompt or the plan generator. Rollback is a revert of the merge commit. The one behaviour change in `scripts/` is that the merge walk's child `flutter test` loses more variables (all control switches no test reads as an input; `DART_BIN_OVERRIDE` is kept for it), verified by explicit `check_regression_catalog.dart` runs with and without the operator variables exported.

## B-pass (§4.3)
**Not required** at `feature` (it starts at `account`). The unit is test-only plus one `scripts/` constants change covered by a literal-list unit test, a derived two-way manifest and the full suite.

## Founder-owned, recorded in the ledger, not done
The OI for PR 2 and the OI for the exit-254 flake are minted through `scripts/mint_oi.sh`: the first needs the founder's go (it pushes a reservation ref; this repo's own precedent, `sot-gate-test-stderr.closure.yaml` row C4, says so) and the second was authorised by decision 2. PR 2 (the other 50 files and the strict guards) is its own plan and its own two reviews.
