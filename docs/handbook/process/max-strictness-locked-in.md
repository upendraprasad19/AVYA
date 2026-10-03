---
title: Max-strictness locked in — don't re-offer weaker options later
category: process
source_memory: feedback_max_strictness_locked_in.md
last_reviewed: 2026-05-28
---

# Max-strictness locked in — don't re-offer weaker options later

## The rule

When max-strictness is locked early in a brainstorm (e.g. "enforce all six failure modes mechanically"), every subsequent menu starts at that level — never below it. Stepping back is a regression of the conversation and implicitly walks back the prior decision.

## How to detect the violation

You're about to violate this rule when:

- You catch yourself drafting a "Light / Medium / Heavy" tier list mid-brainstorm.
- You're mechanically applying a "propose 2-3 approaches" rule from a brainstorming skill without checking whether the prior turn's decisions foreclosed some of those options.
- The implicit offer is "you could relax this if you want" after the user already chose "no, don't relax it."

## Prevention

1. **Before proposing options in any brainstorm question**, scan the running spec / prior turns of the same brainstorm. If the lead has locked a maximum-strictness / "enforce all" / "foolproof" position, all subsequent option lists MUST start at that level.

2. **The "propose 2-3 approaches" rule is satisfied** by 2-3 approaches AT OR ABOVE the locked floor. For an L3 lock — offer L3, L4 (even more rigorous), L5 (paranoid). Or just present L3 as a single proposal with rationale.

3. **If only ONE option is sane given prior locks**, present that one option WITH the rationale for why nothing weaker is on the table. Don't manufacture fake variants for the sake of "2-3 approaches."

4. **Generalization beyond brainstorming.** Same principle applies to code-review options, refactor scopes, test coverage choices, agent dispatch fan-out. Any time max-mode has been set, every subsequent menu starts at max.

## The skill-rule clarification

"Propose alternatives" rules in skills are not absolute. They're a default for when the user's preference is unknown. Once a strong preference is stated (max strictness, max coverage, max parallelism, etc.), the alternatives menu becomes a one-element list — and that's correct, not a violation of the skill.

## References

- Related: [`no-deferrals.md`](no-deferrals.md), [`observation-workflow.md`](observation-workflow.md).
- Skill: `superpowers:brainstorming` (apply with context-awareness, not mechanically).
