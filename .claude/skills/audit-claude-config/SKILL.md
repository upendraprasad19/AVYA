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
