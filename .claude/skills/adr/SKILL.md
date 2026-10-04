---
name: adr
description: Scaffold a new Architecture Decision Record (ADR) in docs/adr/ — MADR-lite convention with next available number and IST-dated frontmatter. Use when the batch made a non-obvious architectural decision (technology choice, pattern adoption, deferred design, supersedence of an earlier ADR).
type: process
priority: medium
self-evolving: true
---

# /adr — Architecture Decision Record scaffolding

## When to invoke

Invoke `/adr` when the batch made a decision that:
- Locks an architectural pattern (e.g., "Riverpod for state", "ai-proxy single endpoint")
- Picks a technology with alternatives that were considered + rejected
- Establishes a non-obvious cross-cutting convention (e.g., "IST throughout")
- Supersedes or modifies an earlier ADR
- Captures reasoning that lives only in the founder's head today

Do NOT invoke for:
- Bug fixes (use diagnose-docs)
- UI tweaks (no architectural weight)
- Minor refactors (no decision-tree)
- Decisions captured fully in a feature CLAUDE.md (those are scoped, not architectural)

## What this skill does

1. Reads `docs/adr/INDEX.md` (auto-generated) for the next free `adr_id`.
2. Asks for the title (or accepts it as `$ARGUMENTS`).
3. Scaffolds `docs/adr/<NNNN>-<kebab-slug>.md` with the MADR-lite
   template + frontmatter:
   - `adr_id` (4-digit zero-padded)
   - `title`
   - `status` (default `proposed`; change to `accepted` when locked)
   - `date` (today, IST)
   - `deciders` (default `Upendra`)
4. Pre-fills the section skeleton:
   - Context
   - Decision
   - Alternatives considered (THIS IS THE HIGH-VALUE SECTION — the
     rejected paths + reasons)
   - Consequences (Good / Bad)
   - Status
   - See also
5. Runs `scripts/validate_adr.dart <new-file>` to confirm frontmatter
   integrity.
6. Reminds operator to regenerate `docs/adr/INDEX.md` via
   `scripts/build_adr_index.dart` (or `/update-docs` does this).

## Template

```markdown
---
adr_id: NNNN
title: <One-line title>
status: proposed
date: YYYY-MM-DD
deciders: Upendra
---

# ADR-NNNN: <Title>

## Context

<Why this decision needed making. What forces / constraints applied.>

## Decision

<What we decided. One paragraph, plus a code-fenced "encoded in X" pointer if applicable.>

## Alternatives considered

1. **<Alternative A>.** Rejected/Considered.
   - <Reason>
   - <Reason>

2. **<Alternative B>.** Rejected.
   - <Reason>

## Consequences

Good:
- <Positive consequence>

Bad:
- <Negative consequence + mitigation if any>

## Status

Active | Superseded by NNNN | Deprecated.

## See also

- <Pointer to CLAUDE.md section / handbook / related ADR>
```

## Red flags (when you're about to write an ADR you shouldn't)

| Symptom | Reality |
|---|---|
| "This is just a small refactor" | Refactors don't need ADRs. Skip. |
| "I'll add the alternatives later" | The alternatives ARE the value. Write them now or don't write the ADR. |
| "I don't remember the rejected options" | Then the ADR will be low-value. Talk to founder + dig through brainstorms first. |
| "Status: accepted, deciders: Claude" | An ADR with no human decider is suspect; ADRs codify human judgment. |

## Self-evolution

When a future batch surfaces a new ADR pattern (e.g., "every ADR
touching a CATASTROPHIC-tier path needs a `requires: hermes_pass`
line"), update this skill's template + add the new check to
`scripts/validate_adr.dart`. Append a changelog entry below.

## Changelog

- 2026-05-28: Initial. 10 historical ADRs (0001-0010) backfilled in
  the same batch.
