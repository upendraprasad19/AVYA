---
name: tech-debt-audit
description: Run a 6-category tech-debt audit on the codebase (Code / Architecture / Test / Dependency / Documentation / Infrastructure). Produces a prioritized backlog with closure YAML. Use quarterly OR after any 3+-batch landing. Audit 2026-05-20 first instance; cadence codified in CLAUDE.md §4.10.
---

# Tech-Debt Audit — 6-Category Parallel Discovery

## When to invoke

- **Quarterly** per CLAUDE.md §4.10 (first Monday of Aug / Nov / Feb / May).
- **After any 3+-batch landing** (multiple consecutive ship cycles whose collective debt has not been audited).
- **Pre-major-refactor** (before starting a multi-week refactor, audit the surrounding code for landmines).

## Cadence schedule

| Date | Status |
|---|---|
| 2026-05-20 | Initial audit. 81 findings. Closure YAML schema introduced. |
| 2026-08-03 | First quarterly run scheduled. |
| 2026-11-03, 2027-02-02, 2027-05-04, ... | Quarterly thereafter. |

## Steps

### 1. Pre-flight

- `git status` clean. Branch off main.
- `bash scripts/pre-commit.sh` — all 38+ gates green BEFORE you start (otherwise you're auditing on top of known violations).
- Skim `docs/audit/LENS_REGISTRY.md` — confirm which lenses (L1-L53+) you'll dispatch.

### 2. Dispatch 6 parallel subagents

**Order matters** (per `feedback_operational_observability_first.md`):

1. **Infrastructure** (FIRST) — operational/CI/secret/cron findings. Apply ×1.2 weight to its findings until baseline parity reached.
2. **Architecture**
3. **Test**
4. **Code**
5. **Dependency**
6. **Documentation**

Each subagent prompt MUST:
- Prepend `docs/agent_brief_preamble.md`.
- Cite the lens(es) from `docs/audit/LENS_REGISTRY.md` in scope.
- Output every finding with `file:line` + verbatim quote + Impact (1-5) / Risk (1-5) / Effort (1-5) score.
- Cap at ~15 findings per category, ≤700 words.

### 3. Synthesize

- Compute Priority = (Impact + Risk) × (6 − Effort) for every finding.
- Rank into a single table.
- Cross-check duplicates / overlaps between categories.

### 4. Verify (do NOT skip)

For EVERY P0/P1 finding:
- Read the cited `file:line` yourself. Don't trust the subagent's reading.
- For schema claims, run a live `information_schema` query.
- For "X doesn't exist" claims, run `git ls-files` / `grep -rn`.

Cite the verification SQL / file:line in the audit report.

Memory references — invoke before acting on any finding:
- `feedback_audit_findings_require_live_verification.md`
- `feedback_audit_verifier_cannot_trust_own_subagent.md`

### 5. Brainstorm + plan + execute

Per CLAUDE.md §4.1 observation/bugfix workflow. NO deferrals; all findings land in the same remediation plan (multi-batch is fine — what's not fine is "we'll get to those next quarter").

### 6. Emit closure YAML

`docs/audit/<YYYY_MM_DD>_audit_closures.yaml`. Schema:

```yaml
audit_date: <YYYY-MM-DD>
audit_name: <name>
total_findings: <N>
closed_count: <K>
findings:
  - id: <id>
    category: <category>
    title: <one-line>
    score: <priority>
    terminal_state: closed_in_commit | upstream_blocked | verified_clean
    # state-specific fields per the schema (see scripts/validate_audit_closure.dart)
```

**NO `deferred:` key permitted** per `feedback_no_deferrals_tech_debt_class.md`. Validator rejects it.

### 7. Final closure test

Write `test/contracts/<date>_audit_closure_test.dart` mirroring `audit_2026_05_20_closure_test.dart`:
- Assert Gate 40 (`validate_audit_closure.dart`) PASSES on the YAML.
- Assert NO `deferred:` key.
- Assert total_findings equals the count surfaced by the audit.

### 8. Update LENS_REGISTRY

For every NEW gate script you wired during remediation, add a row to `docs/audit/LENS_REGISTRY.md`. Cite the discovering finding.

### 9. Skill self-evolution (per CLAUDE.md §5.1)

For every NEW bug class surfaced:
- Append to `.claude/skills/debugging/SKILL.md` §2 Bug Classes.
- Cite the discovering finding + the new gate script + the regression test path.
- Skill edit lands in the SAME commit as the discovering fix.

For new methodology refinements:
- Add to `.claude/skills/update-docs/SKILL.md` extended checklist (nodes 10+).

## Outputs

A successful audit produces:
- `docs/audit/<date>_audit_closures.yaml` — closure ledger
- `test/contracts/<date>_audit_closure_test.dart` — closure test
- N new `scripts/check_*.dart` gates wired into pre-commit + CI
- N new `docs/diagnoses/<date>-*-<id>.md` per closed finding
- N new behavioral contract tests under `test/contracts/`
- M new entries in `.claude/skills/debugging/SKILL.md` §2 Bug Classes
- M new entries in `docs/audit/LENS_REGISTRY.md`
- 1 retrospective at `~/.claude/projects/<project>/memory/project_<date>_audit.md`
- MEMORY.md index updated

## Anti-patterns

- **Single-agent audit.** A single agent's perspective on 6 categories misses cross-category coupling. 6 dispatches in parallel is the design.
- **Skipping live verification.** The audit's #1 false-alarm class. Per the May audit's I1: P0 keystore-exposure flag was a false alarm — `android/.gitignore:12-14` already covered it. Always `git check-ignore -v` AND `git ls-files`.
- **Treating "upstream-blocked" as deferral.** It's a documented terminal state with explicit reopen condition, NOT a placeholder.
- **Closing findings without behavioral tests.** Per CLAUDE.md rule 21 amendment, source-grep alone is presence-only; SoT registry entries need behavioral_test_path.

## Related skills

- `debugging/SKILL.md` — bug-class catalog; extends after every audit
- `update-docs/SKILL.md` — per-batch knowledge-graph maintenance
- `dep-bump-sweep/SKILL.md` — recurring dep update cadence (B3 sibling)

## Changelog

- **2026-05-21** — Skill created. Codifies the audit methodology used in the 2026-05-20 audit (81 findings, ~64% closed at skill-creation time). Sibling skill `dep-bump-sweep` documented but file not yet committed (deferred to B3 continuation).
