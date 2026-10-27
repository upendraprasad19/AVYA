---
branch: oi410-verify-nonactive-row-v2
plan: docs/plans/2026-10-26-oi410-verify-payment-non-active-row.md
date: 2026-10-26
blast_radius: catastrophic
review_rounds: 5
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/3b55547d33d9-review.md
hermes: accepted
hermes_report: docs/audit/2026-10-26-hermes-oi410.md
---

# Plan review - OI-410 (verify-payment answered verified:true for a payment whose subscriptions row was not active)

## Founder decisions (2026-10-26, via AskUserQuestion, pasted from plan "Authorization and founder decisions")

The founder said "start 410" (investigation and the plan only). The four answers below widened that to implementation through the merge; none
covers a live Edge Function deploy, boot probe, signed-in smoke, live log read or rollback, each of which needs its own per-action go listing the live actions.

- **Q1 (4.6 / the catastrophic `feature_flag` requirement).** Question: "OI-410 changes the verify-payment function (payment, catastrophic tier).
  CLAUDE.md 4.6 asks for a feature flag on payment changes. The plan proposes NO runtime switch: the change only narrows one answer (a
  cancelled/expired payment row stops answering 'verified'), changing a secret needs a redeploy anyway so a switch is no faster than redeploying
  the saved previous version, and the old code is one redeploy away. Do you ratify no switch?" **Answer: "No switch; rollback = redeploy
  (Recommended)"** (option text: "Smallest change to a payment function. Rollback is a forward-deploy of the saved previous bundle (minutes, no
  app build). I record your answer in the plan, the diagnose-doc and the plan-review record.").
- **Q2 (closure rule).** Question: "After the fix is deployed, how should OI-410 be closed? The CLAUDE.md deploy skill (6.10) wants a live check
  of a fixed Edge Function's new output. The new refusal only happens when a paid subscription row has been cancelled while the payer's app is
  still confirming (about 22 minutes after paying), so the only live proof is a real captured payment, cancelling its row in the dashboard without
  a refund, and calling verify-payment. There are no live victims today (4 non-active rows, all in the past)." **Answer: "Waive the live proof
  (Recommended)"** (option text: "Close OI-410 at deploy on: handler-level tests with the real client library (reproducing the defect against the
  old code), a boot check and an authenticated smoke. The ledger records the waiver in your words.").

- **Q3 (B2, asked 2026-10-26 after plan v5 converged).** Question: "Design B2: when verify-payment cannot read the payment's row at the replay points
  (the read fails or finds nothing), should it answer a soft failure ('Could not confirm this payment yet; please retry', HTTP 200, verified:false) instead
  of the old seeded 'verified:true'? It needs three failures in one request to fire and the app retries within a minute. The honest-payer cost is up to
  one retry interval of delay in that case. Your earlier 'no switch' answer was given on a question that described the change as only narrowing one
  answer; this is the second changed answer." **Answer: "Accept B2 (Recommended)"** (option text: "Never answer verified:true unless this request read the
  row as active or inserted it itself. Strictest and simplest to state; the plan and its tests are written for this.").
- **Q4 (scope of the go, same time).** Question: "How far may I go on OI-410 now? A deploy is never included: it needs its own go later, listing each live
  action." **Answer: "Implement through merge (Recommended)"** (option text: "Write the fix and tests, run the full gate loop and the mutation run, the
  B-pass and hermes reviews, then 3 commits, push, PR, CI, merge via safe_pr_merge.sh, retire the worktree. No deploy, no migration."). So the founder's
  explicit go now covers implementation, the three commits, the push, the PR and the merge of this branch; it does NOT cover any live Edge Function
  deploy, boot probe, signed-in smoke, live log read or rollback (a separate go listing each, as stated below).

Q4 named "3 commits"; there are four, because the hermes pass found three inaccurate COMMENTS in a catastrophic file (`verify-payment/index.ts`)
and a catastrophic commit needs its own staged, accepted review: `51327572` (the fix), `12efca99` (the three comments, no code), `e763158b`
(hermes report, ledger, board, docs), and this record. The scope of the go (implement through merge, no deploy, no migration) is unchanged.

## Why this is branch `-v2`

The first branch, `oi410-verify-nonactive-row` (PR #177, tip `9a189a9c`), was superseded before merge: its third commit's body contained the prose
"No closes-oi: OI-410 closes in the post-deploy docs PR", and the merge-time gate `check_closes_oi_performed.dart` reads any `closes-oi: OI-N` in a
brought-in commit message, anywhere in the body, as a citation, so it failed Audit Gates on #177 (OI-410 rightly still reads OPEN). Pushed history was not
rewritten: commits 1 and 2 are the same two commits, the third was re-made with a corrected message, and this record was renamed for the new branch
(the plan-review gate keys the record file to the branch name). PR #177 is closed unmerged.

## Review rounds

The plan was reviewed in five context-blind rounds, each seat told to verify every claim against code and live state, never to trust the plan's
own citations: round 1 (the design), rounds 2-4 `not_converged` (each found material issues in the previous round's fold, every one re-verified by the
coordinator before it was folded in; the plan went from v1 to v5), round 5 mechanical-only (it checked each v5 fold and the contradictions between
sections, nothing else) and `converged`. After round 5 the founder was asked B2 as an explicit question (Q3), because the earlier "no switch"
answer had been given on a question that described the change as only narrowing one answer.

## Ground truth

- The three replay doors and the early read were read at file:line in `verify-payment/index.ts` (the plan's "The defect" section); every route to a
  `verified: true` literal was enumerated (exactly two literals).
- Live state, read-only (2026-10-26): the live function is v31 with `verify_jwt` true; four non-active `subscriptions` rows exist, all in the past, so
  the defect is latent, not exploited; the migration-161 function `record_paid_subscription` returns the stored row whatever its status (read from
  the migration, the LAST `CREATE OR REPLACE` wins).
- Deploy tooling read from `.claude/deploy_via_api.js` and `.claude/token_path.js` (the clone-has-no-token trap, the `--rollback` mechanism); the
  hermes pass later corrected two statements in the deploy skill that described flags and a mechanism the script does not have.

## B-pass, per catastrophic commit (section 4.3)

- `51327572`, the fix: `docs/reviews/3b55547d33d9-review.md` (3 Sonnet seats, 16 findings, all dispositioned, `verdict: accepted`).
- `12efca99`, three comments, no code: `docs/reviews/90b3647d99f2-review.md` (1 seat, 2 P3, one fixed and one verified no-change, `verdict: accepted`).
- `e763158b` and this record are not code (feature tier and docs).

Mutation proof (section 4.4 rule 21): 31 mutants (M0 = the pre-fix handler, 36 Deno reds; M1-M29 against the new gate, the chain-shape pin and the log
allowlist), each confirmed applied and restored by sha256; the full gate loop ran after the last code edit.

## Hermes

`docs/audit/2026-10-26-hermes-oi410.md`, `verdict: accepted`: 4 Sonnet seats, lenses L1 L21 L22 L23 L29 L36 L37 L40 L53, 11 findings (0 P0, 0 P1, 0 P2,
9 P3, 2 false alarms); the REAL ones fixed in `12efca99` and `e763158b`, two kept as designed with the reason.

## Open for the founder

The live deploy of `verify-payment`: one per-action go that lists every live action (fresh GET and bundle compare, deploy, anon-key boot probe, signed-in
smoke with a QA account the founder names or an accepted boot-probe-only basis, 24 h log and alerts reads, and a rollback if a trigger fires). OI-410
stays OPEN until the post-deploy docs PR records the deployed SHA, version, payload sha256 and the check results.
