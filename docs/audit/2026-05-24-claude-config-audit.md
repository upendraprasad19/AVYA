# Claude Config Audit — 2026-05-24

First run of the `audit-claude-config` skill (B3 of ECC adoption).

## Files scanned

- `.claude/settings.json` — 2 entries (env block only, no permissions/hooks/MCP).
- `.claude/settings.local.json` — 6 entries (1 Bash allow, 1 MCP allow, 4 Skill allow).
- `~/.claude/settings.json` — not scanned (out of project scope; founder-managed).

## Summary

- **P0:** 0 (no orphan skills, no missing hooks, no suspected secrets).
- **P1:** 0 (no stale binaries, no orphan MCP).
- **P2:** 1 (one stale Bash allow with no recent grep match).

Baseline is clean. One minor housekeeping recommendation only.

## P0 findings

None.

## P1 findings

None.

## P2 findings

### F1: Stale Bash allow — Edge Function inventory one-off

- **Where:** `.claude/settings.local.json` line 4.
- **Entry:**
  ```
  Bash(cd "C:/Upendra/Claude Code/Fitness App" && ls supabase/functions/ | sort > /tmp/local_fns.txt && cat /tmp/local_fns.txt)
  ```
- **Why:**
  - Pattern is very narrow (specific cd + ls + sort + redirect chain) — won't usefully match anything else.
  - Pattern writes to `/tmp/local_fns.txt` — a POSIX path on a Windows host. The bash environment via Git for Windows maps `/tmp` to something workable, but this is a one-off inventory command from a prior batch.
  - No recent grep match for `local_fns.txt` in `docs/diagnoses/`, `docs/audit/`, or `docs/superpowers/notes/`.
  - Binaries (`ls`, `sort`, `cat`) are all installed (`/usr/bin/...` via Git Bash).
- **Suggested fix:** Founder may prune this line on next manual review. It's a one-shot from a previous batch; if the inventory is needed again, a fresh allow will trigger normally.

## Per-category breakdown

### Bash allow rules (1 entry)

| # | Entry | Binary | Installed? | Recent use? | Verdict |
|---|---|---|---|---|---|
| 1 | `Bash(cd ... && ls supabase/functions/ \| sort > /tmp/local_fns.txt && cat /tmp/local_fns.txt)` | `ls` / `sort` / `cat` | ✅ all installed | ❌ no docs match | P2 — stale, founder-prune candidate |

### MCP allow rules (1 entry)

| # | Entry | Server configured? | Verdict |
|---|---|---|---|
| 1 | `mcp__ba7b5e8e-8611-4910-8e25-46712ab747b9__execute_sql` | ✅ active Supabase MCP (project ID, heavy use in CLAUDE.md migration workflow) | OK |

### Skill allow rules (4 entries)

| # | Entry | Skill exists? | Verdict |
|---|---|---|---|
| 1 | `Skill(superpowers:brainstorming)` | ✅ in system-reminder available-skills list | OK |
| 2 | `Skill(superpowers:brainstorming:*)` | ✅ same as above | OK |
| 3 | `Skill(superpowers:writing-plans)` | ✅ in available-skills list | OK |
| 4 | `Skill(superpowers:writing-plans:*)` | ✅ same as above | OK |

### Hook targets

None configured. No findings.

### env vars (2 entries in `.claude/settings.json`)

| # | Key | Value shape | Secret pattern match? | Verdict |
|---|---|---|---|---|
| 1 | `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `"55"` (2-char integer) | None — harness config | OK |
| 2 | `MAX_THINKING_TOKENS` | `"10000"` (5-char integer) | None — harness config | OK |

No `*_API_KEY`, `*_TOKEN`, `*_SECRET`, JWT, Razorpay prefix, PEM, SaaS prefix, or high-entropy string in scope.

## Recommended prunes (founder review)

### Stale Bash allows

- Line 4: `Bash(cd "..." && ls supabase/functions/ | sort > /tmp/local_fns.txt && cat /tmp/local_fns.txt)` — last apparent use: no recent grep match.

### Orphan permissions

None.

### Suspected secrets in env (P0 — rotate ASAP)

None. ✅

## Notes

- First run of skill on this project. Baseline established.
- Next quarterly run: 2026-08-24.
- If `.claude/settings.local.json` accumulates entries, re-run before next APK ship.
