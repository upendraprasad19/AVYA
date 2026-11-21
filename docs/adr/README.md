# Architecture Decision Records (ADRs)

> Track 4 of the 2026-05-28 six-industry-gap closure batch.
> Convention: MADR-lite. Each ADR captures ONE architectural decision.

## When to write an ADR

> Test: "If someone proposed reverting this decision 6 months from now, would I have to re-do the analysis?" — yes → write an ADR.

Good ADR targets:
- Tool / framework / library choice (Hive, Riverpod, Razorpay, Supabase, Gemini)
- Architectural pattern (offline-first, writer-services, sync-fan-out, IST-throughout)
- Rules in CLAUDE.md §4.4 with non-obvious justification
- Decisions that have multiple viable alternatives where rejection reasons matter

Bad ADR targets (these are different artifacts):
- Bug fixes → `docs/diagnoses/<bug-id>.md`
- UI tweaks → batch retrospective
- Per-batch implementation decisions → `docs/superpowers/specs/<batch>.md`
- One-off pragmatic choices that don't constrain future work

## Filename convention

`docs/adr/NNNN-kebab-case-title.md`

- Monotonically increasing 4-digit number (`0001`, `0002`, ...)
- Letter suffix only if you need to insert one between two existing numbers without renumbering (rare)
- Title is short noun-phrase, lowercase, kebab-case

## Frontmatter (MADR-lite)

Required fields:

```yaml
---
adr_id: NNNN
title: <short noun-phrase>
status: <proposed|accepted|superseded by NNNN|deprecated>
date: YYYY-MM-DD
deciders: <name(s)>
---
```

Required sections (body):

```markdown
## Context
<What's the situation forcing this decision? What constraints?>

## Decision
<What did we choose? Stated in active voice.>

## Alternatives considered
<What else did we look at, and why did we reject each? THIS IS THE MOST VALUABLE SECTION.>

1. **<Alternative 1>** — rejected because <reason>.
2. **<Alternative 2>** — rejected because <reason>.

## Consequences
<What changes because of this decision? Both good and bad.>

Good:
- ...

Bad:
- ...
```

## Tooling

- **Scaffold a new ADR:** `/adr` (skill: `.claude/skills/adr/SKILL.md`) — opens template with next-free number + IST date
- **Validate:** `dart run scripts/validate_adr.dart <path>`
- **Build index:** `dart run scripts/build_adr_index.dart` → `docs/adr/INDEX.md`
- **Gate:** `scripts/check_adr_index_fresh.dart` (in pre-commit's gate loop)

## Status workflow

- `proposed` — open for review; not yet authoritative
- `accepted` — currently in force
- `superseded by NNNN` — explicit pointer to the ADR that replaced this one; old ADR stays in repo for traceability
- `deprecated` — no longer applies but no successor (rare)

## Lineage

When an ADR supersedes another, edit BOTH files:
- New ADR's `## Context` cites the old ADR number + reason for the change
- Old ADR's status becomes `superseded by NNNN`

This lineage is what makes ADRs valuable 2 years out — you can trace the evolution.

## Backfill set

The initial 10 ADRs (0001-0010) backfill historical decisions made before this convention existed. They're drafted from CLAUDE.md, architecture docs, and memory `project_*.md` retrospectives. Backfill convention:

- `date:` is the original decision date if known, else the date the rule landed in CLAUDE.md
- `deciders:` is "Upendra" (solo founder)
- `## Alternatives considered` cites historical context where retrievable; placeholder + "(reconstructed, not original analysis)" if not

Going forward, write ADRs as decisions are made — don't backfill except for foundational changes.
