# Quarterly Tech-Debt Audit Cadence

> Codified per CLAUDE.md §4.10 (introduced by audit 2026-05-20 / SE-3).
> Runs at minimum once per quarter AND after any 3+-batch landing.

## First scheduled run

**Monday 2026-08-03** (first Monday of Q3 2026).

## Cadence going forward

- Q3 2026 → **2026-08-03** (Mon)
- Q4 2026 → **2026-11-03** (Mon)
- Q1 2027 → **2027-02-02** (Mon)
- Q2 2027 → **2027-05-04** (Mon)
- ... first Monday of August / November / February / May indefinitely.

## How to run

Invoke the project-local skill (lands in B4):

```
/tech-debt-audit
```

Or manually:

1. Dispatch 6 parallel subagents (one per category): Code / Architecture /
   Test / Dependency / Documentation / Infrastructure. Per
   `feedback_operational_observability_first.md`, dispatch the **infra**
   subagent FIRST.
2. Each subagent produces findings with `file:line` citations and an
   Impact (1-5) / Risk (1-5) / Effort (1-5) score.
3. Synthesize into a prioritized list. Score = (Impact + Risk) × (6 − Effort).
4. Apply ×1.2 weight to infra findings until baseline operational parity
   reached (per `feedback_operational_observability_first.md`).
5. Verify EVERY P0/P1 finding live before acting on it — per
   `feedback_audit_findings_require_live_verification.md` and
   `feedback_audit_verifier_cannot_trust_own_subagent.md`. Read the cited
   `file:line` yourself; run live SQL where claimed.
6. Brainstorm + plan + execute per CLAUDE.md §4.1.
7. Produce closure YAML at `docs/audit/<YYYY_MM_DD>_audit_closures.yaml`
   enumerating every finding with terminal_state. **NO `deferred:` key
   permitted** (per `feedback_no_deferrals_tech_debt_class.md`).
8. Validate the closure YAML: `dart run scripts/validate_audit_closure.dart`.
9. Final-step regression test: `test/contracts/<date>_audit_closure_test.dart`.

## What "passing" looks like

- Closure YAML validates (Gate 40).
- All 38+ existing gate scripts still PASS (`bash scripts/pre-commit.sh`).
- Audit findings ledger has total_findings == findings.length.
- Every finding has terminal_state ∈ {closed_in_commit, upstream_blocked, verified_clean}.

## What "failing" looks like (escalate immediately)

- Quarterly run skipped or delayed >14 days past scheduled date.
- Closure YAML uses `deferred:` key → schema validator catches it.
- Audit produces 80+ findings and "we'll handle the rest later" → that's
  the recurring no-deferrals violation; reschedule the work into the
  same plan.

## How this gets triggered

**Manual** (current state): operator runs `/tech-debt-audit` on the
scheduled date.

**Automated** (B4 deliverable, not yet wired): a `/schedule` recurring
task fires on the first Monday of each quarter to re-prompt the operator.
The schedule itself doesn't run the audit — it spawns a Claude Code
session that walks the operator through dispatch + synthesis.

## Audit history

| Date | Findings | Closed | Notes |
|---|---|---|---|
| 2026-05-20 (initial) | 81 | (in progress) | First explicit zero-deferral audit; closure YAML schema introduced; 10 new gates wired. |
| Next: 2026-08-03 | TBD | TBD | Quarterly cadence begins. |

## Related

- `docs/audit/LENS_REGISTRY.md` — 53 lenses to dispatch against (L1-L53)
- `docs/audit/<date>_audit_closures.yaml` — per-audit closure ledger
- `scripts/validate_audit_closure.dart` — Gate 40
- `test/contracts/<date>_audit_closure_test.dart` — final closure test
- `feedback_no_deferrals_tech_debt_class.md`
- `feedback_audit_closure_yaml_required.md`
- `feedback_operational_observability_first.md`
- `feedback_audit_methodology_lenses.md`
- `feedback_audit_findings_require_live_verification.md`
- `feedback_audit_verifier_cannot_trust_own_subagent.md`
