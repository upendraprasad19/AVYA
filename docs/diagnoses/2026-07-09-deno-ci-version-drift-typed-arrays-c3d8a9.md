---
bug_id: c3d8a9
date: 2026-07-09
batch: deno-type-debt-cleanup
status: fixed
blast_radius: catastrophic
symptom: >
  Immediately after merging the deno-type-debt-cleanup work (which widened the CI
  `deno check` step from 3 named files to the full supabase/functions/ tree, claiming
  0 errors), the CI run on main (commit b2d32a1) FAILED at that exact step with 5 NEW
  type errors: `_shared/tool-loop.ts:361` (`Type 'Timeout' is not assignable to type
  'number'` on a setTimeout-handle assignment), and 4 sites where `base64Encode(...)`
  is called with a `Uint8Array<ArrayBuffer>` argument that TypeScript 5.7+'s tightened
  typed-array generics no longer structurally match `string | ArrayBuffer`
  (ai-media-proxy/index.ts:302, create-razorpay-order/index.ts:178,
  razorpay-webhook/index.ts:392, verify-payment/index.ts:305). Root cause: the
  author's local Deno (2.1.4, bundled TypeScript 5.6.2) is older than what CI's
  FLOATING `denoland/setup-deno@v2` `deno-version: v2.x` pin resolved to at CI run
  time (2.9.2, bundled TypeScript 6.0.3) — a local-vs-CI environment-version
  divergence, not a logic bug introduced by the batch. Confirmed by upgrading local
  Deno to 2.9.2 and reproducing the exact same 5 errors locally (byte-for-byte
  matching CI's error log), then re-verifying 0 errors after the fix on the SAME
  upgraded local Deno version.
concept: deno_ci_environment_version_drift
sot_registry_entry: >
  Not a Hive/cloud writer-reader storage concept — this is a build/CI-tooling
  version-consistency gap. The invariant this bug violates: a floating CI toolchain
  pin (`deno-version: v2.x`) can silently diverge from whatever version a
  contributor's local machine has installed, so a locally-clean `deno check` does
  not guarantee a CI-clean one. No registry entry exists for this class; not adding
  one here (single fix-and-move-on, not a recurring registered contract).
writers:
  - "{ file: supabase/functions/_shared/tool-loop.ts, method: (tool-loop read-kind timeout race), line: 355 } — `timeoutHandle` retyped from `number | undefined` to `ReturnType<typeof setTimeout> | undefined` (environment-portable idiom; matches whatever concrete type the active setTimeout/clearTimeout pair returns, avoiding the Node-vs-Deno/browser `Timeout`-vs-`number` split)."
  - "{ file: supabase/functions/ai-media-proxy/index.ts, method: fetchImageAsBase64, line: 301 } — removed the intermediate `new Uint8Array(arrayBuffer)` wrap; `base64Encode` now called directly on the already-`ArrayBuffer`-typed `arrayBuffer`, which already satisfies its `string | ArrayBuffer` parameter type."
  - "{ file: supabase/functions/create-razorpay-order/index.ts, method: (order-creation Basic Auth header build), line: 177 } — removed the manual `new TextEncoder().encode(...)` wrap; `base64Encode` now called directly on the template-literal string."
  - "{ file: supabase/functions/razorpay-webhook/index.ts, method: (auto-capture Basic Auth header build), line: 391 } — same fix as create-razorpay-order."
  - "{ file: supabase/functions/verify-payment/index.ts, method: (payment-verification Basic Auth header build), line: 304 } — same fix as create-razorpay-order."
readers: n/a — these are self-contained expression-level type fixes, not writer/reader data-flow contracts; each site's only "reader" is the very next line in the same function (base64Encode's return value used as an HTTP Authorization header value, or clearTimeout's argument), verified inline above.
hive_key_prefix: n/a (server Edge-Function type-check fix; no keyed Hive concept)
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: n/a (no query, no table, no column touched — pure expression-level type fixes)
cloud_columns: n/a
contract_test_path: >
  No separate Dart/Deno contract test file — the regression-detection mechanism IS
  the CI job itself: `.github/workflows/test.yml`'s "Deno type-check (full tree)"
  step (`deno check --node-modules-dir=auto supabase/functions/`), which is exactly
  the step that caught this. See regression_test_planned for how this is verified
  going forward.
ist_handling: n/a (no date-key logic changed)
provider_invalidations: n/a (server-side, no Riverpod provider involved)
telemetry_op_types: n/a (no new runtime telemetry; no runtime behavior changed at all — see impact_analysis)
cross_account_guard: n/a (no user-scoped read/write touched; pure expression-level type fixes on already-existing values)
forbidden_patterns_checked: >
  Every fix must be a PURE type-level/expression-simplification change with IDENTICAL
  runtime output. Verified for the 4 base64Encode sites by reading
  deno.land/std@0.177.0/encoding/base64.ts's encode() signature (`ArrayBuffer |
  string`) and confirming it UTF-8-encodes a string argument internally via the exact
  same `TextEncoder().encode()` call the removed code used to do manually — so
  passing the raw string (or, for ai-media-proxy, the raw ArrayBuffer instead of a
  redundant Uint8Array wrapper) produces byte-identical output. Verified for
  tool-loop.ts by confirming `ReturnType<typeof setTimeout>` is the standard,
  environment-portable idiom for this exact Node/Deno/browser setTimeout-return-type
  split, and that `clearTimeout(timeoutHandle)` (the sole other reader of this
  variable) accepts whatever setTimeout returns by construction (they're a matched
  pair in every JS runtime's lib).
proposed_fix: >
  (1) tool-loop.ts: retype timeoutHandle via ReturnType<typeof setTimeout> instead of
  a hardcoded number. (2-5) 4 base64Encode call sites: stop pre-encoding to
  Uint8Array/manually calling TextEncoder().encode() before handing the value to
  base64Encode, since base64Encode's own signature already accepts (and internally
  UTF-8-encodes) a plain string, or already accepts the ArrayBuffer directly without
  an intermediate Uint8Array wrap.
regression_test_planned: >
  No new test file added (this is a pure type-level fix on already-tested runtime
  code — the existing 244-test Deno suite, unchanged, already covers runtime
  behavior for these files' other logic; `deno test --allow-all
  --node-modules-dir=auto supabase/functions/` gives 244 passed / 0 failed, identical
  before and after these 5 edits, confirmed on the SAME upgraded Deno 2.9.2 used to
  reproduce the bug). The actual regression gate for THIS bug class is
  `.github/workflows/test.yml`'s full-tree `deno check` step, already permanent from
  the prior batch — it will catch this class again if it recurs (e.g. a future Deno
  version bump introducing yet another typed-array/global tightening). Locally
  reproduced 5/5 of CI's exact errors after upgrading `deno --version` from 2.1.4 to
  2.9.2 (matching CI's floating `v2.x` resolution at run time), then reproduced 0/5
  after the fix, on the identical upgraded binary — this before/after pair on the
  CI-matching toolchain IS the regression test.
touched_layers_checked:
  - "{ layer: client_code, status: not_applicable, evidence: zero lib/ or test/ Flutter files touched — this is a server-only Deno Edge Function type-check fix. }"
  - "{ layer: edge_function_code, status: fixed_in_this_batch, evidence: 5 sites across 5 files fixed; deno check --node-modules-dir=auto supabase/functions/ on Deno 2.9.2 (CI-matching) goes from 5 errors to 0; deno test --allow-all on the same binary stays 244 passed / 0 failed before and after. }"
  - "{ layer: edge_function_code_vs_deploy, status: not_applicable, evidence: type annotations and a redundant intermediate variable/wrapper are erased at Deno's transpile step; no deployed EF bundle's emitted JS changes byte-for-byte for these 5 sites (base64Encode(str) and base64Encode(new TextEncoder().encode(str)) compile to functionally identical emitted call expressions with the wrapper removed, not preserved as dead code — confirmed by the encode() signature accepting both forms with identical internal UTF-8 handling). No EF redeploy required to fix a live bug; these Edge Functions were never runtime-broken. }"
  - "{ layer: client_to_server_contract, status: verified, evidence: no HTTP request/response shape, header value, or Authorization credential VALUE changes -- base64Encode(rawString) and base64Encode(TextEncoder().encode(rawString)) produce byte-identical base64 output per encode()'s own internal string-handling branch, confirmed by reading deno.land/std@0.177.0/encoding/base64.ts's documented behavior. }"
impact_analysis: >
  Zero runtime behavior change. This fixes 5 latent TypeScript strictness gaps that
  were invisible under the author's local (older) Deno/TypeScript version but real
  under CI's floating, newer pin -- restoring CI to green on main. The 3
  payment-critical files touched (create-razorpay-order, razorpay-webhook,
  verify-payment) each had the identical, narrow fix applied (stop manually
  pre-UTF-8-encoding a string before base64-encoding it, since the base64 encoder
  already accepts and internally UTF-8-encodes a plain string) -- verified
  behavior-preserving via the encoder's own documented string-handling path, and via
  an unchanged 244/0 full Deno test-suite pass count on the exact Deno version that
  originally caught the bug. No feature flag needed (strictly a compile-time
  correctness fix, not a behavior change). No EF redeploy required to fix a live
  incident -- these functions were never runtime-broken; CI (not production) was
  red. Whether `.github/workflows/test.yml`'s `denoland/setup-deno@v2` pin should be
  changed from floating `v2.x` to an exact version is a separate infrastructure
  policy decision (not a bug this diagnose's fix touches) -- noted here for
  visibility only, since a floating pin is the root mechanism that let this class
  of error reach CI undetected; this diagnose's scope is the 5 concrete type errors
  it fixes, not the CI pinning policy.
closes-diagnose: c3d8a9
---

# c3d8a9 — Deno CI/local version drift surfaces 5 latent typed-array/setTimeout type errors

## What happened
The deno-type-debt-cleanup merge (261 `deno check` errors → 0, merged to main as
`b2d32a1`) widened `.github/workflows/test.yml`'s `deno check` step from 3 named
files to the full `supabase/functions/` tree, verified 0 errors locally multiple
times. CI ran the SAME step on the SAME merged commit and failed with 5 NEW errors
never seen locally.

## Root cause
CI's `denoland/setup-deno@v2` step pins `deno-version: v2.x` — a FLOATING version
range, resolved to whatever the latest v2.x release is at the moment CI runs (in
this case 2.9.2, bundling TypeScript 6.0.3). The author's local Deno was 2.1.4
(TypeScript 5.6.2) — 8 minor versions behind. TypeScript 5.7 tightened typed-array
generics (`Uint8Array` became generic over its backing buffer type,
`Uint8Array<ArrayBuffer>`), which no longer structurally satisfies an
`ArrayBuffer`-typed parameter the way it used to. This surfaced at 4 call sites
where `base64Encode()` (from `deno.land/std@0.177.0/encoding/base64.ts`, declared
`(data: ArrayBuffer | string) => string`) was being called with a manually-produced
`Uint8Array` instead of a plain `ArrayBuffer` or `string`. Separately, one site
(`_shared/tool-loop.ts`) assigned `setTimeout(...)`'s return value into a variable
hardcoded as `number` — correct under Deno's own DOM-lib globals, but apparently
resolved to Node's `Timeout` ambient type under the newer toolchain in this
codebase's dependency graph.

**Confirmed, not guessed:** upgraded local Deno 2.1.4 → 2.9.2 (`deno upgrade`),
re-ran the full-tree `deno check` — reproduced the EXACT same 5 errors, same files,
same lines, same messages as CI's log. This rules out any CI-runner-specific quirk
(env vars, OS, etc.) — it is purely the Deno/TypeScript version gap.

## Fix
1. `_shared/tool-loop.ts:355` — `let timeoutHandle: number | undefined;` →
   `let timeoutHandle: ReturnType<typeof setTimeout> | undefined;` (the standard,
   environment-portable idiom for this exact split; `clearTimeout` accepts whatever
   `setTimeout` returns by construction).
2. `ai-media-proxy/index.ts:301` — `base64Encode(new Uint8Array(arrayBuffer))` →
   `base64Encode(arrayBuffer)` (the source `arrayBuffer` is already an `ArrayBuffer`;
   the intermediate wrap was redundant).
3-5. `create-razorpay-order/index.ts:177`, `razorpay-webhook/index.ts:391`,
   `verify-payment/index.ts:304` — `base64Encode(new TextEncoder().encode(str))` →
   `base64Encode(str)` (identical pattern, all 3 building an HTTP Basic Auth header
   for the Razorpay API; `base64Encode` already accepts a plain string and internally
   UTF-8-encodes it the same way the removed code did manually).

## Verification
- `deno check --node-modules-dir=auto supabase/functions/` on the CI-matching Deno
  2.9.2: 5 errors → 0.
- `deno test --allow-all --node-modules-dir=auto supabase/functions/` on the same
  binary: 244 passed / 0 failed, unchanged before and after.
- Fresh context-blind review dispatched specifically on these 5 sites (payment-file
  risk), given 3 of 5 touched files are Razorpay-facing.

## Recurrence
New class — first instance of a floating-CI-toolchain-pin version drift on this
codebase. Related in SPIRIT (not mechanism) to `feedback_local_ci_env_divergence.md`
("local PASS + CI red same commit") — that memory lists CRLF/LF, TZ, async timing,
and CI timeout-cancellation as known causes; Deno/TypeScript toolchain version drift
via a floating `setup-deno@v2` pin is a NEW cause to append to that memory's list.
