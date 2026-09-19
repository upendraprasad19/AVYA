---
branch: deno-type-debt-cleanup
date: 2026-07-10
blast_radius: catastrophic
review_rounds: 7
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/deno-type-debt-cleanup-bpass.md
hermes: accepted
hermes_report: docs/audit/deno-type-debt-cleanup-hermes.md
---

# Plan-review record — deno-type-debt-cleanup (Deno type-debt cleanup, catastrophic)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Catastrophic-tier
(the fix touches `razorpay-webhook/index.ts` + `verify-payment/index.ts`, both on the catastrophic
glob in `docs/blast_radius.yaml`) — classification is mechanical (file paths touched), not because the
edits are payment-logic changes; both B-pass and Hermes independently confirmed this.

## Scope
Eliminate all pre-existing `deno check` type errors across `supabase/functions/` (261 errors, 32 of
111 `.ts` files — scoping found this was 10x the task chip's original "~26" estimate). Every fix is a
TypeScript annotation/import change (signature widening, literal-ifying a concatenated `.select()`
string, adding a missing test argument, casting through `unknown`) with the invariant that **zero
runtime behavior changes** — verified by an identical `deno test` pass count (244/0) before and after.
4 root-cause classes (12-file `ReturnType<typeof createClient>` idiom fix; 2-file/3-site `.select()`
string-literal collapse; 12 test-file `intentBuilder` arity fix; 1-file heterogeneous-array widening)
plus 3 standalone one-offs (a cross-version `SupabaseClient` type-import alignment; an `HttpError`
union widening matching an already-live throw; explicit types on a previously-implicit-any callback).
Also widens the CI `deno check` gate from 3 named files to the full tree (permanent regression guard).

## Review arc (all context-blind; every claim verified against live `deno check`/`deno test`, not
subagent prose)

- **Plan-level ×4 (pre-execution):** the design went through four independent, founder-requested
  review rounds before a line was written. Round 1 caught a mischaracterized root cause
  (`registry.ts`'s ~20 errors were wrongly bucketed as harmless secondary notes — actually 20
  independent primary errors, now Class 4) plus 3 unaccounted-for standalone one-offs. Round 2
  actually applied and live-tested the new/uncertain fixes (Class 4, both one-offs) rather than just
  reading code, confirming them and refining one (`morning-alert`'s minimal fix was under-scoped;
  worked out a fuller one). Round 3 went further on live testing — applied Classes 1-3 live on real
  files — and found the plan's "downstream bonus" claim was false: `coach_memory.ts`'s 9 caller sites
  don't resolve for free after Class 1, they mutate into a new cross-version mismatch needing an
  explicit fix (folded in). Round 4 (structurally read-only, could not mutate/test) re-confirmed
  everything else held. **Verdict at the time: converged** — 2+ rounds kept finding real, substantive,
  but successively narrower issues (a sign of convergence, not a sign to keep splitting).
- **Execution (file-by-file, live-verified after every class):** `deno check` dropped monotonically and
  exactly as predicted at each step (261→152→141→121→118→...→0), confirmed live at every checkpoint,
  not extrapolated. Final sweep: 0 errors / 111 files. `deno test --allow-all` (type-checked, not
  `--no-check`): 244 passed / 0 failed, identical to the pre-batch baseline.
- **B-pass (post-execution, fresh Sonnet agent, 5 lenses + targeted risk hunts):** 0 defects from its
  own lens set. Verified razorpay-webhook/verify-payment byte-identical outside import+type edits,
  all 3 Class-2 string collapses byte-identical (programmatic diff), the test-file `await` additions
  align 12 stale tests to an already-correct production contract, `HttpError`'s pre-existing throw
  unchanged, version-bump completeness across all real callers. Record:
  `docs/reviews/deno-type-debt-cleanup-bpass.md` (verdict: accepted).
- **Hermes (post-execution, 4 parallel Opus lenses — L1 writer/reader drift, L21 EF semantic
  correctness, L26 CQRS purity, L36 idempotency replay):** L1 and L26 clean. L21 and L36 —
  **independently, via different verification paths — converged on the same real P2**: the
  `coach_memory.ts`/`compute-coach-signals.ts` cross-version alignment was billed as type-only but
  `coach_memory.ts` imported `createClient` as a VALUE (not `import type`), so the version-pinned URL
  wasn't actually erased at transpile (confirmed: no function imports the bare specifier, so
  `import_map.json`'s pin never applies; the inline `esm.sh` URL is authoritative). **Fixed in-batch**
  (see Ground-truth section). Both lenses also independently confirmed the two catastrophic-tier
  payment files themselves are clean (idempotency guards, replay windows, and promo-redeem gates all
  untouched). Record: `docs/audit/deno-type-debt-cleanup-hermes.md` (verdict: accepted).

## Ground-truth verification (live, 2026-07-09)
`deno check --node-modules-dir=auto supabase/functions/` → **0 errors, 111/111 files clean** (down
from 261/32). `deno test --allow-all --node-modules-dir=auto supabase/functions/` → **244 passed, 0
failed** — re-run and re-confirmed identical AFTER the Hermes-surfaced fix below, not just once
before it.

**Hermes-surfaced fix, applied and re-verified live:** read `coach_memory.ts` directly — confirmed
`createClient` was imported but never invoked in the file (a dead value import, a leftover requirement
of the original broken `ReturnType<typeof createClient>` idiom). Changed the import to `import type {
SupabaseClient } from ".../supabase-js@2.39.3"` — erased at transpile by TypeScript specification, now
genuinely zero runtime effect. Re-ran both commands above post-fix: identical 0-error / 244-pass
result. `compute-coach-signals/index.ts` retains a **real, accepted, documented** version change (it
genuinely constructs its own client) — see the Hermes report's Finding 1 for the full risk reasoning
(converges to a version 6 sibling functions already run live in prod; minor-version step within the
same major version; non-payment, non-user-facing cron function; follow-up: smoke-test after next
redeploy).

## Convergence + outcome (as of round 6, merged to main as `b2d32a1`)
All review findings folded in (no deferrals). This is the ONE correction to the batch's own blanket
"no EF redeploy required — every bundle byte-for-byte unaffected" claim: `compute-coach-signals/index.ts`
is the sole exception (its bundled supabase-js dependency genuinely changes version). Every other
touched file, including both catastrophic-tier payment files, is confirmed transpile-erased and
behavior-identical by 2 independent post-execution review passes (B-pass + 4-lens Hermes) on top of
the 4 pre-execution plan-review rounds. `git diff --stat` file list: 32 files (30 `.ts`/`.yml` + 1
`.dart` companion test), matching the plan's own diff-review checklist exactly — no scope creep.

## Round 7 — post-merge CI failure, root-caused and fixed (2026-07-10)

**What happened:** immediately after `b2d32a1` merged to `main` and was pushed, CI's
`deno-edge-functions` job — running the exact full-tree `deno check` this batch's own CI-gate-widening
(§ above) had just made a hard blocker — failed with **5 NEW type errors**, never seen in rounds 1-6's
repeated live `deno check` runs.

**Root cause (confirmed, not assumed):** CI's `denoland/setup-deno@v2` step pins a FLOATING
`deno-version: v2.x`, resolved at CI run time to 2.9.2 (TypeScript 6.0.3). Every local verification in
rounds 1-6 ran on the author's local Deno 2.1.4 (TypeScript 5.6.2) — 8 minor versions behind. TypeScript
5.7 tightened typed-array generics (`Uint8Array` became generic over its backing-buffer type), which
broke structural compatibility at 4 `base64Encode(...)` call sites that passed a manually-constructed
`Uint8Array`/pre-encoded value instead of the plain `ArrayBuffer`/`string` the function's signature
already accepts; a 5th site's `setTimeout`-handle variable, hardcoded as `number`, hit a similar
ambient-lib version-sensitivity gap. **This means rounds 1-6's repeated "0 errors" ground-truth
verification was true and reproducible — but only against the older local toolchain, not against CI's
actual resolved one.** Confirmed by `deno upgrade`-ing the local install to 2.9.2 (matching CI) and
reproducing CI's exact 5 errors, byte-for-byte, before applying any fix.

**Scope of the 5 errors relative to this batch's own 32-file diff:** independently verified via
`git diff bec0f06^..bec0f06 -- <each file>` — `bec0f06` (this batch's execution commit) touched
`ai-media-proxy/index.ts` only at its `HttpError` union (unrelated line), and `razorpay-webhook/index.ts`
+ `verify-payment/index.ts` only at their `ReturnType<typeof createClient>` → `SupabaseClient`
substitution (also unrelated lines) — it never touched the `base64Encode`/`TextEncoder` lines now being
fixed. `_shared/tool-loop.ts` and `create-razorpay-order/index.ts` don't appear in `bec0f06`'s file list
at all. **All 5 errors are genuinely pre-existing latent bugs, invisible under the old local toolchain,
not regressions introduced by this batch's own edits.**

**Fix:** 5 files —
- `_shared/tool-loop.ts:355`: `number | undefined` → `ReturnType<typeof setTimeout> | undefined` for the
  timeout-handle variable (the same idiom already in live use, unmodified, at `memory_retrieval.ts:67`).
- `ai-media-proxy/index.ts:301`: removed a redundant `new Uint8Array(arrayBuffer)` wrap —
  `base64Encode` already performs this exact internal normalization for a plain `ArrayBuffer` input.
- `create-razorpay-order/index.ts:177`, `razorpay-webhook/index.ts:391`, `verify-payment/index.ts:304`:
  removed a redundant manual `new TextEncoder().encode(...)` wrap on each Basic-Auth-header string —
  `base64Encode` already performs this exact internal UTF-8 encoding for a plain `string` input.

**Verification (fresh, independent, context-blind review dispatched specifically for this round, given
3 of 5 files are Razorpay-payment-critical):** fetched and read `deno.land/std@0.177.0/encoding/base64.ts`'s
actual `encode()` source directly (not assumed from memory) — confirmed its internal normalization branch
is `typeof data === "string" ? new TextEncoder().encode(data) : data instanceof Uint8Array ? data : new
Uint8Array(data)`, i.e. byte-for-byte the same operation the removed manual wraps were doing, one line
earlier, at each of the 4 sites — provably behavior-preserving, not just plausible. Confirmed
`ReturnType<typeof setTimeout>` doesn't change either `clearTimeout` call site's behavior (both already
guarded `!== undefined`) and matches a pre-existing, unmodified idiom elsewhere in this codebase.
Grepped tree-wide for any other `base64Encode(new (TextEncoder|Uint8Array)` or bare-`number`-typed
timeout-handle pattern — zero additional sites missed. `deno check` on the CI-matching upgraded Deno:
5 errors → 0. `deno test --allow-all`: 244 passed / 0 failed, unchanged before and after.

**Process note (raised independently by the round-7 reviewer, addressed here):** these 5 fixes land as
their own `fix:`-prefixed commit with a dedicated diagnose-doc
(`docs/diagnoses/2026-07-09-deno-ci-version-drift-typed-arrays-c3d8a9.md`, bug id `c3d8a9`) — NOT folded
silently into the already-merged `bec0f06`/`b2d32a1` history. Rounds 1-6's "converged" verdict stands as
an accurate description of what was verified at the time; this round documents the environment-version
gap those rounds could not have caught without upgrading Deno first, and closes it.

**Verdict: converged.** The fix is correct and behavior-preserving on independent, source-verified review;
CI-gate-widening from this same batch is exactly what caught the gap it left open — working as intended.
