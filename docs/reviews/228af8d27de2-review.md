---
reviewed_at: 2026-08-15T16:40:00+05:30
staged_against: 228af8d27de2
reviewed_diff_hash: 36a5740eae0d
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [secrets_in_tree, skip_gate_completeness, ci_silent_green, would_ci_actually_go_green, seed_sql_consistency, blast_radius_mismatch, test_can_actually_fail]
findings_count: 5
verdict: accepted
---

# Code Review — QA credentials from the environment

**Two hashes, deliberately.** The reviewer ran against `36a5740eae0d`; the fixes
for its findings moved the staged diff to `228af8d27de2`, which is what the gate
reads and what this file is named for. Both are recorded so the review can be
traced to the tree it actually examined.

Every finding below was reproduced first-hand before being accepted or rejected.

## Finding 1 — P1 — skip_gate_completeness — the guard was defined and wired to nothing

- **file:line:** `integration_test/helpers/auth_helper.dart:18` (definition);
  `signInWithTestUser()` and `integration_test/flows/auth_flow_test.dart` (no callers)
- **claim:** `kTestCredentialsPresent` had exactly ONE occurrence in the repo — its
  own definition — while `docs/operations/DEVICE_TESTING.md` asserted it *is* the
  guard and that "every flow that signs in must check this first". A device run
  without the defines would type an EMPTY email and password into the sign-in form
  and fail on a UI error naming neither cause. The one call path the guard was
  written for was the one it did not cover.
- **verification:** `git grep -n "kTestCredentialsPresent" -- '*.dart'` → 1 hit,
  the definition.
- **resolution:** FIXED. The check now sits at the top of `signInWithTestUser()`,
  the single choke point every device flow passes through before typing anything.
  It **throws** rather than skipping: a silent skip on a hand-invoked suite is the
  OI-105 shape, where the run looks like it passed and verified nothing. Post-fix
  `git grep -c` → 3 hits in that file.
- **note:** This is the batch author's own error, and the worst-shaped kind — a
  documented enforcement claim that was not true. Recorded rather than quietly
  corrected.
- **status:** fixed

## Finding 2 — P1 — seed_sql_consistency — the repoint made an accidental prod run WORSE

- **file:line:** `supabase/seed_qa.sql` — every upsert block
- **claim:** The seed's uuid moved from a placeholder (`00000000-…-0001`, matching
  no `auth.users` row anywhere) to test6's **real production id**. Every statement
  is `ON CONFLICT … DO UPDATE`, so an accidental run against prod changed from a
  loud FK violation into a **silent successful overwrite** of a real account's
  profile, goal, subscription_status and measurements, plus synthetic rows in its
  real history. The failure mode moved from loud to silent — the wrong direction.
- **verification:** read `seed_qa.sql` in full; cross-checked the new uuid against
  the diagnose-doc's tier-4 evidence. `git grep -n "seed_qa.sql"` confirms it is
  invoked only via `supabase db reset` / manual `psql`, never from CI — so this
  needs human misuse, but the diff makes that misuse's outcome measurably worse.
- **resolution:** FIXED. A blocking-visibility header now states plainly that the
  uuid names a real account, that every statement is an upsert so a prod run
  corrupts silently rather than erroring, and gives the one command that
  distinguishes local from prod (`select current_database(), inet_server_addr();`)
  with an explicit STOP condition.
- **status:** fixed

## Finding 3 — P2 — stale SKIPPED message text

- **file:line:** `test/supabase/auth_restore_test.dart:17`, `sync_service_test.dart:21`
- **claim:** Both gate correctly on the widened four-input `hasCredentials`, but
  their skip-test names still read `SUPABASE_URL / SUPABASE_ANON_KEY not set` —
  unlike the two `edge_functions` siblings, which were updated. Functionally
  harmless, misleading in CI output.
- **verification:** `grep -n "SKIPPED:" test/supabase/*.dart`
- **resolution:** FIXED — both now name all four.
- **status:** fixed

## Finding 4 — P2 — **FALSE ALARM** — the quota does not accumulate

- **file:line:** `test/edge_functions/ai_proxy_test.dart` T15/T19/T18
- **claim:** three live `ai-proxy` calls per run against test6's 10/day free quota,
  so the 4th push in an IST day reddens CI on a 429.
- **why it is false:** `cleanup()` **deletes** `ai_coach_interactions`
  (`supabase_test_helper.dart:321`) and runs in `setUp` of both `test/supabase/`
  files — and the `Run Supabase tests` step (`test.yml:386`) executes **before**
  `Run Edge Function tests` (`:396`) in the same job. Every run therefore zeroes
  the rows before `ai_proxy_test` inserts its three. Steady state ≤3; it never
  approaches 10.
- **verification:** `grep -n "ai_coach_interactions" test/supabase/supabase_test_helper.dart`;
  `grep -n "SupabaseTestHelper.cleanup()" test/supabase/*.dart`;
  `grep -n "name: Run Supabase tests\|name: Run Edge Function tests" .github/workflows/test.yml`
- **⚠ THIS IS THE THIRD REVIEWER TO ASSERT THIS PREMISE.** It is intuitive and its
  refutation is non-local — the deleter lives in a different file *and* a different
  workflow step from the inserter and the counter. Anyone re-raising it should run
  the three commands above before writing it up again. Recorded here so a fourth
  pass does not spend the same effort.
- **status:** false_alarm

## Finding 5 — P2 — identity drift in a profile assertion

- **file:line:** `integration_test/flows/profile_flow_test.dart:74`
- **claim:** `anyTextVisible([... 'qa@', 'icanbefitter'])` — stale literals for the
  new account, untouched by the batch. The test still passes via `'QA Tester'` /
  `kTestEmail`, so its stated intent had silently drifted from what it verifies.
- **verification:** `sed -n '74p'` on the file; it was absent from the staged diff.
- **resolution:** FIXED — reduced to `['QA Tester', 'QA', kTestEmail]`.
- **status:** fixed

## Lenses that came back clean, with evidence

- **secrets_in_tree** — `git grep` for both literals returns hits ONLY in
  `docs/audit/`, `docs/diagnoses/`, `docs/reviews/` (historical record). Zero in
  any `.dart` / `.sql` / `.yml`. `.env.example` additions are placeholders.
- **ci_silent_green** — the announce step and both step `if:` guards check the
  identical four inputs; no disagreement is possible between them. A missing
  secret yields a green job **with** a `::warning::` naming exactly which.
- **shell quoting** — the reviewer re-derived rather than assumed: bash substitutes
  `"$VAR"` once without re-scanning for `$()`/backticks, so a password containing
  metacharacters cannot execute. A real improvement over the previous unquoted
  form, which would word-split on spaces.
- **test_can_actually_fail** — the `credentialsComplete` group has one
  discriminating case per clause. The ZERO-deletes test overrides the `deleteRows`
  seam and asserts `attempted.isEmpty` after the throw, so it genuinely fails if
  the guard moves after the delete loop — independently confirmed by the author's
  mutation run, which reddened exactly that case.
- **seed uuid/email pairing** — the new uuid and email are used together
  consistently across all 8 upsert blocks and match `qaUserIds` in the helper.

## Triage

Five findings: 2 P1 fixed, 2 P2 fixed, 1 P2 false_alarm with the refutation
recorded. Nothing outstanding.

**verdict: accepted**
