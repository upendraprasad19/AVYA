# Regression test debt (backlog)

Every entry: a commit that shipped without a regression test (pre-rule-21)
or with a source-grep-only test where a real round-trip test would catch
more. Resolved in a future batch (test added) or moved to `permanently-skipped`
with reason.

Status codes: `open` = test not yet added; `closed:<sha>` = resolved; `skipped:<reason>` = permanently waived.

## Backlog

| bug_id | concept | missing test type | commit-sha | status |
|---|---|---|---|---|

<!-- Add rows via: echo "| <id> | <concept> | <type> | <sha> | open" >> docs/regression-test-debt.md -->

## Permanently skipped

<!-- Move rows here when they are genuinely infeasible (e.g., integration test
     requires physical device capability unavailable in CI). -->
