---
bug_id: b6e2a4
date: 2026-09-20
batch: food-logging-observations (fix round, B-pass reviewer A finding 1)
status: fixed
blast_radius: platform
symptom: |
  Tasks 9-10 of this batch (commits 72a4aa7d, c84eb796) added
  `reportGeminiExhaustion` — a new write into the `public.alerts` table,
  reused by the existing `trg_dispatch_critical_alert_notify` trigger
  (migration 133) to push a Telegram message to the founder on every
  terminal Gemini failure across 3 ai-proxy request types. Both touched
  paths (`supabase/functions/_shared/gemini_failure_alert.ts` and the 3
  call sites in `supabase/functions/ai-proxy/index.ts`) fall under the
  `supabase/functions/_shared/**` and `supabase/functions/ai-proxy/**`
  globs in docs/blast_radius.yaml, both `platform`-tier, whose
  `requires:` list includes `feature_flag` (root CLAUDE.md §4.6). No such
  gate existed — a founder with no prior experience of this alert volume
  had no way to silence it without a code change and redeploy if it
  turned out to be noisy (e.g. a real Gemini outage spamming the same
  Telegram channel `founder-digest` and `alert-critical-notify` already
  use). Found by B-pass reviewer A (lens 3, blast_radius_mismatch),
  verified via a repo-wide grep for feature_flag/kDebugMode/RemoteConfig
  hits in the diff (zero).
concept: gemini_failure_alert
sot_registry_entry: not_applicable
writers:
  - { file: supabase/functions/_shared/gemini_failure_alert.ts, method_or_widget: reportGeminiExhaustion, line: 32 }
readers:
  - { file: supabase/functions/ai-proxy/index.ts, method_or_widget: food_text_analysis handler, line: 443 }
hive_key_prefix: (n/a — server-side Edge Function, no Hive involvement)
hive_key_formula: (n/a)
sync_methods: []
restore_methods: []
cloud_table: alerts
cloud_columns: [source, severity, summary, context_json, suggested_action]
contract_test_path: supabase/functions/_shared/gemini_failure_alert_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — this is a founder-only admin alert, not user data; the `alerts` table is not user-scoped.
forbidden_patterns_checked: []
proposed_fix: |
  Add a `DISABLE_GEMINI_FAILURE_ALERT` Deno environment secret check at
  the top of `reportGeminiExhaustion`, returning immediately (before any
  Supabase call) when set to `"true"`. Matches the existing server-side
  pattern of gating new/risky behavior behind an env var the founder can
  flip from the Supabase dashboard's Edge Function secrets UI without a
  redeploy of the function body (the redeploy IS needed to pick up a new
  secret read, but not to change the gate's value once the check exists).
regression_test_planned:
  - supabase/functions/_shared/gemini_failure_alert_test.ts
impact_analysis: |
  Purely additive: one guard clause at function entry, before any
  Supabase client call. No behavioral change when the env var is unset
  (the default) — every existing classify/dedup/insert behavior from
  Task 9/10 is unchanged. When set, the function becomes a no-op,
  restoring the pre-Task-9/10 behavior (terminal Gemini failures still
  return the same client-facing error text; only the admin-only Telegram
  side-channel is silenced). No client-facing contract change either way.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "This function runs server-side only (supabase/functions/_shared/); no lib/ code touched." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check --node-modules-dir=none supabase/functions/_shared/gemini_failure_alert.ts passes with 0 errors. NOT yet deployed — per this batch's standing instruction, the live ai-proxy deploy is a separate, founder-authorized action that has not been requested." }
  - { tier: 10, name: "Secrets / API keys", status: fixed_in_this_batch, evidence: "DISABLE_GEMINI_FAILURE_ALERT is read via Deno.env.get with no default-true fallback — absence (the normal state before the founder ever sets it) is functionally identical to explicit 'false', preserving Task 9/10's behavior for every existing deployment until the founder opts out." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "The client-facing ai-proxy response shape is unchanged in both the flag-set and flag-unset cases — this alert is a founder-only side channel with no client-visible effect either way." }
mutation_proven:
  mutated: "Replaced the guard line `if (Deno.env.get(\"DISABLE_GEMINI_FAILURE_ALERT\") === \"true\") return;` with a no-op comment, confirmed applied by reading the file."
  result: "Ran `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/_shared/gemini_failure_alert_test.ts`: RED — 'DISABLE_GEMINI_FAILURE_ALERT=true skips the alert entirely' failed (expected 0 inserted rows, got 1), 6 passed / 1 failed. Reverted the mutation; re-ran the full file: GREEN, 7/7 passed."
  confirmed_applied: "Read the file (Read tool) before and after each edit to confirm the guard line's presence/absence matched the intended mutation, not just grepped for a string."
---

## Summary

Tasks 9-10 of this batch added a new admin-only Telegram alert on terminal Gemini
failures across the 3 nutrition AI endpoints. Both touched files
(`_shared/gemini_failure_alert.ts`, `ai-proxy/index.ts`) are `platform`-tier per
`docs/blast_radius.yaml`, which requires a `feature_flag` for any change at that tier —
none existed, so the founder had no way to silence a potentially noisy new alert
channel without a code change and redeploy.

## Root cause

Task 9/10's own review (documented in the SDD ledger) explicitly assessed the "never
throws" guarantee and the mechanical, branch-free nature of the wiring as making the
change low-risk — a reasonable functional-correctness judgment, but orthogonal to
the blast-radius registry's structural requirement, which applies to the FILE'S tier
regardless of how confident a specific change's author is in its safety. `ai-proxy`
and `_shared/**` are platform-tier by path; any new platform-tier behavior needs a
feature flag as a matter of process, not a case-by-case risk call.

## Fix

Added a `DISABLE_GEMINI_FAILURE_ALERT` Deno environment-secret check at the top of
`reportGeminiExhaustion`, returning before any Supabase client call when set to
`"true"`. Unset (the default across every existing deployment), behavior is
unchanged from Task 9/10.

## Verification

- New test: with `DISABLE_GEMINI_FAILURE_ALERT=true`, `reportGeminiExhaustion` inserts
  zero rows into `alerts`.
- New mirror test: with the env var unset/deleted, the function still alerts exactly
  as before (1 row inserted) — the mirror case for the new guard (B-pass lens 6,
  guard_without_its_mirror).
- Mutation proof: removed the guard clause — the "skips the alert entirely" test
  caught it (expected 0 inserted, got 1); reverted, 7/7 green again.
- `deno check --node-modules-dir=none supabase/functions/_shared/gemini_failure_alert.ts`
  — 0 errors.

## Files changed

- Modified: `supabase/functions/_shared/gemini_failure_alert.ts` (added the
  `DISABLE_GEMINI_FAILURE_ALERT` guard clause).
- Modified: `supabase/functions/_shared/gemini_failure_alert_test.ts` (added the
  flag-set and flag-unset-mirror tests).
- Created: this diagnose-doc.
