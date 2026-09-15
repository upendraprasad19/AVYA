# ECC Adoption Batch — Design Spec (2026-05-24)

## Context

You linked [affaan-m/ECC](https://github.com/affaan-m/ECC). It's an agent-harness performance system for Claude Code (and other harnesses) — 60+ specialized subagents, 232 skills, hooks, security scanner, instinct-based learning.

Most of what ECC offers either overlaps with what we already have (memory system, audits, gates) or is irrelevant (multi-language reviewers, cross-harness adapters). But **5 pieces are concrete wins** for our workflow. This spec covers them.

**Top pain (locked by founder 2026-05-24):** same bugs keep coming back — writer/reader drift class has surfaced 7+ times since Test #6. Doc drift hides it. We need (a) a dedicated subagent to catch drift, and (b) a way to keep CLAUDE.md from lying.

**Scope (locked by founder 2026-05-24):** ship B1 + B2 + B3 + B5 + B6 in one batch. Defer B7 (memory TTL) to a separate batch later.

**Out of scope:** B4 (PostToolUse hook). Eliminated because Windows path fragility + `flutter analyze` whole-project slowness makes the cost-benefit poor. B7 (memory TTL) ships separately — it's the only item that touches existing files.

**Prompt-sourcing decision (locked by founder 2026-05-24):** adopt ECC's *intent and structure*, but rewrite prompts for our context. Bake in our SoT registry, known drift signatures, Hive/Riverpod/Supabase patterns. Don't copy ECC text verbatim.

---

## B1 — Writer/Reader Drift Detector Agent

### What it does

A subagent dispatched during audits or end-of-batch reviews. Given a writer file (e.g. `lib/core/services/workout_write_service.dart`) or a domain name (e.g. "workout", "nutrition", "health"), it scans the codebase for every reader of every field that writer emits, and flags mismatches.

### Why this specifically

Writer/reader drift is the **#1 recurring bug class** on ICANBEFITTER (codified in [feedback_writer_reader_field_drift_recurring.md](../../../C:\Users\upend\.claude\projects\C--Upendra-Claude-Code-Fitness-App\memory\feedback_writer_reader_field_drift_recurring.md), 7+ instances). We already have 170+ contract tests, but [feedback_source_grep_false_confidence.md](../../../C:\Users\upend\.claude\projects\C--Upendra-Claude-Code-Fitness-App\memory\feedback_source_grep_false_confidence.md) notes ~73% are source-grep-only and have **caught 0 of 9** drift instances. An agent that *actively traces writer→reader paths per audit* is structurally different from a static grep.

### File location

`.claude/agents/writer-reader-drift-detector.md`

Fits the existing pattern — 6 domain agents already in `.claude/agents/` (auth, backend, database, manager, qa, screen).

### Frontmatter sketch

```yaml
---
name: writer-reader-drift-detector
description: |
  Use this agent to scan for writer/reader field drift in a specified writer file or
  domain. The #1 recurring bug class on this codebase (7+ instances since Test #6).
  Run as part of every audit batch and before merging any WriteService refactor.
tools: Read, Grep, Glob
---
```

Read-only tools by design — agent reports, doesn't edit.

### Prompt body (high-level shape — actual prompt drafted during implementation)

The prompt baked into the agent will cover:

1. **Inputs accepted:**
   - A writer file path (e.g. `lib/core/services/workout_write_service.dart`)
   - A domain name (`workout` | `nutrition` | `health` | `coach` | `community`)
   - A specific field rename (e.g. "I just renamed `sets_completed` → `set_number`, verify all readers")

2. **Procedure:**
   - Identify Hive key prefix(es) the writer emits (`exlog_*`, `nlog_*`, etc.) and all field names in each emitted map
   - Identify cloud column projections (read `_syncXxx` methods if the writer is a sync helper)
   - For each field, grep the codebase for readers (`box.get`, `map['field']`, `.field`)
   - Compare: field name, type, semantic meaning (sum-vs-each, max-vs-first, count-vs-list)
   - Special-case our known drift signatures:
     - `exlog_*` keys MUST come from `WorkoutWriteService.exlogKey()` only (Gate 17 — codified)
     - `set_number` (per-set ordinal in `sets[]`) ≠ `sets_completed` (total — historical name)
     - `duration_sec` (canonical) vs `duration_seconds` (legacy from restore path)
     - `coaching_notes` (Hive — plural) ≠ `coach_notes` (cloud — singular, different word)
     - Per-item nutrition fields: `name`, `quantity_g`, `calories`, `protein`, `carbs`, `fat`, `fiber`
     - IST date keys MUST come from `istDateStr()` only (no `DateTime.now().toIso8601String().substring(0,10)`)

3. **Output format:** structured markdown report with sections:
   - Summary: N findings (P0 / P1 / P2)
   - Per-finding: writer location, reader location, drift type, suggested fix shape
   - Recommended next actions (contract test to add, etc.)
   - Output saved to `docs/audit/<date>-drift-scan-<writer-or-domain>.md`

4. **Cross-reference with SoT registry** (`docs/sot_registry.yaml`) — every writer covered in the registry should be checkable against this agent; flag any writer NOT in the registry as "missing SoT entry."

### Alternatives considered & rejected

- **PostToolUse hook (B4)** — slow + Windows-fragile, see top spec context.
- **Static grep contract test** — already exists for 73% of SoT entries; has caught 0 of 9 drifts. Static patterns don't catch semantic drift.
- **Add to `superpowers:requesting-code-review`** — too broad; reviewers don't trace writer→reader paths systematically. A dedicated agent forces the discipline.

### Validation

1. **Dry-run on `WorkoutWriteService`.** Expected: 0 findings (we've audited this domain extensively). If it finds something, the agent did its job. If false positives flood, tune the prompt.
2. **Dry-run on `NutritionWriteService`.** Same expected result.
3. **Synthetic-drift test:** introduce a known field rename in a test branch (e.g. rename `weight_kg` → `weight_kilograms` in one writer, leave readers alone). Verify the agent catches it.
4. **Document the agent's findings format in CLAUDE.md** so future batches know how to invoke it.

### Estimated effort

~1.5 hours (1h to draft + iterate prompt, 30min to validate against two writers).

---

## B2 — Settings env vars

### What it does

Two lines added to `.claude/settings.json` (file currently doesn't exist; we have `settings.local.json` only). Tells Claude Code to:
1. Auto-compact conversation context at 55% full (default ~95%).
2. Cap "extended thinking" budget at 10,000 tokens.

### Why

Long batches blow through context. Compacting at 95% means we lose state mid-task. Compacting at 55% leaves headroom (and still keeps us above the 5-minute prompt-cache TTL of ~280s wall-clock for typical messages). ECC ships these defaults; no reason we shouldn't.

10K thinking-token cap prevents Opus from over-thinking trivial steps when the right move is to just act. We rarely need >10K thinking tokens — when we do, the model can request more.

### File location

`.claude/settings.json` (new file at the project-root `.claude/` directory, NOT `settings.local.json` which is gitignored). This file IS committed to git so the setting applies for any contributor / future automation.

### Content sketch

```json
{
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "55",
    "MAX_THINKING_TOKENS": "10000"
  }
}
```

If a `.claude/settings.json` already exists (none found at write-time), MERGE — don't overwrite.

### Alternatives considered & rejected

- **40% compaction** — too aggressive, would compact mid-phase.
- **No `MAX_THINKING_TOKENS` cap** — fine for short tasks; for batches it lets Opus burn tokens deliberating.

### Validation

After applying, run a batch and observe context bar. Confirm compaction triggers at ~55%. Confirm thinking budget doesn't exceed 10K (visible in `/cost` or `/context` output if available).

### Estimated effort

~5 minutes.

---

## B3 — Claude config audit skill

### What it does

A new skill `.claude/skills/audit-claude-config/SKILL.md` that, when invoked, audits `.claude/settings.json` + `.claude/settings.local.json` for stale or risky permission grants, hook configurations, and env vars. Produces a structured report; founder approves prunes manually.

### Why

[feedback_secrets_pattern_audit_before_first_push.md](../../../C:\Users\upend\.claude\projects\C--Upendra-Claude-Code-Fitness-App\memory\feedback_secrets_pattern_audit_before_first_push.md) codified manual discipline against secrets in settings, but we have no audit of *existing* permission allow-rules. Some Bash allows may be 6+ months old, reference commands we don't run anymore, or pattern-match more broadly than intended.

### File location

`.claude/skills/audit-claude-config/SKILL.md`

### Procedure sketch

When invoked, the skill:

1. Read `.claude/settings.json` + `.claude/settings.local.json` + (if it exists) `~/.claude/settings.json`.
2. For each entry under `permissions.allow`:
   - **Bash allows:** parse the command; cross-reference against recent commits + diagnose-docs (grep `docs/diagnoses/` for the command's keyword) to estimate "last used." Flag entries with no apparent recent use.
   - **MCP tools:** list which MCP servers are referenced. Cross-reference against `mcp-registry` connectors actually in use.
   - **Skill grants:** list. Flag skill grants for skills not present in `.claude/skills/` or known global skill set.
3. For each entry under `hooks`: verify the script/command referenced exists and is executable.
4. For each entry under `env`: flag any value that looks like a literal secret (matches our 14 secret patterns).
5. Output: `docs/audit/<date>-claude-config-audit.md` with sections:
   - Stale Bash allows (recommend prune)
   - Unknown MCP refs (recommend remove)
   - Missing hook targets (recommend fix or remove)
   - Suspected secrets in env (recommend rotate + move to Vault)
6. Founder reviews report, applies prunes manually.

### Alternatives considered & rejected

- **ECC's `npx ecc-agentshield scan`** — requires a Node CLI install + their packaging. Same outcome, more dependency surface. A local skill is cheaper.
- **Auto-prune mode** — too risky. Stale-looking allows might be needed by an upcoming batch we haven't started yet.

### Validation

1. Run skill once now. Expect ~3-8 findings (Bash allows from older batches).
2. Founder reviews. Prune approved entries in one commit.
3. Run skill again. Expect zero findings.
4. Schedule: quarterly re-audit (calendar reminder).

### Estimated effort

~1 hour (30min skill draft, 30min first run-and-prune).

---

## B5 — Strategic-compact skill

### What it does

A skill `.claude/skills/strategic-compact/SKILL.md` that Claude invokes at logical breakpoints during long batches, suggesting `/compact` with a curated message about what to preserve and what to drop.

### Why

[feedback_no_stop_until_done.md](../../../C:\Users\upend\.claude\projects\C--Upendra-Claude-Code-Fitness-App\memory\feedback_no_stop_until_done.md) is codified 5 times. Mid-batch context blow-out is a recurring failure mode. Default auto-compact at 95% (or 55% post-B2) compacts whatever's in context with no guidance on what's load-bearing.

A strategic-compact skill says "compact NOW, here at the phase boundary, with this preserve/drop guidance" — much cleaner handoff than emergency auto-compact.

### File location

`.claude/skills/strategic-compact/SKILL.md`

### Trigger heuristics (built into the skill description, so it's invoked when contextually appropriate)

- A multi-phase plan completes one phase (last commit landed, next phase about to start).
- A parallel subagent fan-out returns (Hermes-style audit dispatches just finished).
- A batch ships (APK built + push complete) but follow-up work continues in same session.
- Founder explicitly says "compact now" or "we're about to start fresh phase."

### Procedure sketch

When invoked, the skill:

1. Identify the logical breakpoint (which trigger fired).
2. Compose a `/compact` invocation with curated guidance:
   - **Preserve:** open OIs from `docs/audit/open_issues.md`, next-phase task list, current branch state (branch name + last commit SHA), unresolved founder questions, scope-locking decisions.
   - **Drop:** old tool outputs, file reads >1 hour old, completed audit reports (their conclusions are now in commits + docs), exploratory subagent transcripts whose findings already landed in code.
3. Surface the suggested `/compact` invocation for founder approval (don't auto-run).

### Alternatives considered & rejected

- **Auto-compact at every phase boundary** — too aggressive; sometimes a phase boundary is just a logical pause, not a state-change point.
- **Just lower `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`** (already done in B2) — solves the "out of context" problem but doesn't add semantic preservation. B2 + B5 are complementary.

### Validation

1. Run a batch with ≥3 phase boundaries.
2. Skill should auto-invoke at each boundary.
3. Founder reports whether the curated preserve/drop guidance was useful. Tune skill prompt based on feedback.

### Estimated effort

~30 minutes.

---

## B6 — Sync-CLAUDE.md skill

### What it does

A skill `.claude/skills/sync-claude-md/SKILL.md` that, when invoked, scans `CLAUDE.md` for drift against current code/database state and produces a structured report. Founder approves fixes manually.

### Why

`CLAUDE.md` is 200+ lines (grew ~20 lines per batch). Hermes audit 2026-05-17 caught it saying "21 tables" in §2 and "46 tables" in §7 (closed in OI-35). Gate 18 (`check_doc_internal_consistency.dart`) catches *explicit* drift pairs we've registered, but not *new* drift the audit didn't anticipate.

The cost of stale CLAUDE.md is real: a memory pointing at a stale file path enables a fresh fix to re-introduce the old bug (codified in [feedback_writer_reader_field_drift_recurring.md](../../../C:\Users\upend\.claude\projects\C--Upendra-Claude-Code-Fitness-App\memory\feedback_writer_reader_field_drift_recurring.md)).

### File location

`.claude/skills/sync-claude-md/SKILL.md`

### Procedure sketch

When invoked, the skill:

1. Read `CLAUDE.md`.
2. **Path validation:** extract every file path mentioned (regex `[a-z_/]+\.(dart|ts|sql|json|md|yaml)`). For each: verify file exists via Read or Glob. Flag broken paths.
3. **Line-number sanity:** extract every `file.dart:line` reference. For each: verify the cited line is within file length and contains a plausible match for the surrounding prose context (e.g. if §15 says "see `nutrition_provider.dart:790-835`", read those lines and check they still look like food-logging code).
4. **Count claims:** extract count assertions like "46 tables", "18+12 Edge Functions", "21 OIs closed". Cross-reference:
   - DB tables: `information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'` via Supabase MCP.
   - Edge Functions: `mcp__supabase__list_edge_functions` count.
   - Migrations: `ls supabase/migrations/*.sql | wc -l`.
   - Skills/agents/contract tests: filesystem counts.
5. **Version claims:** extract version refs like "ai-proxy v66". Cross-reference live function versions via `mcp__supabase__get_edge_function`.
6. **Memory cross-refs:** extract every `[[name]]` style reference in CLAUDE.md (if any) and every memory file mentioned by name. Verify the named memory exists.
7. **Output:** `docs/audit/<date>-claude-md-drift.md` with one finding per drift, suggested fix shape, severity (P0 broken-path / P1 count-mismatch / P2 stale-version).
8. Founder reviews, applies fixes manually.

### Alternatives considered & rejected

- **Auto-fix mode** — risky; auto-changing CLAUDE.md could compound drift if the agent's understanding is wrong.
- **Just extend Gate 18** — Gate 18 covers known drift pairs. This skill catches drift Gate 18 doesn't know about yet.
- **Run as a build gate** — too slow (needs MCP calls); better as an opt-in end-of-batch skill.

### Validation

1. Run skill once now. Expect ≥5 findings (CLAUDE.md is a year of accreted text).
2. Founder reviews + fixes findings. Commit corrections.
3. Run skill again immediately. Expect zero findings.
4. Add to end-of-batch checklist in `/build-apk` skill — invoke before committing CLAUDE.md changes.

### Estimated effort

~1.5 hours (45min skill draft, 30min first run, 30min first cleanup).

---

## Adoption order & timeline

| Order | Item | Risk | Effort | Why this order |
|---|---|---|---|---|
| 1 | B2 (env vars) | Very low | 5 min | Smallest, immediate effect, validates settings.json works |
| 2 | B5 (strategic-compact skill) | Very low | 30 min | Pure suggestion, no enforcement |
| 3 | B6 (sync-CLAUDE.md skill) | Low | 1.5h | Stand-alone, validates skill-pattern works |
| 4 | B1 (drift detector agent) | Low | 1.5h | Most architectural; needs careful prompt |
| 5 | B3 (config audit skill) | Low | 1h | One-time + quarterly cadence |

Total: ~4.5 hours of one-shot setup work.

**Shipping strategy:**
- Single batch (this work happens on one feature branch).
- One commit per item (5 commits) so each is reviewable + revertable in isolation.
- After B1 ships, run it against `WorkoutWriteService` + `NutritionWriteService` as part of the validation step — surfaces real findings or confirms zero.
- After B3 ships, run it once + close findings in same batch.
- After B6 ships, run it once + close findings in same batch.

---

## What this batch does NOT include

- **B4 (PostToolUse hook):** Windows fragility + `flutter analyze` slowness. Out of scope.
- **B7 (memory TTL):** Touches every existing memory file. Higher risk. Ships as a separate dedicated batch after this one stabilizes.
- **ECC's other 230 skills:** out of scope. We add only what we'll actually invoke.
- **Plugin distribution / external sharing:** not a goal.
- **Cross-harness adapters (Cursor, Codex, etc.):** founder uses Claude Code only.

---

## Verification (end-of-batch gates)

Before declaring this batch done:

1. **B2 verified:** Next batch's `/context` shows compaction at ~55%, not ~95%.
2. **B5 verified:** Skill invoked at ≥1 phase boundary in the next batch.
3. **B6 verified:** Run twice — second run reports zero drift after first-run fixes.
4. **B1 verified:** Run against `WorkoutWriteService` + `NutritionWriteService` — either zero findings (confirmed clean) or any findings are real drift (filed as OIs).
5. **B3 verified:** Run once — findings reviewed + closed.
6. **CLAUDE.md updated** with a §X "Adopted ECC patterns" entry referencing this spec + the 5 new tools.
7. **Memory file written:** `project_ecc_adoption_2026_05_24.md` capturing what we adopted and why, plus first-use observations.

---

## Open questions for founder

None remaining — all locked during 2026-05-24 brainstorm:

- Top pain: recurring bugs ✓
- Scope: B1 + B2 + B3 + B5 + B6 ✓
- Prompt source: adopt + customize ✓
- B7: defer ✓
- B4: skip ✓

Ready for implementation plan once you've reviewed this spec.
