---
reviewed_at: 2026-10-25T05:30:00+05:30
staged_against: 59f092dc27a9
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 10
verdict: accepted
---

# Code Review — 59f092dc27a9 (branch payment-hardening, commit 6: the hermes-pass fixes, diagnose c7e3b1)

Two context-blind Sonnet reviewers (exhaustive command lists, no scripts, no database, mutation protocol with
sha256-restored backups; every final sha256 OK, no unstaged file left):
- **Round A** read the staged commit at `bfaeb6fb79da` and ran 20 mutants: 5 findings (1 P2, 4 P3).
- **Round B (delta)** read only the round-A fixes (staged at `aabb2b0dbdbb`) and ran 18 mutants: 5 findings
  (5 P3), no P0-P2.

All 10 accepted and fixed in this commit; the fixes moved the hash to `59f092dc27a9` (this file's name). The author
re-ran every surviving mutant after its fix (each now red) and mutated each new guard (diagnose c7e3b1
`mutation_proof`). Neither reviewer found a P0 or P1, a way past the H12 ordering, or a change to a payment's
recorded row.

## Round A

## Finding A1 — P2 — guard_without_its_mirror
- **file:line:** supabase/functions/_shared/payment_log_safe.ts (`stackFrames`), used by the four catch-alls
- **claim:** `stackFrames` kept any stack line starting with "at ", and a SyntaxError message quoting a body with a newline + "at " put a body fragment in the log as a "frame", unescaped.
- **verification:** reviewer probe: `JSON.parse('{"a":\n at SECRETPAY ...')` gave first frame `at SECRETP"... is not valid JSON`.
- **suggested-fix:** read the stack after the message; escape frames.
- **status:** accepted — fixed: the stack is read only after the end of `err.message` (`no_stack` when the message is not found), each frame cut to 200 characters and every C0/C1/U+2028/U+2029/Cf character escaped; unit tests with a JSON.parse body and a forged multi-line message. The old split reddens 2 unit tests and the catch-all tests.

## Finding A2 — P3 — asserted_fixture_value (test gap)
- **file:line:** the four outer catch-alls
- **claim:** H10 was pinned only by the Dart source contract; reverting a catch-all left every Deno test green (M8, M8b).
- **verification:** reviewer mutants M8, M8b: Deno green, Dart red.
- **suggested-fix:** one behavioural test per handler with an unparseable body.
- **status:** accepted — fixed: a "catch-all:" test in verify-payment, create-razorpay-order and validate-promo (and, after round B finding 3, the webhook) posts an unparseable body holding a newline + "at " and asserts 500, exactly one `unhandled SyntaxError at at ...` line and no body text. M8/M8b-style mutants red in each.

## Finding A3 — P3 — writer_reader_drift (docs)
- **file:line:** docs/sot_registry.yaml (`promo_validate_rate_limit`); docs/audit/open_issues.md (OI-348 B6)
- **claim:** both still said "Try again in an hour".
- **verification:** `grep -rn "Try again in an hour"`.
- **suggested-fix:** the minutes wording.
- **status:** accepted — fixed in both.

## Finding A4 — P3 — guard_without_its_mirror (claim scope)
- **file:line:** razorpay-webhook/index.ts (`derivePlanFromAmount`, `amount_no_match`)
- **claim:** "a payment no row can record is not captured" holds only for the user_id refusals; an unmatched amount is still captured first.
- **verification:** read the handler (capture before derive).
- **suggested-fix:** reword, or move the derive step.
- **status:** accepted — fixed: the webhook comment, payment.md rule 11(f) and the diagnose say "no usable user id" and name the remaining case; moving the derive step in both writers is filed as OI-409 (it changes the B2a alert's meaning and needs the shared-account question answered live by the founder).

## Finding A5 — P3 — guard_without_its_mirror (H6 tradeoff)
- **file:line:** _shared/founder_digest_content.ts `NON_ACTIVITY_KEYS`
- **claim:** Top users no longer names an account hammering the limits.
- **verification:** read `buildDigestText`.
- **suggested-fix:** state the tradeoff or add a users-at-limit count.
- **status:** accepted — fixed: the tradeoff and where the per-user signal lives (each refusal's `rate-limited` warn line names the user) are stated in the comment.

## Round B (delta, on the round-A fixes)

## Finding B1 — P3 — blast_radius_mismatch (no-deferral)
- **file:line:** the webhook comment, payment.md 11(f), diagnose c7e3b1
- **claim:** the three texts said the amount case was "tracked on the OI board", but no such OI existed in the tree.
- **verification:** `git diff --cached -- docs/audit/open_issues.md`.
- **suggested-fix:** file it and cite the number.
- **status:** accepted — fixed: OI-409 minted (`scripts/mint_oi.sh`) and written in this commit; all three texts cite it.

## Finding B2 — P3 — guard_without_its_mirror (unpinned escape classes)
- **file:line:** payment_log_safe.ts `FRAME_UNSAFE`
- **claim:** dropping the C1 range or `\p{Cf}` from the frame escape left every test green.
- **verification:** reviewer mutants F-noCf, F-noC1: green.
- **suggested-fix:** a fixture with U+0085 and a Cf character.
- **status:** accepted — fixed: a frame fixture with U+0085, U+202E and U+200B; both mutants red.

## Finding B3 — P3 — asserted_fixture_value (test gap)
- **file:line:** razorpay-webhook/index.ts catch-all
- **claim:** the webhook (the money path) had no catch-all behavioural test; a message-printing mutant passed its Deno suite.
- **verification:** reviewer mutant W1: Deno green, Dart red.
- **suggested-fix:** a signed body that is not JSON.
- **status:** accepted — fixed: harness `signedRawWebhookRequest` (a valid HMAC over any text) and a webhook "catch-all:" test; W1 red.

## Finding B4 — P3 — writer_reader_drift (stale text)
- **file:line:** docs/plans/2026-10-24-payment-hardening.md (the promo reason); razorpay-webhook/index_test.ts (the H12 section header)
- **claim:** the plan still said "an hour"; the test header repeated the overclaim.
- **verification:** `git grep -n -i "an hour"`, `git grep -n "cannot record"`.
- **suggested-fix:** reword or annotate.
- **status:** accepted — fixed: the header says "no usable notes.user_id"; the plan keeps its text with a dated note of the shipped wording (it records what was planned).

## Finding B5 — P3 — function_exception_swallow (hostile Error)
- **file:line:** payment_log_safe.ts `stackFrames`
- **claim:** a throwing `stack` or `message` getter made stackFrames throw inside the catch-all, losing the sanitised 500; a non-string message was treated as empty, so the whole stack was scanned (the reviewer's one un-run case).
- **verification:** reviewer probe: "THROWS from stackFrames Error: boom".
- **suggested-fix:** try/catch, `no_stack`.
- **status:** accepted — fixed: the body is wrapped in try/catch (`no_stack`), and a non-string message is `no_stack`; tests for both getters and an object message whose toString forges a frame. Mutants (no try/catch; non-string message read as empty, in a form that compiles) red.

## Lenses returned clean (both rounds, condensed)
- Client contract: `callFunction` retries 502/503/504 only (500 only with `retryOn500`, set solely for nutrition); create-order's 500 shows the same `_extractServerError` text; the paywall shows `reason` verbatim.
- Every registry line_range citing the seven files: first and last lines land on the cited code (both rounds).
- H12 mirrors: a valid authorized payment is captured once and recorded; payment.captured never enters the capture block; a replay hits the idempotency pre-select first.
- H1/H3 switch OFF paths equal the frozen origin handlers (goldens); H9 non-23505 still an error line.
- Real handler errors (req.json SyntaxError, fetch TypeError, NotFound, AbortError, async chains, an Error subclass setting `name` after `super()`) all give real frames, not `no_stack`.
- secrets_in_tree, unawaited_no_error_sink, missing_input: none.

## Founder triage notes
Self-triaged by the author under the founder's commit go for this batch (2026-10-24): 10 accepted, all fixed in
this commit (one by filing OI-409, which the commit also writes); no false alarm.

## Tuning entry
- **2026-10-25** - blast-radius catastrophic - 10 findings; 0 false_alarm; tuning: none (a sanitiser that FILTERS a structured string by a line prefix must be attacked with input that forges the prefix: a stack's header quotes the message, so "keep lines starting with `at `" is a parser of attacker text; cut at a located boundary and fail closed when the boundary is not found. And a guard's doc claim ("tracked on the OI board") is itself a writer whose reader must exist in the same tree).
