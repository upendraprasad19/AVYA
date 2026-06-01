---
name: hermes-pass
description: End-of-batch deep cross-lens review using parallel Opus subagents. Auto-suggested by /update-docs when batch blast-radius ≥ account. Run manually via /hermes-pass. Names from the 2026-05-17 Hermes external cross-check that caught 13 P0/P1 findings my own verifier missed.
type: process
priority: high
self-evolving: true
---

# Hermes Pass (E-pass) — Per-Batch Multi-Lens Deep Review

> Track 1 of the 2026-05-28 six-industry-gap closure batch. **Per-batch deep reviewer.** Different from `/review` (per-commit lightweight reviewer).

## 0. When to invoke

- **Auto-suggested** by `/update-docs` walk when batch's max blast-radius ≥ `account`
- **Manual** any time: `/hermes-pass [--lenses=L1,L21,L29]` (founder picks lens subset; default = "p0-blockers" set = L1, L21, L22, L23)
- **Required** before APK build for batches with any `catastrophic`-tier commit (per `docs/blast_radius.yaml` `requires:` list)
- **Skip**: doc-only batches; cosmetic refactors; isolated bug-fix batches with blast-radius `feature` for all commits

## 1. The contract

Produces `docs/audit/<date>-hermes-<batch-name>.md` — one consolidated report from parallel lens dispatches.

### Output format

```markdown
---
hermes_pass_id: 2026-05-28-hermes-<batch-slug>
ran_at: 2026-05-28T19:45:00+05:30
batch_scope: <commit-sha-range or working-tree>
lens_set: [L1, L2, L8, L21, L22, L23, L29, L34]
agents_dispatched: 8
findings_total: <count>
findings_by_severity: { P0: N, P1: N, P2: N, false_alarm: N }
verdict: pending  # → accepted | spawn_followup_batch | block_ship
---

# Hermes Pass — <batch-name>

## Summary
- N P0 findings, N P1, N P2, N false_alarm
- Ship-blockers: [list of P0s]
- Spawn-followups: [list]

## Findings by lens
### L1 — writer_reader_drift
[findings...]

### L21 — Edge Function semantic correctness
[findings...]

[…]

## Founder triage
<filled in by founder>

## Action items
- [ ] <fix in this batch> — owner
- [ ] <spawn follow-up batch for: ...> — owner
```

## 2. Lens registry

Hermes draws from the full **53-lens** `docs/audit/LENS_REGISTRY.md`. Each invocation picks a subset (default: 4-8 lenses from the "p0-blockers" + most relevant for the batch's blast-radius profile).

### Recommended lens sets

| Trigger | Lens set |
|---|---|
| Default (`--lenses` omitted) | L1, L21, L22, L23 (p0-blockers) |
| Payment / auth batch | L1, L2, L21, L22, L23, L29, L40 |
| Sync / restore batch | L1, L11, L15, L16, L37, L39 |
| Migration / schema batch | L1, L14, L22, L35 |
| New Edge Function | L21, L22, L23, L31, L40 |
| Refactor (no behaviour change) | L1, L25, L26, L34 |
| Quarterly comprehensive | `--all` (all 53) |

## 3. Dispatch protocol

When invoked:

1. Collect batch scope: `git log <last-merge-or-base>..HEAD --name-only` if on a feature branch; else `git diff main..HEAD --name-only`.
2. Compute aggregate blast-radius across all touched paths via `scripts/blast_radius_from_diff.dart`.
3. Determine lens set: founder-specified `--lenses=...`, or pick by-batch-shape from the table above.
4. **Dispatch N parallel Opus subagents** via `Agent({subagent_type: 'general-purpose', model: 'opus', ...})` — ONE PER LENS. Each agent:
   - Gets the lens charter from `LENS_REGISTRY.md`
   - Gets the batch's diff or list of changed files
   - Returns 0-5 findings in structured format (file:line / verbatim quote / REAL|FALSE_ALARM|PARTIAL / cite-precedent)
   - Reports cap: 800 words per agent
   - Does NOT propose fixes (that's consolidation phase)
5. **Master agent (Opus)** consolidates: dedup findings, rank by severity, write final report.
6. Output written to `docs/audit/<date>-hermes-<batch>.md`.

## 4. Triage workflow

Founder reviews the report. Per finding, mark:
- `accepted` — fix in same batch (per `feedback_no_deferrals.md`)
- `false_alarm` — annotated reason; tune lens prompt for next time
- `spawn_followup_task` — new batch (DOCUMENTED, not deferred — see `feedback_no_deferrals_recurrence.md` for the distinction)

Verdict:
- `accepted` — all findings resolved (fixed, annotated, or spawned). Batch can ship.
- `block_ship` — at least one P0 not yet resolved. Batch cannot ship.
- `spawn_followup_batch` — P0 findings exist but founder explicitly authorizes a follow-up batch within 24h.

## 5. Cost / latency expectations

- 4-lens default: ~$0.50-1.50, 2-4 minutes wall-clock with parallel dispatch
- 8-lens batch: ~$1-3, 4-8 minutes
- `--all` (53 lenses): ~$8-15, 15-30 minutes — reserved for quarterly comprehensive

Budget is OK per founder Q&A. If a single pass produces > $5 cost, log it in self-evolution.

## 6. Anti-patterns (DO NOT)

- Run Hermes per-commit. That's `/review`'s job. Hermes is per-BATCH.
- Skip the master consolidation step — N raw lens reports without dedup overwhelms founder.
- Pass conversation context to lens agents (must be fresh, same rule as `/review`).
- Re-use stale lens findings — every invocation runs fresh lenses.
- Tag every finding as P0 (anchoring). Lenses must rate per their own severity rubric.
- Skip Hermes on "small" batches with catastrophic-tier changes. Catastrophic = mandatory regardless of size.

## 7. Self-evolution

Append after each invocation:
- date / batch / lens set / findings count / dispatch cost / wall-clock
- Lens-level signal-to-noise ratio (real findings / total per lens)
- Any new lens that should be added to LENS_REGISTRY (with charter)
- Any lens that consistently produces noise → flag for retirement or tuning

## 8. History

> The 2026-05-17 Hermes external cross-check (Phase A → D batch) caught 13 P0/P1 findings my own verification subagent missed — including 3 payment-blocking TDZ + SSRF + NOT NULL bugs. That cross-check was MANUAL and ad-hoc. This skill codifies it as a repeatable pass.

> **First invocation: 2026-06-01** — derive-only AI-coach tool-surface batch (platform tier). Targeted 8-lens set (L1, L14, L21, L26, L28, L34, L37, L40), 8 parallel Opus agents. Findings: 1 P1 + 3 P2 + 1 false_alarm. The P1 (L37) — the batch's own a9c3e2 snapshot-budget fix re-breached the 10000-char server cap because `enrichContextForQuery` re-inflated the payload AFTER the trim — was a correct-cap-at-the-wrong-pipeline-point gap that 5 clean lenses AND the per-commit B-pass had missed; fixed in-batch. Validated the skill's premise (a deep multi-lens pass catches what a single reviewer misses). Report: `docs/audit/2026-06-01-hermes-derive-only-coach.md`. Lesson: run L37 on any batch that adds a size/budget cap — verify the cap sits at the LAST mutation before the bounded sink.
