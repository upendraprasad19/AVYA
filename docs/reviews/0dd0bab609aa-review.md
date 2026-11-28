---
reviewed_at: 2026-10-17T20:30:00+05:30
staged_against: 0dd0bab609aa (staged diff of branch referral-unit-c-client, the unit C build commit)
blast_radius: account
reviewer: fresh-context-blind-sonnet-agents (2 seats, read-only, exhaustive command list, no database access)
lens_set: [writer_reader_drift, guard_without_its_mirror, unawaited_no_error_sink, asserted_fixture_value, missing_input, blast_radius_mismatch]
findings_count: 12
verdict: accepted
---

# Code Review (B-pass) - unit C, the referral client surface (OI-336)

Two fresh, context-blind Sonnet seats read the STAGED diff of branch `referral-unit-c-client` against plan `docs/plans/referral-unit-c-client.md` v4: seat A (the notifier, gate, repository and cross-account state: lenses L1, L15, L16, L37) and seat B (surfaces, tests, copy truthfulness, layout, accessibility, docs and ledger claims). Both were told to find bugs, not validate; neither could edit, run scripts or touch a database. Seat B ran 58 tests, all green; seat A ran none. The tree they read is the tree of this commit except for the fixes below, which were applied after the reports and are what the hash above covers.

**Overall verdict: SHIP-WITH-FIXES, no P0, no P1.** 2 P2 and 10 P3 records across the two seats (12 findings after merging the one throttle note both seats made). Every one is a row of the closure ledger (`BP-A1..A4`, `BP-B1..B8`): 8 fixed with a test, 2 verified clean by the plan's own decision, 1 fixed by renaming a vacuous test and documenting the guard, 1 left to the founder's wording review (`BP-B8`).

## Findings and dispositions

| # | Sev | Finding | Disposition |
|---|---|---|---|
| A1 | P2 | A second concurrent `check()` skipped the forced verify (the card could precede the entitlement) and the first call could resurrect a card the user had already dismissed | FIXED: every check awaits one shared verify future and re-decides after it. Tests: no card until the verify completes; a re-baseline during the wait is not overwritten. Mutants N1, N2, N4 killed |
| A2 | P3 | The 6-hour resume throttle was stamped before the read, so one offline resume blocked six hours | FIXED: stamped only after a read that answered. Test + mutant N3 |
| A3 | P3 | A sign-out discards an unseen credit | VERIFIED CLEAN: the plan's stated re-baseline and the founder's silent-first-run decision |
| A4 | P3 | The sheet can make a second RPC after the code loads | VERIFIED CLEAN: no correctness impact; comment and build record corrected |
| B1 | P2 | The invite copy overpromised ("when a friend subscribes") against migration 159 (first payment, 90 days, 7-day vest, void on cancel) | FIXED: copy states the conditions; test asserts them |
| B2 | P2 | The "dismissal write after the account changed is dropped" test was vacuous | FIXED: renamed to what it proves; the unreachable guard is documented; the real protections have their own killers |
| B3 | P3 | SoT registry line ranges pointed at the wrong code | FIXED; parity gate green |
| B4 | P3 | Unverifiable doc claims (OI-348 lives on another branch; budget not re-baselined; gate loop claimed early) | FIXED: wording exact |
| B5 | P3 | `ReferralRepository.redeem` failed OPEN on a 200 without `success` (the old sheet required it) | FIXED: fails closed; pure and sheet tests; mutant killed |
| B6 | P3 | Layout: skeleton shift, only the REGENERATE state tested, keyboard test checked overflow only | FIXED: `loadCodeForTest` seam, Share-state test, apply field reachable with a 300-dp keyboard |
| B7 | P3 | Accessibility: PENDING missing from the Semantics label, 9 px labels, low-contrast welcome disclosure | FIXED |
| B8 | P3 | The friend disclosure is true but does not say that with ONE friend the aggregate identifies that friend | LEFT TO THE FOUNDER'S WORDING REVIEW (ledger `BP-B8`; privacy sentence is row X7) |

## Checked and found clean (both seats)

The notice algorithm (first run silent, difference announced, equal silent, lower re-baselined, dismiss stores the total); per-account state reset in `build()` and the token captured before every `await`; the late-summary-after-swap drop; the single-flight map keyed per token and unable to wedge; the owner-null guard and the user-scoped key registration (the key is touched in exactly one file); `tryParse`, the absence classifier and the telemetry tests; the cold start (zero rows, RPC missing); the repointed tests were repointed, not loosened; the doc counts.

## Tests run after the fixes

Full local suite (`TZ=Asia/Kolkata flutter test --exclude-tags golden`): 9814 passed, 9 skipped, 0 failed. Pre-commit gate loop green on the staged tree. Mutation: 25 of 25 deliberate mutants of the unit caught, plus 4 of 4 for the fixes above and 1 for the fail-closed change (the 26th, a comment-only edit, is equivalent).
