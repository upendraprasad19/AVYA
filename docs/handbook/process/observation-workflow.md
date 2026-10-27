---
title: Observation handling — wait, brainstorm, plan, work
category: process
source_memory: feedback_observation_workflow.md
last_reviewed: 2026-05-28
---

# Observation handling — wait, brainstorm, plan, work

## The rule

When the user starts giving observations from on-device APK testing (or any test session that produces a list of issues):

1. **Wait for ALL observations before acting.** Do not jump to fixes after the first one or two items. Acknowledge the observation, capture it, and explicitly invite the next one.
2. **Once the user signals they're done listing**, invoke the brainstorming skill.
3. **For EACH observation, the brainstorm must answer:**
   - Why did this happen? (root cause, not symptom)
   - Was this issue fixed in a past batch? (search bug history + memory files for prior bugs of this class)
   - If yes, why isn't the fix in effect? (regression / partial fix / new code path / wrong location)
   - What's the proposed solution?
4. **Present all root-causes + solutions together** for review.
5. **Only after approval of the brainstorm output**, write a spec + implementation plan.
6. **Only after plan approval**, start implementation.

## Why

APK testing produces interrelated observations. Fixing them one-at-a-time fragments the response, misses root-cause patterns (e.g. a single bug class can produce 4 superficially-different observations), and burns context on diagnoses that get re-done when the next observation lands.

Patterns like "the same bug class keeps re-surfacing across surfaces" are only visible when you look at the whole batch.

## How to apply

- **Trigger phrases:** "i tested the apk", "i installed the app and noticed", "i have observations", "few more inputs", numbered observation lists ("1. ... 2. ...").
- Even if the user pastes an obvious one-liner bug, ASK whether more observations are queued before invoking any brainstorm or fix.
- **The only exception:** the user explicitly asks for an immediate fix on a single isolated item ("just fix this one thing now"). In that case, fix + return to wait-for-more-observations posture.
- **Emergencies** (data loss, security, app-bricking crash) on a SINGLE observation: surface the urgency and ask whether to hot-fix or wait. Don't just hot-fix without checking.
- Brainstorm output should be a structured table per observation: `{observation, root_cause, prior_fix_attempt, why_not_fixed, proposed_solution}`. Then ask which solutions to lock.
- Spec + plan only AFTER all observations are locked. Do not interleave brainstorming + implementation.

## References

- CLAUDE.md §4.1 (observation/bugfix workflow).
- Skill: `superpowers:brainstorming`, `superpowers:writing-plans`.
- Related: [`no-deferrals.md`](no-deferrals.md), [`sot-audit-required.md`](../bug-classes/sot-audit-required.md).
