---
title: No deferrals — fix every surfaced issue in the same batch
category: process
source_memory: feedback_no_deferrals.md, feedback_no_deferrals_recurrence.md, feedback_no_deferrals_tech_debt_class.md
last_reviewed: 2026-05-28
---

# No deferrals — fix every surfaced issue in the same batch

## The rule

When a bug-fixing session, brainstorm, or multi-category audit surfaces multiple issues — even those that seem peripheral or "low priority" — fix all of them in the same batch. No deferrals. No "out of scope." No "Phase 2 follow-up."

The ban is on the SEMANTIC, not the literal string. Every common euphemism counts.

## How to apply

1. **In brainstorm proposals.** Never tag a bug as "out of scope this batch" or "Phase 2." List ALL of them. If scope is genuinely too large for one ship, the founder/lead makes that call — not the agent.

2. **In plan documents.** Don't include "Out of scope" sections for issues surfaced in the same brainstorm. The plan covers the full surfaced set.

3. **In commit/PR messages.** If you find a bug while fixing another, fix that one too in the same commit (or stack a sibling commit in the same PR). Don't punt with a TODO comment.

4. **The exception.** If a newly discovered issue requires architectural redesign (≥1 day of careful work), it MAY split into a follow-up — but ONLY after explicit founder approval, called out by name in the proposal. The default is *fix it now*.

## Banned phrases (and their euphemisms)

Every entry below is the SAME violation:

- `defer`, `follow-up batch`, `Phase 2`, `lower priority`, `lower urgency`, `out of scope`.
- `dedicated batch`, `test-maintenance batch`, `cleanup batch`, `next-batch baseline`, `documented baseline for next batch`.
- `minimum viable ship`, `pragmatic re-scope`, `responsible focus management`, `dilute focus`, `risk management of large refactors`.
- `What's still open`, `gradual population`, `can be folded into a future pass`, `lower-severity`.
- `safety net`, `defer-friendly`, `contingency to pull out`, `if scope feels too big`.

If you find yourself building a "what's the minimum to call this done?" mental model mid-execution, recognize it as a tell — you're about to violate the rule.

## Multi-category tech-debt audits (extends the rule)

For audits producing 20+ findings across 3+ categories, the same discipline applies. Every finding lands in the SAME remediation plan; none get "follow-up batch" tags. The only legal terminal states are:

- `closed_in_commit: <SHA>` — fixed, with verification citation.
- `upstream_blocked: <package@version or external system>` — cannot proceed; cite the blocker + the reopen condition.
- `verified_clean: <evidence>` — the audit subagent flagged it, but live verification showed no real issue (cite the verification SQL / file:line / command output).

There is NO `deferred:` key in the audit closure YAML schema. Validator `scripts/validate_audit_closure.dart` rejects it. See [audit-closure-yaml](../audit/audit-closure-yaml.md).

## Anti-patterns to avoid

- "We can defer X because it doesn't affect the critical path." → Everything affects the critical path eventually.
- "X is technically a different system, let's track separately." → Tracking separately means forgetting separately.
- "X is purely cosmetic, low impact." → If the bug surfaced, it was noticed. Fix it.
- Tagging items "lower priority" in proposal tables — same as deferring, with softer language.
- Building a "Defer-friendly safety net" / "if execution hits blockers" section in the plan. A contingency to defer IS deferring; a plan that contemplates pulling scope under any circumstance is a plan that defers under that circumstance.
- Renaming deferred items to "open" or "still to be addressed" to make it sound like a status update rather than a scope cut. Same scope cut, more deniable language.

## What to do when context budget feels tight

The answer is "stop now, hand off to a fresh session", NOT "defer scope". A fresh session can pick up the remaining tasks with full context budget. The work doesn't change; only WHO does it changes.

Focus management is the agent's job, not the founder's. If you sense you can't focus, dispatch agents in parallel for independent work + tighten your own edits, NOT stop scope.

## Recurrence pattern (be honest about the trap)

The recurrence loop:

1. Documented rule exists.
2. Trigger condition fires.
3. Agent reaches for a "but this case is different" justification (new euphemism each time: "context anxiety", "leverage analysis", "risk-management", "responsible focus", "safety net", "lower-severity").
4. Agent acts on the rationalization.
5. Founder catches it.
6. Another feedback file gets written.

The fix isn't another memory file — it's enforcement. Before any action that resembles "defer", "skip", "follow-up batch", etc., STOP and grep for this rule. If the rule exists, the answer is no.

## Companion rules

- [`observation-workflow.md`](observation-workflow.md) — Audit thoroughly BEFORE proposing fixes.
- [`audit-closure-yaml.md`](../audit/audit-closure-yaml.md) — Terminal-state ledger for multi-category audits.
- CLAUDE.md §4.2 (no-deferrals invariant), §4.4 rule 23 (no stopping mid-batch).
