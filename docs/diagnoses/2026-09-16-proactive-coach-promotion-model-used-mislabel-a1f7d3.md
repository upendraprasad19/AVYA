---
bug_id: a1f7d3
date: 2026-09-16
batch: cron-ai-removal
status: fixed
blast_radius: platform
symptom: |
  `proactive-coach-promotion`'s `ai_coach_interactions` insert hardcoded
  `model_used: "gemini-2.5-flash"` unconditionally, unchanged by this
  batch's earlier fix (`f4d771d2`, diagnose `b7c9e2`) that removed the
  Gemini call entirely and replaced `composeCongrats` with a pure,
  synchronous, deterministic template. Every rank-promotion celebration
  since that fix landed is now mislabelled in the very ledger a
  post-429-incident batch should want accurate — any future audit that
  greps `ai_coach_interactions.model_used` to count real Gemini spend
  would over-count `proactive-coach-promotion`'s contribution by 100%
  (it now makes zero Gemini calls). Two sibling functions already
  established the correct convention for a deterministic, non-AI
  message: `evaluate-rank-promotions` writes `model_used:
  "ceremony_template"` and `i-see-you-callout` writes `model_used:
  "i_see_you_template"` — this fix commit did not apply that convention
  here. Caught by an independent context-blind plan-review round
  (CLAUDE.md §4.12, Round 2) dispatched on the post-b7c9e2 state,
  verified against the live file content before acting on it.
concept: proactive_coach_promotion_congrats
sot_registry_entry: |
  No existing docs/sot_registry.yaml entry covers this concept (per the
  same reasoning recorded in the sibling b7c9e2 diagnose-doc — a
  same-process synchronous field write, not a cross-layer writer/reader
  pair the registry exists to pin). Not adding one here either.
writers:
  - { file: supabase/functions/proactive-coach-promotion/index.ts, method_or_widget: "ai_coach_interactions insert — model_used field, now congrats_template matching the sibling ceremony_template/i_see_you_template convention", line: 129 }
readers:
  - { file: supabase/functions/evaluate-rank-promotions/index.ts, method_or_widget: "sibling convention reference — its own ai_coach_interactions insert already uses model_used: 'ceremony_template' for its own deterministic, non-AI message", line: 329 }
hive_key_prefix: "n/a"
hive_key_formula: "n/a — server-side Edge Function only. model_used is a plain string column on ai_coach_interactions, no Hive involvement."
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [model_used]
contract_test_path: supabase/functions/proactive-coach-promotion/index_test.ts
ist_handling:
  - "Not applicable — no date keys or clock-derived values involved in this fix."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — the insert is already scoped to the single triggering user's own user_id (unchanged by this fix)."
forbidden_patterns_checked:
  - { pattern: 'model_used: "gemini-2.5-flash" (the mislabel this fix removes)', absent: true }
proposed_fix: |
  Change the hardcoded model_used value from "gemini-2.5-flash" to
  "congrats_template", matching the established sibling convention
  (evaluate-rank-promotions' "ceremony_template", i-see-you-callout's
  "i_see_you_template") for a deterministic, non-AI-generated proactive
  message written into the same ai_coach_interactions table.
regression_test_planned:
  - "supabase/functions/proactive-coach-promotion/index_test.ts — new source-shape test asserting the literal model_used: \"gemini-2.5-flash\" string is gone and model_used: \"congrats_template\" is present."
impact_analysis: |
  Scope: proactive-coach-promotion is platform-tier
  (docs/blast_radius.yaml's supabase/functions/** catch-all). This fix
  changes only the value written to one column (model_used) on one
  insert — it does not touch the congrats copy itself, the OneSignal
  push, the trigger, or any read path. The client-side coach sync
  (sync_coach.dart) reads ai_coach_interactions rows down but does not
  branch on model_used (confirmed by grep — no client reference to that
  column), so this is purely an observability/audit-accuracy correction
  with no user-visible behavior change.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "Server-side Edge Function only; grepped lib/ for model_used — no client code reads this column." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "supabase/functions/proactive-coach-promotion/index.ts changed in this worktree but NOT yet deployed — deploy requires separate explicit founder authorization per CLAUDE.md §4.3. deno check --node-modules-dir=none passed clean; deno test --no-check --allow-all --node-modules-dir=none supabase/functions/proactive-coach-promotion/ passed 8/8." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "model_used is a free-text audit/observability column; its value is never contractually consumed by the client." }
---

## Summary

A Round 2 CLAUDE.md §4.12 context-blind plan-review pass, dispatched on
the state after this batch's first two bug fixes (`b7c9e2`, `9c3d7a`)
landed, found that `f4d771d2`'s composeCongrats rewrite (removing the
Gemini call) left the `ai_coach_interactions` insert's `model_used` field
still hardcoded to `"gemini-2.5-flash"` — a stale label the fix commit
should have updated but didn't. Independently re-verified against the
live file (index.ts:129) and against the two sibling functions' actual
conventions (grepped, not assumed) before acting.

## Bug-history lookup (CLAUDE.md §4.1.5)

Grepped `docs/diagnoses/INDEX.md` for "model_used" — no prior diagnose-doc
on this exact field. Not a recurrence of a previously-diagnosed bug; a
gap this batch's own earlier fix (`b7c9e2`) introduced by omission
(removing the Gemini call without updating the label describing it).

## Root cause (writer + reader named before proposing, per CLAUDE.md §4.1)

**Writer:** `proactive-coach-promotion/index.ts`'s `ai_coach_interactions`
insert (line 129, pre-fix) — hardcoded `model_used: "gemini-2.5-flash"`,
unchanged since before `f4d771d2` removed the actual Gemini call this
label described.

**Reader:** any future audit or dashboard query that groups/filters
`ai_coach_interactions` by `model_used` to measure real Gemini call
volume (the exact metric a post-429-incident batch should want
accurate) — would count every `proactive-coach-promotion` event as a
Gemini call, when the function makes none.

Not a writer/reader field-name drift; a stale VALUE left behind when the
underlying behavior it described changed.

## Fix

Changed the hardcoded value to `"congrats_template"`, matching the
established convention two sibling functions already use for their own
deterministic, non-AI proactive messages
(`evaluate-rank-promotions/index.ts:329` → `"ceremony_template"`,
`i-see-you-callout/index.ts:123` → `"i_see_you_template"`).

## Verification

`deno test --no-check --allow-all --node-modules-dir=none supabase/functions/proactive-coach-promotion/`
— 8/8 passed. `deno check --node-modules-dir=none supabase/functions/proactive-coach-promotion/index.ts`
— clean.

**Mutated and run** (rule 21): the new test was written FIRST against the
pre-fix source and confirmed to fail (`model_used: "gemini-2.5-flash"`
still present) — the natural pre-fix state itself is the mutation proof,
reddening exactly the 1 new test while the other 7 stayed green. Applying
the one-line fix turned it green (8/8). Not re-mutated separately since
the pre/post states already demonstrate the exact before/after the test
is meant to distinguish.

## Related

Sibling fixes in the same batch: `b7c9e2` (proactive-coach-promotion's
missing fallback — the fix that introduced this stale label as a side
effect) and `9c3d7a` (future-prediction's streak-weeks zero-schedule
collapse) — both from earlier review rounds on this same branch.
