# Plan — OI-410: verify-payment must not answer `verified: true` for a payment whose subscription row is not active

**Version 5 (2026-10-26), after plan-review round 4.** Round 4 = seat G (mechanism, tests, registry: `converged`, 0 P0, 0 P1, 1 P2, 6 P3) and
seat H (governance: `not_converged`, 1 P1, 3 P2, 9 P3) on plan v4. v5 folds every round-4 finding: (1) **closure basis (H, P1):** a ledger sentence written at
commit 2 would have claimed an authenticated smoke that might never run; the commit-2 ledger row now states only the waiver and what exists at that
time, the deploy-time boot probe and smoke are written by the post-deploy PR, and with no named tester account OI-410 stays OPEN until the founder
names one or accepts a boot-probe-only basis in words; (2) **B2 is asked, not restated:** it is put to the founder as an explicit question with the
go-ask for implementation, before any code; (3) the diagnose id is fixed when the doc is written, before the B-pass stages the diff; (4) T0 takes
`replayVerdict` from the namespace of the existing `importWithEnv` import (a static import loads the module before the env exists and breaks M0);
(5) the red count is 10 plus 3 vacuous tests, two citations and mutant M20 are corrected; (6) `--yes` on the forward deploy, `--token-file` only on
`deploy_via_api.js` calls, real lens labels, tier 12 `not_applicable`, and the other governance text fixes. Earlier rounds, as summarised in v4:
Round 1 = seats A and B, round 2 = seats C and D, round 3 = seats E (mechanism, tests,
registry) and F (governance, commit layout, rollout, closure); all `not_converged`, none with a P0. Round 3 on plan v3: 1 P1, about 10 P2, about
14 P3, all text or test-plan defects, NO design change (seat E enumerated every path to `verified:true` and found none that skips the status read).
Every finding was re-read in the code or the gate before it was folded. What changed in v4 (from v3):

1. **P1, Gate 9:** the SoT concept and its Dart test must have the same name. The sibling shape carries `key_prefix: "n/a"`, which
   `scripts/check_writeservice_contracts.dart:57-82` treats as Hive-backed and then demands `test/contracts/<concept>_writer_to_reader_test.dart`.
   The test is renamed to follow the concept (below).
2. **Fixture recipes rebuilt.** A door-3 / ON fixture needs the planted row hidden from the early read AND the pre-select (an active row would
   otherwise be found by the pre-select and take door 1); the U0 test's one intercept serves BOTH the origin and the new handler; the red count is
   corrected (8 from the select change, `:270` from the refusal, 2 from the ON fixtures: 11); a mislabelled test is fixed; a normaliser branch that
   no test reaches is dropped; the mutant table gains the missing filter mutant.
3. **The branch base moved** (landing C1, #176, merged after this branch started): fast-forwarded to `5794439a`; the v3 ban on a sync merge was
   obsolete and the rule is rewritten, with the reason the base must be current BEFORE the B-pass.
4. **Rollout:** the deploy go-ask enumerates every live action (read, deploy, boot probe, signed-in smoke, 24 h reads), a rollback needs its own go,
   the diff from the live-equal sha to merged `main` must be exactly this fix, SKILL section references corrected, closure is AT DEPLOY (Q2) and the
   watch window is monitoring.
5. **Records:** the diagnose-doc carries Q1, Q2 and B2's `unconfirmed` outcome; `review_rounds` is the honest count; record frontmatter fields; the
   B-pass file's Tuning entry; the section 5 rows; OI-348 row C10; the ledger header note for the waiver row; gate names corrected.
6. **Q1's question did not mention B2's `unconfirmed` outcome** (it spoke of narrowing one answer). It is now stated in the Founder decisions
   section and is put to the founder as an explicit question with the go-ask for implementation; declining it returns the plan to option B3 and to review.

Branch and worktree `oi410-verify-nonactive-row`, from `origin/main` `5794439a` (landing C1, CI green). The branch was created at f683076f and
fast-forwarded to `5794439a` on 2026-10-26 while it held no commit, so commit 1 is the first commit.

## Authorization and founder decisions (verbatim)

The founder said "start 410" (2026-10-26): investigation and this plan. It does NOT cover implementation (code or tests in the tree), a commit, push, PR, merge, or the live deploy: each
needs its own go (CLAUDE.md 4.3; a live Edge Function deploy needs a per-action go even after a plan is approved).
Founder answers, 2026-10-26, via AskUserQuestion, pasted as given:

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

Consequences: no `DISABLE_*` secret, no golden OFF test, no SECRET_INVENTORY row, no removal OI. Rollback = forward-deploy the saved previous
bundle (Q1 ratifies this as the answer to 4.6's "old path reachable"; CLAUDE.md itself does not); the old code is live v31 (the frozen
fixture `_shared/fixtures/verify_payment_origin_main.ts.txt` is the older pre-Piece-A code). The waiver is recorded in the
closure ledger row for the live proof, in the founder's words. The reasons for no switch, stated accurately: a switch OFF would restore the very
defect this OI closes, so it protects nothing; the changed answers happen only when a PRE-EXISTING row is non-active or unreadable; the secret flip
would need a redeploy of the function anyway (`docs/operations/SECRET_INVENTORY.md:41`, the stacking switch precedent), so it is no faster than the
forward-deploy rollback. Precedent: payment-hardening F-2 (`docs/plans/2026-10-24-payment-hardening.md:49`, recorded in `docs/plan-reviews/payment-hardening.md:17-19`).

**What Q1's question did not say.** It described the change as narrowing one answer. Design B2 (below) also makes an UNREADABLE or absent row at
doors 2 and 3 a soft failure (HTTP 200 `verified:false`, "Could not confirm this payment yet; please retry") where d6b736 F2 answered `verified:true` with a
seeded date. That is a fail-safe direction, it needs three failures in one request to fire, and the client retries, but it IS a second changed answer.
Q1 stands as given. A restatement is not a ratification, so B2 is put to the founder as an EXPLICIT question (accept B2, or fall back to B3: refuse
only on proof) with the go-ask for implementation, BEFORE any code is written; the answer is recorded verbatim in the diagnose-doc and the
plan-review record and repeated in the deploy go-ask. If the founder declines, the plan returns to B3 and to review.

Execution mode (4.12.7): **inline**, one worktree; review seats Sonnet only (founder rule 2026-10-07), at most 4 at once, read-only, exhaustive
command list. Fix tier (4.12.6): **L / catastrophic** (`docs/blast_radius.yaml:42`: `supabase/functions/verify-payment/** -> catastrophic`; the
tier `requires` list, `blast_radius.yaml:26-34`: regression_test, behavioral_test_path, code_review_b_pass, feature_flag (ratified as "none" by
Q1), rollback_documented, hermes_pass). Required: this plan reviewed twice (round 5 is the mechanical-only confirmation on v5), a B-pass, a hermes pass (`hermes:
accepted`), the full gate loop, a SEPARATE live-deploy go. Lenses (4.8): L1 writer/reader drift, L21 Edge Function semantic correctness, L36
idempotency replay completeness, L37 empty-state / null-shape readers (absent, null and unreadable rows), L23 ownership, L53 Edge Function deploy reversibility.

## The defect, with writers and readers named (4.1)

- **Writer of the wrong answer:** `supabase/functions/verify-payment/index.ts` handler.
  - `:370-376` the early read `existingSub` filters `.eq("status","active")` and answers `verified:true, source:"existing"`.
  - `:606-611` the idempotency pre-select `paymentSubRow` reads the same key (`razorpay_payment_id` + `user_id`) with NO status filter and selects
    only `id, end_date`; `:612-617` a read ERROR is only `console.warn`ed and `paymentSubRow` stays null ("continuing to insert").
  - `:750-755` the `else` arm (a row was found) takes that row's `end_date` and falls through to `:795-804`, which answers 200
    `{verified:true, plan, end_date, source:"razorpay_api"}`. Nothing between looks at the row's status.
  - `:698-749` the OFF-branch 23505 arm (the insert hit `unique_razorpay_payment_id`) re-reads `end_date` only (`:738-745`) and falls through to
    the same answer; if the re-read fails or finds nothing it answers with the value seeded before the insert (d6b736 F2).
  - `:627-671` the stacking-ON path calls `public.record_paid_subscription`, whose idempotency fast path returns the STORED row "whatever its
    status" with `out_inserted = false` (migration 161, `:90-100`); the handler maps that to the same `verified:true`.
- **Readers of the answer:** `lib/core/services/razorpay_service.dart:915-927` (`_pollAndActivate` Phase 2: `verified == true` writes PRO with
  the row's `end_date`, calls `clearPaymentInFlight`, returns without a refresh) and `lib/core/services/payment_retry_attempt.dart:82-101`
  (`verified == true` writes PRO, clears the grace window, refreshes, clears `localActivationAt`). Both treat anything else as a soft failure
  (Phase 2 falls to Phase 3, the helper returns false). The invariant the client states and relies on, `razorpay_service.dart:1011-1017` ("a
  `verified:true` reply always means an active subscriptions row exists"), is false today.
- **When a row is non-active at that moment:** a FULL refund is stopped earlier (`index.ts:504-515` answers `Payment status is 'refunded', not
  'captured'`, a soft failure; Razorpay's status semantics are from its documentation, not verified live). A row becomes `cancelled`/`expired` only
  by an operator action (neither payment writer handles refund events; payment.md rule 8), so the realistic trigger is an operator cancel
  (dashboard or SQL) of a paid row, with no refund or a partial one (the payment stays `captured`), inside the poll/retry window. The OI-348 C8
  refund walk cancels AFTER the activation flow has finished, so it does NOT exercise this arm.
- **Reachability of the three doors:** the pre-select arm is reached whenever the early active-only read misses; the 23505 arm and the ON path are
  reached whenever the pre-select ERRORS (any transient PostgREST error) while a non-active row for the payment exists. No race is needed.
- **Who can exploit it:** nobody new. The caller must own the payment (`notes.user_id === userId`, `:438-460`) and Razorpay must still say
  `captured`. The owner of a cancelled payment gets a `verified:true`, nothing more.
- **Bug history (4.1.5):** the pre-select arm comes from F31/F33 (audit-2026-06-07, diagnose `b3f0d9`) and review `d6b736` F1/F2 ("report the
  canonical row's end_date"; "seed the value this call stored in case the winner cannot be re-read"), which wanted the replay idempotent and never
  considered the row's status. Filed by the payment-hardening hermes pass (`docs/audit/2026-10-25-hermes-payment-hardening.md`, H5, P3) as OI-410.
  `INDEX.md` greps for `verify-payment`, `status filter`, `idempotency` and the concept find no earlier instance of this exact class. The recorded
  recurrence classes: (a) guard-without-its-mirror (`.claude/skills/debugging/bug-classes.md`, the references in classes 2.49, 2.51 and 2.133): a fix on one door leaves its
  siblings, which is what round 1 found here; (b) class 2.49 "a helper's fail-safe direction belongs to the CALLER" (diagnose `f0b6d8`, OI-321): the
  d6b736 F2 seed is a fail-OPEN direction chosen for the replay's convenience, wrong in front of an entitlement answer. Same handler: `c8f229`,
  `b5e8d2`, `d1a4f6`, `f5d8c3` (a boot failure killed the client fallback: the deploy must boot-verify).
- **Measured live, read-only (`public.subscriptions`, project `dedsavbjuwgarrhphgnl`, 2026-10-26):** 14 rows: `active` 10 (6 with a payment id),
  `cancelled` 3, `expired` 1 (all four non-active rows have a payment id and an `end_date` in the past), so today the defect has no live victim.
  No CHECK constraint on `status` (pkey, `user_id` FK, `unique_razorpay_payment_id`): free text. LATENT.

## Design

**Invariant (exact):** for any path where THIS request did not itself insert the row, `verify-payment` answers `verified:true` only after it READ
that payment's row in this same request and saw `status === "active"`. Paths where this request inserted the row (OFF insert succeeded; ON
`out_inserted === true`) are unchanged. Consequently it never answers `verified:true` after reading a non-active row, and an unreadable or absent
row at a replay door is not a verification either.

**ONE decision function, used at all three doors** (module-level, exported for the unit test, placed AFTER the handler and before
`if (import.meta.main)` so no existing handler line shifts except by the edits themselves):

```ts
export type ReplayVerdict = "ok" | "not_active" | "unconfirmed";
export function replayVerdict(row: unknown, readFailed: boolean): ReplayVerdict {
  if (readFailed || row == null || typeof row !== "object") return "unconfirmed";
  return (row as { status?: unknown }).status === "active" ? "ok" : "not_active";
}
```

and a small responder `replayGate(row, readError, paymentId): Response | null` that returns `null` for `ok`, else logs and returns the soft failure:

- `not_active`: HTTP 200 `{ "verified": false, "error": "Subscription for this payment is not active" }`; log
  `[verify-payment] replay refused, row not active payment_id=${paymentId} status=${codeToken(rowStatus)}`.
- `unconfirmed`: HTTP 200 `{ "verified": false, "error": "Could not confirm this payment yet; please retry" }`; log (warn)
  `[verify-payment] replay unconfirmed payment_id=${paymentId} code=${pgErrorCode(readError)}` (`no_code` when there is no error object).
- Both carry `corsHeaders` and `Content-Type: application/json`, same shape as the "not captured" answer (`:504-515`); no `end_date`, `plan`,
  `source` or raw status in the body. Strict equality, like the early read's `.eq("status","active")`: `NULL`, `""`, `"ACTIVE"`, `cancelled`,
  `expired`, `refunded` and any future value are `not_active`.

**The three doors (all in this batch):**
1. **Pre-select `else` arm** (a row was found): the select becomes `id, end_date, status`; before `existingEnd` is read,
   `const refused = replayGate(paymentSubRow, null, paymentId); if (refused) return refused;`. (`readFailed` is false here: a failed pre-select
   leaves `paymentSubRow` null and goes to doors 2/3.)
2. **OFF-branch 23505 arm:** the re-read becomes `.select("end_date, status")` and now keeps its `error`:
   `const { data: raceRow, error: raceError } = ...; const refused = replayGate(raceRow, raceError, paymentId); if (refused) return refused;`
   BEFORE `raceEnd` is read. The d6b736 F2 seed (`canonicalEndDateIso = storedEnd`) still serves the successful-insert path; its comment is
   updated: it no longer covers an unreadable winner row, which is now `unconfirmed`.
3. **Stacking-ON path with `rec.inserted === false`:** one extra read (named `storedRow`/`storedError`, NOT `existingSub`: the
   `audit_2026_06_07_batch6_server_test.dart` pin caps that name) `from("subscriptions").select("status").eq("razorpay_payment_id",
   paymentId).eq("user_id", userId).maybeSingle()`, then `const refused = replayGate(storedRow, storedError, paymentId); if (refused) return refused;`. With `inserted === true` there is NO extra
   read. No migration, no change to `record_paid_subscription`.

In all three, `weInsertedTheRow` and `offInserted` stay false/null, so no promo redemption, no insert, no mismatch alarm happens. An ACTIVE row
(the webhook-won-the-race case that is the reason the arm exists) behaves exactly as today.

**Options considered:** A pre-select arm only (rejected: leaves two reachable doors); B3 refuse on proof only (v2; rejected after round 2: leaves a
reachable `verified:true` after a non-active row under two read failures and contradicts the stated invariant); **B2 (chosen; accepted by the founder, Q3)**: also a soft failure
when unreadable, no 500 path; failing the request with a 500 on a pre-select ERROR (rejected, it removes the "keep recording the payment"
backstop at `:612-617`); a runtime kill switch (rejected by the founder, Q1).

**What B2 costs, stated plainly.** In the compound case "pre-select ERROR + insert 23505 + the re-read ALSO fails" the client now gets a soft
failure instead of the seeded `verified:true` that d6b736 F2 deliberately returned. The webhook has already written the active row in that case,
so the client's next confirmation (60 s retry, early active-only read, `source:"existing"`) succeeds; cost: up to one retry interval of delay in a
three-failure case, no money or entitlement lost. Side effect (pre-existing gap closed, not claimed exploitable): a foreign-owned row with the
same payment id (impossible by the notes check and the unique index, but unguarded in the OFF 23505 arm today) answers `unconfirmed`, not the
seeded `verified:true`.

**Logging.** Two new console calls, each ONE argument built from literals. New exact-text entries in
`_allowed['supabase/functions/verify-payment/index.ts']` of `test/contracts/payment_log_safety_writer_to_reader_test.dart`:
`codeToken(rowStatus)` and `pgErrorCode(readError)` (the file already allows `paymentId`); `rowStatus` is a named local derived inside
`replayGate`, never an inline cast inside `${...}`. The allowlist has a stale-entry mirror check, so both must be used. The hostile-status case
(a newline plus a forged `[verify-payment]` line; a 40-character value) must log `no_code`.

**Client effect (corrected, was contradictory in v2).** No client code change; the fix reaches every installed build when the function is
deployed. For a non-active row, Phase 2 no longer writes PRO with that row's date and no longer clears the in-flight marker. The marker stays open
for the grace window (`kPaymentGraceWindow`, about 21m45s: 15 min + activation budget + 60 s + 2 min, `lib/core/constants/payment_timing.dart:87-90`,
sot_registry 1344). While it is open, `refreshFromSupabase` returns early (`subscription_service.dart:870-880`) and `verifyFromServer` suppresses a
downgrade (`:1086-1098`), so the optimistic local PRO the payment wrote stays for up to about 22 minutes, then the next reconcile demotes. Other
in-flight consumers: `progress_photos_screen.dart:243` ("still activating" copy) and `home_provider.dart:495` (the expiry banner is suppressed).
Reconcile callers are splash (`splash_screen.dart:238`), the restore steps (`sync_service.dart:2268`, `:2485`), the session bootstrapper
(`auth_session_bootstrapper.dart:1103`) and the paywall (`paywall_sheet.dart:342`); the payment itself schedules two more at 60 s and 5 min (`razorpay_service.dart:956`, `:959`), both no-ops while the marker
is open, and the `gate()` / `verifyFromServer` path is the same suppression; none runs on app resume. So **the fix DELAYS an honest demotion
by up to about 20 minutes for this rare class (an operator-cancelled, still-captured paid row inside the confirmation window) in exchange for the
server never asserting a verification it did not make.** It is not a user-visible improvement; the value is the server's `verified:true` contract and
any reader that relies on it. The plan, the diagnose-doc and payment.md say so.

## Change set

**Base rule.** Before the B-pass starts, and again immediately before commit 1, run `git fetch origin main && git merge --ff-only origin/main`.
The B-pass review file is named by the hash of commit 1's RAW staged diff (`git diff --cached`, `index <old>..<new>` lines included;
`scripts/check_code_review_pass_exists.dart`), so a base that moves after the review makes the file's name wrong and the review must be
re-hashed or redone. After commit 1 exists, a moved `origin/main` is taken by an ordinary `git merge origin/main`: since landing C1 (#176) a
conflicted sync merge is graded only by what it ADDS beyond main (`docs/architecture/hooks.md`, "Review-acceptance gate and branch sync"; fails
closed to the full list on any doubt). The v3 rule "rebuild, never sync-merge" is withdrawn. Pushed history is never rewritten without its own go.

Commit 1 (`fix(payments):`, `closes-diagnose: <id>`; the diagnose id is minted when the doc is WRITTEN, before the B-pass stages the diff: the review hash covers the diagnose-doc's path and content, so an id chosen later renames the required review file): code, tests, docs, diagnose-doc, this plan, the
B-pass review file. NOTHING under `docs/audit/` (the review hash covers it). NEVER write the literal `closes-oi: OI-410` in commits 1 to 3:
`check_closes_oi_cited.dart` wants it on an OPEN to CLOSED flip and `check_closes_oi_performed.dart` compares the citations in the commits a merge
brings in with the board, and OI-410 stays OPEN until the deploy.
1. `supabase/functions/verify-payment/index.ts`: the three doors, `replayVerdict`, `replayGate`, the select changes; the stale header contract
   (`:16-31`: `{verified:false, status:"pending"}` is not an output of this handler; add the two soft failures and correct the "same 200 payload on
   replay" sentence); the d6b736 F2 comment at the OFF seed.
2. Tests (below).
3. Docs. **SoT registry** concept `verify_payment_verified_means_active_row`, shaped like its sibling `verify_payment_owner_before_capture`
   (`hive: {box: "n/a ...", key_prefix: "n/a"}`, `cloud`, `sync_methods: []`; writer `verify-payment/index.ts` handler; readers `razorpay_service.dart`
   `_pollAndActivate` and `payment_retry_attempt.dart` `runVerificationRetryAttempt`, written as PROSE `method:` strings like the sibling's;
   `behavioral_test_path: supabase/functions/verify-payment/index_test.ts`). **Gate 9** (`check_writeservice_contracts.dart:57-82`) treats the sibling's
   `key_prefix: "n/a"` as non-empty, so the Dart regression test is named EXACTLY
   `test/contracts/verify_payment_verified_means_active_row_writer_to_reader_test.dart` in the registry `regression_test:`, the diagnose-doc
   `sot_registry_entry`, the ledger and everywhere else; before the commit, `grep -rn "_writer_to_reader_test.dart"` over the plan, ledger and
   diagnose-doc and confirm every name for this batch equals the concept (CLAUDE.md 4.9, d3f8a6). **The seven `line_range` citations of
   `verify-payment/index.ts` are re-anchored BY HAND after the final edit**, from the code. At base `5794439a` they sit under
   `file: supabase/functions/verify-payment/index.ts` entries, whose `line_range:` lines are at `sot_registry.yaml` lines 8356 (678-755), 13660 (681-693), 16507 (619-755), 16589
   (619-791), 17109 (428-462), 17114 (464-516), 17155 (1-822); landing C1 moved six of them, each by exactly 5 lines, so these numbers are a map, not an
   input: recount with `grep -n` at implementation time. `scripts/check_sot_registry_parity.dart:150-185` checks bounds and, when `method:` is a
   bare or backticked identifier, that the symbol sits inside the range; a prose method is bounds-only. Also `grep -rn
   "verify-payment/index.ts:[0-9]"` over `docs/` and `test/` and re-anchor the LIVE docs (payment.md, `supabase/functions/CLAUDE.md`); historical
   reviews, diagnoses and plans are records and are not edited. `docs/architecture/payment.md` (the verify-payment rule: the exact invariant, the
   three doors, the corrected client effect); `supabase/functions/CLAUDE.md` (a row in the contracts table and the pinned-tests list);
   `docs/naming_conventions.md` (new terms: replay verdict, replay gate).
4. Diagnose-doc `docs/diagnoses/2026-10-26-verify-payment-non-active-row-<id>.md` (full template). It carries the founder's Q1, Q2 and B2 answers
   verbatim; `recurrence:` cites classes (a) and (b); `touched_layers_checked`: tier 1 `fixed_in_this_batch`, tier 3
   `verified` (no CHECK, free-text status), tier 4 `verified` (14 rows, no live victim), tier 6 `verified` ("live verify-payment is v31,
   verify_jwt true: read-only `list_edge_functions` on 2026-10-26, the same version `docs/audit/payment-hardening.closure.yaml:66` records; the
   deploy of this fix is a separate go"), tier 12 `not_applicable` ("no live trace: handler-level only, fake fetch under the real client; the live proof is waived by the
   founder, Q2"); no `deferred` status; the placeholder scan rejects `TBD`, `TODO`, `tbd`, `todo`, `<...>` and `???`
   (`scripts/validate_diagnose_doc_lib.dart:31-33`; the scan reads the frontmatter, and none of them appears anywhere in the file anyway).
5. `docs/audit/2026-10-25...` is not touched. The index and OI board are not touched in commit 1.
6. Skill self-evolution (CLAUDE.md 5.1), in THIS commit: `.claude/skills/debugging/bug-classes.md` gets the replay-door census entry ("an idempotent
   replay arm must re-check the stored row's entitlement status; enumerate EVERY arm that reads the stored row, including the ones a read ERROR
   makes reachable"), and the edge-function-deploy skill gets the finding already known from this plan: in a throwaway clone
   `.claude/token_path.js` (`primaryRoot` `:41-55`, `candidateEntries` `:63-74`) resolves "primary" as the clone itself, which holds no token, so a clone deploy needs `--token-file`. Anything the
   deploy itself reveals goes into the post-deploy PR (it cannot be in commit 1).
7. The B-pass review file `docs/reviews/<hash>-review.md` carries a dated `## Tuning entry` section (CLAUDE.md 5.1; `check_skill_tuning_history.dart`).
8. The section 5 walk at batch end, each row answered: project retrospective `project_oi410_*.md` and the MEMORY index (a shipped batch goes to
   `MEMORY_ARCHIVED.md`); `feedback_*.md` only if the founder corrects a claim or a recurring class shows (state which); root CLAUDE.md: no new
   invariant (state it); the new bug-classes entry takes the next free number (`check_bug_class_numbers_unique`); `dart run
   scripts/check_context_artifact_budget.dart` (`open_issues.md` is in the soft band, about +4.7% against a 15% band, so no `--record` unless the run
   says otherwise); device verification NOT APPLICABLE and stated so (no device-exercisable path, A2; the live proof is waived, Q2); review seats get
   `docs/agent_brief_preamble.md` prepended (4.8); worktree retirement after the merge and main CI green (4.13.8).
Hermes (after commit 1): four Sonnet seats on the COMMITTED diff (lenses above); the report `docs/audit/2026-10-26-hermes-oi410.md` carries a
line-anchored `verdict: accepted` and lands in commit 2. A hermes finding that needs code is a NEW commit with its own B-pass and review file.
Commit 2 (`docs(oi):`, NO `closes-oi`): the hermes report; the closure ledger named after the branch,
`docs/audit/oi410-verify-nonactive-row.closure.yaml`, whose header carries a note that the `verified_clean` live-proof row records a FOUNDER WAIVER
and not a live run (as the OI-414 ledger header does for its census rows); that row's `evidence:` states ONLY the waiver (Q2 verbatim) and what exists at commit time (the handler-level tests, the M0 proof): the deploy-time boot probe and signed-in smoke are NOT pre-written into it, the post-deploy PR adds them; OI-410 stays OPEN with "Blocked on: the founder's per-action deploy go"
and the corrected Verified/trigger text (SKILL 6.10: a merged Edge Function fix is not a fixed bug until it is deployed); one NEW OI-348 row, **C10**
(section C, log reads and dashboard looks, after C9): "OI-410 observation: if verify-payment's logs show `replay refused, row not active` or
`replay unconfirmed`, this is the expected form; read as 'if seen, else N/A'; ABSENCE PROVES NOTHING; not listed under Flips and never blocking
an OI"; it carries no ledger row, its result is noted in the C10 row itself. C9 is NOT extended (it cannot expect to see these lines and gates other OIs).
Commit 3: the plan-review record `docs/plan-reviews/oi410-verify-nonactive-row.md`, frontmatter `branch: oi410-verify-nonactive-row` (the gate
cross-checks it, `plan_review_record_lib.dart` `recordBranchFieldMatches`), `plan: docs/plans/2026-10-26-oi410-verify-payment-non-active-row.md`,
`date: 2026-10-26`, `blast_radius: catastrophic`, `review_rounds:` the rounds actually run (round 5 is the mechanical-only confirmation on v5, so 5 if it
converges; never fewer: rounds 2 to 4 were `not_converged`), `ground_truth_verified: true` with a "Ground truth" section, `verdict: converged`,
`bpass: accepted` + `bpass_review: <file>`, `hermes: accepted` + `hermes_report: <file>` (each cited file with a line-anchored `verdict: accepted`);
a "Founder decisions" section pasting Q1, Q2 and the B2 answer verbatim. Commit 3 is apart from commit 1 so its citation of the
review file does not move the review's staging hash.
**Post-deploy docs PR** (own worktree, after the deploy go and the deploy): records the deployed git SHA, the version, the payload sha256 and the
boot probe and smoke results (OI-405: the payload archive is untracked, so this PR is the durable record), flips the ledger deploy row, archives
OI-410 to `closed_issues.md` (as `04adb84b` did for OI-414) and CLOSES it (`closes-oi: OI-410`) AT THE DEPLOY, as Q2 chose, provided the checks Q2 names (boot probe, signed-in smoke) were actually run: with no named tester account it does NOT close OI-410 until the founder names one or accepts a boot-probe-only basis in words. Its own commit, push, PR and merge each need a founder go. The 24 h watch window
that follows is monitoring: a rollback trigger opens a NEW OI and asks for the rollback go; it does not delay the close.

## Tests (each mutated, 4.4 rule 21)

Deno, `supabase/functions/verify-payment/index_test.ts`, on the fetch-level fake (the real supabase-js client), plus one Dart source pin. Baseline
today: 62 passed (46 `t(` plus 16 from loops). The Deno suite needs write permission (`Deno.makeTempDir` in `loadOriginMainHandler`): local form
`deno test --no-check --allow-env --allow-read --allow-write --node-modules-dir=none supabase/functions/verify-payment/`; CI runs the directory form
with `--allow-all`. The frozen fixture `_shared/fixtures/verify_payment_origin_main.ts.txt` is the PRE-Piece-A code (669 lines, commit 8be9371d), not
live v31; it still has the pre-select defect (`:539-541`, `:620`), so T3 holds, and the only revert-to-CURRENT-code proof is M0.

**Fixtures.** The early read is active-only and keyed on `status=eq.active` + `razorpay_payment_id`; a non-active row misses it by itself. The
pre-select is keyed on the EXACT select string `id,end_date,status` (no `status` filter). The 23505 re-read is keyed on `end_date,status`. The
fake enforces the unique index (`postgrest_fake_fetch.ts:216-224`): an insert for a payment id already in the table answers 23505. The rpc fake is
canned (`recordPaid`): it plants nothing, so a door-3 row must already be in the table. Two helpers:
- `webhookWon(activeRow)` (door 1, T2): the ACTIVE row is planted and ONE intercept answers `[]` for the early active-only read only, so the later
  pre-select finds the active row and takes door 1.
- `replayBehindPreselect(row, how)` (doors 2 and 3, and the repaired ON tests): the row is planted; for an ACTIVE row a first intercept answers `[]`
  to the early read (a non-active row misses it by itself); a second intercept answers the pre-select (exact select `id,end_date,status`) with a 500
  (`how = "error"`) or `[]` (`how = "empty"`); the door's own read (`end_date,status` for door 2, `status` for door 3) stays LIVE. Door 2 then
  reaches its 23505 through the unique index; the `beforeInsert` plant of `index_test.ts:280` is the intercept-free alternative for a door-2 row
  (active or not: the plant runs after the early read and the pre-select, which models the real race more faithfully than a pre-select error).

- **T0 import.** `index.ts` reads `RAZORPAY_KEY_SECRET`, `SUPABASE_URL` and the service-role key at module load (`index.ts:56-59`), and the harness sets
  the env only around a DYNAMIC import (`payment_writer_harness.ts:33-47`), so a static `import { replayVerdict } from "./index.ts"` would load the
  module with no env and cache that broken instance for the later `importWithEnv(...)`. T0 takes the function from the namespace of the existing
  import: `const mod = await importWithEnv(() => import("./index.ts"))`, then `mod.handler` and `mod.replayVerdict`. Under M0 only the T0 tests then
  fail on the missing function; the handler tests redden on behaviour.
- **Console assertions.** The new lines are a `log` (refused) and a `warn` (unconfirmed): `captureConsole` sends those to `all` only and `error` to both
  `errors` and `all` (`payment_writer_harness.ts:98-122`), so every assertion on them reads `r.all`.
- **T0 (pure table):** `replayVerdict` over `active` -> ok; `cancelled`, `expired`, `refunded`, `pending`, `""`, `null`, absent key, `ACTIVE`,
  `"active "`, number, object -> not_active; `null`/`undefined` row, non-object row, `readFailed=true` (with and without a row) -> unconfirmed.
- **T1 (door 1):** statuses `cancelled, expired, refunded, pending, ""`, `null`, an absent `status` key, `ACTIVE`, a hostile value (a newline plus a
  forged `[verify-payment]` line, and a 40-character one), for stacking OFF and ON, and a row with `end_date: null`: HTTP 200, body DEEP-EQUAL to
  `{verified:false, error:"Subscription for this payment is not active"}`, response headers `access-control-allow-origin` and `content-type:
  application/json` present; zero inserts, zero `record_paid_subscription` calls, zero promo increments, zero mismatch reads, zero alert inserts;
  exactly one log line `replay refused, row not active` whose status is the `codeToken` (`no_code` for empty/null/absent/hostile/long), never a
  date and never the raw hostile text.
- **T1b (door 2):** `replayBehindPreselect(cancelled, "error")`, switch OFF: the insert gets the fake's 23505, the re-read selects `end_date,status`,
  the answer is the T1 refusal; no promo. Plus the `ACTIVE`-cased and `null` status.
- **T1c (door 3):** `replayBehindPreselect(cancelled, "error")` PLUS a second active row for the same user (a user-id-only read would hit PGRST116 and
  answer `unconfirmed`, killing M16), switch ON, `out_inserted:false`: the status read hits the cancelled row, T1 refusal; exactly one rpc call and
  exactly one status read, whose filters are exactly `razorpay_payment_id=eq.PAY`, `user_id=eq.USER`, `select=status`, no `status` filter.
- **T2 (positive control, why the else arm exists):** `webhookWon(active row)`: 200, `verified:true`, `source:"razorpay_api"`, `end_date` = that
  row's, no insert, no rpc, no promo; OFF and ON. **T2b/T2c:** doors 2 and 3 with `replayBehindPreselect(ACTIVE row, ...)` still answer
  `verified:true` (the refusal needs the status to be non-active).
- **T2d (B2, the unreadable cases, explicit):** door 2 and door 3, each with (i) the door's read answering `[]` (row absent) and (ii) answering 500:
  HTTP 200 body DEEP-EQUAL to `{verified:false, error:"Could not confirm this payment yet; please retry"}`; one `replay unconfirmed` line with
  `code=no_code` for (i) and `code=XX000` for (ii); no insert beyond the one that produced the 23505, no promo, no alert. Do not use a foreign-owner
  row as the "absent" fixture (the ledger records the foreign-owner gap as closed by B2 without a fixture).
- **T2e (negative):** ON with `out_inserted:true`: ZERO `subscriptions` GETs after the rpc (`helperReads` filters `end_date=gt.` and would not see
  door 3, so this test counts all subscriptions GETs after the rpc call).
- **T3 (frozen-origin control, NOT the regression proof):** the unmodified pre-Piece-A handler on the cancelled scenario answers `verified:true`
  with the row's end date: the defect is reproduced by old code. The red-without-fix proof is M0/M14/M15 below.
- **T4 (request shapes):** the pre-select selects `id,end_date,status` with filters `razorpay_payment_id` + `user_id` and no `status`; the race
  re-read selects `end_date,status` with the same filters; the door-3 read as in T1c. T4 is also what kills a mutant that drops the
  `razorpay_payment_id` filter at door 1 or door 2 (M22).
- **Existing tests repaired** (4.9 "repairing an enforcement breaks the tests that relied on it not enforcing"). Ten go red before the repair: 8
  from the select change (the 6 OFF goldens of the `for (const sw of [...])` loop at `:224`, the golden at `:242`, the U0 test), 1 from the refusal
  (`:270`) and 1 from the ON fixtures ((e): the `false` iteration at `:108-117`, which asserts `verified === true`); three more go VACUOUS, not red (`:123-134`, `:322-333`, `:413-418`). (a) `:270` pinned the DEFECT (cancelled row, canonical end returned): repointed to T1's answer keeping
  its no-rpc/no-insert/no-promo assertions. (b) The 7 OFF golden comparisons compare `normalizeRequests` (which INCLUDES `query`,
  `_shared/payment_writer_harness.ts:128-130`) to the pre-Piece-A handler's `select=id,end_date`: a narrow harness normaliser `withoutStatusSelect`
  rewrites ONLY a subscriptions GET whose `select` is exactly `id,end_date,status` back to `id,end_date`, on the NEW-handler side only (applied to
  both it would make M18 equivalent). The `end_date,status` rewrite is NOT written: no OFF golden reaches the 23505 re-read, and a branch no test
  exercises is a surviving mutant. (c) The U0 test (`:631-646`) uses ONE intercept for both the origin handler (select `id,end_date`, the positive
  control at `:638`) and the new handler (`id,end_date,status`): the intercept accepts BOTH strings. (d) `:322-333` (the switch-log-line test; its
  cancelled sub-case) and `:413-418` (the alarm test that uses a cancelled row as a stand-in for the pre-select arm) go VACUOUS, not red (the refusal
  returns before the code they watch): repointed to `webhookWon`. `:280` (the plain 23505 race) stays green and untouched (its winner row is ACTIVE).
  (e) The ON tests with `rows: []` + `out_inserted:false` (the `false` iteration at `:108-117` goes red; the "no" case at `:123-134` stays green and goes vacuous) fall to
  `unconfirmed`: their fixtures use `replayBehindPreselect(active, "empty")`. (f) The reader pins already exist and are cited, not duplicated:
  `test/core/payment_retry_attempt_test.dart:94-98` and `verify_payment_owner_before_capture_writer_to_reader_test.dart:64-68`.
- **Dart regression test (CLAUDE.md 4.1: every fix lands with one in `test/contracts/`; Gate 9 name rule):**
  `test/contracts/verify_payment_verified_means_active_row_writer_to_reader_test.dart`, comments stripped before matching: `export function
  replayVerdict` with the single `=== "active"` comparison; exactly three `const refused = replayGate(` call sites with first arguments
  `paymentSubRow`, `raceRow`, `storedRow` (the `function replayGate(` definition does not match the `const refused =` prefix);
  the pre-select select string `id, end_date, status`; the re-read `end_date, status`; the door-3 read `select("status")` with BOTH
  `.eq("razorpay_payment_id"` and `.eq("user_id"` in a compact chain (the sibling `verify_payment_notes_user_id_required_test.dart` uses a
  200-character lazy window: no long comment between). Presence only; the registry entry carries the Deno file as `behavioral_test_path`.
- **Derived sweep:** `clean_orphan_media_pro_recheck_test.dart` (~:262-295, a user-keyed `maybeSingle` needs `.limit(1)`) exempts a payment-id key;
  the door-3 read has the same shape as the `:606` pre-select (the precedent) and stays green. Run it to confirm.

**Mutants** (computed before written, each confirmed applied with `grep -c`, source restored with an equal sha256; the Deno suite plus the Dart pin
and `payment_log_safety_writer_to_reader_test.dart` as the oracle; a compile error is NOT a kill, check `failed=` counts and a named test):
**M0 revert the whole handler to `git show origin/main:supabase/functions/verify-payment/index.ts`** (the true red-without-fix proof: T1/T1b/T1c/T2d
must redden); M1 door-1 `replayGate` call removed; M2 `replayVerdict` condition inverted; M3 compares to `"cancelled"` only; M4 pre-select without
`status` (the status is then absent, so even an ACTIVE row is `not_active`: T2 reddens); M5 `null` status treated as active; M6 refusal body keeps
`verified:true`; M7 refusal answers 409/500; M8 refusal body includes `end_date`; M9 `unconfirmed` mapped to `ok` (kills B2: T2d); M10 log carries
the raw status (killed by the hostile-status T1 case and the Dart allowlist); M11 the verdict check on the early read as well (reddens only because
that select lacks `status`, via `:261`; describe it so); M12 case-insensitive compare; M13 refusal nested under `if (existingEnd)` (the `end_date:
null` row); M14 door 2 removed; M15 door 3 removed; M16 door 3 reads by `user_id` only (T1c's second row); M17 door 2 treats an ABSENT row as `ok`
(T2d(i)); M18 `withoutStatusSelect` strips every select (a golden must redden); M19 CORS/content-type headers dropped from the refusal (the T1 header
assertion); M20 door 3 passes `null` as the read error (`replayGate(storedRow, null, ...)`): killed ONLY by T2d(ii)'s `code=XX000` assertion, because `row == null`
already yields `unconfirmed` without it; M21 door 3 read also runs when `inserted===true` (T2e); M22 the `razorpay_payment_id` filter dropped from the
door-1 select or the door-2 re-read (T4). A green mutant is a finding.

## Census (every door that answers entitlement from a payment row), with true reachability

`closure.yaml` rows: early read (`verified_clean`, active-only; a read ERROR on it is ignored by design and falls to the pre-select, covered);
pre-select arm, 23505 arm, ON `!inserted` (all `closed_in_commit`); the unreadable-status residual at doors 2/3 (`closed_in_commit`, by B2: this
replaces v2's `verified_clean` A3 row, which round 2 correctly called a reachable hole); the foreign-owner row in the OFF 23505 arm (`closed_in_commit`
as a B2 side effect, no fixture); `razorpay-webhook` idempotency pre-select (`verified_clean`: `razorpay-webhook/index.ts:464-482, 706-720`, id-only,
acks Razorpay with `alreadyProcessed:true`, not read as entitlement); `verify-subscription` (`verified_clean`: `.eq("status","active")` at
`index.ts:68-70` and the end-date term at `:91-100`); `redeem-referral:132` (an "ever paid" check, not an entitlement answer);
`admin-verify-payment` (a 410 stub); client Phase 1 poll and `refreshFromSupabase` (filter active); the shared predicate `status = 'active' AND
end_date > now()` (`_shared/subscription.ts:10-14`) versus the early read's missing end-date term (`verified_clean` for THIS flow only: Phase 2 and the
retries run within about 22 minutes of a payment, so a paid row whose end is already past cannot occur; not asserted for other callers); the live
behavioural proof of the refusal (`verified_clean`, `evidence:` "WAIVED by the founder 2026-10-26, Q2, answer 'Waive the live proof (Recommended)':
closure rests on the handler-level tests against the real client library, the M0 revert proof; the deploy-time boot probe and signed-in smoke are recorded by the post-deploy PR, not pre-written here"; SKILL
6.10(2) wants a live check, so this row names the waiver as the founder's call, not as evidence of a live run); the live deploy (`blocked_on_user`
until the deploy go; flipped by the post-deploy PR).

## Accepted properties and not-claimed

- A1 The fix restores the server contract; it delays an honest demotion by up to about 20 minutes for the rare class (Client effect paragraph).
- A2 NOT observed live (4 non-active rows with a payment id, none with a future end date); the live proof is waived by the founder (Q2). The arm is
  not device-exercisable; the OI-348 observation row sees it only if it ever fires, and its absence proves nothing.
- A3 (REPLACED by B2, above): there is no "refusal needs proof" property any more.
- A4 `status` is unconstrained free text; "exactly `active` or not verified" fails closed for a future value.
- A5 Refund events are not handled by either writer; how a row becomes `cancelled` is an operator action. OI-410 adds no refund handling.
- A6 The server answer for a non-active row is a 200 soft failure; the retries (60 s, 5 min, 15 min) re-hit the function a bounded number of times
  (its budget is 20 per 10 minutes).
- A7 `unconfirmed` makes a compound three-failure case cost one retry interval (B2 cost paragraph).

## Verification, review, rollout

Gate loop BEFORE any review round that has a draft diff (4.12.5, 4.12.8): whole-project `flutter analyze --no-fatal-infos`; `deno check
--node-modules-dir=none supabase/functions/verify-payment/index.ts` (`PATH=$HOME/.deno/bin:$PATH`); the Deno directory suite
(`deno test --no-check --allow-all --node-modules-dir=none supabase/functions/`; the `:8000` AddrInUse pair is a known local quirk); the touched
Dart tests plus `TZ=Asia/Kolkata flutter test --exclude-tags golden`; `PRE_COMMIT_GATE_JOBS=1 sh scripts/pre-commit.sh`. Plan review x2: round 5 on
THIS post-round-4 plan, one fresh seat per part (mechanical-only: it checks each v5 fold and the contradictions, nothing else; a new material finding means the unit is too large and is
split, 4.12.1); B-pass (3 seats); hermes (4 seats, after commit 1). Merge only via `sh scripts/safe_pr_merge.sh <pr>` after CI; replay the
merge-to-main plan-review gate (`hermes: accepted`, the bpass and hermes files with line-anchored `verdict: accepted`) in a scratch clone first.
After the merge: main CI green, retire the worktree (4.13.8). Each of commit, push, PR and merge needs the founder's explicit word.

**Live deploy: a separate, per-action go asked for after the merge.** The ask lists EVERY live action it covers, by name, and the founder may grant
them together or one by one: (1) the read-only fresh GET of the live function and the multipart bundle compare; (2) the deploy, including the tool's own pre-deploy snapshot GET and post-deploy smoke POST (`--rollback --dry-run` makes no network call); (3) the anon-key
boot probe; (4) the signed-in smoke, with a QA test account the founder names in that ask (the reset-test-user skill lists the QA accounts), whose
credential the founder types into the shell or names in a gitignored file, and which is never printed or committed; if no account is named, the founder either names one or accepts in words a boot-probe-only basis (Q2 named an authenticated smoke, so the plan does not assume it away), and until then OI-410 stays OPEN with the smoke row the post-deploy PR adds (`blocked_on_user` until then); (5) the 24 h read-only reads (`query_logs`, a SELECT on `alerts`). The ask also repeats the founder's recorded B2 answer. A ROLLBACK is a live deploy and needs its own go at the moment a trigger fires, unless the founder grants it in the ask in
words. Per `.claude/skills/edge-function-deploy-rollback/SKILL.md`: section 2 (the standard deploy) with the pre-flight 1.1-1.3, 3.2 and 6.13 (the
rollback recipe), 6.5 and 6.7 (boot and auth verification), 6.9 (live-equal sha, multipart compare), 6.10 (the verification obligation; its
live-output part is waived by Q2; the rest is done by the steps below), 6.13 (a fresh GET of `verify_jwt` and the explicit flag).
1. Deploy from a THROWAWAY CLONE at merged `main` (not the primary, not a worktree: the deploy tool rewrites tracked backups and leaves untracked
   payloads, OI-405). In a clone `.claude/token_path.js` (`primaryRoot` `:41-55`, `candidateEntries` `:63-74`) resolves "primary" as the clone itself, which has no token, so EVERY `deploy_via_api.js` call (not `emit_payload.js`, which rejects unknown arguments) gets
   `--token-file "/home/ubuntu/projects/avya/.supabase/supabase access token.txt"` (the working file; never the revoked `supabase/.supabase/` one).
   `SUPABASE_ANON_KEY` comes from the primary's `.env`; the tester JWT from (4) above.
2. Fresh GET of the live function: record version (v31 expected; the GET is the proof), `verify_jwt`, and confirm the live bundle equals the pre-merge
   source of the whole import closure by the multipart method (6.9). **Then compute the diff from the live-equal sha to merged `main` over the whole
   import closure (`supabase/functions/verify-payment/` and the `_shared/` files it imports): it must be exactly this fix. Anything else (another
   merged change to the function or to an imported `_shared` file) means STOP and ask the founder.** Then `node .claude/deploy_via_api.js --rollback
   verify-payment <live-equal sha> --dry-run`; copy the rollback payload to the scratchpad with its sha256.
3. Deploy: `node .claude/emit_payload.js verify-payment --auto --functions-dir <clone>/supabase/functions`, then `node .claude/deploy_via_api.js
   dedsavbjuwgarrhphgnl verify-payment .claude/_payload_verify-payment.json <verify_jwt from step 2> --yes --token-file ...` (`--yes` because the tool aborts without a TTY, `deploy_via_api.js:885-921`; added only after the go). Afterwards confirm the
   version bumped and the decoded bundle equals merged `main`.
4. Boot-verify with the anon-key Bearer (the module's own 4xx, never a 503). Smoke with a REAL user JWT and a fake `pay_` id: assert "not 401 and
   not 503" (a fake id gets 502 from Razorpay); this proves auth and boot ONLY, not the refusal.
5. **Watch window: 24 hours** after the deploy: monitoring, not a closing condition (Q2). Read the function's logs (`query_logs`) for `replay refused`,
   `replay unconfirmed`, 5xx and 503/boot lines, and `alerts` for `payment_record_failed`. Expected: no 5xx change, no boot error, both new lines
   absent or explained.
6. **Rollback triggers (any one):** a 503/boot failure; a 5xx rate change on verify-payment; any `replay unconfirmed` for a payment whose row is
   active and readable; any report of an honest paid user shown "not activated" with an active row. Rollback: forward-deploy the saved previous
   payload `node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl verify-payment .claude/_payload_verify-payment_rollback_<sha>.json true --yes
   --token-file ...` (the flag is the `verify_jwt` read in step 2, stated explicitly: 6.13), re-check version and boot; no client build is needed.
   A trigger opens a NEW OI.
7. The post-deploy docs PR (Change set) records the SHA, version, payload sha256 and the boot and smoke results, and closes OI-410 at the deploy ONLY IF the checks Q2 names were actually run (see go-ask item (4) above). That PR's own commit, push, PR and merge each need a founder go. A rollback, if one happens, gets its own diagnose-doc (SKILL 3.3 and 8).

## Out of scope (stated)
The early read's end-date term; refund-event handling; any client change; any migration; `razorpay-webhook`; a runtime kill switch (Q1).
