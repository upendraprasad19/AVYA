---
name: incident
description: Scaffold a production-incident post-mortem under docs/incidents/. Use when an alert fires or a user reports a production issue. Generates the template with IST timestamp + 6-char hex id, prompts founder through the frontmatter, links to relevant diagnose-docs.
type: process
priority: high
self-evolving: true
---

# /incident — Production-incident post-mortem scaffolding

## When to invoke

Invoke `/incident` when:
- A `public.alerts` row fires AND its severity is `warn` or `critical`
  AND it indicates a real user-visible problem (not a cron-auth
  hiccup that resolved itself).
- A user (DM, app store review, support email) reports a production
  issue that affected someone other than the founder testing.
- Self-noticed production breakage (data corruption, sync stuck, AI
  responses broken, payment flow degraded).

Do NOT invoke for:
- Bugs found in development before shipping (use diagnose-docs).
- Test failures (use diagnose-docs).
- Internal-only issues (founder's test device misbehaving).

## What this skill does

1. Generates a 6-char hex `incident_id` (e.g., `a3f2c1`).
2. Asks for a 1-line title.
3. Scaffolds `docs/incidents/<YYYY-MM-DD>-<slug>-<id>.md` from
   `_template.md`, pre-filling:
   - `incident_id` (generated)
   - `detected_at` (now, IST)
   - `status` (`detected`)
   - `blast_radius` (prompts: feature / account / platform /
     catastrophic — uses `docs/blast_radius.yaml` to suggest)
4. Asks founder to fill in the user-impact + initial hypothesis;
   skill saves and confirms path.
5. Reminds operator to:
   - Update `linked_alerts:` with the alerts row id (if surfaced via
     alert).
   - Run `scripts/validate_incident_doc.dart <path>` before commit.
   - Run `scripts/build_incident_index.dart` (or `/update-docs`).

## Status lifecycle

1. `detected` — incident scaffolded; root cause unknown or still
   being investigated.
2. `mitigated` — user-visible impact stopped (workaround, rollback,
   feature flag off). Set `mitigated_at:`.
3. `resolved` — root cause fixed in code/migration/EF deploy. Set
   `resolved_at:` + `linked_diagnose_docs:`.
4. `post-mortem` — the "Why our gates didn't catch it" + "Prevention"
   sections are complete + any preventive gate/test has shipped.

The doc is "done" at `post-mortem`. Anything earlier means follow-up
work is owed.

## Why this skill exists

In a solo-founder, pre-paying-user phase, "incidents" are theoretical.
Phase 1 alert infra ships 2026-05-28 with placeholder thresholds; Phase 2
re-tunes 2026-06-03. The first real incident is likely months away.
This skill exists so when it happens, the founder has a structured
landing pattern instead of an improvised note.

## Red flags

| Symptom | Reality |
|---|---|
| "It's just a small issue" | If it affected a user, it's an incident. |
| "I'll write the post-mortem later" | Write the `detected` shell now; finish later. Memory decays fast. |
| "blast_radius: feature" + payment flow | If payment touched it, it's catastrophic. Don't undersell. |
| Status: resolved but no `linked_diagnose_docs:` | The diagnose-doc IS the resolution receipt. Required. |
| Prevention: empty | The post-mortem isn't done. The "why gates didn't catch it" lens MUST produce at least one preventive action OR an explicit "accept residual risk" note. |

## Self-evolution

When a future incident surfaces a new failure mode not covered by
existing handbook bug-classes, the resolution batch MUST:
1. Add a new entry under `docs/handbook/bug-classes/`.
2. Cite the incident as the first instance.
3. Update `debugging` skill's bug-class table.
4. Append a changelog entry below.

## Changelog

- 2026-05-28: Initial. No incidents recorded yet.
