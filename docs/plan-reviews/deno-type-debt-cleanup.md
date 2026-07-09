---
branch: deno-type-debt-cleanup
date: 2026-07-09
blast_radius: catastrophic
review_rounds: 6
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

## Convergence + outcome
All review findings folded in (no deferrals). This is the ONE correction to the batch's own blanket
"no EF redeploy required — every bundle byte-for-byte unaffected" claim: `compute-coach-signals/index.ts`
is the sole exception (its bundled supabase-js dependency genuinely changes version). Every other
touched file, including both catastrophic-tier payment files, is confirmed transpile-erased and
behavior-identical by 2 independent post-execution review passes (B-pass + 4-lens Hermes) on top of
the 4 pre-execution plan-review rounds. `git diff --stat` file list: 32 files (30 `.ts`/`.yml` + 1
`.dart` companion test), matching the plan's own diff-review checklist exactly — no scope creep.
