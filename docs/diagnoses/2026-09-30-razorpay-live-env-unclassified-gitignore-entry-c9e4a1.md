---
bug_id: c9e4a1
date: 2026-09-30
batch: sync-aab-build-check-408772
status: fixed
blast_radius: feature
related_bugs: [a9c4f2, b4d7e9, f2a9c7, d7b3e9]
recurrence: >
  FIFTH instance of the same class a9c4f2 (2026-09-04) built the gate for: a tool in THIS repo
  writes a new gitignored path into a worktree, and nobody adds it to either
  `regenerableIgnoredPaths` or `deliberatelyPreciousIgnoredPaths`. The difference from all four
  prior instances: this one was caught IMMEDIATELY, at commit time, by the gate a9c4f2 built —
  the class fix worked exactly as designed. This diagnose-doc exists because rule 22 still
  requires one for a `fix:` commit, not because the gate needed repair.
symptom: >
  `test/scripts/gitignore_classification_test.dart`'s completeness assertion failed:
  `Expected: empty / Actual: ['.claude/.razorpay_live.env']`. A prior step in this same session
  added `.claude/.razorpay_live.env` to `.gitignore` (commit `4bcd41d8`, a one-time live Razorpay
  credential handoff file used to push the live Key Id/Secret to Supabase + Vercel) without
  adding it to either classification list in `scripts/retire_worktree_lib.dart` /
  `test/scripts/gitignore_classification_test.dart`. Surfaced when a merge-commit's
  `pre-commit.sh` "regression catalog" walk (`scripts/check_regression_catalog.dart`) ran this
  test as one of ~132 recently-cited regression tests and it failed.
concept: >
  Same concept as a9c4f2: `retire_worktree_lib.dart` treats any gitignored file absent from
  `regenerableIgnoredPaths` as PRECIOUS by default (correct, fail-safe direction), and
  `gitignore_classification_test.dart` requires every literal `.gitignore` entry in the tracked
  tree to be EXPLICITLY placed in one of the two lists — `regenerableIgnoredPaths` (a script in
  this repo rebuilds it, safe to destroy) or `deliberatelyPreciousIgnoredPaths` (a human typed it
  by hand, destroying it silently reverses a decision). `.claude/.razorpay_live.env` is neither
  regenerable (no script in this repo recreates it — a human pastes real Razorpay credentials
  into it once) nor a case where retirement destroying a leftover copy would be safe by accident,
  since it can hold live production secret material. It belongs with its exact sibling,
  `.claude/.alerts.env`, in the precious list.
sot_registry_entry: not_applicable
sot_registry_note: >
  Worktree retirement is operator tooling, not a data concept — no writer/reader pair in
  `docs/sot_registry.yaml`, no Hive key, no cloud column, same as a9c4f2.
writers:
  - { file: .gitignore, method_or_widget: "the entry added in commit 4bcd41d8, documenting .claude/.razorpay_live.env as a local-only, gitignored credential handoff file", line: 86 }
readers:
  - { file: test/scripts/gitignore_classification_test.dart, method_or_widget: "deliberatelyPreciousIgnoredPaths -- the human-maintained precious ledger; anything ignored and unclassified fails the completeness assertion", line: 58 }
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "regenerableIgnoredPaths / isRegenerableIgnored -- exact-match list retirement actually consults; unaffected by this fix since the entry belongs on the OTHER list", line: 236 }
hive_key_prefix: null
hive_key_formula: "not_applicable -- no Hive involvement."
sync_methods: not_applicable — operator tooling, no cloud fan-out.
restore_methods: not_applicable — nothing is restored.
cloud_table: none
cloud_columns: []
contract_test_path: test/scripts/gitignore_classification_test.dart
ist_handling:
  - { file: scripts/retire_worktree_lib.dart, line: 236, fn: "not_applicable -- no date/timestamp involved." }
provider_invalidations: none — no client state.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  not_applicable — this fix only adds one literal string to a classification ledger; it does not
  change which worktrees are eligible for retirement or how the predicate evaluates them.
forbidden_patterns_checked: >
  - Added to `deliberatelyPreciousIgnoredPaths`, NOT `regenerableIgnoredPaths` — verified this is
    the correct list by checking whether any script in this repo recreates the file's content:
    none does. `.claude/.razorpay_live.env` is populated once, by hand, by a human pasting real
    Razorpay Key Id/Secret values, exactly like `.claude/.alerts.env`'s own classification
    rationale ("Destroying any of these is unrecoverable").
  - No loosening of the exact-match matcher — a single new literal string, following the existing
    convention exactly (placed adjacent to its closest sibling, `.claude/.alerts.env`).
proposed_fix: >
  Add `.claude/.razorpay_live.env` to `deliberatelyPreciousIgnoredPaths` in
  `test/scripts/gitignore_classification_test.dart`, next to `.claude/.alerts.env`.
regression_test_planned:
  - test/scripts/gitignore_classification_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ file touched; test/ + .gitignore only." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive box involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No rows touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involvement." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No table, no policy." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket." }
  - { tier: 10, name: secrets_api_keys, status: verified, evidence: "The file this classification protects held real live Razorpay credentials at one point this session; it has since been deleted from disk (both Supabase and Vercel destinations were confirmed complete) but the .gitignore pattern and its classification obligation remain regardless of whether a file currently matches it." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service call in this fix itself." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "No request shape changed." }
impact_analysis: >
  Product impact ZERO. Operational impact, had this shipped unclassified: this worktree
  (`food-logging-observations-126ab3`) would have joined the a9c4f2 class the next time someone
  tried to retire it after merging — `retire_worktree.dart` would report
  `KEEP food-logging-observations-126ab3 [1 non-regenerable ignored file(s)]` with no path named,
  even though the file itself had already been deleted from disk before this fix (only the
  `.gitignore` pattern, and the classification-completeness assertion tied to it, persist as a
  concept independent of whether a matching file currently exists).

  WHY IT WAS CAUGHT THIS TIME, unlike all four prior instances: a9c4f2's own gate
  (`gitignore_classification_test.dart`) is itself one of the ~132 tests
  `scripts/check_regression_catalog.dart` re-runs on every merge commit (any bug fixed in the
  last 30 days keeps its regression test in that rotation). This is the gate working as designed
  — the first instance of this bug class caught before merge rather than discovered later by a
  KEEP report with no path named.
mutation_evidence: >
  Rule 21 mutate-it-and-run-it. Removed the new `.claude/.razorpay_live.env` entry (and its
  comment) from `deliberatelyPreciousIgnoredPaths`, confirmed applied via
  `grep -c razorpay_live test/scripts/gitignore_classification_test.dart` (1 -> 0), re-ran the
  file: 6 passed / 1 failed, with the SAME assertion this diagnose-doc's `symptom` describes
  (`Actual: ['.claude/.razorpay_live.env']`) reappearing verbatim. Restored the entry, re-ran:
  7/7 green.
---

# c9e4a1 — a live Razorpay credential handoff file was gitignored but never classified for worktree retirement

## What happened

Earlier in this session, `.claude/.razorpay_live.env` (a local-only, gitignored file used once to
hand off live Razorpay Key Id/Secret values for pushing to Supabase Edge Function secrets and the
Vercel dashboard) was added to `.gitignore` in commit `4bcd41d8`. The `.gitignore` entry was never
added to either classification list `gitignore_classification_test.dart` requires every ignored
literal to belong to. The gap surfaced the moment a merge commit's regression-catalog walk
(`scripts/check_regression_catalog.dart`, which re-runs every test cited by a diagnose-doc from
the last 30 days — this repo's own `gitignore_classification_test.dart` among them) ran this test
and it failed.

## Why this is the same bug class as a9c4f2, working as intended

a9c4f2 built this exact gate after four prior instances of "a tool writes a new gitignored path,
nobody classifies it, a worktree becomes permanently unretirable with no path named in the
failure." This is the fifth instance of the underlying gap (a new ignored path with no
classification decision made), but the FIRST one caught by the gate itself rather than discovered
later via an opaque `KEEP <slug> [N non-regenerable ignored file(s)]` report. That is the gate
doing its job, not a defect in it.

## The fix

Added `.claude/.razorpay_live.env` to `deliberatelyPreciousIgnoredPaths`, immediately next to its
closest sibling `.claude/.alerts.env` — both are hand-typed credential files with no regenerating
script in this repo, so both belong on the same list for the same reason.
