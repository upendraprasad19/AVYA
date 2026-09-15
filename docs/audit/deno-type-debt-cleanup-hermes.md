---
staged_against: deno-type-debt-cleanup
verdict: accepted
---

# Hermes cross-lens review — deno-type-debt-cleanup (261→0 `deno check` errors, 32 files)

Four parallel Opus lens passes, all context-blind, dispatched against the actual working-tree diff
(not the plan). Blast-radius is catastrophic (`razorpay-webhook/index.ts` + `verify-payment/index.ts`
both touched, both on the catastrophic glob in `docs/blast_radius.yaml`).

## Verdict: **accepted** (1 P2 found + fixed in-batch; 1 P2 accepted as a documented low-risk
exception; all other lenses clean)

### L1 — writer_reader_drift — 0 findings
Reconstructed all 3 Class-2 `.select()` string collapses character-by-character (OLD concatenated
fragments vs NEW single literal): `restore-user-snapshot/index.ts` `coach_memory` 10-column and
`user_progress` 4-column projections, `weekly-report/index.ts` `user_profile` 13-column projection —
all byte-identical, no column added/dropped/renamed. Both `restore-user-snapshot` query results are
stored as opaque blobs and never field-accessed by the Edge Function itself (client is the sole
consumer, contract unchanged since the string is unchanged). No Class-1 site touches a table name,
column list, `.eq()` filter, or `.rpc()` name — confirmed by grepping every diff-changed line
containing `.from(`/`.select(`/`.eq(`/`.rpc(`.

### L21 — Edge Function semantic correctness — 3 findings (1 real, fixed; 2 false alarm)
**Finding 1 — real, P2 (fixed in-batch):** the brief's claim of "same version specifier" for the
`coach_memory.ts` / `compute-coach-signals/index.ts` cross-version alignment was false — both files
changed `@supabase/supabase-js@2.45.4` → `@2.39.3` as a **value import** (not `import type`), and since
every function in this codebase imports supabase-js via a fully-qualified `esm.sh` URL (never the bare
specifier `import_map.json` pins), the import map does not neutralize this — the version genuinely
changes at runtime for any file importing it as a value.

**Resolution:** read `coach_memory.ts` directly — confirmed `createClient` was imported but never
invoked anywhere in the file (dead value import, a leftover requirement of the OLD broken
`ReturnType<typeof createClient>` idiom, which needs the value import for `typeof` to resolve).
Changed the import to `import type { SupabaseClient } from ".../supabase-js@2.39.3"` — TypeScript's
`import type` is fully erased at transpile by specification, so this now has genuinely zero runtime
effect while still fixing the nominal cross-version type mismatch against its 6 real callers (all on
`@2.39.3`). Re-verified live: `deno check` still 0 errors, `deno test` still 244 passed / 0 failed.

`compute-coach-signals/index.ts` is the one file where this does NOT fully resolve to zero-runtime-
change: it genuinely calls `createClient(...)` itself (confirmed via direct grep — `createClient(` at
line 27), so its own client construction really is now built against `@2.39.3` instead of `@2.45.4`.
There is no type-only escape hatch here (unlike `coach_memory.ts`, this file must construct a real
client, and that client's type must match `coach_memory.ts`'s parameter type for the call to
type-check). **Accepted as a documented exception**, not reverted, because: (a) reverting would
re-introduce the original cross-version TS error this batch exists to fix; (b) the alternative — bump
the other 6 real callers UP to `@2.45.4` instead — is strictly worse (6 files touched instead of 1,
including `ai-proxy`, `daily-snapshot`, `morning-alert`); (c) `@2.39.3` is not a novel/untested version —
it's the version 6 sibling coach-memory-calling functions (`ai-proxy`, `daily-snapshot`,
`morning-alert`, `pr-detection`, `protein-gap-alert`, `workout-window-closing`) already run live in
production today, unchanged by this batch — `compute-coach-signals` converges to an already-proven
version rather than adopting something new; (d) it's a minor-version step within the same major
version (2.x) on a narrow, stable API surface (`.from().select()/.upsert()`), on a non-payment,
non-user-facing cron function. **Follow-up action:** smoke-test `compute-coach-signals` after its next
redeploy (standard practice for any dependency-version-touching redeploy per
`supabase/functions/CLAUDE.md`'s deploy protocol) — this is the one function in the batch where "no EF
redeploy required, byte-for-byte unaffected" does NOT hold; its bundle genuinely differs.

**Finding 2 — false alarm** (razorpay-webhook TDZ/ordering): read the full file. The diff touches only
the import list (no reordering/duplication) and 3 helper functions' parameter types
(`derivePlanFromAmount`, `computeExpectedAmount`, `redeemPromo`) — all `function` declarations
(hoisting-safe). The load-bearing `const supabaseClient = createClient(...)` and the OI-26 TDZ-guard
comment are unchanged, still positioned above its first use. No new TDZ.

**Finding 3 — false alarm** (verify-payment / morning-alert / ai-media-proxy / registry ordering): all
4 files read in full. verify-payment's idempotency guards (`existingSub`, `paymentSubRow`,
`weInsertedTheRow`) untouched by the diff's 2 retyped helper functions. morning-alert's new type +
casts emit no runtime code and the guarded branches read identical runtime values. ai-media-proxy's
`HttpError` union widening only makes the compiler accept an already-live runtime string; no other
call site's checking loosens. registry.ts's `any,any` widening touches only declared return types, not
the array's filter/find bodies.

### L26 — CQRS / pure-function discipline — 0 findings
All 13 production `intentBuilder` implementations read in full: 12 are synchronous arrow functions
that never reference `ctx` (confirmed pure w.r.t. the injected test stub); the 13th
(`logMealByText.ts`, genuinely `async`) was correctly excluded from this batch's 12-file test-migration
list (its own test was already correctly awaited pre-batch). `registry.ts`'s `allTools()`/`byName()`
bodies (`ALL_TOOLS.filter(...)` / `ALL_TOOLS.find(...)`) are byte-unchanged; only their declared return
types widened. Confirmed no migrated test asserts a throw/rejection on `intentBuilder` (grepped for
`assertThrows`/`assertRejects`/`.rejects`/`try{` across all 12 files — zero hits), so the new `await`
cannot change failure attribution.

### L36 — idempotency replay completeness — 2 findings (1 real, same as L21 Finding 1; 1 false alarm)
Independently confirmed the same `coach_memory.ts`/`compute-coach-signals` version-downgrade finding as
L21 (via a different path — traced the replay-relevant `upsertCoachMemory`'s `onConflict:"user_id"`
upsert and confirmed the import-map does not neutralize the version change). Same resolution applies
(see L21 Finding 1 above).

**False alarm** (payment files' idempotency guards): read both files in full. razorpay-webhook's H-19
pre-SELECT + unique-violation catch (23505) + replay-age window + promo one-time-redeem gate are all
untouched. verify-payment's `existingSub` early-return + `paymentSubRow` pre-SELECT + `weInsertedTheRow`
gate + 23505 race handling are all untouched. Both files stayed on `@2.39.3` with no version change —
only `SupabaseClient` added to the already-present value import. No idempotency-relevant test assertion
changed value (the 12 changed test files are all workout/plan `intentBuilder` tests, none
webhook/payment/dedup-related).

## Cross-lens convergence
Two independently-dispatched lenses (L21, L36), using different verification paths, converged on the
exact same real finding — the version-import-kind distinction (`import type` vs value import)
mattering for the "erased at transpile" claim. This is the kind of subtle-but-real gap the ×2-lens
redundancy in this process is designed to surface. Both lenses also independently confirmed the two
catastrophic-tier payment files themselves are clean.

## Post-fix live verification
`deno check --node-modules-dir=auto supabase/functions/` → 0 errors, 111/111 files clean.
`deno test --allow-all --node-modules-dir=auto supabase/functions/` → 244 passed, 0 failed (identical
to the pre-batch baseline). Both re-run after the `coach_memory.ts` `import type` fix, both hold.
