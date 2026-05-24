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
