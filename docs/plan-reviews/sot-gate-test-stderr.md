---
branch: sot-gate-test-stderr
date: 2026-10-05
blast_radius: feature
review_rounds: 2
ground_truth_verified: true
verdict: converged
---

# Plan-review record — the SoT-citation gate test prints the subprocess's output when it fails (`sot-gate-test-stderr`)

One unexplained main-CI failure on 2026-10-04 (run 37203140849: `test/contracts/sot_registry_citations_test.dart`, "a POST-cutoff doc DECLARING non-applicability in prose is accepted", `Expected: <0> Actual: <254>`, nothing else) and the founder's go on 2026-10-05 for "a one-line, test-only fix so the failure message includes the error text if it ever repeats".
Plan: `docs/plans/sot-gate-test-stderr.md` (v3, after both rounds). Fix tier M (a diff that touches only `test/**` and `docs/**` is not S-eligible, §4.12.6), blast radius `feature`, inline execution. Commit type `test(contracts):` (no product behaviour changes, so no diagnose-doc).

## Review rounds
- **R1** — a fresh, context-blind reviewer, read-only, on the v1.1 plan and the staged draft. Verdict **harden**; 9 findings: 1 × P1 (the pin's third check was satisfied by the pin's own literal and by the site it names, so it could never fail), 5 × P2 (a doc comment that spelled the red-path text `check_gate_test_ledger.dart` searches for; a pin that saw only a variable named `r`; a one-call alternative for proportionality; no bug-history lookup; no tracker for the unexplained 254) and 3 × P3 (a one-line stderr fixture; stale plan text; a dated "8 of 28" in the gate-test ledger). The first design (a `reason:` on each of eight assertions plus a source scan) was dropped for the choke-point design the reviewer offered.
- **R2** — a fresh Opus context, a different reviewer who had not seen R1's report, read-only (89 tool calls), on the post-R1 plan and diff, after the full gate loop had run. Verdict **harden**; 5 findings: 2 × P2 (the wiring pin checked three pieces of text, not their order or which `r`, and five edits survived it; the fix covers only this file although the earlier sighting a7f3d1 predates it and was in another test) and 3 × P3 (a skill row claimed done but not written; stale citations in the ledgers; a two-space label). All folded: `runGateOn` now takes a `report` function (default `printOnFailure`), two cases read the report of a REAL gate run, the pin is order-sensitive and counts every spawn; C3's `reopen_when` covers any test whose spawned `dart` exits 254; the extension to the other spawn tests is ledger row C5, `blocked_on_user` (a scope call beyond the founder's go).
- **Converged-after-fold is a SELF-ATTESTATION, not a third review.** No third round was run: both rounds are done and R2's findings were about proof and scope, not behaviour (the change is test-only). The new protection is checked by mutation round 3 (20 of 20 red, including the five edits R2 said would survive, each red by the test the plan names) and by the whole gate loop on the final tree.

## Ground truth
- Code, read at the base `01a34097` and the staged tree by both reviewers and the main thread: the test file, `scripts/check_sot_registry_citations.dart` (it only calls `exit(0)` / `exit(1)` and reads no environment variable), `scripts/gate_test_ledger_lib.dart` (the red-path regex over the RAW text), the `test_api` sources for `printOnFailure` and the reporters, and the diagnose-docs a7f3d1, 4f2a9e, c3f8e1, c3f9a7 for the prior art. No live system was read or written.
- Run, not just read: `dart run` exit codes (254 on a compile error, 255 on an uncaught exception, checked with real scripts); a scratch test under the expanded and the compact reporter (the report lands under the failing test and not under a passing one); the whole file with the gate script made uncompilable in a sandbox copy (10 of 33 tests red, the compiler's own errors in each log); the `parseConcepts` mapping-shape mutation (9 red of 33; 8 of 28 at the base); the whole suite and the whole pre-commit loop on the final tree (counts in the commit message).
- The cause of the 254 itself is NOT established: 200 of 200 concurrent local spawns passed, the re-run was green, the last 30 failed CI runs hold no such failure (ledger row C3, `upstream_blocked`).

## §4.6 disposition (CLAUDE.md feature-flag protocol)
**Not applicable.** Test-only: no `lib/`, no `scripts/`, no product behaviour. Rollback is a revert of the merge commit.

## B-pass (§4.3)
**Not required** (it starts at blast radius `account`).

## Founder-owned, recorded in the ledger, not done
C4 an OI for the unexplained 254 (`scripts/mint_oi.sh` pushes a reservation to GitHub); C5 the same one call in the other spawn tests, starting with `test/scripts/gate_input_family_e2e_test.dart`; C7 a defect found at the push of the Progress-screen PRO-gate batch (`test/scripts/contract_sweep_e2e_test.dart` inherits `CONTRACT_SWEEP_NESTED=1` when the pre-push sweep runs it and fails 5 of 7; a third pull request, which needs the founder's go). Only `sot_registry_citations_test.dart` prints the error text after this change. Added after both review rounds, with no change to the design: the skill row (ledger C6, written in the batch commit) and C7 (the ledger now has 22 rows).
