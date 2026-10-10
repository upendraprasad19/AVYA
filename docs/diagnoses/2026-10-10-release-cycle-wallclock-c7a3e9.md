---
bug_id: c7a3e9
date: 2026-10-10
batch: release-cycle-speedup B1 (pre-push branch-push skip + safe_pr_merge.sh; OI-275)
status: fixed
blast_radius: platform
symptom: |
  A change to this repo spends most of its wall-clock waiting on test suites that run more than once. Measured 2026-10-09/10: the founder PC's local pre-push full suite takes about 39 minutes (one measurement, OI-275, 2026-10-01) at every blast-radius tier from `account` up, and CI then runs the same suite again on the PR (Unit Tests job 13.0-13.5 min) and a third time on the push to main. A branch push therefore paid 39 minutes locally for a gate that CI repeats in 13. The founder's directive on 2026-10-09 was "push and merge and CI is taking a lot of time everyday; that time is wasted". This batch (B1) removes the local run for BRANCH pushes only; the other levers are B2-B4 in docs/plans/2026-10-10-release-cycle-speedup.md.
concept: release_cycle_prepush_gate
sot_registry_entry: |
  Not a Hive/cloud writer-reader concept. This is process tooling: the pre-push hook (scripts/pre-push.sh) decides whether the local full suite runs, and the new scripts/safe_pr_merge.dart decides whether a PR may be merged. No SoT registry entry applicable.
writers:
  - { file: scripts/pre-push.sh, method_or_widget: "PUSH_REFS capture (formerly `cat > /dev/null`) and push_class: classifies the pushed refs BRANCH_ONLY / DELETE_ONLY / OTHER", line: 108 }
  - { file: scripts/pre-push.sh, method_or_widget: "the BRANCH_ONLY skip arm (known tiers only) before the fall-through run_full_suite", line: 244 }
  - { file: scripts/safe_pr_merge_lib.dart, method_or_widget: "evaluateCheckRuns: the fail-closed required-job rule that replaces the local suite as the merge control", line: 123 }
readers:
  - { file: test/scripts/pre_push_branch_push_skip_e2e_test.dart, method_or_widget: "runs the REAL hook with git-style stdin and stub flutter/dart; asserts which flutter subcommands ran", line: 118 }
  - { file: test/scripts/safe_pr_merge_e2e_test.dart, method_or_widget: "runs the REAL safe_pr_merge.dart against a fake gh; asserts the merge call is made only when green", line: 80 }
  - { file: test/scripts/safe_pr_merge_lib_test.dart, method_or_widget: "evaluateCheckRuns against the real PR #96 check-runs fixture", line: 40 }
hive_key_prefix: "N/A -- infra/tooling change, no Hive involvement"
hive_key_formula: "N/A"
sync_methods:
  - "N/A -- no cloud sync involved"
restore_methods:
  - "N/A"
cloud_table: "N/A -- no cloud table involved"
cloud_columns:
  - "N/A"
contract_test_path: test/scripts/pre_push_branch_push_skip_e2e_test.dart
ist_handling:
  - "Not applicable -- no date offsets in this change."
provider_invalidations:
  - "N/A -- no Riverpod providers involved"
telemetry_op_types:
  success:
    - "N/A"
  failure:
    - "N/A"
cross_account_guard: "N/A -- repo-local tooling with no per-user data access."
forbidden_patterns_checked:
  - { pattern: "a skip arm reachable for a main/develop/tag push or an unknown tier (the suite must run there)", absent: true }
  - { pattern: "cat > /dev/null draining pre-push stdin", absent: true }
proposed_fix: |
  (1) scripts/pre-push.sh captures git's pre-push stdin and classifies the pushed refs with an awk pass over the whole string (a `while read` after a pipe would lose its variables in the pipe's subshell). BRANCH_ONLY = at least one line, every line a well-formed 4-field update or delete of a `refs/heads/<x>` other than main/develop. DELETE_ONLY = BRANCH_ONLY where every line deletes (all-zero local sha), which skips even when the pushed range is empty. Anything else, including empty or malformed stdin, is OTHER and keeps the full suite. At a KNOWN account/platform/catastrophic tier a BRANCH_ONLY push skips the local suite; an unknown or empty tier still runs it. Analyze (212 s) and the contract sweep stay unconditional and above every exit.
  (2) `main` has NO required status checks (strict:true, contexts:[]), so nothing server-side makes a merge depend on CI. scripts/safe_pr_merge.sh forwards exactly one argument (the PR number) to scripts/safe_pr_merge.dart, which merges (`gh pr merge --merge --match-head-commit <sha>`) only when Analyze, Unit Tests, Deno Edge-Function tests, Audit Gates and Build Check (APK) are `success` on the PR head SHA (GitHub-Actions check-runs only, latest non-cancelled run per name; the two push-only jobs may be skipped; any other github-actions check must not be red or running). It FAILS CLOSED on any gh error, unreadable output, zero check-runs, a total_count that disagrees with the parsed runs, an unlisted job whose only runs were cancelled, a draft, a conflict, a closed PR, a PR into a base other than main/develop (CI does not run for it), a PR that edits .github/ (its green checks ran its OWN workflow) unless the caller passes the deliberate `--allow-workflow-change` after reading that diff, or a head that moved between two reads; and after `gh pr merge` it reads the PR state back and exits 2 UNVERIFIED unless it is MERGED. The skip message states that no suite has run for the branch until a PR into main/develop exists. The three new files are pinned `platform` in docs/blast_radius.yaml so a loosening edit gets a review record.
  (3) Wording that said the pre-push suite runs the golden tests was wrong (both CI and pre-push pass `--exclude-tags golden`) and is corrected in dart_test.yaml and docs/blast_radius.yaml.
regression_test_planned:
  - "test/scripts/pre_push_branch_push_skip_e2e_test.dart (23 cases: SKIP half = branch-only at account/platform/catastrophic, several branches, the no-false-backstop message, delete-only with an empty range, delete-only with NO origin/main, a 64-zero sha256 delete, feature tier; RUN half = main, branch pushed INTO remote main, develop, tag, main mixed with branches, a sha that merely STARTS with 0 (anchor of the zero test), a mixed update+delete push at an unknown tier / empty range, delete of main, empty stdin, malformed line, malformed mixed with good, unknown tier, PRE_PUSH_FULL=1 on a branch push and on a delete-only push)."
  - "test/contracts/pre_push_blast_radius_failsafe_test.dart (reworded 'ONLY on feature tier' case + two mirror cases) and the unchanged hook_gate_placement_test.dart / pre_push_matches_ci_invocation_test.dart / pre_push_analyze_always_e2e_test.dart (all green)."
  - "test/scripts/safe_pr_merge_lib_test.dart (65 cases incl. the real PR #96 fixture, every required job failed/running/skipped/missing and every odd conclusion (timed_out, action_required, startup_failure, stale, neutral), re-run ordering, cancelled-only unlisted jobs, third-party checks, pagination and total_count parsing, changed-files parsing, the CI-config-edit rule, evaluatePr incl. the base-branch rule, and a mirror asserting the job names equal the `name:` fields of .github/workflows/test.yml) and test/scripts/safe_pr_merge_e2e_test.dart (17 cases against a fake gh, incl. base branch, .github/ edits with and without the acknowledgement flag, unreadable file list, an exit-0 merge that is not MERGED, and the sh entry point's hand-off, its exact argument forwarding observed through a scratch copy with a stub dart, and its argument allowlist)."
  - "Mutation proof (rule 21, backup -> mutate -> run -> restore, each mutation confirmed APPLIED by cmp, every file byte-identical afterwards, none counted if it merely failed to COMPILE). Round A (before the B-pass): pre-push.sh 5 mutants all RED (the `|| $3 == refs/heads/main` clause removed: 4 e2e failures; deletes not detected: 1; malformed lines tolerated: 2; any tier skips: 2; empty stdin not OTHER: 1); safe_pr_merge 5 valid mutants all RED (required-job loop dead: 23; fail-open refusal: 5; merge without --match-head-commit: 1; no second PR read: 1; no github-actions app filter: 1); a sixth (`runs == null` check disabled) did not compile and is not counted. The independent B-pass reviewer then found 4 mutants that SURVIVED (unanchored zero test; mixed push counted as delete-only; DELETE_ONLY block below the origin/main guard; weakened `!= success` predicate). Round B (after fixing every B-pass finding), all RED on the 110 tests of the four files: unanchored /^0+/ (1 failure); mixed counted as delete (1); DELETE_ONLY block moved below the origin/main guard (1); weak success predicate (5, one per required job); unlisted cancelled-only jobs ignored (1); CI-config paths never flagged (3); base-branch check off (2); post-merge MERGED read-back off (1); total_count check off (1); sh wrapper drops the PR argument (2), drops the flag forward (1), accepts a different flag literal (1)."
impact_analysis: |
  Saves about 35 minutes per branch push at account tier or above (the 39-minute local suite becomes analyze only; the PR's CI was needed anyway). Risk, stated: a red branch can now leave the machine; it is caught by the PR CI, by safe_pr_merge.sh when it is used, and by the main CI run (which B4 will skip only when the identical tree already passed on a PR). The GitHub web UI merge button remains an uncontrolled path (founder-owned; requiring status checks on main was tried on 2026-07-25 and blocked every direct push and /build-apk, see feedback_mistake_branch_protection_semantics.md). The installed git hook is a COPY of scripts/pre-push.sh, so each clone keeps the old behaviour until `sh scripts/setup-hooks.sh` is re-run; check_hooks_installed.dart only warns on drift. Scope: scripts/pre-push.sh, scripts/safe_pr_merge.*, tests, docs. No product code, schema, Edge Function or cloud state.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "scripts/pre-push.sh:108-256 and scripts/safe_pr_merge{.sh,.dart,_lib.dart}; flutter analyze lib/ unaffected (no lib/ change)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive access." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema access." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data access." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "No cron." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No cloud access." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "No secret read or written; safe_pr_merge uses the already-authenticated gh CLI." }
  - { tier: 11, name: "External services", status: verified, evidence: "GitHub: branch protection read live with `gh api repos/upendraprasad19/AVYA/branches/main/protection` (strict:true, contexts:[], enforce_admins:true, required_conversation_resolution:true); repo is public and merge-commit only; check-run names and the skipped push-only jobs read from run 37958167385 and the PR #96 head 691d826b." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The one cross-boundary contract is the job names in .github/workflows/test.yml versus safe_pr_merge_lib.dart; test/scripts/safe_pr_merge_lib_test.dart parses test.yml and fails if either side drifts." }
recurrence: "Not a recurrence of a fixed bug class. Adjacent history: pre-push was made risk-aware 2026-06-01 (lean-workflow batch), analyze moved there 2026-08-11 (ADR-0018), within-suite CI sharding was tried and reverted 2026-08-10, and OI-275 (2026-10-01) filed the version-bump instance of this wall-clock problem."
---

## Summary

The local pre-push full suite (~39 min on the founder PC) duplicated a gate that CI runs on the PR in ~13 min. For a branch push the local run bought nothing CI does not provide, so it is skipped at a known risky tier; to keep merging dependent on CI (main has no required checks) a new fail-closed wrapper, `scripts/safe_pr_merge.sh`, merges only a PR whose required jobs are green on the head SHA.

## Root Cause

Each gate was added for a good reason at the time (pre-push suite 2026-05-20/06-01, CI on PRs later) and none was retired when a later one made it redundant for the common path. Nothing measured the total: 39 + 13 + 13 minutes of the same suite per change.

## Fix

See `proposed_fix`. B2 (version-bump merge exemption), B3 (parallel whole-file test matrix) and B4 (skip the duplicate main run by tree hash) follow in `docs/plans/2026-10-10-release-cycle-speedup.md`; OI-275 stays OPEN until its item D (the founder's settings allow-rule `Bash(sh scripts/safe_pr_merge.sh:*)`) is closed.

## Related

OI-275 (`docs/audit/open_issues.md`), `docs/plans/2026-10-10-release-cycle-speedup.md`, ADR-0018 (the earlier pre-commit/pre-push cost split).
