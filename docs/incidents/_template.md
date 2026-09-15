---
incident_id: <6-char hex, generated>
status: detected | mitigated | resolved | post-mortem
detected_at: <IST ISO8601>
mitigated_at: <IST ISO8601 or null>
resolved_at: <IST ISO8601 or null>
blast_radius: feature | account | platform | catastrophic
users_affected: <integer or "unknown">
impact_summary: <one-line user-visible impact>
contributing_factors:
  - <factor 1>
  - <factor 2>
detection_path: <how it was caught — alert / dm / self-noticed>
resolution: <one-line summary of the fix>
prevention:
  - <action 1: ship a gate, add a test, document a rule>
  - <action 2>
linked_diagnose_docs:
  - <docs/diagnoses/YYYY-MM-DD-slug-id.md>
linked_alerts:
  - <alerts.id integer references, if surfaced via alert>
---

# Incident <incident_id> — <one-line title>

## Timeline (IST)

- `<detected_at>` — Detected.
- `<mitigated_at>` — User-visible impact stopped (workaround / rollback).
- `<resolved_at>` — Root cause fixed.
- `<now>` — Post-mortem written.

## What happened

<2-3 paragraph narrative. Plain English; this is read by future-you
who has no context. Cite file:line for every claim.>

## User impact

<Who saw what. How many. For how long. Specific symptoms.>

## Root cause

<The actual bug. Not just "X was broken" — the chain of decisions /
state that allowed it to ship.>

## Why our gates didn't catch it

<Honest assessment. Was there a test that should have failed? A gate
that didn't run? An audit lens that wasn't applied? This section is
the highest-value part of the doc.>

## Resolution

<What was changed, by which commit / migration / EF deploy.>

## Prevention

<New gate / test / rule / audit-lens that catches this class in
future. If none — explicitly note why (e.g., "this is a third-party
service failure; we accept the residual risk").>

## Linked artifacts

- Diagnose docs: ...
- Commits: ...
- Migrations: ...
- Edge Function versions: ...

## Self-evolution notes

<If this incident surfaced a new bug class, did we promote it to
docs/handbook/bug-classes/? Did we add to debugging skill's "Bug
classes" table? Did CLAUDE.md gain a new rule? Cite the commits.>
