---
title: Audit closure YAML — per-finding terminal-state discipline
category: audit
source_memory: feedback_audit_closure_yaml_required.md, feedback_closure_yaml_per_finding_discipline.md
last_reviewed: 2026-05-28
---

# Audit closure YAML — per-finding terminal-state discipline

## The rule

Every multi-category audit (tech-debt, security, performance — any audit producing 20+ findings across 3+ categories) MUST produce a structured closure artifact at `docs/audit/<YYYY_MM_DD>_audit_closures.yaml`.

The YAML enumerates every finding by ID, the terminal state from the allowed set, and an actionable verification reference (commit SHA, gate script name, or external system citation).

Every finding ID MUST carry a `terminal_state:` key directly on its entry. Stale `# NOT YET CLOSED — pending …` comments are INSUFFICIENT even when the work is actually done.

## Allowed terminal states

Per [no-deferrals](../process/no-deferrals.md), the only legal terminal states are:

- `closed_in_commit: <SHA>` — fixed, with verification citation.
- `upstream_blocked: <package@version or external system>` — cannot proceed; cite blocker + reopen condition.
- `verified_clean: <evidence>` — flagged by audit, but live verification showed no real issue.

There is NO `deferred:` key. The validator rejects it.

## Schema

```yaml
audit_date: 2026-05-20
audit_name: tech_debt_six_category_v1
total_findings: 81
findings:
  - id: I1
    category: infrastructure
    score: 50
    terminal_state: verified_clean
    evidence: "android/.gitignore:12-14 matched key.properties and *.jks at audit time; git check-ignore -v confirmed."
    defense_in_depth_added_in: <commit SHA>
  - id: D4
    terminal_state: upstream_blocked
    blocker: "health 13.x -> device_info_plus 12.x -> win32 5.x chain"
    reopen_when: "health package bumps device_info_plus to ^13"
    citation: project_share_plus_13_blocked.md
```

## Closure test contract

The closure test `test/contracts/<date>_audit_closure_test.dart` asserts:

1. Every finding ID 1..N appears in the YAML (no silent drops).
2. Every entry has exactly one terminal-state key (no double-marking).
3. `closed_in_commit` entries reference a real SHA in `git log`.
4. `upstream_blocked` entries have both `blocker:` and `reopen_when:` fields.

## Per-finding discipline (don't let it drift)

When a finding's work lands in a commit, update the YAML entry in the SAME commit that ships the fix:

1. Replace the `# NOT YET CLOSED — …` comment with the full `terminal_state: closed_in_commit` block.
2. Include `commit:`, `verification:`, and `notes:` fields.

`closed_count:` is a DERIVED field — recompute it from per-entry data, never increment without simultaneously updating the corresponding entries.

Strengthen the validator (Gate 40) to flag entries whose ONLY status is a comment without a `terminal_state:` key.

Pre-merge audit: before merging an audit-related branch, run:

```bash
grep -c "^    terminal_state:" docs/audit/<date>_audit_closures.yaml
```

and verify it equals `closed_count:` minus the count of partial states.

If the work spans multiple commits / branches, the entry's `commit:` field points to the SHA where the fix landed, even if the YAML update lands in a later reconciliation commit. The reconciliation commit itself goes in a top-of-file comment under "RECONCILIATION" with the date.

## How to apply

- When kicking off an audit, scaffold the YAML with `findings: []` and an estimated `total_findings`.
- Populate progressively as each finding lands or gets reclassified.
- Final closure step: run the validator. Any missing IDs block the audit from being declared closed.
- Subsequent audits use the same schema (date-prefixed filename) — reusable + diff-able quarter to quarter.

## Instances

During one tech-debt audit, 13 findings had work landed in named commits across multiple batches. The closure YAML's `closed_count:` field was incremented to reflect the work, BUT each individual finding entry retained its original `# NOT YET CLOSED — pending B2 continuation step N` comment.

Result: the closure validator passed (it only inspected entries that HAD a `terminal_state:`), the closure test asserted every finding ID appeared, the schema looked clean — but a human or downstream tool reading the YAML would conclude 13 findings were still pending.

This is exactly the false-confidence the closure ledger was supposed to prevent. The lesson: schema checks that pass can still hide semantic drift.

## References

- Validator: `scripts/validate_audit_closure.dart` (Gate 40).
- CLAUDE.md §4.10 (tech-debt audit cadence + closure YAML requirement).
- Related: [`no-deferrals.md`](../process/no-deferrals.md), [`source-grep-limits.md`](../testing/source-grep-limits.md), [`live-verification.md`](live-verification.md).
