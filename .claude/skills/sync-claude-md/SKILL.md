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
