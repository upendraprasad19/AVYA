---
bug_id: f2d8ae
date: 2026-05-31
batch: derive-only-ai-coach-tool-surface
status: fixed
blast_radius: platform
symptom: >
  `ai-proxy` host-shell redeploy failed twice with HTTP 400 "Module not found
  https://deno.land/x/zod@v3.25.76/mod.ts". The deno.land/x zod module was removed
  upstream and now returns HTTP 404, so the Supabase Edge bundler aborts the deploy
  of any function whose graph imports zod from deno.land/x. Latent, platform-wide:
  every Edge Function importing zod was un-deployable.
concept: edge_function_dependency_resolution
sot_registry_entry: not_applicable (deploy-time remote-dependency resolution, not a runtime SoT concept)
writers:
  - supabase/functions/import_map.json (canonical zod pin — was deno.land/x, now npm:zod@3.25.76)
  - supabase/functions/_shared/tools (24 .ts files migrated from deno.land/x/zod to npm:zod@3.25.76 inline)
readers:
  - Supabase Edge bundler / Deno module resolver (resolves every import in the deploy graph; 404 on any remote import aborts the deploy)
  - .claude/emit_payload.js + .claude/deploy_via_api.js (host-shell deploy pipeline that submits the payload)
hive_key_prefix: not_applicable (no Hive involvement — server-side dependency resolution)
hive_key_formula: not_applicable
sync_methods: not_applicable (no client/cloud sync path; this is a build/deploy dependency)
restore_methods: not_applicable
cloud_table: not_applicable (no table — Edge Function deploy artifact)
cloud_columns: not_applicable
contract_test_path: test/contracts/no_denoland_zod_import_test.dart
ist_handling: not_applicable (no date/time logic involved)
provider_invalidations: not_applicable (no Riverpod providers involved)
telemetry_op_types: not_applicable (deploy-time failure surfaced via the deploy API HTTP 400 response, not runtime telemetry)
cross_account_guard: not_applicable (no user-scoped data path)
forbidden_patterns_checked:
  - "deno.land/x/zod import re-introduced — pinned absent by test/contracts/no_denoland_zod_import_test.dart"
  - "import_map.json zod alias pointing at a deno.land/x URL — pinned to npm:zod@3.25.76 by the same test"
proposed_fix: >
  Migrate every zod importer to the npm specifier `npm:zod@3.25.76`, which Supabase
  Edge (Deno) resolves natively and which is verified live (esm.sh/zod@3.25.76 →
  HTTP 200; deno.land/x/zod@v3.25.76/mod.ts → HTTP 404). Two layers: (1) the 24
  inline imports under _shared/tools were migrated to `npm:zod@3.25.76`; (2) the
  canonical pin in import_map.json (the dependency single-source per the 2026-05-20
  tech-debt audit D2/D3 convention) was changed from the dead deno.land/x URL to
  `npm:zod@3.25.76` — closing the latent landmine that any future bare `"zod"`
  import would have re-triggered. Redeploy ai-proxy via the host-shell flow and
  smoke-test.
regression_test_planned: >
  test/contracts/no_denoland_zod_import_test.dart — walks supabase/functions/,
  strips comments (colon-lookbehind line-strip so it does not eat the `//` inside
  https:// URLs), and FAILS if any .ts file or import_map.json contains a
  `deno.land/x/zod` import; a second case pins import_map.json's zod alias to
  `npm:zod@3.25.76`. Fails on the pre-fix tree, passes post-fix.
touched_layers_checked:
  - { tier: 6, layer: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "grep -rn deno.land/x/zod supabase/functions = 0 post-fix (was 25: 24 inline + 1 import_map); ai-proxy redeployed via host-shell emit_payload+deploy_via_api = v68 ACTIVE, smoke HTTP 401 reachable+gated; esm.sh/zod@3.25.76=200, deno.land/x=404 confirmed live via curl" }
  - { tier: 1, layer: client_code, status: not_applicable, evidence: "no Flutter/client code in the deploy dependency graph; flutter analyze 0/0 unaffected" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "ai-proxy tool-calling contract unchanged — zod used only for server-side tool-arg schema validation; npm:zod@3.25.76 is the same library version, so zodToGemini schema output is byte-equivalent" }
impact_analysis: >
  Platform blast radius. Before the fix, ANY Edge Function whose import graph
  reached zod via deno.land/x could not be deployed — this includes the entire AI
  coach tool surface (ai-proxy + _shared/tools) and any future function importing
  the bare "zod" specifier through import_map.json. The failure was latent: already
  deployed functions kept running, but the next deploy of any of them would have
  failed at bundle time with an opaque HTTP 400. Discovered while redeploying
  ai-proxy for the derive-only tool prune. No user-facing data was affected; the
  risk was an inability to ship server changes. Fixed by migrating to npm: and
  pinned against recurrence by a source-grep contract test.
---

# zod dependency rot blocked every Edge Function redeploy (deno.land/x → 404)

## What happened

While redeploying `ai-proxy` for the derive-only tool-surface prune (ADR-0012),
the host-shell deploy (`node .claude/deploy_via_api.js`) failed twice with:

```
HTTP 400 — Module not found "https://deno.land/x/zod@v3.25.76/mod.ts".
```

The zod package was removed from the `deno.land/x` third-party registry upstream.
That URL now returns **HTTP 404**. Supabase Edge bundles a function by resolving
its full import graph at deploy time; a 404 on any remote import aborts the deploy.

## Why it was latent / platform-wide

- Functions **already deployed** kept serving (their bundle was cached server-side).
  Nothing broke at runtime — so dashboards and smoke tests stayed green.
- The break only manifests **on the next deploy** of any zod-importing function.
- 24 inline `_shared/tools/**.ts` files imported `https://deno.land/x/zod@v3.25.76/mod.ts`,
  and `supabase/functions/import_map.json` pinned the bare `"zod"` specifier to the
  same dead URL. So every AI-tool-surface function — and anything resolving `"zod"`
  through the import map — was a deploy landmine.

## Verification (live)

```
curl -s -o /dev/null -w "%{http_code}" https://deno.land/x/zod@v3.25.76/mod.ts   → 404
curl -s -o /dev/null -w "%{http_code}" https://esm.sh/zod@3.25.76                → 200
grep -rn "deno.land/x/zod" supabase/functions   → 0 (post-fix; was 25)
```

ai-proxy redeploy after the migration: **v68 ACTIVE**, smoke HTTP 401 (reachable +
auth-gated, the expected unauthenticated response).

## Fix

1. Migrate the 24 inline imports under `_shared/tools/**` to `npm:zod@3.25.76`.
2. Update the canonical pin in `supabase/functions/import_map.json` from the dead
   deno.land/x URL to `npm:zod@3.25.76` (closes the bare-`"zod"` landmine).
3. Pin against recurrence: `test/contracts/no_denoland_zod_import_test.dart`.

## Lesson / class

Remote-URL dependencies (deno.land/x, esm.sh, raw GitHub) can **rot** — disappear
or change — without any local change, turning a previously-green deploy red with an
opaque bundler error. Prefer `npm:` / `jsr:` specifiers (registry-backed, immutable
per version) for Supabase Edge. Pin once in `import_map.json` and grep-guard the dead
sources. See `feedback_mistake_remote_dep_rot.md` and debugging skill §2 (new class:
remote dependency rot).

## See also

- ADR-0012 (the derive-only batch this surfaced in)
- `supabase/functions/import_map.json` (canonical dependency pins)
- `.claude/skills/edge-function-deploy-rollback/SKILL.md` (deploy + smoke flow)
- `test/contracts/no_denoland_zod_import_test.dart` (regression pin)
