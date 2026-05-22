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
| 2026-05-20 | Initial audit. 84 findings (81 primary + 3 byproducts). Closure YAML schema introduced. CLOSED 81/81 = 100% on 2026-05-22 (B5 final closure). |
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

**NO `partial` terminal_state permitted** (added B5 learning) — `partial` was a sneak-path deferred state during 2026-05-20 audit; Gate 40 now rejects it. If work is genuinely in progress, use a scheduled-comment block (`# SCHEDULED FOR <day> — <plan path>`) and fill in `terminal_state: closed_in_commit` when the scheduled day's work merges. Gate 40 emits WARN for scheduled-comment entries; doesn't fail. WARN → FAIL flip happens via `--strict` at audit close.

**Per-finding `terminal_state:` is source of truth** (B5 D1 codification per `feedback_closure_yaml_per_finding_discipline.md`). `closed_count:` is a derived tally — recompute from per-entry data, never increment without simultaneously populating the corresponding finding's `terminal_state:`. The 2026-05-20 audit had 13 findings closed in commits but their YAML entries retained `# NOT YET CLOSED` comments — Gate 40 schema-passed but the per-entry truth was wrong. Gate 40 was hardened in B5 D1 to detect stale-pattern comments.

**Closure validator MUST itself be tested for parsing bugs.** B5 D1 discovered that `validate_audit_closure.dart` had a CRLF parsing bug on Windows checkouts that made it silently miss every key:value pair after a multi-line YAML comment — the gate couldn't see what it was designed to catch. Test the validator on the actual closure YAML it'll guard, on the actual OS the team uses, BEFORE relying on it.

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

For audit-procedure refinements (this skill itself):
- Update this file's Anti-patterns + Changelog sections in the same audit-closure batch.
- If 3+ batches have shared a pattern that this skill doesn't cover, create a new sibling skill at `.claude/skills/<topic>/SKILL.md` (e.g. `edge-function-deploy-rollback`, `writer-reader-drift-detector` from the 2026-05-20 audit).

### 10. Audit-closure pre-merge gate (added B5)

Before the merging the closure commit to main, run:
```bash
dart run scripts/validate_audit_closure.dart docs/audit/<date>_audit_closures.yaml --strict
```
This fails if ANY finding lacks `terminal_state:` — catches the stale-comment trap (B5 D1 discovery). If a finding genuinely cannot close in this batch, use scheduled-comment style with explicit plan-day pointer; the WARN surfaces it and human review decides whether to ship.

Pair with the closure contract test:
```bash
flutter test test/contracts/<date>_audit_closure_test.dart
```
Asserts every finding ID 1..N appears with a terminal state.

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
- **Closing findings without behavioral tests.** Per CLAUDE.md rule 21 amendment, source-grep alone is presence-only; SoT registry entries need behavioral_test_path. If a real behavioral test won't fit in the audit-closure batch, use `behavioral_test_required: true` honest-TODO marker on the SoT entry — Gate 42 surfaces it as WARN; future bug fixes touching that concept write the behavioral test in the same commit.
- **`partial` as terminal state.** B5 found this used as a deferred-state sneak path. Gate 40 now rejects it. Either close fully OR use a scheduled-comment block pointing at the named day in the closure plan.
- **Incrementing `closed_count` without populating per-finding `terminal_state`.** The aggregate count drifts from the per-entry truth. Always update the per-entry first; `closed_count:` is derived.
- **Trusting Gate 40 schema-pass as proof of closure.** Until Gate 40 detects stale-pattern comments (post B5 D1 hardening) AND CRLF is normalised, the validator can pass while half the YAML is unparsed. Re-run with `--strict` at audit close; verify on the team's OS.
- **Paternalistic pause framing during execution** (B5 D1 5th-instance codification per `feedback_no_stop_until_done.md`). When the agent is tempted to write a status update with "options" / "honest path" / "natural session boundary" / "fresh sessions" / "13-15 days of focused work cannot fit" — those are banned framings. The work IS the status update; commits + closure YAML + diagnose-docs ARE the report. Stop ONLY when the batch is genuinely done OR genuinely blocked on user action.
- **Subagent runs out of usage mid-task.** Recovery pattern (B5 D9-D10 first instance): parent reads the agent's partial state, verifies with `flutter analyze --no-fatal-infos`, completes the missing scaffolding (gate / regression test / diagnose-doc) itself, then commits combining the agent's work + the recovery scaffolding. Document in commit message that the agent terminated early and the parent finished.
- **Refactor without its detection gate landing first** (CLAUDE.md §4.11). A refactor touching a known bug class doesn't merge without its detection gate. Gate ships in the SAME batch as the refactor, in an EARLIER commit. Default the gate to WARN for 24h smoke window before flipping to hard-fail.

## Related skills

- `debugging/SKILL.md` — bug-class catalog; extends after every audit
- `update-docs/SKILL.md` — per-batch knowledge-graph maintenance
- `dep-bump-sweep/SKILL.md` — recurring dep update cadence (B3 sibling)

## Changelog

- **2026-05-21** — Skill created. Codifies the audit methodology used in the 2026-05-20 audit (81 findings, ~64% closed at skill-creation time).
- **2026-05-22** — Updated with B5 final closure (81/81 = 100%) learnings:
  - `partial` banned as terminal state (was a deferred-state sneak path)
  - Per-finding `terminal_state:` is source of truth; `closed_count:` is derived
  - Validator self-test requirement (Gate 40 had a CRLF parsing bug — fixed but the meta-lesson is "test the gate that guards the gate")
  - `behavioral_test_required: true` honest-TODO marker pattern for SoT entries (Gate 42 emits WARN; future bug fixes write the missing test)
  - Subagent partial-state recovery pattern (parent finishes gate/test/diagnose-doc when agent runs out of usage)
  - Paternalistic pause framing list explicitly banned in anti-patterns (5th-instance codification)
  - Scheduled-comment YAML pattern for honest closure-pending state
  - 4 new project-local skills shipped this audit: `tech-debt-audit` (this file, B4), `dep-bump-sweep` (B3 — file landed B3), `edge-function-deploy-rollback` (B5 D1), `writer-reader-drift-detector` (B5 D1)
  - 26 new gates wired (Gate 25-47) across B1-B5
  - 14 new debugging bug-class entries (2.14-2.27)
  - 14 new update-docs checklist nodes (10-23)
  - CLAUDE.md root: §4.10 (cadence + closure-YAML schema discipline) + §4.11 (gates before refactor) + rule 21 amendment (behavioral_test_path) + §7 pointer table sync
