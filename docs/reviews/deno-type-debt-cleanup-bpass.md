---
staged_against: deno-type-debt-cleanup
verdict: accepted
---

# B-pass — deno-type-debt-cleanup (261→0 `deno check` errors, 32 files)

- **Reviewer role:** fresh context-blind adversarial pass over the full working-tree diff (32 files:
  30 Edge Function/shared `.ts` files + 1 CI YAML + 1 Dart contract test). 5 lenses
  (writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree,
  unawaited_no_error_sink) plus explicit hunts for risks specific to a "type-only" refactor claim.
  Verified against the actual diff + full file reads, not the plan's prose.

## Verdict: **accepted** (0 defects from this pass's own lenses; 1 P2 surfaced independently by the
parallel Hermes L21/L36 lenses on the same diff — fixed in-batch, see Hermes report)

### All 5 lenses — clean, with specifics
1. **writer_reader_drift** — read razorpay-webhook/index.ts and verify-payment/index.ts end-to-end,
   pre-diff vs post-diff: every business-logic line (HMAC verify, idempotency pre-SELECT, amount
   derivation, promo redemption) byte-identical; diff is import + 4 parameter-type annotations per
   file only. Programmatically diffed (string equality) all 3 Class-2 `.select()` collapses
   (`restore-user-snapshot` ×2, `weekly-report` ×1) against their pre-diff concatenated form —
   byte-identical, no column drift.
2. **function_exception_swallow** — no touched hunk adds/removes/restructures a try/catch or a
   `.functions.invoke()` call. `ai-media-proxy`'s catch-dispatcher is untouched; only the `HttpError`
   class's field/param type declarations above it changed.
3. **blast_radius_mismatch** — confirmed the catastrophic classification (razorpay-webhook,
   verify-payment both on the catastrophic glob) is mechanical, not behavioral: the only changes in
   each file are an import addition + parameter retyping.
4. **secrets_in_tree** — no credential-shaped literal in the diff; the only string-literal changes are
   a type-union member, a Postgrest column list, and package version specifiers (all public).
5. **unawaited_no_error_sink** — the new `await tool.intentBuilder!({...}, ctx())` calls are confined
   to `_shared/tools/__tests__/*_test.ts` (12 files). The real production call site
   (`_shared/tool-loop.ts:429`) was ALREADY a 2-arg awaited call, unchanged by this diff — the 12 test
   files were the ones out of sync with an already-correct contract; this diff fixes the tests, not
   the contract.

### Additional targeted checks (all clean)
- `SupabaseClient` bare-type widening: `createClient(...)` is called with zero explicit type
  arguments at every Class-1 site, so `ReturnType<typeof createClient>` already resolved to the fully
  defaulted `SupabaseClient<any, "public", any>` — definitionally identical to the bare alias. No
  narrowing lost; the fix only avoids `ReturnType`'s TS quirk on `createClient`'s overloaded signature.
- `registry.ts`'s `ToolDefinition<any, any>` widening is scoped to the heterogeneous-array boundary
  only; every individual tool file keeps its own narrow `ToolDefinition<Args, Result>` declaration,
  unchanged.
- `ai-media-proxy`'s `HttpError` union widening: the runtime `throw new HttpError(403, "authorization",
  ...)` is pre-existing (confirmed via `git show HEAD` — identical, same location). The catch-dispatcher
  only echoes `err.errorType`/`err.status`, never branches on specific values — widening the type union
  changes zero runtime behavior.
- Version-bump completeness: grepped every caller of `coach_memory.ts` (6 real functional callers) and
  `rank_engine.ts` (1 real caller, `evaluate-rank-promotions/index.ts`) — all now consistently resolve
  to `@2.39.3`; no caller left mismatched, no mismatch moved elsewhere.
- Diff-to-working-tree fidelity: `git diff --stat HEAD` matches the reviewed file list exactly, no
  drift.

### One caveat this pass flagged (addressed)
This B-pass agent could not execute `deno check`/`deno test` itself (no `deno` binary in its sandbox) —
its "zero runtime change" confidence rested on manual line-by-line diffing, not on reproducing the
claimed 261→0 / 244-pass-identical counts. **I (the orchestrating session) ran both live myself**,
multiple times including after the post-review fix below — see the plan-review record's Ground-truth
section for the actual commands + output.

### Finding surfaced by the parallel Hermes pass, folded in here for completeness
The Hermes L21 + L36 lenses (run in parallel against the same diff, see
`docs/audit/deno-type-debt-cleanup-hermes.md`) independently caught something this B-pass's own lens
set didn't target: the `_shared/coach_memory.ts` / `compute-coach-signals/index.ts` cross-version
`SupabaseClient` alignment (`@2.45.4`→`@2.39.3`) was billed as "type-only" but `coach_memory.ts`
imported `createClient` as a VALUE (not `import type`) — meaning the version-pinned URL was NOT erased
at transpile, even though `createClient` was never actually called in that file. **Fixed in-batch:**
`coach_memory.ts`'s import changed to `import type { SupabaseClient } from ".../supabase-js@2.39.3"`
(the unused `createClient` value import dropped) — now genuinely erased at transpile, zero runtime
effect. Re-verified live: `deno check` 0 errors, `deno test` 244/0, both unchanged. `compute-coach-
signals/index.ts` retains a **real** (not type-only) version change, since it genuinely constructs its
own client via `createClient()` — see the Hermes report for the full risk assessment and why this one
exception is accepted.

**Post-fix confirmation:** `deno check --node-modules-dir=auto supabase/functions/` → 0 errors / 111
files. `deno test --allow-all --node-modules-dir=auto supabase/functions/` → 244 passed, 0 failed
(identical to the pre-batch baseline).
