---
branch: progress-photos-client-b2
date: 2026-10-08
blast_radius: feature
review_rounds: 4
ground_truth_verified: true
verdict: converged
recorded_at: 2026-10-08T21:30:00+05:30
---

# Plan-review record — progress-photos-client-b2 (unit B2: OI-314, OI-322)

Founder decisions of 2026-10-06: 5 (delete the repository's free-tier branch once the server rule exists) and 6 (a lapsed PRO user may VIEW and DELETE old photos, no new uploads). B1 (migration 154) is applied live and merged (PR #83, `c3986806`). Plan: `docs/plans/progress-photos-client-b2.md` (sections 1-4 original, 5-8 the folds; section 8 is final). Fix tier **M**, inline execution, one worktree. §4.6 feature flag: not applicable (a client-only change; rollback is a revert of the merge commit).

## Review rounds (four fresh, context-blind Sonnet readers, each on the plan after the previous round's folds)
- **R1** — harden: 5 x P1, 3 x P2, 1 x P3 group. The just-paid refusal was undetectable by a verify (`verifyFromServer` returns the optimistic local PRO while a payment is in flight); local PRO state never corrected; no verify timeout; four existing test files named for REWRITE not "keep"; test-plan gaps; list failure states; the `taken_at` deploy-day effects. Folded (section 5).
- **R2** — harden: 3 x P1, 5 x P2, 2 x P3, all in one mechanism, the verify-after-refusal step (a bare 403 sending a payer to the paywall; the forced verify re-entering the screen; a just-paid user with no photos parked on the locked card). The mechanism was DELETED, not patched (section 6).
- **R3** — harden: 2 x P1, 5 x P2, 2 x P3: five async writers of the screen state; the in-flight leg misfiring on a plain network failure (storage_client turns every non-HTTP failure into a `StorageException` whose `statusCode` is a Dart type name). Single-writer redesign `_reload` (section 7).
- **R4** — harden, "do not split further": 1 x P1 (the upgrade listener had no loop guard once the spinner is gone), 4 x P2, 4 x P3. Folded as plan section 8 (v5, final): listener rule with `_dirty` and one re-run, post-write reloads reuse the last verdict, first frame and the never-PRO user, honest 'couldn't confirm' copy, catch-all, `_uploading` held through the verify.
- Severities fell each round (5, 3, 2, 1 P1). §4.12.1 says a unit whose reviews keep finding new material issues is too large; the response was structural (delete the mechanism, one writer) and the reviewer of R4 recommended not splitting. **Self-attested:** no fifth reader checked section 8; what compensates is the behavioural tests, 34 mutants (first pass 27 of 29 red; the two survivors were genuine gaps and were closed) and a code-level B-pass on the real diff.
- All four rounds ran on Sonnet, per the founder's rule of 2026-10-07.

## B-pass (self-initiated; the tier is `feature`, where §4.3 does not require one)
A fresh, context-blind Sonnet reviewer read the real diff: verdict accepted-with-fixes, no P0 or P1, three P2, all fixed in this batch with a test that fails without the fix: (1) a reload carrying a known verdict could overwrite a payer's running full re-check (`_fullInFlight`; the first version of the test passed for the wrong reason, because Add re-gates, and was rewritten around deleting the last photo); (2) the OI-322 device-local-window regression was invisible under the CI zone (a source pin; the zone matrix is stated as run by hand and self-attested); (3) the cap boundary unpinned (`progressPhotoCapReached`, tested at 0/4/5/6). P3 items are in the ledger rows B4-B8.

## Ground truth
Code read at base `c3986806` by the author and all four reviewers (repository, screen, hub, `gateAndVerify`, `verifyFromServer`, `_downgradeLocally`, `writeSubscriptionState`, `ist_date.dart`, storage_client 2.8.0 `fetch.dart` and `types.dart`, migration 154 header and body, B1 evidence E10/E27 and live-verify V4/V8d). Run: the targeted files after every change; `flutter analyze lib/`; the full suite; the pre-commit gate loop; 34 mutants. Not verified here: a real Storage refusal's error shape, an image render for a lapsed account, anything on a device. No database or Edge Function was read or written in this unit.

## Founder-owned, in the ledger (not done): X1 live Storage error shape (needs a throwaway authed account: a live write), X2 signed URL for a lapsed account, X3 the device check. OI-320 and OI-321 (from B1) are unchanged.
