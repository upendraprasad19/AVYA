---
reviewed_at: 2026-06-08T17:40:00+05:30
staged_against: b7c8040
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 3
verdict: accepted
---

# Code Review (B-pass) — b7c8040

`fix(ai-proxy): accept recompose in regeneratePlanBlock goal enum + server goal-enum gate`.
About to deploy `ai-proxy` to prod + push to origin/main. Fresh context-blind Sonnet
reviewer. All 5 lenses + 3 change-specific correctness concerns. Lenses 2/4/5 clean;
lens 1 (writer/reader drift) clean with a P2 asymmetry; lens 3 surfaced the P1.
The reviewer independently verified the gate regex (no `equipment:`/intentBuilder
mis-match), the token parse (non-vacuous, all 5 tokens), and the `describe()` text
(no stale goal enumeration) — no false-greens.

## Finding 1 — P1 — blast_radius_mismatch — diagnose-doc metadata mislabeled
- **file:line:** docs/diagnoses/2026-06-08-ai-proxy-regenerate-goal-enum-missing-recompose-a4f7e1.md:6
- **claim:** frontmatter `blast_radius: account`, but the change edits `supabase/functions/**` (platform tier per docs/blast_radius.yaml + the pre-commit hook's own computation). Under-classification if tooling reads the field.
- **verification:** `dart run scripts/blast_radius_from_diff.dart` on the staged set → platform; CLAUDE.md registry maps `supabase/functions/**` to platform.
- **suggested-fix:** `blast_radius: account` → `blast_radius: platform`.
- **status:** fixed (this batch)

## Finding 2 — P2 — writer_reader_drift (defense-in-depth asymmetry) — regeneratePlanBlock dispatch lacked the isKnown guard
- **file:line:** lib/features/ai_coach/services/tool_dispatcher.dart `_executeRegeneratePlanBlock` (~666)
- **claim:** `_executeSwitchGoal` guards `FitnessGoals.isKnown(newGoal)` before writing; `_executeRegeneratePlanBlock` did not. An unknown goal would flow to PlanGenerator, which in release silently falls back to general_fitness (the `assert` fires only in debug) and the tool reports success — the F19 silent-fallback class. No current bug (all 5 tokens known; the new gate Check 4 prevents the server enum from drifting), but an asymmetric drift window.
- **verification:** read both methods; `_executeSwitchGoal` has the guard at ~798, `_executeRegeneratePlanBlock` had none; `FitnessGoals.of` falls back to general_fitness for unknown tokens in release.
- **suggested-fix:** mirror the guard at the entry of `_executeRegeneratePlanBlock` reading `intent.payload['goal']`.
- **status:** fixed (this batch — guard added reading `intent.payload['goal']`, returns `ToolExecutionResult.failure('Unsupported goal: …')`; symmetry pinned by a new presence test in `ai_proxy_goal_enum_parity_test.dart`)

## Finding 3 — P2 (soft) — `_humanGoal` uses `default:` for recompose, no explicit case
- **file:line:** lib/features/ai_coach/widgets/diff_preview/regenerate_plan_diff.dart `_humanGoal` (~241); switch_goal_diff.dart `_humanGoal` (~268)
- **claim:** recompose is labelled via the `default:` arm → `FitnessGoals.isKnown(raw) ? FitnessGoals.label(raw) : raw`. Correct + functional today; the soft risk is showing the raw token if `isKnown` ever returned false. No current bug, no missing blocking test.
- **verification:** read both widgets; the default arm resolves recompose via `FitnessGoals.label`, which returns "Recomposition" for the canonical token.
- **suggested-fix:** none required — the pattern is intentional (commented) and the token-known guarantee (enforced by the parity test + the SoT) makes the fallback path unreachable for recompose.
- **status:** false_alarm (intentional pattern; covered by the FitnessGoals SoT + parity test)

## Founder triage notes
Self-triaged during the autonomous B-pass (founder authorized the ai-proxy deploy:
"switchGoal recompose enum that ships on the next ai-proxy deploy — lets do this").
Finding 1 + 2 fixed in-batch per no-deferrals (§4.2); Finding 3 is an intentional,
SoT-covered pattern → false_alarm. Lens false-alarm rate 1/3 (Finding 3) is within
tolerance for a 3-finding pass; the noisy lens was lens 1's soft sub-finding, not a
systemic lens problem — no tuning. Verdict: accepted.
