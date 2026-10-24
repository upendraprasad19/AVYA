---
reviewed_at: 2026-10-17T22:30:00+05:30
staged_against: d88f0a837e41 (staged diff of branch oi341-purchase-in-trial, OI-341 Piece A build commit)
blast_radius: catastrophic
reviewer: fresh-context-blind-sonnet-agents (2 B-pass seats, read-only, exhaustive command list, mutation only on private copies, no database access) plus a 4-seat hermes pass on the same tree (triaged in docs/plans/oi341-purchase-in-trial.md section 8)
lens_set: [writer_reader_drift, function_exception_swallow, guard_without_its_mirror, unawaited_no_error_sink, secrets_in_tree, blast_radius_mismatch, missing_input, asserted_fixture_value, fake_fidelity, mutation_honesty, test_hygiene, sql_case]
findings_count: 12
verdict: accepted
---

# Code Review (B-pass) - OI-341 Piece A, the server-side stacking writers (dark)

Two fresh, context-blind Sonnet seats read the STAGED diff against plan `docs/plans/oi341-purchase-in-trial.md` v4.1: seat A (the two writers and the shared module: lenses 1-6 plus an OFF-path line diff against `origin/main`, the timezone arithmetic, double-run and half-written-state questions) and seat B (the tests, the fetch-level fake, the golden fixtures and the new SQL case: lenses 7-12). Both mutated private copies only; the worktree was untouched.

**Overall verdict: SHIP-WITH-FIXES, no P0.** 1 P1, 3 P2 and 8 P3 across the two seats. Every one is a row of `docs/audit/oi341-purchase-in-trial.closure.yaml` (`BP-A1..A3`, `BP-B1..B5`, `BP-X1`, `G10`). The hermes pass on the post-fix tree (no P0, no P1) is recorded in the same ledger (`H-*`) and plan section 8.

## Findings and dispositions

| # | Sev | Finding | Disposition |
|---|---|---|---|
| B1 | P1 | `test/contracts/razorpay_webhook_supabase_client_decl_order_test.dart` source-greps the old `serve(async (req: Request) => {` wrapper and broke; the diff touched no `test/` file besides the SQL one | FIXED: repointed to the exported handler signature (not loosened). My targeted run had shown two reds and I had attributed both to the quota-ledger test; the full local suite is what caught the right one |
| A1 | P2 | With the switch ON a malformed payment id in a signed webhook payload failed 500 on every retry, with it OFF it was accepted (verify-payment rejected it with 400 regardless) | FIXED: the webhook rejects it with 400 before any request, not switch-gated; tests for both switch values plus a conforming control; mutants M34, M34b, M37 |
| B2 | P2 | The webhook OFF golden tests flaked about 3 in 60 runs: each request got its own `created_at` and the HMAC signature is stored in the row | FIXED: one event time per process; 0 failures in 25 consecutive runs (the CI step retries three times and would have hidden it) |
| B3 | P2 | 29 of 61 tests failed under a DST timezone: the oracle used UTC milliseconds, the module uses local `setDate` | FIXED: the oracle uses the same local-time arithmetic; 65 (now 68) tests green in UTC, Asia/Kolkata, America/New_York, Europe/London, Australia/Lord_Howe |
| A2 | P3 | No Invalid Date guard on the computed end | FIXED: `resolveEndDate` returns `ok:false bad_end_date`; unit test with a chain stub at the Date limit; mutant M35 |
| A3 | P3 | Two different concurrent payments by one user would both stack on the same base | RECORDED: unreachable while the order function's 409 guard stands; a hard Piece B prerequisite in `payment.md` rule 9 and ledger G10 |
| A4 / B4 | P3 | The harness leaked a temp directory per run and built a `file://` URL by string concatenation (not Windows-safe) | FIXED: `toFileUrl` plus removal in a `finally`; the blast-radius delete scan needed the harness allow-listed with its reason (`blast_radius_data_deleting_paths_catastrophic_test.dart`) |
| B5 | P3 | The fake's unique-constraint name differed from migration 010 | FIXED: `unique_razorpay_payment_id` |
| B6 | P3 | Edge cases not proved at handler level (malformed id with the switch ON and OFF) | FIXED: added for both writers |
| B7 | P3 | The new SQL comment reused the label `V-c` | FIXED: `V-d` (the case ids V12 and V12b were unique) |
| B8 | P3 | `limit(1)` removal is caught only by the query-string pin (the fake returns the latest first anyway) | KEPT AS IS: the pin is the protection; mutant M36 is in the set |
| X1 | - | Mutations that stayed red in both seats: own-payment exclusion, bare `neq`, error fallback, stored end reported (both writers), `user_id`, `status`, `gt`, ordering, switch variants, read-when-OFF, helper before the pre-SELECT | VERIFIED CLEAN: no seat mutation survived |

## Checked and clean (both seats)

The fixtures equal `git show origin/main:` byte for byte (blob SHAs); the staged diff equals the diff against `origin/main`; the only switch-OFF behaviour changes are the wrapper and the id check; every reader of `subscriptions.end_date` takes the latest end and none assumes `end_date - start_date` equals a plan length; the `razorpay_*` columns, constraints and the cancelled_at trigger are unaffected; `blast_radius.yaml` classifies `_shared/subscription_stacking*.ts` catastrophic ahead of `_shared/**`; no secret-shaped literal is in the diff; the new log lines carry ids and an error code only; `emit_payload.js` follows only relative imports from `index.ts`, so the tests, fake, harness and `.ts.txt` fixtures are not bundled; V12 would catch a job that derived the payment time from anything but `start_date`.

## Not verified by this review

That LIVE PostgREST accepts the helper's `.or(...)` query string and the `gt` instant comparison (only the fake and a read-only SQL equivalent were run; the first enabled call is the proof, a Piece B flip step), and that Razorpay re-stamps `created_at` on a webhook retry (Piece B flip precondition).
