# ECC Adoption Batch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopt 5 ECC patterns into our Claude harness — drift detector agent + env vars + 3 skills — to harden the workflow against the #1 recurring bug class (writer/reader drift) and the doc-drift that hides it.

**Architecture:** Five independent artifacts (one settings file, three skills, one agent). Each lives in `.claude/` and is a markdown/JSON file — no executable code, no schema migrations, no app changes. Validation is by dry-running each artifact and observing output.

**Tech Stack:** Markdown (skills/agent), JSON (settings), Bash (validation commands), Supabase MCP (live-state checks for B6/B1).

**Spec:** [docs/superpowers/specs/2026-05-24-ecc-adoption-design.md](../specs/2026-05-24-ecc-adoption-design.md)

**Adoption order (smallest/safest first):**
0. Task 0 — Commit spec + plan (1 min)
1. Task 1 — B2 settings env vars (5 min)
2. Task 2 — B5 strategic-compact skill (30 min)
3. Task 3 — B6 sync-CLAUDE.md skill + first run (1.5h)
4. Task 4 — B1 writer/reader drift detector agent + first run (1.5h)
5. Task 5 — B3 audit-claude-config skill + first run (1h)
6. Task 6 — Doc CLAUDE.md update + memory file (15 min)

**Total: ~4.5 hours of one-shot setup.**

**Working branch:** `claude/frosty-bardeen-cce54b` (already on this branch, worktree at `.claude/worktrees/frosty-bardeen-cce54b/`).

---

## File Structure

```
.claude/
  settings.json                                          # NEW (Task 1)
  skills/
    debugging/                                           # existing
    strategic-compact/SKILL.md                           # NEW (Task 2)
    sync-claude-md/SKILL.md                              # NEW (Task 3)
    audit-claude-config/SKILL.md                         # NEW (Task 5)
  agents/
    auth-agent.md, backend-agent.md, ...                 # existing
    writer-reader-drift-detector.md                      # NEW (Task 4)

docs/audit/
  2026-05-24-claude-md-drift.md                          # NEW (Task 3 run-output)
  2026-05-24-drift-scan-workout.md                       # NEW (Task 4 run-output)
  2026-05-24-drift-scan-nutrition.md                     # NEW (Task 4 run-output)
  2026-05-24-claude-config-audit.md                      # NEW (Task 5 run-output)

C:/Users/upend/.claude/projects/C--Upendra-Claude-Code-Fitness-App/memory/
  project_ecc_adoption_2026_05_24.md                     # NEW (Task 6)
  MEMORY.md                                              # MODIFY (Task 6)
```

Boundary discipline:
- Each artifact is one file; one responsibility.
- Skills under `.claude/skills/<name>/SKILL.md` — discovered automatically by Claude harness.
- Agents under `.claude/agents/<name>.md` — discovered automatically.
- `settings.json` is at `.claude/settings.json` (project-committed) NOT `settings.local.json` (gitignored). We want this committed so future sessions/contributors inherit the tuning.

---

## Task 0: Commit spec + plan (foundation)

**Files:**
- Already created: `docs/superpowers/specs/2026-05-24-ecc-adoption-design.md`
- Already created: `docs/superpowers/plans/2026-05-24-ecc-adoption.md`

- [ ] **Step 0.1: Verify both files exist**

```bash
ls "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b/docs/superpowers/specs/2026-05-24-ecc-adoption-design.md"
ls "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b/docs/superpowers/plans/2026-05-24-ecc-adoption.md"
```
Expected: both paths printed.

- [ ] **Step 0.2: Commit spec + plan**

```bash
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" add docs/superpowers/specs/2026-05-24-ecc-adoption-design.md docs/superpowers/plans/2026-05-24-ecc-adoption.md
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" commit -m "docs(superpowers): ECC adoption design + plan (2026-05-24)

Brainstorm locked 5-item adoption scope from affaan-m/ECC:
- B1 writer-reader-drift-detector agent
- B2 settings env vars (CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=55, MAX_THINKING_TOKENS=10000)
- B3 audit-claude-config skill
- B5 strategic-compact skill
- B6 sync-claude-md skill

Skipped: B4 (PostToolUse hooks — Windows fragility), B7 (memory TTL — deferred).

Spec: docs/superpowers/specs/2026-05-24-ecc-adoption-design.md
Plan: docs/superpowers/plans/2026-05-24-ecc-adoption.md
"
```

---

## Task 1: B2 — Settings env vars

**Files:**
- Create: `.claude/settings.json`

- [ ] **Step 1.1: Verify settings.json does not yet exist**

Run:
```bash
ls "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b/.claude/settings.json" 2>/dev/null && echo "EXISTS" || echo "MISSING"
```
Expected: `MISSING` (only `settings.local.json` exists per pre-flight check).

- [ ] **Step 1.2: Create `.claude/settings.json`**

File content (complete file):
```json
{
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "55",
    "MAX_THINKING_TOKENS": "10000"
  }
}
```

- [ ] **Step 1.3: Verify JSON parses**

Run:
```bash
node -e "JSON.parse(require('fs').readFileSync('C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b/.claude/settings.json','utf8'))" && echo "PARSED OK"
```
Expected: `PARSED OK`

- [ ] **Step 1.4: Commit**

```bash
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" add .claude/settings.json
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" commit -m "chore(harness): adopt ECC env-var tuning (B2)

CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=55 — compact at 55% not 95%, leaves
headroom for phase boundaries in long batches.

MAX_THINKING_TOKENS=10000 — cap thinking budget at 10K so Opus
does not over-deliberate on trivial steps.

Spec: docs/superpowers/specs/2026-05-24-ecc-adoption-design.md (B2)
"
```

- [ ] **Step 1.5: Validation note**

Effect is visible only on next session start (env vars are read once per Claude Code launch). Capture observation during next batch: does `/context` show compaction kicking in around 55% instead of 95%? If not, re-check env-var pickup (the var-name must match what Claude Code's harness reads; verify against [Claude Code docs](https://docs.claude.com/claude-code) if behavior unchanged after one batch).

---

## Task 2: B5 — Strategic-compact skill

**Files:**
- Create: `.claude/skills/strategic-compact/SKILL.md`

- [ ] **Step 2.1: Verify skill directory does not exist**

```bash
ls "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b/.claude/skills/strategic-compact" 2>/dev/null && echo "EXISTS" || echo "MISSING"
```
Expected: `MISSING`

- [ ] **Step 2.2: Create skill file**

Create `.claude/skills/strategic-compact/SKILL.md` with this exact content:

```markdown
---
name: strategic-compact
description: Use at logical phase boundaries during long batches to suggest /compact with curated preserve/drop guidance. Triggers — after a commit lands and a new phase is about to start; after a parallel subagent fan-out returns; after an APK ships but follow-up work continues; when founder says "compact now" / "fresh phase"; when context bar is approaching 70%.
type: process
priority: medium
---

# Strategic Compact — Phase-Boundary Compaction Skill

## When to invoke

- A multi-phase plan has just completed one phase (last commit landed in the prior phase, next phase about to start).
- A parallel subagent dispatch returned and findings have been incorporated into code/docs.
- A batch has shipped (APK built + pushed, or branch merged) but follow-up work continues in the same session.
- Founder explicitly says "compact now" / "fresh phase" / "let's reset context."
- Context bar is approaching 70% (mid-warning, before auto-compact at 55% per `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`).

## Procedure

1. **Identify the trigger.** State which condition fired (phase boundary / fan-out return / batch ship / explicit / context pressure).

2. **List what to preserve (in chat, for founder visibility):**
   - Current branch name + last commit SHA.
   - Open OIs from `docs/audit/open_issues.md` relevant to the next phase.
   - Next-phase task list (specific items still pending — read from active plan file if one exists).
   - Any unresolved founder questions or scope-locking decisions made earlier this session.
   - Active in-flight memories — `feedback_*.md` items referenced this session.

3. **List what to drop:**
   - Old tool outputs (Bash command stdout from >1 hour ago).
   - File reads of files we've since edited (stale context).
   - Completed audit reports — their conclusions are in commits/docs now.
   - Exploratory subagent transcripts whose findings already landed in code.

4. **Surface the suggested compaction:** present the curated preserve/drop list to the founder. **Do NOT auto-run /compact.** Wait for explicit approval.

5. **After founder approves:** invoke /compact with the preserve list as guidance for what to keep in the summary.

## What this skill is NOT

- An auto-compactor. It surfaces a suggestion; founder approves.
- A replacement for `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=55` — that env var is the safety net for blown context. This skill is the proactive version.

## After every invocation

Append one line to `docs/superpowers/skills-log.md` (create if missing) noting: timestamp, trigger reason, founder accepted/declined. Helps tune trigger conditions over time.
```

- [ ] **Step 2.3: Verify file exists and frontmatter parses**

```bash
ls "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b/.claude/skills/strategic-compact/SKILL.md"
head -7 "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b/.claude/skills/strategic-compact/SKILL.md"
```
Expected: file path printed; first 7 lines show YAML frontmatter with `name: strategic-compact`.

- [ ] **Step 2.4: Commit**

```bash
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" add .claude/skills/strategic-compact/SKILL.md
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" commit -m "chore(harness): add strategic-compact skill (B5)

Surfaces /compact suggestions at logical phase boundaries with curated
preserve/drop guidance. Founder-approves; never auto-runs.

Spec: docs/superpowers/specs/2026-05-24-ecc-adoption-design.md (B5)
"
```

- [ ] **Step 2.5: Validation note**

Skill becomes available next session (Claude harness reads `.claude/skills/` on session start). No immediate test — observe whether the skill auto-invokes at phase boundaries during the next batch.

---

## Task 3: B6 — Sync-CLAUDE.md skill + first run + cleanup

**Files:**
- Create: `.claude/skills/sync-claude-md/SKILL.md`
- Create (after first run): `docs/audit/2026-05-24-claude-md-drift.md`
- Modify (after founder review): `CLAUDE.md` (drift fixes)

- [ ] **Step 3.1: Create skill file**

Create `.claude/skills/sync-claude-md/SKILL.md` with this content:

```markdown
---
name: sync-claude-md
description: Audit CLAUDE.md for drift against current code/database/migration state. Extracts every file path, line-number reference, count claim (e.g. "46 tables"), version claim (e.g. "ai-proxy v66"), and memory file reference; verifies each against live state via MCP/filesystem; produces a structured drift report at docs/audit/. Founder approves fixes manually. Run at end of every batch before committing CLAUDE.md changes.
type: process
priority: medium
---

# Sync CLAUDE.md Skill

## When to invoke

- End of every batch, before committing any CLAUDE.md changes.
- After a major migration ships (table counts change).
- After Edge Function deploys (version numbers change).
- After significant file moves/renames.
- Quarterly maintenance pass.

## Procedure

### Phase 1: Extract claims from CLAUDE.md

Read `CLAUDE.md` end-to-end. Build a structured claim list:

**1.1 File path claims**
- Regex: `[\w/_.-]+\.(dart|ts|sql|json|md|yaml|html|js|sh|toml|kt)\b`
- Extract every full or partial path reference. Note §section.

**1.2 Line-number references**
- Pattern: `file.dart:N` or `file.dart:N-M`
- Pair each with the surrounding sentence for context.

**1.3 Count claims**
- Patterns: "N tables", "N Edge Functions", "N migrations", "N skills", "N contract tests", "N gates", "N agents", "N memory files", any `X+Y` sums.
- Note the §section number for each.

**1.4 Version claims**
- Patterns: "ai-proxy v66", "migration NNN", "APK Test #N", "appVersion `X.Y.Z+N`".

**1.5 Memory file references**
- Pattern: `feedback_*.md`, `project_*.md`.
- Pair with the link target.

### Phase 2: Verify each claim

**2.1 File paths.** For each cited path, run `Read` or `Glob`. If file doesn't exist → P0 broken-path finding.

**2.2 Line refs.** Read the cited line ±5 lines. Verify the surrounding prose context from §1.2 still loosely matches what the line contains. Stale match → P2 line-drift finding.

**2.3 Counts.** Cross-reference live state:
- DB tables — query `SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'` via `mcp__ba7b5e8e-8611-4910-8e25-46712ab747b9__execute_sql`.
- Migrations — `ls supabase/migrations/*.sql | wc -l` (top-level only; exclude subfolders).
- Edge Functions — `mcp__ba7b5e8e-8611-4910-8e25-46712ab747b9__list_edge_functions`.
- Skills — `ls .claude/skills/ | wc -l` (count directories with SKILL.md).
- Agents — `ls .claude/agents/*.md | wc -l`.
- Contract tests — `find test/contracts/ -name '*_test.dart' | wc -l`.
- Build gates — `ls scripts/check_*.dart | wc -l`.
- Memory files — `ls C:/Users/upend/.claude/projects/C--Upendra-Claude-Code-Fitness-App/memory/*.md | wc -l`.
- Mismatch → P1 count-drift finding.

**2.4 Versions.** For each Edge Function version reference, fetch live via `mcp__ba7b5e8e-8611-4910-8e25-46712ab747b9__get_edge_function`. Tolerate ±2 versions; >2 behind → P2 version-stale finding.

**2.5 Memory refs.** For each `feedback_*.md` / `project_*.md` mention, verify file exists in the memory dir. Missing → P0 broken-memory-ref finding.

### Phase 3: Output report

Write to `docs/audit/<YYYY-MM-DD>-claude-md-drift.md`:

\```
# CLAUDE.md Drift Audit — <date>

## Summary
- P0 (broken refs): N
- P1 (count drift): N
- P2 (line/version drift): N

## P0 findings
### Finding 1: <short title>
- **Where:** CLAUDE.md §<section>, line <line>
- **Claim:** "<verbatim quote>"
- **Reality:** <verified state>
- **Suggested fix:** <one-line>

## P1 findings
[...]

## P2 findings
[...]
\```

### Phase 4: Surface to founder

Print the summary in chat. List P0 findings inline. For P1/P2, point at the report file.

**DO NOT auto-edit CLAUDE.md.** Founder reviews report and edits CLAUDE.md manually (or instructs you to make specific changes).

## What this skill is NOT

- A linter. It doesn't enforce style.
- An auto-fixer. Founder approves every fix.
- A replacement for Gate 18 (`check_doc_internal_consistency.dart`). Gate 18 catches REGISTERED drift pairs ahead of commit; this skill catches NEW drift the gates don't know about yet.
```

- [ ] **Step 3.2: Verify file**

```bash
ls "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b/.claude/skills/sync-claude-md/SKILL.md"
head -7 "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b/.claude/skills/sync-claude-md/SKILL.md"
```
Expected: file printed; frontmatter `name: sync-claude-md` visible.

- [ ] **Step 3.3: First commit — skill only**

```bash
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" add .claude/skills/sync-claude-md/SKILL.md
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" commit -m "chore(harness): add sync-claude-md skill (B6)

Audits CLAUDE.md for drift against live code/DB/migration state.
Extracts paths, line refs, count claims, version claims, memory refs;
verifies each; produces structured report at docs/audit/.

Spec: docs/superpowers/specs/2026-05-24-ecc-adoption-design.md (B6)
"
```

- [ ] **Step 3.4: First run — invoke skill**

In a new turn, invoke:
```
Skill(skill="sync-claude-md")
```

Expected: Skill runs Phase 1 → 4. Produces `docs/audit/2026-05-24-claude-md-drift.md` with at least one finding (CLAUDE.md is a year of accreted text; some drift is near-certain).

- [ ] **Step 3.5: Review report with founder**

Read `docs/audit/2026-05-24-claude-md-drift.md`. Present P0 findings inline in chat. Ask founder which to fix in this batch vs defer.

**HALT here for founder direction.** Do not auto-edit CLAUDE.md.

- [ ] **Step 3.6: Apply approved fixes**

For each fix the founder approves, edit CLAUDE.md inline (use the Edit tool, never Write — preserves untouched sections).

- [ ] **Step 3.7: Re-run skill to verify**

Invoke skill again. Expected: only deferred findings remain (or zero if founder fixed everything). No NEW findings.

- [ ] **Step 3.8: Second commit — report + CLAUDE.md fixes**

```bash
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" add docs/audit/2026-05-24-claude-md-drift.md CLAUDE.md
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" commit -m "docs(claude-md): first sync-claude-md run + drift fixes

Ran new sync-claude-md skill against CLAUDE.md. Closed N drift findings:
- <one-line per fix>

Deferred N findings (tracked in report).

Report: docs/audit/2026-05-24-claude-md-drift.md
"
```

- [ ] **Step 3.9: Validation note**

After this task, CLAUDE.md is canonical. Future batches should invoke `sync-claude-md` before committing any CLAUDE.md edits.

---

## Task 4: B1 — Writer/Reader Drift Detector Agent + first run

**Files:**
- Create: `.claude/agents/writer-reader-drift-detector.md`
- Create (after first run): `docs/audit/2026-05-24-drift-scan-workout.md`
- Create (after first run): `docs/audit/2026-05-24-drift-scan-nutrition.md`

- [ ] **Step 4.1: Verify agent does not exist**

```bash
ls "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b/.claude/agents/writer-reader-drift-detector.md" 2>/dev/null && echo "EXISTS" || echo "MISSING"
```
Expected: `MISSING`

- [ ] **Step 4.2: Create agent file**

Create `.claude/agents/writer-reader-drift-detector.md` with this content:

```markdown
# Writer/Reader Drift Detector Agent — ICANBEFITTER

You are the Writer/Reader Drift Detector Agent. Your job is to scan the codebase for field-name, type, or semantic mismatches between code that WRITES data and code that READS it. This is the #1 recurring bug class on this codebase — 7+ instances since Test #6.

## Background — read first

- `CLAUDE.md` §15 "Source of Truth Rules" — canonical SoT contracts.
- `docs/sot_registry.yaml` — machine-readable registry of every SoT concept (writers + readers + class constraints).
- `C:/Users/upend/.claude/projects/C--Upendra-Claude-Code-Fitness-App/memory/feedback_writer_reader_field_drift_recurring.md` — every prior drift instance enumerated with file:line cites.
- `C:/Users/upend/.claude/projects/C--Upendra-Claude-Code-Fitness-App/memory/feedback_source_grep_false_confidence.md` — why static grep contract tests caught 0 of 9 drifts; do not rely on grep alone.

## Inputs you accept

The dispatch prompt will give you ONE of:

1. **A writer file path** — e.g. "Scan `lib/core/services/workout_write_service.dart` for drift."
2. **A domain name** — `workout` | `nutrition` | `health` | `coach` | `community`. Resolve to canonical writer:
   - `workout` → `lib/core/services/workout_write_service.dart` + `lib/core/services/sync/sync_workout.dart`
   - `nutrition` → `lib/core/services/nutrition_write_service.dart` + `lib/core/services/sync/sync_nutrition.dart`
   - `health` → `lib/core/services/health_write_service.dart` + `lib/core/services/sync/sync_health.dart`
   - `coach` → `supabase/functions/ai-proxy/` + `lib/core/services/sync/sync_coach.dart` + `lib/features/ai_coach/repositories/ai_coach_repository.dart`
   - `community` → `lib/shared/repositories/submissions_repository.dart` + `lib/core/services/sync/sync_community.dart`
3. **A field rename** — e.g. "I just renamed `sets_completed` → `set_number`. Verify all readers updated."

## Procedure

### Step 1 — Identify what the writer emits

If given a writer file:
- Open the file. Identify Hive `box.put(...)` and `box.putAll(...)` calls. Capture key prefix (e.g. `exlog_*`, `nlog_*`, `schedule_*`) and the full `Map<String, dynamic>` field set.
- Identify any cloud projection — look in the matching `_syncXxx` method in `sync_<domain>.dart`. The `.upsert(...)` payload defines the cloud column set.
- Build an **emit set**: every `(key_prefix, field_name)` pair this writer produces locally, plus every `(cloud_table, column_name)` it projects upward.

If given a domain: resolve to writer + sync helper per the table above, then apply Step 1.

If given a field rename: skip emit-set discovery; just trace readers of both old + new names.

### Step 2 — Locate readers

For each `(key_prefix, field_name)` or `(cloud_table, column_name)` in the emit set:
- Grep for `box.get('<key_prefix>...')` and `boxName.toMap()` followed by prefix filtering.
- Grep for `['<field_name>']` map-access patterns across the codebase.
- Grep for `.from('<cloud_table>').select(...)`, `.from('<cloud_table>').upsert(...)`, `.from('<cloud_table>').update(...)`.
- Grep for `<field_name>` as a property access on a model class (less common — most data is map-shaped on this codebase).

### Step 3 — Compare each writer↔reader pair

For each reader location, verify:
- **Field name match.** Writer emits `set_number`, reader reads `set_number` (not `sets_completed` / `sets_detail`).
- **Type match.** Writer emits `int`, reader expects `int` (not `String` or `num?`).
- **Semantic match.** Writer emits "sum across sets" but reader treats as "per-set value" → same name, different meaning. Compare doc comments + surrounding code patterns. When semantics aren't documented, flag for human review.

### Step 4 — Special signature checks (always apply)

Run these baked-in known-drift signatures regardless of input domain:

- **`exlog_*` keys MUST be produced ONLY by `WorkoutWriteService.exlogKey(date, name)`.** Any literal `'exlog_'` string assembly outside that one method = Gate 17 violation → P0 finding.
- **`nlog_*` and `wlog_*` keys MUST come from `NutritionWriteService` / `WorkoutWriteService` respectively.** Direct literal assembly outside those services → P0.
- **Hive duration field names:** writer emits `duration_sec` (canonical). Readers MUST accept BOTH `duration_sec` AND `duration_seconds` (legacy from restore path). A reader that accepts ONLY `duration_seconds` (legacy-only) → P1 finding. A reader that emits `duration_seconds` outside restore → P2 finding.
- **Hive `coaching_notes` (plural) ↔ cloud `coach_notes` (singular, different word):** projections in BOTH directions (Hive→cloud + cloud→Hive) must remap. A projection without the remap → P0.
- **IST date keys:** any date key string assembly MUST go through `istDateStr()`. Flag any of: `DateTime.now().toIso8601String().substring(0,10)`, `'${y}-${m}-${d}'` hand-assembly, `DateFormat('yyyy-MM-dd')` direct usage on a local `DateTime`. P0 if writes a Hive/cloud key; P2 if used only for display.
- **UUID v5 deterministic IDs:** `user_custom_exercises` + `user_custom_foods` IDs MUST use `_customEntityId()` (UUID v5 over `(user_id, type, lower(name))`). Any `.hashCode`-based ID assembly for these tables → P0.
- **Auth-scoped Riverpod providers:** any provider that reads user-scoped Hive (via `MigratedKey`, `wrapUserScopedBox`, user-filtered Supabase tables) MUST `ref.watch(authUserIdTokenProvider)` as its first line. Provider that does not → P1 finding.

### Step 5 — Output

Write findings to `docs/audit/<YYYY-MM-DD>-drift-scan-<writer-or-domain>.md`:

\```
# Drift Scan — <writer-or-domain> — <date>

## Summary
- P0 (active bug or contract violation): N
- P1 (latent risk / partial coverage): N
- P2 (convention drift): N

## Writers covered
- file:line — emit-set summary (N Hive fields + M cloud columns)

## Readers covered
- N readers across M files

## Findings

### F1: <short title>
- **Severity:** P0/P1/P2
- **Writer:** path/to/writer.dart:LINE — emits `field_name: type` with semantic `<sum|max|first|per-set|...>`
- **Reader:** path/to/reader.dart:LINE — reads as `<actual_name_and_type>` with semantic `<...>`
- **Drift type:** field name | type | semantic | signature violation
- **Suggested fix:** <one-line>
- **Regression test to add:** <suggested file path + assertion shape>

[... etc ...]

## SoT registry coverage
- Writers in scope: N
- Of those present in `docs/sot_registry.yaml`: M
- Absent from registry (recommend adding entry): K writers
\```

## What this agent is NOT

- Not a linter — runs on demand, not on every edit.
- Not a fixer — read-only. Reports findings; humans fix.
- Not a replacement for contract tests — complements them. Source-grep contract tests caught 0 of 9 drift instances (per `feedback_source_grep_false_confidence.md`). This agent traces semantics, not just patterns.

## When in doubt

Read `feedback_writer_reader_field_drift_recurring.md` — every prior drift instance is enumerated with file:line cites. Use them as ground truth for what "real drift looks like" in this codebase.
```

- [ ] **Step 4.3: Verify file**

```bash
head -10 "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b/.claude/agents/writer-reader-drift-detector.md"
```
Expected: first line `# Writer/Reader Drift Detector Agent — ICANBEFITTER`.

- [ ] **Step 4.4: First commit — agent only**

```bash
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" add .claude/agents/writer-reader-drift-detector.md
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" commit -m "chore(harness): add writer-reader-drift-detector agent (B1)

Read-only subagent that traces writer→reader paths for a given writer
file or domain and flags field-name / type / semantic mismatches.
Includes baked-in known drift signatures (exlog keys, IST dates,
UUID v5 IDs, auth token watch).

Targets the #1 recurring bug class on this codebase (7+ instances
since Test #6, per feedback_writer_reader_field_drift_recurring.md).

Spec: docs/superpowers/specs/2026-05-24-ecc-adoption-design.md (B1)
"
```

- [ ] **Step 4.5: Dry-run against `workout` domain**

In a new turn, dispatch the agent:
```
Agent(
  subagent_type="writer-reader-drift-detector",
  description="Drift scan: workout domain",
  prompt="Scan the `workout` domain for drift. Report findings to docs/audit/2026-05-24-drift-scan-workout.md per the agent's procedure. Cross-reference against docs/sot_registry.yaml. Expected baseline: zero P0 findings (this domain has been audited heavily). Any P0/P1 finding should be treated as a real drift — file as an Open Issue with proposed fix."
)
```

- [ ] **Step 4.6: Review workout findings**

Read `docs/audit/2026-05-24-drift-scan-workout.md`. Expected: zero P0 (audit-clean baseline). If non-zero P0 → real drift surfaced; surface in chat for founder triage.

- [ ] **Step 4.7: Dry-run against `nutrition` domain**

```
Agent(
  subagent_type="writer-reader-drift-detector",
  description="Drift scan: nutrition domain",
  prompt="Scan the `nutrition` domain for drift. Report findings to docs/audit/2026-05-24-drift-scan-nutrition.md per the agent's procedure. Cross-reference against docs/sot_registry.yaml. Same expected baseline as workout."
)
```

- [ ] **Step 4.8: Review nutrition findings**

Same as Step 4.6, for nutrition.

- [ ] **Step 4.9: Second commit — scan outputs**

```bash
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" add docs/audit/2026-05-24-drift-scan-workout.md docs/audit/2026-05-24-drift-scan-nutrition.md
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" commit -m "docs(audit): first writer-reader-drift-detector run (workout + nutrition)

Workout: <N P0 / N P1 / N P2 findings>
Nutrition: <N P0 / N P1 / N P2 findings>

<If any P0:> Real drift surfaced — see open_issues.md OI-NN, OI-NN+1.
<If zero P0:> Baseline clean — agent calibrated; ready for routine
audit use.
"
```

- [ ] **Step 4.10: If real drift surfaced — HALT for founder**

Any P0 finding = real drift in a heavily-audited domain. Surface in chat with file:line cites. **Do not auto-fix.** Founder triages: fix in this batch (separate task) vs file as Open Issue for next batch.

---

## Task 5: B3 — Audit-Claude-Config skill + first run

**Files:**
- Create: `.claude/skills/audit-claude-config/SKILL.md`
- Create (after first run): `docs/audit/2026-05-24-claude-config-audit.md`

- [ ] **Step 5.1: Create skill file**

Create `.claude/skills/audit-claude-config/SKILL.md` with this content:

```markdown
---
name: audit-claude-config
description: Audit .claude/settings.json + settings.local.json + ~/.claude/settings.json for stale Bash allows, missing hook targets, orphan MCP refs, orphan Skill grants, and suspected secrets in env. Produces structured report at docs/audit/; founder reviews and prunes manually. Run on adoption + quarterly.
type: process
priority: low
---

# Audit Claude Config Skill

## When to invoke

- Adopting this skill (first run).
- Quarterly maintenance pass.
- Before sharing the project (or its config) externally.
- After major refactors that may have orphaned old permission grants.

## Procedure

### Phase 1: Read configs

Read in order (skip any that don't exist):
1. `.claude/settings.json` (project, committed).
2. `.claude/settings.local.json` (project, gitignored).
3. `~/.claude/settings.json` (global, if accessible).

Parse JSON. Collect into a unified view:
- Permissions allow rules
- Permissions deny rules
- Hooks
- env vars
- Model overrides
- MCP server allowlist

### Phase 2: Per-category audit

**2.1 Bash allow rules**

For each `Bash(...)` entry under `permissions.allow`:
- Parse the command (everything between `Bash(` and `)`).
- Identify the leading binary (first word after any `cd ... && `).
- For each binary, sanity check:
  - Is it still installed locally? Quick `which <binary>` (or `Get-Command` on PowerShell).
  - Has it been invoked recently? Grep `docs/diagnoses/`, `docs/audit/`, `docs/superpowers/notes/` for the binary name + key flags.
  - Does the pattern have wildcards or path-specific narrowing? Broad patterns (e.g. `Bash(rm:*)`) deserve scrutiny.
- Severity:
  - **P1** if binary not installed OR clearly stale (no docs mention in last 90 days).
  - **P2** if pattern is broader than needed.

**2.2 MCP allow rules**

For each `mcp__<server-id>__*` entry:
- Match the server ID against `.claude/settings.json mcpServers` map or `~/.claude/mcp_config.json`.
- If the server isn't configured anywhere → **P1: orphan permission**.
- If the server is configured but never invoked recently → **P2: stale**.

**2.3 Skill allow rules**

For each `Skill(<name>)` or `Skill(<name>:*)`:
- Check if the skill exists in `.claude/skills/`, in known plugin caches under `C:/Users/upend/.claude/plugins/`, or in the system-reminder available-skills list.
- Missing → **P0: orphan permission referencing a deleted skill**.

**2.4 Hook targets**

For each entry under `hooks`:
- Resolve the script/command path.
- If the script doesn't exist → **P0**.
- If the script is unreadable / non-executable → **P0**.
- If the command pattern has obvious injection risk (env-var interpolation into unquoted shell) → **P0**.

**2.5 env vars**

For each `env.<KEY>` entry:
- Check against secret patterns from `feedback_secrets_pattern_audit_before_first_push.md`:
  - `*_API_KEY=<non-empty>` / `*_TOKEN=<non-empty>` / `*_SECRET=<non-empty>`
  - `RAZORPAY_*` literals
  - `SUPABASE_SERVICE_*` literals
  - `GEMINI_*` literals
  - JWT shape (3 dot-separated base64 segments)
  - `Bearer <token>` patterns
  - Razorpay key prefixes (`rzp_test_`, `rzp_live_`)
  - Long hex strings (≥32 chars)
  - PEM blocks (`-----BEGIN`)
  - 40-char hex (Git SHAs OK; secrets in env aren't)
  - SaaS prefixes (`xoxb-`, `sk-`, `pk_`, etc.)
  - High-entropy strings inside quotes
- Any match → **P0: rotate the secret + move to Vault/Dashboard**.

### Phase 3: Output report

Write to `docs/audit/<YYYY-MM-DD>-claude-config-audit.md`:

\```
# Claude Config Audit — <date>

## Files scanned
- .claude/settings.json (N entries)
- .claude/settings.local.json (N entries)
- ~/.claude/settings.json (N entries, if accessible)

## Summary
- P0: N (orphan skills, missing hooks, suspected secrets)
- P1: N (stale binaries, orphan MCP)
- P2: N (overbroad patterns, unused MCP)

## P0 findings
### F1: <short title>
- **Where:** <file> line N
- **Entry:** `<verbatim>`
- **Why:** <reason>
- **Suggested fix:** <one-line>

## Recommended prunes (founder review)

### Stale Bash allows
- Line N: `<entry>` — last apparent use: <date or "no recent grep match">

### Orphan permissions
- Line N: `<entry>` — target not found

### Suspected secrets in env (P0 — rotate ASAP)
- Line N: `<KEY>=<masked value>` — matches pattern: <pattern name>
\```

### Phase 4: Surface to founder

Print summary inline. Highlight P0 secrets first. Founder reviews report + applies prunes manually.

## What this skill is NOT

- An auto-pruner. Stale-looking allows might be needed by an upcoming batch.
- A replacement for the pre-push secret-audit discipline (`feedback_secrets_pattern_audit_before_first_push.md`). It catches what slipped past.
```

- [ ] **Step 5.2: Verify file**

```bash
head -7 "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b/.claude/skills/audit-claude-config/SKILL.md"
```
Expected: frontmatter visible with `name: audit-claude-config`.

- [ ] **Step 5.3: First commit — skill only**

```bash
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" add .claude/skills/audit-claude-config/SKILL.md
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" commit -m "chore(harness): add audit-claude-config skill (B3)

Audits .claude/settings.json + settings.local.json for stale Bash
allows, missing hook targets, orphan MCP refs, orphan Skill grants,
and suspected secrets in env. Founder-reviewed; not an auto-pruner.

Spec: docs/superpowers/specs/2026-05-24-ecc-adoption-design.md (B3)
"
```

- [ ] **Step 5.4: First run — invoke skill**

```
Skill(skill="audit-claude-config")
```

Expected: report written to `docs/audit/2026-05-24-claude-config-audit.md`. Likely findings: a few stale Bash allows (the worktree's settings.local.json currently has 4 entries; could be 0-2 stale).

- [ ] **Step 5.5: Founder reviews report**

Read `docs/audit/2026-05-24-claude-config-audit.md`. Surface P0 findings (especially any suspected secrets) inline. **HALT for founder direction.**

- [ ] **Step 5.6: Apply approved prunes**

Edit `.claude/settings.local.json` (or `.claude/settings.json`) per founder approval.

- [ ] **Step 5.7: Second commit — report + prunes**

```bash
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" add docs/audit/2026-05-24-claude-config-audit.md .claude/settings.local.json .claude/settings.json
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" commit -m "chore(harness): first audit-claude-config run + prunes

Closed N findings:
- <one-line per fix>

Deferred N findings (tracked in report).

Report: docs/audit/2026-05-24-claude-config-audit.md
"
```

Note: `.claude/settings.local.json` is gitignored on most projects but per the founder convention here, both project-level settings files MAY be staged when modified for accountability. Verify with `git check-ignore .claude/settings.local.json` before staging. If gitignored, only stage `settings.json` and the report.

---

## Task 6: CLAUDE.md adoption notes + project memory

**Files:**
- Modify: `CLAUDE.md` (add a new short section)
- Create: `C:/Users/upend/.claude/projects/C--Upendra-Claude-Code-Fitness-App/memory/project_ecc_adoption_2026_05_24.md`
- Modify: `C:/Users/upend/.claude/projects/C--Upendra-Claude-Code-Fitness-App/memory/MEMORY.md` (add one index entry)

- [ ] **Step 6.1: Add CLAUDE.md section**

Use Edit to insert a new section in CLAUDE.md. Locate the last section before "## 19. COMMON BUGS TO AVOID" (or wherever the section numbering currently ends — check live state first; **do NOT hardcode a section number — use the next available**).

Content to insert (adjust §number to match current CLAUDE.md):

```markdown
## §X. ADOPTED ECC PATTERNS (2026-05-24)

Five tools adopted from [affaan-m/ECC](https://github.com/affaan-m/ECC) on 2026-05-24:

1. **`.claude/settings.json`** — `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=55` + `MAX_THINKING_TOKENS=10000`. Compact at 55% not 95%; cap thinking budget. Effect visible from next session.
2. **`.claude/skills/strategic-compact/`** — surfaces /compact suggestions at logical phase boundaries with curated preserve/drop guidance. Founder-approved; never auto-runs.
3. **`.claude/skills/sync-claude-md/`** — audits THIS file for drift vs live code/DB state. Run at end of every batch before committing CLAUDE.md changes.
4. **`.claude/agents/writer-reader-drift-detector.md`** — read-only subagent that traces writer→reader paths for a domain or writer file. Targets the #1 recurring bug class (7+ instances since Test #6). Run during audits + before merging any WriteService refactor.
5. **`.claude/skills/audit-claude-config/`** — audits `.claude/settings*.json` for stale Bash allows, orphan permissions, suspected secrets. One-time + quarterly.

Spec: [docs/superpowers/specs/2026-05-24-ecc-adoption-design.md](docs/superpowers/specs/2026-05-24-ecc-adoption-design.md)
Plan: [docs/superpowers/plans/2026-05-24-ecc-adoption.md](docs/superpowers/plans/2026-05-24-ecc-adoption.md)

Explicitly NOT adopted: PostToolUse hooks (Windows fragility), memory TTL (deferred to separate batch), cross-harness adapters (Claude Code only), ECC's 230+ skills (only adopted what we'll actually invoke).
```

- [ ] **Step 6.2: Write project memory**

Create `C:/Users/upend/.claude/projects/C--Upendra-Claude-Code-Fitness-App/memory/project_ecc_adoption_2026_05_24.md`:

```markdown
---
name: ecc-adoption-batch-2026-05-24
description: 5-item adoption from affaan-m/ECC repo — settings env vars + 3 skills + 1 agent — to harden Claude harness workflow on this project.
metadata:
  type: project
---

**What shipped (2026-05-24):**
- `.claude/settings.json` with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=55` + `MAX_THINKING_TOKENS=10000`.
- `.claude/skills/strategic-compact/` — phase-boundary /compact suggestions.
- `.claude/skills/sync-claude-md/` — CLAUDE.md drift audit.
- `.claude/agents/writer-reader-drift-detector.md` — writer/reader drift subagent.
- `.claude/skills/audit-claude-config/` — settings audit.
- N CLAUDE.md drift fixes (see `docs/audit/2026-05-24-claude-md-drift.md`).
- N config audit prunes (see `docs/audit/2026-05-24-claude-config-audit.md`).
- 2 first-run drift scans (workout + nutrition) — baseline clean / N P0 findings.

**Non-obvious decisions:**
- Skipped B4 (PostToolUse hooks) — Windows path fragility + `flutter analyze` whole-project slowness make the cost-benefit poor. Documented in spec.
- Skipped B7 (memory TTL) — touches every existing memory file; deferred to dedicated batch later.
- Adopted ECC's INTENT but rewrote every prompt for our codebase (SoT registry refs, Hive/Riverpod/Supabase patterns, known drift signatures baked in).

**Tried-and-rejected:**
- Verbatim ECC prompts — too generic; would miss our specific drift signatures.
- Auto-pruning in B3 — risky; stale-looking allows might be needed by upcoming batches.
- Auto-fixing CLAUDE.md in B6 — founder reviews every change.

**Follow-ups explicitly deferred:**
- B7 memory TTL (separate batch after these stabilize).
- ECC's tdd-guide agent (overlaps with our rule 21 + superpowers TDD skill — revisit if we find ours insufficient).
- ECC's harness-optimizer agent (optimize after we've added gates, not before).

**How to apply (future sessions):**
- Invoke `Skill(skill="strategic-compact")` at every phase boundary.
- Invoke `Skill(skill="sync-claude-md")` before committing CLAUDE.md edits.
- Invoke `Skill(skill="audit-claude-config")` quarterly.
- Dispatch `writer-reader-drift-detector` agent during every audit batch + before merging WriteService refactors.

**Cross-refs:** [[feedback_writer_reader_field_drift_recurring]] (target of B1), [[feedback_no_stop_until_done]] (target of B5), [[feedback_secrets_pattern_audit_before_first_push]] (foundation for B3).
```

- [ ] **Step 6.3: Add memory index entry**

Use Edit on `C:/Users/upend/.claude/projects/C--Upendra-Claude-Code-Fitness-App/memory/MEMORY.md`. Insert a new line in the `## Project — recent batches (newest first)` section (at the very top of that section, since this is newest):

```
- [project_ecc_adoption_2026_05_24.md](project_ecc_adoption_2026_05_24.md) — **2026-05-24 ECC adoption batch**: 5 items shipped (env vars + 3 skills + 1 agent). Hardens harness against writer/reader drift class + doc drift. Spec + plan in `docs/superpowers/`.
```

- [ ] **Step 6.4: Final commit**

```bash
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" add CLAUDE.md
git -C "C:/Upendra/Claude Code/Fitness App/.claude/worktrees/frosty-bardeen-cce54b" commit -m "docs(claude-md): record ECC adoption batch (5 items)

CLAUDE.md §X 'Adopted ECC patterns' section added.
Project memory + index entry written separately (~/.claude/projects/...).

Closes ECC adoption batch — spec + plan in docs/superpowers/.
"
```

Note: Memory files live outside the worktree (`C:/Users/upend/.claude/projects/...`) and are NOT committed to this repo. They're per-user state.

---

## Self-review checklist (run after writing the plan)

- [ ] **Spec coverage:** Every item from the spec (B1, B2, B3, B5, B6) has at least one task implementing it. ✓ (B2→T1, B5→T2, B6→T3, B1→T4, B3→T5, doc→T6).
- [ ] **No placeholders:** Search for "TBD", "TODO", "implement later". None present in the plan body (skill/agent content uses `<placeholder>` only inside report templates, which are the literal output format the skill produces, not gaps in the plan).
- [ ] **Type consistency:** File paths consistent across tasks (e.g. `.claude/skills/sync-claude-md/SKILL.md` referenced same way everywhere). Skill names match between frontmatter and invocation (e.g. `name: sync-claude-md` → `Skill(skill="sync-claude-md")`).
- [ ] **Commit messages reference the spec** for every commit (`Spec: docs/superpowers/specs/2026-05-24-ecc-adoption-design.md (BN)`).
- [ ] **HALT-for-founder gates** explicit on Steps 3.5, 4.10, 5.5. No silent auto-edits to CLAUDE.md, settings, or fixing drift findings.

---

## Verification (end-of-batch gates)

Before declaring this batch done:

1. ✅ **B2 verified:** Next batch's compaction triggers at ~55% (observation, not automated test).
2. ✅ **B5 verified:** Skill invoked at ≥1 phase boundary in the next batch. `docs/superpowers/skills-log.md` shows entry.
3. ✅ **B6 verified:** Run twice — second run reports zero drift after first-run fixes (or only deferred items).
4. ✅ **B1 verified:** Run against workout + nutrition. Zero P0 findings (clean baseline) — OR any P0 findings filed as Open Issues with proposed fix.
5. ✅ **B3 verified:** Run once. Findings reviewed + closed (or deferred to issue tracker).
6. ✅ **CLAUDE.md updated** with §X "Adopted ECC patterns" entry.
7. ✅ **Memory file written** + indexed in MEMORY.md.

---

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `.claude/settings.json` env vars not picked up by Claude Code | Low | Low | Vars are documented in ECC; if Claude doesn't honor them, revert (one-line change). |
| B6 first run hits Supabase MCP quota | Low | Low | Only ~10 MCP calls per run (table count, list functions). Well within free-tier. |
| B1 agent produces excessive false positives | Medium | Medium | Tune prompt after first dry-run. Start with known-clean domains (workout, nutrition). |
| B3 first run flags secrets that are actually placeholders | Low | Low | Founder reviews every P0; no auto-prune. |
| Skill names collide with existing skills | Very low | Low | Pre-flight check confirmed only `debugging` skill exists locally. |
| Founder rejects a skill's design after seeing it run | Medium | Low | Each skill ships in own commit; easily reverted. |
