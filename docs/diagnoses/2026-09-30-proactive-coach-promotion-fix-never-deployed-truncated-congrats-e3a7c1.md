---
bug_id: e3a7c1
date: 2026-09-30
batch: gemini-quota-promotion-message
status: fixed
blast_radius: platform
symptom: |
  Founder APK screenshot (2026-09-30 09:25 IST): the coach chat shows a rank
  promotion message cut off mid-sentence -- "Congratulations, Upendra! Your
  dedication to your" (49 chars, LS promotion, ai_coach_interactions row
  created 2026-09-30 03:41 UTC). Live query showed EVERY proactive_promotion
  row since 2026-09-16 is 29-59 chars long and carries model_used =
  'gemini-2.5-flash'. The template fix (f4d771d2, diagnose b7c9e2, in
  origin/main since 2026-09-16) writes model_used = 'congrats_template' and
  never produces that copy, so the deployed function was NOT the fixed code.
concept: proactive_coach_promotion_congrats
sot_registry_entry: |
  No sot_registry.yaml entry -- same reasoning as sibling b7c9e2/a1f7d3
  (same-process synchronous write, not a cross-layer pair). The gap here is
  git-vs-deployed drift, which is a process gap, not a writer/reader field pair.
writers:
  - { file: supabase/functions/proactive-coach-promotion/index.ts, method_or_widget: "ai_coach_interactions insert (ai_response = composeCongrats output)", line: 125 }
readers:
  - { file: lib/core/services/sync/sync_coach.dart, method_or_widget: "coach sync-down maps ai_response verbatim into the local entry (no truncation client-side)", line: 243 }
hive_key_prefix: "n/a"
hive_key_formula: "n/a -- the defect is in the server-written ai_response value; the client displays it verbatim."
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [ai_response, model_used]
contract_test_path: supabase/functions/proactive-coach-promotion/index_test.ts
ist_handling:
  - "Not applicable -- no date keys involved."
provider_invalidations: []
telemetry_op_types:
  success: [proactive_coach_promotion_dispatched]
  failure: [proactive_coach_promotion_failed]
cross_account_guard: "Row repair is scoped by row id, only rows with tool_calls.kind = 'proactive_promotion' AND model_used = 'gemini-2.5-flash'."
forbidden_patterns_checked:
  - { pattern: 'generativelanguage.googleapis.com in proactive-coach-promotion (the deployed v11 shape)', absent: true }
recurrence:
  - "Not a writer/reader field drift. Related class: gemini_flash_reliability (diagnose 7fbe21) -- hidden thinking tokens consume maxOutputTokens; the deployed v11 used a raw fetch with maxOutputTokens: 256 and no thinkingBudget: 0, so replies stopped after ~50 chars."
  - "New class: FIX-MERGED-BUT-NEVER-DEPLOYED. Diagnose a1f7d3 (2026-09-16) itself records 'changed in this worktree but NOT yet deployed'; nothing later closed that loop."
proposed_fix: |
  (1) Deploy proactive-coach-promotion from main (already contains the
  deterministic composeCongrats). (2) Repair the truncated rows by rewriting
  ai_response with composeCongrats output and model_used = 'congrats_template'.
  (3) Add deploy-verification bug-class 6.10 to the deploy skill so a merged
  EF fix is not called done until the LIVE row shape is checked.
regression_test_planned:
  - "supabase/functions/proactive-coach-promotion/index_test.ts (existing, 8/8) pins the SOURCE shape; it cannot see deployment. Post-deploy live check: no proactive_promotion row created after the deploy carries model_used = 'gemini-2.5-flash' or ai_response shorter than 80 chars."
impact_analysis: |
  Scope: one Edge Function redeploy plus a one-off data repair on
  ai_coach_interactions (5+ founder/test rows). Client display, OneSignal push
  payload and the trigger are unchanged. The push preview is sliced to 80
  chars, so pushes were also truncated-then-elided.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "grep lib/ for 'Your dedication' and proactive_promotion found no client-side copy or truncation; the bubble renders ai_response as stored." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "select over ai_coach_interactions where tool_calls->>'kind'='proactive_promotion': every row since 2026-09-16 has len 29-59 and model_used gemini-2.5-flash." }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "MCP get_edge_function on proactive-coach-promotion returned v11 source containing generativelanguage.googleapis.com, maxOutputTokens: 256 and model_used: \"gemini-2.5-flash\" with 0 occurrences of congrats_template; git HEAD (== origin/main, 0 behind) has the template version." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "The fixed function makes no Gemini call, so GEMINI_API_KEY is irrelevant to it." }
---

## Summary

The promotion copy was truncated because production still ran the pre-2026-09-16
Gemini implementation. That version called Gemini 2.5 Flash through a raw `fetch`
with `maxOutputTokens: 256` and no `thinkingBudget: 0`; hidden thinking tokens ate
the budget and the visible reply stopped after about 50 characters. The fix
(template-only copy, `f4d771d2`) merged on 2026-09-16 but the deploy was never
authorised or run, and the earlier diagnose-doc a1f7d3 recorded it as "NOT yet
deployed" with no follow-up.

## Bug-history lookup (CLAUDE.md 4.1.5)

Grepped `docs/diagnoses/INDEX.md` for promotion/truncat/maxOutputTokens: b7c9e2 and
a1f7d3 (same function, the fix), 7fbe21 (thinking tokens vs maxOutputTokens, the
mechanism). Recurrence of the 7fbe21 mechanism in a function outside `_shared/gemini.ts`;
the deploy gap is new.

## Root cause

**Writer:** deployed `proactive-coach-promotion` v11 `index.ts` insert (model_used
`gemini-2.5-flash`, ai_response truncated by the token cap).
**Reader:** coach sync-down and chat bubble, which display `ai_response` verbatim.
The client is not at fault.

## Fix

Redeploy from `main` (payload emitted from a worktree at 0 behind `origin/main`),
then repair stored rows with the deterministic `composeCongrats` output. Deploy and
row repair each need their own live-apply authorisation; see Verification for state.

## Verification

- `deno check --node-modules-dir=none supabase/functions/proactive-coach-promotion/index.ts` clean.
- `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/proactive-coach-promotion/` 8/8.
- **Deployed 2026-09-30 by the founder** (host shell, `deploy_via_api.js`, token from
  `SUPABASE_ACCESS_TOKEN_FITNESS` = the file token, HTTP 200 vs the stale
  `SUPABASE_ACCESS_TOKEN` env var HTTP 403): HTTP 201, v11 -> **v17**, `ezbr_sha256`
  `ab1f94e0...`, smoke 401 (auth-gated, reachable). MCP `get_edge_function` on v17 shows
  `composeCongrats`, `model_used: "congrats_template"` and no `generativelanguage` call.
  Rollback payload archived at `backups/edge_function_payloads/proactive-coach-promotion/v4_6f22cbd.json`.
- **Row repair (founder scope call: own row only):** one UPDATE scoped by id + user_id +
  `model_used = 'gemini-2.5-flash'` on the founder's LS row `545f92d2-...`, using the
  `composeCongrats` variant 1 text (35 workouts, 4 weeks, fat loss); 1 row returned,
  `model_used = 'congrats_template'`, 160 chars. The other 17 truncated rows (other users,
  no historical stats available) were deliberately left alone. Whether the device re-reads
  an updated cloud row (vs keeping its local copy) is NOT verified.
- **Still owed:** a post-deploy LIVE row (next real promotion) showing
  `model_used = 'congrats_template'`.
- No new test was added: the SOURCE shape is already pinned. The gap was deployment,
  which no offline test can observe; protection is the bug-class 6.10 live-row check.
  Self-attested, no gate.
