---
bug_id: d4c8e1
date: 2026-06-08
batch: psych-skill-and-audit-2026-06-07 (Batch 6 deploy — prod incident)
status: fixed
blast_radius: catastrophic
symptom: >
  During the Batch 6 audit deploy (2026-06-08), redeploying razorpay-webhook (the
  live Razorpay payment webhook) returned HTTP 503 BOOT_ERROR ("Function failed to
  start") on EVERY request — the webhook was DOWN. Root cause: commit ec01b46
  (2026-05-20) bumped std@0.177.0 to 0.224.0 across several Edge Functions while
  keeping `import { encode as hexEncode / base64Encode } from
  std@0.224.0/encoding/(hex|base64).ts`. The bare `encode` / `decode` exports were
  REMOVED from deno std encoding at 0.210, so the 0.224.0 module has no such export
  and module load throws at boot. The functions kept serving their pre-bump bundles,
  so the dead import stayed LATENT for ~19 days until this deploy (the first redeploy
  of razorpay-webhook) surfaced it. The same latent import sat in verify-payment,
  ai-media-proxy, and create-razorpay-order.
concept: std_encoding_dead_export_deploy_rot
sot_registry_entry: "n/a — EF dependency hygiene; subscriptions writer (razorpay-webhook) restored. Regression guard: scripts/check_std_encoding_import_rot.dart"
writers:
  - "{ file: supabase/functions/razorpay-webhook/index.ts, line: 33 } — encode import reverted to std@0.177.0 (payment webhook, redeployed v20)"
  - "{ file: supabase/functions/verify-payment/index.ts, line: 39 } — encode import reverted to std@0.177.0 (redeployed v14)"
readers:
  - "{ file: supabase/functions/ai-media-proxy/index.ts, line: 3 } — same latent import defused in source (not redeployed)"
  - "{ file: supabase/functions/create-razorpay-order/index.ts, line: 36 } — same latent import defused in source (not redeployed)"
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: subscriptions
cloud_columns: "n/a — runtime boot failure of the writer Edge Function, not a schema change"
contract_test_path: scripts/check_std_encoding_import_rot.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: "n/a — Razorpay webhook returned 503; Razorpay retries failed deliveries for 24h + the client verify-payment fallback also grants PRO, so no payment was lost in the window"
cross_account_guard: n/a
forbidden_patterns_checked: >
  scripts/check_std_encoding_import_rot.dart (new gate) bans `{ encode | decode }`
  imported from deno.land/std@>=0.210/encoding/(hex|base64) across all Edge
  Functions; PASS after the 4 reverts. The other 28 functions on std@0.224.0
  /http/server `serve` are FINE — `serve` is deprecated-but-still-exported there
  (confirmed by i-see-you-callout deploying cleanly on 0.224.0 serve + a live fetch
  of the module showing the export present).
proposed_fix: >
  Revert the dead `encode` imports to std@0.177.0 (where the export exists) in all 4
  affected functions — byte-identical to the bundles that were working before
  ec01b46. razorpay-webhook (v20) + verify-payment (v14) redeployed + smoke-verified
  (400 / 401, healthy); ai-media-proxy + create-razorpay-order defused in source
  (kept on their working old bundles, not redeployed). New gate prevents recurrence.
regression_test_planned: scripts/check_std_encoding_import_rot.dart (auto-wired via the check_*.dart glob) — PASS
touched_layers_checked:
  - "{ layer: edge_function_code, status: fixed_in_this_batch, evidence: 4 dead-encode imports reverted to std@0.177.0; new gate PASS + analyze clean }"
  - "{ layer: edge_function_deploy, status: verified, evidence: razorpay-webhook v20 + verify-payment v14 redeployed; live smoke 400/401 (healthy); full 5-function health sweep all non-503 }"
  - "{ layer: external_services, status: verified, evidence: Razorpay webhook restored (HTTP 400 on unsigned, was 503); Razorpay 24h retry + verify-payment fallback meant no payment lost in the window }"
impact_analysis: >
  A live payment webhook was DOWN for the deploy window. Real impact was bounded —
  Razorpay retries failed webhooks for 24h and the client polls verify-payment as a
  fallback, so PRO still unlocks — but a payment webhook returning 503 is a P0-class
  prod incident. This is the deploy-surfaces-latent-rot class
  (feedback_mistake_remote_dep_rot): a dependency bump that compiles in git but only
  fails at the NEXT deploy of each affected function. The gate now blocks the dead
  combination so a future std bump cannot reintroduce it.
closes-diagnose: d4c8e1
---

# Prod incident: std encoding dead-export deploy rot (razorpay-webhook DOWN)

## Timeline (2026-06-08)
1. Deploying Batch 6: pr-detection / proactive-coach-promotion / i-see-you-callout
   deployed clean (smoke 401).
2. **razorpay-webhook deploy → smoke 503 BOOT_ERROR.** 3 direct probes all 503 →
   real boot error, webhook DOWN.
3. Diagnosed: imports unchanged by my edit (`git diff 7f82b6d 9627837` = replay block
   only); `git log -S` showed `ec01b46` bumped std@0.177.0 → 0.224.0 keeping
   `import { encode }`; std removed `encode` at 0.210.
4. Reverted the 3 std imports to 0.177.0 (proven v18 lineage; a code rollback would
   NOT have helped — the bad import predates my edit). Redeployed **v20 → smoke 400**
   (healthy).
5. Scanned all functions: confirmed `serve@0.224.0` is fine; found the same dead
   `encode` import latent in verify-payment, ai-media-proxy, create-razorpay-order.
6. Fixed verify-payment (deployed **v14**, smoke 401) + defused ai-media-proxy +
   create-razorpay-order in source.
7. Health sweep — all 5 live functions non-503.

## Prevention
`scripts/check_std_encoding_import_rot.dart` (auto-wired) FAILS any `{ encode | decode }`
imported from `std@>=0.210/encoding/(hex|base64)`. Forward fix for a modern std:
`encodeHex` / `encodeBase64`.

## Lesson
A dependency bump (`ec01b46`) that compiles in git can sit latent for weeks and only
boot-fail at the **next deploy** of each affected function. Smoke-on-deploy caught it;
the byte-identical archive + SHA-pinned rollback made recovery safe. Per-function deploy
verification (not "deploy all 5 blind") is what contained the blast radius to one
function at a time.
