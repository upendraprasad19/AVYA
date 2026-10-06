---
bug_id: f7c3a1
date: 2026-09-14
batch: telegram-admin-bot-task-13-push-gate
status: fixed
blast_radius: platform
symptom: |
  `test/contracts/admin_metrics_functions_role_revoke_test.dart`'s "EVERY
  post-103 migration ... re-asserts the anon + authenticated revoke (a9d3f1
  replay guard)" test failed on the first full `flutter test` run of the
  telegram-admin-bot branch (surfaced only at pre-push, since pre-commit does
  not run `flutter test`). Migrations 135 and 136 each carry a
  signature-unchanged `CREATE OR REPLACE FUNCTION public.founder_metrics_ops()`
  with no revoke of their own, which the test's per-file replay-guard
  correctly flags as drift from the established a9d3f1 / e4a1b7 defense-in-
  depth pattern (every migration touching a founder_metrics_* function must
  carry its own explicit `revoke execute ... from anon, authenticated;`).
  Neither Review Round 1, Review Round 2, the B-pass on migrations 135/136,
  nor the 8-lens Hermes pass caught this, because none of them ran
  `flutter test` locally — only live SQL verification and Deno tests were
  run against the migrations, and this is a static Dart contract test.
concept: founder_metrics_ops_acl_replay_guard
sot_registry_entry: |
  Not applicable — this is a database-function ACL invariant enforced by a
  static contract test over supabase/migrations/, not a Hive/Postgres
  writer-reader data contract.
writers:
  - { file: supabase/migrations/135_founder_metrics_ops_exclude_info_client_errors.sql, method_or_widget: "CREATE OR REPLACE FUNCTION public.founder_metrics_ops() — no revoke of its own", line: 24 }
  - { file: supabase/migrations/136_founder_metrics_ops_exclude_info_client_errors_7d.sql, method_or_widget: "CREATE OR REPLACE FUNCTION public.founder_metrics_ops() — no revoke of its own", line: 27 }
  - { file: supabase/migrations/137_founder_metrics_ops_reassert_role_revoke.sql, method_or_widget: "revoke execute on function public.founder_metrics_ops() from anon, authenticated; — the follow-on fix", line: 30 }
readers:
  - { file: test/contracts/admin_metrics_functions_role_revoke_test.dart, method_or_widget: "'EVERY post-103 migration ... re-asserts the anon + authenticated revoke' test", line: 73 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: null
contract_test_path: test/contracts/admin_metrics_functions_role_revoke_test.dart
ist_handling:
  - "Not applicable — no date keys or counters involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — SECURITY DEFINER function ACL, not a user-account concept.
forbidden_patterns_checked:
  - { pattern: "CREATE OR REPLACE FUNCTION public.founder_metrics_* without its own anon+authenticated revoke, post-103", absent: false, note: "was present in 135/136 — fixed by 137 + a narrow, documented test exemption for the two already-applied files" }
proposed_fix: |
  1. Verify live ACL state via has_function_privilege before concluding
     anything — confirmed anon=false, authenticated=false, service_role=true,
     meaning migration 103's original revoke survived 135's and 136's
     signature-unchanged CREATE OR REPLACE (ordinary Postgres ACL-preservation
     semantics; there was never a live security exposure).
  2. Since migrations 135 and 136 are already APPLIED and, per
     supabase/migrations/CLAUDE.md, an applied migration is IMMUTABLE
     (including its comments), the fix cannot edit those two files. Instead:
     write migration 137, which re-asserts
     `revoke execute on function public.founder_metrics_ops() from anon,
     authenticated;` as defense-in-depth for any future full replay of the
     migration set.
  3. Add a narrow, fully-documented exemption in
     admin_metrics_functions_role_revoke_test.dart naming migrations 135 and
     136 by filename, explaining why (immutable + live-verified safe +
     covered by 137), so the guard's protection is unweakened for every other
     migration, past or future.
  4. Add a new test pinning migration 137's own revoke line, so deleting 137
     is itself caught by the suite (closing the loop the exemption opens).
regression_test_planned:
  - test/contracts/admin_metrics_functions_role_revoke_test.dart
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "No client-side code involved." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive involvement." }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "founder_metrics_ops() signature unchanged across 135/136/137 (no args, same return table); pg_get_functiondef confirms live body matches 136's file exactly." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data migration; ACL-only change." }
  - { tier: 5, name: "Migrations applied", status: fixed_in_this_batch, evidence: "Migration 137 applied live after founder authorization; backups/applied_migrations.json updated in this commit." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not cron-related." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "SECURITY DEFINER function ACL, not RLS." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "No storage involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: "Client → server contract", status: verified, evidence: "has_function_privilege('anon', ...) and ('authenticated', ...) both false pre- and post-137; ('service_role', ...) true throughout — no change in observable behaviour for any caller." }
impact_analysis: |
  No live exposure at any point: has_function_privilege confirmed
  anon/authenticated EXECUTE were already false before migration 137 was
  written, because Postgres preserves a function's ACL across a
  signature-unchanged CREATE OR REPLACE (migration 103's original revoke on
  founder_metrics_ops() survived both 135's and 136's replaces). The bug is
  purely a SOURCE-level defense-in-depth gap: a full replay of the migration
  set from an empty database would rely on that implicit ACL-preservation
  behaviour holding, which the project's own contract test (and prior
  incidents a9d3f1, e4a1b7) treat as too fragile to trust without an explicit
  re-assertion. Migration 137 closes that gap. Cost of the fix: one
  near-no-op migration (idempotent revoke), one documented test exemption,
  one new pinning test, and one live-apply cycle with founder authorization.
---

## Root Cause

Migrations 135 and 136 (`telegram-admin-bot`, Review Round 2 / Hermes findings
R2-10 and F1) each fix a bug in `founder_metrics_ops()`'s SQL body via
`CREATE OR REPLACE FUNCTION`, copying the REVOKE-from-PUBLIC + GRANT-to-
service_role tail from the function's prior definition — but neither carries
an explicit `revoke execute on function public.founder_metrics_ops() from
anon, authenticated;`, which is the actual defense against the a9d3f1 class
(REVOKE FROM PUBLIC is a no-op against Supabase's platform default privileges,
which grant EXECUTE to `anon`/`authenticated` directly). The author (working
from the live-verified fact that current privileges were already correct)
did not re-derive that this project's own contract test requires every
migration TOUCHING the function to carry the revoke, not just the migration
that most recently established it.

`test/contracts/admin_metrics_functions_role_revoke_test.dart`'s second test
scans every migration file numbered >103, detects any `CREATE OR REPLACE` /
`DROP` of a `founder_metrics_*` function, and requires an effective revoke
positioned after the last such touch IN THAT SAME FILE — deliberately, per
its own header comment, because migration 120 (a DROP+CREATE) proved that
relying on ACL preservation is unsafe in the general case. The test does not
distinguish a signature-unchanged `CREATE OR REPLACE` (which Postgres does
preserve the ACL across) from a DROP+CREATE or signature change (which it
does not) — a deliberate conservative simplification, not a bug in the test.

Because pre-commit does not run `flutter test` (cost-split, CLAUDE.md §0 /
ADR-0018) and this branch's migrations were only verified via live SQL
(`has_function_privilege`, `BEGIN...ROLLBACK` probes) and Deno tests — never
a local `flutter test` invocation — this Dart-side static contract test never
ran until `scripts/pre-push.sh`'s full-suite gate, at merge time.

## Fix

1. Verified live ACL first (ground truth, not assumption):
   `has_function_privilege('anon'/'authenticated'/'service_role',
   'public.founder_metrics_ops()', 'execute')` → `false / false / true` —
   confirming no live exposure.
2. Migration 137 (`137_founder_metrics_ops_reassert_role_revoke.sql`) adds
   the explicit `revoke execute on function public.founder_metrics_ops()
   from anon, authenticated;`, applied live after founder authorization via
   AskUserQuestion.
3. `admin_metrics_functions_role_revoke_test.dart` gained a narrow, named,
   fully-documented exemption for `135_founder_metrics_ops_exclude_info_
   client_errors.sql` and `136_founder_metrics_ops_exclude_info_client_
   errors_7d.sql` — the only two files exempted, both already-applied and
   immutable per `supabase/migrations/CLAUDE.md`, both covered by 137's
   re-assertion. The exemption does not weaken the guard for any other
   migration (past or future).
4. A new test pins migration 137's own revoke line, closing the loop: if 137
   is ever deleted or its revoke line removed, this new test catches it
   even though 137 itself is not a "touching" migration under the existing
   detector (it contains no CREATE/DROP of the function).

## Verification

- `flutter test test/contracts/admin_metrics_functions_role_revoke_test.dart`
  — 3/3 green after the fix.
- **Mutated it and ran it** (CLAUDE.md §4.4 rule 21):
  - Commented out migration 137's revoke line → the new pinning test
    reddened (`Expected: true, Actual: <false>`), confirming it actually
    detects the failure mode it exists for.
  - Removed the exemption-skip line from the replay-guard test → the
    original "EVERY post-103 migration ..." test reddened on migration 135
    exactly as it did before the fix, confirming the exemption is load-bearing
    and not a silent no-op.
  - Both mutations restored from a pre-mutation backup; final run confirmed
    clean (3/3 green).
- Post-apply live check (after migration 137): `has_function_privilege`
  unchanged (`anon`/`authenticated` false, `service_role` true) — the
  migration is idempotent against the already-safe live state, as expected.

## Related Bugs

- `a9d3f1` (2026-07-13, migration 101/103) — the original anon-executable
  SECURITY DEFINER leak on `public.founder_metrics_*` functions.
- `e4a1b7` (2026-08-26, migration 123) — second recurrence, a different
  `public` SECURITY INVOKER function with the same missing-explicit-revoke
  gap (inert that time because `auth.uid()` is NULL for anon, but the ACL
  gap itself was real).
- This is the **third** occurrence of the same underlying class (a
  `CREATE OR REPLACE` / `DROP` on a `public`-schema function silently
  resetting or failing to carry forward an anon/authenticated revoke),
  though this instance — unlike the first two — never reached a live
  exposure, because the specific migrations involved were signature-unchanged
  replaces where Postgres's ACL-preservation semantics happened to hold.

## Recurrence

Third instance of the `founder_metrics_*` / `public`-schema-function
role-revoke class. `supabase/migrations/CLAUDE.md`'s pitfalls table already
documents the first two; this diagnose-doc is the citable record for the
third, and no further CLAUDE.md edit is needed since the existing pitfall row
("A deliberately-narrowed function ACL survives CREATE OR REPLACE but NOT a
signature change") already states the exact mechanism this instance
confirms — this occurrence is evidence FOR that row's accuracy, not evidence
of a gap in it. The gap this batch actually exposes is process, not
documentation: **plan a static `flutter test` run against any new/replaced
migration's own regression-test file locally, before relying on live SQL
verification alone** — filed as a lesson for future SDD batches touching
`founder_metrics_*` or any function with an existing named contract test in
`test/contracts/`.

## B-pass follow-up

`docs/reviews/9765a1fbaf00-review.md` — 3 findings (2 Medium, 1 Low), 0 false
alarms, all accepted and fixed in the same batch:

- **Finding 1 (blast_radius_mismatch):** this doc's own frontmatter had
  self-declared `blast_radius: catastrophic` while `blast_radius_from_diff.dart`
  computes `platform` for the actual commit (migration 137 carries no
  `SECURITY DEFINER` text, unlike 135/136). Overstated, not gate-bypassing —
  no review round was skipped — but inconsistent with this doc's own
  `impact_analysis`. Corrected to `platform` here.
- **Finding 2 (stale_or_wrong_citation):** the `writers:` entry for migration
  135 cited line 27 for its `CREATE OR REPLACE FUNCTION` statement; the real
  line is 24 (135's header is 3 lines shorter than 136's, so 136's correct
  `line: 27` had been copy-pasted onto 135). Corrected here.
- **Finding 3 (guard_without_its_mirror):** the test exemption
  (`admin_metrics_functions_role_revoke_test.dart`) originally skipped
  migrations 135/136 at the FILE level, before the scanner extracted which
  function(s) each touches — so if either were ever (improperly) edited to
  touch a second `founder_metrics_*` function, that touch would silently
  inherit the exemption too. Tightened to a `(file, function)` pair set,
  checked only after `fns` is computed, so an exemption for
  `135 → founder_metrics_ops` cannot cover `135 → founder_metrics_engagement`.
  Re-mutation-proven after the tightening: commenting out migration 137's
  revoke still reddens exactly the pinning test; disabling the (now
  pair-scoped) exemption check still reddens exactly the replay-guard test,
  naming migration 135.

Live `has_function_privilege` re-verified a third time during triage (values
unchanged: anon=false, authenticated=false, service_role=true), closing the
review's one unresolved item (its own live re-check attempt hit a transient
DB-connection timeout).
