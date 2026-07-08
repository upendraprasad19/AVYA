---
branch: v74-coach-telemetry
date: 2026-07-08
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: pending
---

# Plan-review record — v74-coach-telemetry (H2: coach-history telemetry)

Keystone record for the §4.12 merge gate. Follow-up to the coach-memory-snapshot batch (Units
2+3+FC8, merged `237c347`) — its end-of-batch Hermes report (`docs/audit/coach-memory-snapshot-hermes.md`)
offered three optional, non-blocking hardening items to the founder as a future "v74" batch: H1
(same-user assistant-echo-laundering residual — already accepted+recorded in the
`coach_chat_history_replay` SoT entry), H2 (history-correlated telemetry), H3 (a server-side history
kill-switch). Founder resolved all three 2026-07-08: **H1 → skip**, **H3 → drop** (duplicates the
shipped client `disable_coach_history` flag + the existing `--rollback ai-proxy <sha>` lever),
**H2 → ship**. This branch is H2 only.

## The change
Two additive log edits to `supabase/functions/ai-proxy/index.ts` (no other files, no client change,
no schema change, no change to response shape/status, no change to what's sent to Gemini):
1. After `const cappedHistory = capCoachHistory(history);` — log `history_len=<N>` on every chat
   request (same density class as the existing unconditional `system_prompt_size=` log at `:787`).
2. In the existing `catch (loopErr)` block around `runToolLoop()` — extend the existing
   `console.error` to add `had_history=<bool>`, keeping `loopErr` as the last positional arg (preserves
   the `supabase/functions/CLAUDE.md`-pinned `console.error("[fn-name] request_id=X", err)` shape).

## Design review arc (×2, context-blind, both independently verified against live source at HEAD)
- **Reviewer 1 (correctness lens): SHIP**, one fold-in. Confirmed scope/closure/type safety (no
  shadowing; `cappedHistory`/`chatRequestId` both `const` in the enclosing scope, already referenced
  inside this exact catch today; `capCoachHistory` never returns undefined — `tool-loop.ts:169` guards
  non-array input to `[]` — so `.length` is always safe). Confirmed log-volume reasoning via the
  `index.ts:787` precedent (same density class, no new volume regime). **Found the originally-proposed
  test strategy (extracting the two log templates into pure formatter functions for unit-testability)
  disproportionate** — `tool-loop.test.ts` only asserts on `capCoachHistory`/`repairHistoryAlternation`'s
  *return values*, never log-string content, and every existing `console.log`/`console.error` in
  `index.ts` (incl. the `:787` precedent, and `:283`/`:333`/`:907`/`:926`) is a plain untested inline
  template literal — extraction would be a new, unprecedented pattern for a diagnostic log line.
  **Folded in: ship plain inline edits; verify via a founder-gated live post-deploy smoke check**
  (one coach turn with history present → `get_logs` on ai-proxy confirms `history_len=N>0`), matching
  how the `:787` log was verified.
- **Reviewer 2 (scope/convention lens): NEEDS-WORK → resolved.** Confirmed H1/H2/H3 scoping faithful
  to the Hermes report + `memory/project_coach_ux_batch_inflight.md:139-147`; confirmed edit LOCATION
  matches H2's spec exactly (index.ts's own catch, not tool-loop.ts's internal catch); confirmed
  blast-radius tier (`platform`, path-based per `docs/blast_radius.yaml:54`, independent of diff size);
  confirmed the SoT-registry skip is correct (diagnostic Deno logs, ~24h retention, not a persisted
  read/write contract — matches existing unregistered `console.error` calls in the same file);
  confirmed commit-type precedent (`feat(ai-proxy):`, no `closes-diagnose` — matches Unit 2 `c376f93`
  `feat(coach):` / Unit 3 `4fe2839` `perf(coach):` in the immediately-prior batch). **Blocking finding
  (process, not code): no `docs/plan-reviews/<branch>.md` keystone existed yet for a v74 branch, and
  the §4.12.1 pre-implementation ×2 review needed to be shown to have run, not just a B-pass.**
  Resolved: this document IS that record. **Additional finding:** verify edit 2 keeps `loopErr` as the
  last positional arg to `console.error` — confirmed already true in the shipped diff.
- One fold-in (simplification — dropping code, not adding it) + one process item (this document) →
  neither touches the actual runtime code path beyond what both reviewers already verified →
  **converged at Round 1, no Round 2 needed.**

## Ground truth (main agent — verified in source, not subagent prose)
Re-read `supabase/functions/ai-proxy/index.ts:810-836` directly in the worktree copy before editing
(identical to the main-folder copy read moments earlier — same HEAD `ef7afb9`). `capCoachHistory`'s
return type (`supabase/functions/_shared/tool-loop.ts:158-169`) is `Array<{role, text}>`, guarded to
`[]` on non-array input — `.length` access is unconditionally safe. `history` is untyped JSON from
`req.json()` (`:180`), matching `capCoachHistory(raw: unknown, ...)`'s signature.

## STATUS — implementing
Edit applied in worktree `v74-coach-telemetry`. Next: commit (`feat(ai-proxy): add coach-history
telemetry (v74 H2)`), self-triggered B-pass (≥platform, before the `--no-ff` merge) → set
`bpass: accepted` here, merge to local main. ai-proxy deploy (v73→v74, verify_jwt=false, standard
host-shell flow) + push = each their own explicit founder go, separate from this plan's approval.
