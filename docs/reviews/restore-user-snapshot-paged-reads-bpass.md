---
reviewed_at: 2026-10-06T23:30:00+05:30
staged_against: working tree of claude/avya-streak-data-check-b506de on top of HEAD f5087888 (Slice B1 built in a scratch workspace outside the repo, then copied in byte-identical: paged_reads.ts 8fad43d8, index.ts 647c0535, paged_reads_test.ts 5742f8ae, wiring test e03d3a1a)
blast_radius: platform
reviewer: fresh-context-blind-agents (Sonnet; round 1 two seats: A correctness / fidelity / test adequacy, B cross-user security under service_role; round 2 one seat: C delta re-review; read-only, no command beyond git diff/show/grep, Read, Grep, Glob)
lens_set: [L1, L8, L11, L17, L23, writer_reader_drift, guard_without_its_mirror, asserted_fixture_value, function_exception_swallow, blast_radius_mismatch, missing_input]
findings_count: 14
verdict: accepted
---

# Code Review (B-pass) — restore-user-snapshot returns every row and is scoped on every read (diagnose e4c1d7)

Scope: `supabase/functions/restore-user-snapshot/{paged_reads.ts,index.ts}`, the Deno test `paged_reads_test.ts` with its
old-chains fixture, and `test/contracts/restore_user_snapshot_paged_reads_wiring_test.dart`. Self-attested (rule 21): the
mutation drivers are scratch scripts, not in the repo. Reviewers were told to find defects and to say what they checked;
the coordinator re-read every cited file:line (and re-ran the arithmetic) before accepting a finding, and treated a
reviewer's suggested fix as a separate claim. One reviewer statement was WRONG and was not acted on: seat B said
`index.ts` validated the user id case-sensitively; its regexp carries the `/i` flag (the finding it fed, F-B3, stands on
`scopeEmbed`'s strict compare, which is real).

Round 1 found no P0 or P1 in either seat and confirmed the user scope on every read in the function (about 30), the
fidelity of all thirteen manifest entries to the old source (compared by hand, not via the fixture), and the client's
fail-closed handling of a 500. Round 2 re-reviewed the changes made for round 1.

## Findings (14: 0 P0, 0 P1, 3 P2, 11 P3) and what happened to each

### Round 1, seat A (correctness: 1 P2, 4 P3)

| # | sev | finding | disposition |
|---|---|---|---|
| A1 | P2 | No Deno test asserted the `select` string or the window filter that `readPaged` actually SENT (the fake ignored `select`; every fixture row was dated 2024, so a dropped `gte` excluded nothing). Deleting the filter or sending `select("*")` stayed green; `nutrition_logs` would have lost its `nutrition_log_items` embed. | FIXED: the generic loop asserts the exact select and filters per request, and a row older than the window must be excluded. Mutations M16 (33 red), M17 (7), M18, M19, M20 red. |
| A2 | P3 | Date-primary tables could not tell `[date, id]` from `[id]` (dates rose with ids); the fake's `serverCap` option was never used. | FIXED: dataset C (ids opposite to every time column); a server-cap-500 case. The docblock was corrected in round 2: a MANIFEST that lost its primary term is caught by the old-chains oracle (M28), dataset C catches a reader that stopped using the manifest order. |
| A3 | P3 | `user_custom_*` were unordered before and are `ORDER BY id` (a random uuid) now; the client keeps the first row per name. | FIXED: `[created_at, id]` for both; a behavioural test with created_at opposite to id; M27 red. |
| A4 | P3 | `scopeEmbed` compared owners with strict equality while `UUID_RE` accepts uppercase; `UUID_RE` duplicated. | FIXED with seat B F3 below; one exported `UUID_RE`; W14/W16 red. |
| A5 | P3 | Comment drift: "eleven reads used one .range(0, 49999)" (nine did); "caps inherit today's behaviour verbatim"; SoT registry line citation. | FIXED: comments corrected; the registry entry is updated in this commit. |

### Round 1, seat B (cross-user security: 1 P2, 3 P3)

| # | sev | finding | disposition |
|---|---|---|---|
| B1 | P2 | One authenticated request could fan out to 13 tables x 51 pages = 663 sequential service_role queries and hold every row in memory; a user can write unbounded rows of their own. | FIXED: a per-request page budget (`TOTAL_PAGE_BUDGET = 120`, required argument of `readPaged`, charged in a `finally`). Cost recorded in the diagnose doc: an account above about 100,000 rows in total restores through the legacy path. Memory (bytes) is NOT bounded by it and was not verifiable from here. M6/M6b/M22/M26/M29/M31 red. |
| B2 | P3 | `scopeEmbed` returned a truthy primitive embed unchanged (unreachable from PostgREST today). | FIXED: any non-null, non-plain-object embed becomes null; hostile-shapes test; M23 red. |
| B3 | P3 | An uppercase caller id would pass the guards and null every OWNED template embed (silent hydration loss, fail-closed for security). | FIXED: case-insensitive compare; the first version of the test used an all-digit uuid and let M24 survive, fixed with hex-letter ids (M24 red). |
| B4 | P3 | The `index.ts` header still said `template_exercises` is parent-scoped (the claim C13 disproved); no test pinned the user scope of the reads that stay in `index.ts`. | FIXED: header reworded; the wiring test pins that EVERY `tables["X"] =` assignment mentions `vUid` (W12 red). |

### Round 2, seat C (delta re-review: 1 P2, 4 P3)

| # | sev | finding | disposition |
|---|---|---|---|
| C1 | P2 | The wiring test only compared the budget's position with the first `readPaged`; hoisting `createPageBudget()` above `serve(...)` would have made ONE budget for the whole isolate (every restore after the first few would answer 500 and take the slow path) and passed. | FIXED: the test requires the call inside the handler; mutation W17 (declaration moved above `serve`) red. |
| C2 | P3 | The budget comment was wrong (an empty table costs ONE request; two 50,000-row tables fit only if at most 7 other tables hold rows). | FIXED: comment corrected; the arithmetic is pinned by tests (51 + 51 then 18). |
| C3 | P3 | A budget trip surfaced as fetchAllPages' "an unstable sort key can loop forever" message. | FIXED: rethrown as "page budget exhausted at '<name>'"; M30 red. |
| C4 | P3 | No test read all thirteen tables under one budget for a realistic user, or pinned the floor. | FIXED: a test over 0 / 400 / 1,200 / 3,000 rows per table (13 / 26 / 39 / 52 requests) and `TOTAL_PAGE_BUDGET >= 2 x tables`; M31 red. |
| C5 | P3 | Dataset C's docblock and one `scopeEmbed` branch overstated what they catch. | FIXED: docblock cites the oracle test; the branch is labelled defence in depth. |

## Checked clean by the reviewers (the parts that carry the argument)

- User scope on every read: 13 paged reads and the coach read apply `.eq("user_id", vUid)` as the first filter of every page; the 15 non-paged reads each carry `vUid` (users by id; referral_redemptions by the dual-FK `.or`, which matches its RLS policy, migration 037).
- `vUid` comes only from `getUser(token)` on the service_role client, is a `const`, is UUID-validated before any query, and the validation regexp is anchored without an `m` flag.
- `scheduled_workouts.template_id` is the only child key a caller controls (migration 002: insert check `auth.uid() = user_id`, no check on the FK); `nutrition_log_items` and `template_exercises` inserts require an owned parent.
- Budget arithmetic: the page factory is called once per page request (no retry loop); `pagesTaken` equals the requests sent on every exit path; the budget cannot go negative; the 13 awaits are sequential; no module-level mutable state (two concurrent requests cannot share a budget object).
- Client: a non-200 returns null from `_attemptSingleCallRestore` before the first Hive write and the legacy fan-out runs; a 500 is not retried (retry set is 502/503/504); a partial restore is not reachable.

## Could not verify (recorded in the diagnose doc)

The Edge Function's memory and CPU limits (the budget bounds requests, not bytes; a killed worker answers non-200, the same fallback); live `workout_templates.user_id` nullability and live `db-max-rows` as seen from inside the function (the clamp itself WAS measured live from outside, with the real `fetchAllPages`); that the CI Deno job executes the new test (it runs `deno test --no-check --allow-all --node-modules-dir=auto supabase/functions/`).
