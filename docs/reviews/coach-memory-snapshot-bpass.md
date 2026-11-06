---
branch: coach-memory-snapshot
date: 2026-07-08
blast_radius: platform
method: Workflow adversarial B-pass — 3 fresh-context Opus reviewers on the committed branch diff (c467423..HEAD), find-bugs mandate, structured findings verified against code + live state.
verdict: accepted
---

# B-pass (code review) — coach-memory-snapshot (Units 2 + 3 + FC8)

Self-triggered ≥account B-pass BEFORE the `--no-ff` merge (§4.3). Three fresh context-blind reviewers
on the committed branch diff (Unit 2 coach short-term memory [client + ai-proxy EF, already deployed
v73]; Unit 3 snapshot trim; FC8 Go-PRO CTA). Scopes: (1) Unit 2 impl, (2) Unit 3 + FC8, (3)
cross-cutting / contract / test integrity.

## Verdict: **SHIP** (all 3 reviewers), converged after one fix round.

## Confirmed safe (verified against code + live state)
- **Unit 2 self-leak defended** — the current turn's pending row (empty `ai_response`, `pending:true`,
  written at `ai_coach_provider.dart:698` / reset on retry `:691`) is assembled-AFTER and excluded by the
  pending/empty filters. History assembled ONCE, threaded into BOTH `chat()` sites (`:755` + `:826`) and
  both request bodies; `predict()` correctly carries none.
- **Server cap→repair order** — `capCoachHistory` (ai-proxy) runs BEFORE `repairHistoryAlternation`
  (tool-loop); repair is provably shrink-only and always emits strictly-alternating `user→model`, so a
  malformed/hostile history can never trigger Gemini's consecutive-same-role 400. Caps (≤16/≤2000/≤12000)
  enforced. An absent/empty history reproduces the exact pre-change `messages[]` — backward-compat with
  the already-live v73 for old clients. Deployed v73 confirmed to contain `capCoachHistory`/
  `repairHistoryAlternation` (matches committed source).
- **Unit 3 no null-read regression** — no EF/cron/widget reads `step_history_7d`/`sleep_7d`/`water_7d` off
  the persisted snapshot (verified across `supabase/functions` + `lib/`); `today_steps` retained;
  emit-then-remove keeps the source-based snapshot-contract gate honest; kill-switch works.
- **FC8 sound** — `isLimitReached ⟹ isWarning` (both `!isPro`-gated, `>= perDay` vs `>= perDay-3`); the
  opaque GestureDetector wins the tap over the disabled field; no double-paywall; below-limit field
  byte-identical after hoisting.
- Gate-19 `_alwaysOk` additions safe (never real exlog/nlog/wlog field names); Deno tests exhaustively
  cover repair + cap; the Dart behavioral test genuinely fails without the new method.

## Findings folded in (no deferrals, same batch — B-pass-fixes commit)
- **MED** — `_isHistoricalQuery` missed the natural weekly phrasings (`this week`/`how's`/`lately`/…), so
  the Unit-3 on-demand re-add (and the older weight/nutrition/exercise trends) didn't fire for
  "how's my sleep this week?" (the code's own docstring example). FIXED: added the keywords
  (`ai_snapshot_builder.dart:_isHistoricalQuery`) + a test (`coach_snapshot_trim_test` (b2)).
- **LOW** — sort tie-breaker on equal `created_at` (added the unique `coach_<ms>` key as the tie-break);
  strengthened `coach_snapshot_trim` (b) to a real regression guard (starts from a keys-removed base);
  fixed an invalid fixture timestamp (`01:60:00`); set the fixture `profile.id` to the session UUID (no
  more cross-account-guard fire); corrected stale line refs in the FC8 diagnose-doc (`182/76`→`198/111`)
  and the plan-review ground-truth (`742/810`→`755/826`).
- **Noted, no change (pre-existing, no regression)** — `_compactContext.trimSteps` lists `step_history_7d`
  + `water_7d` but not `sleep_7d`, so an over-budget power-user's on-demand re-add is asymmetric. Behavior
  is unchanged from before Unit 3 (reactive drop always applied); out of scope for this batch.

## Ground-truth (main agent)
All B-pass fixes applied + re-verified: `flutter analyze` clean on the changed lib; the affected contract
tests (coach_snapshot_trim incl. the new (b2), coach_chat_history_replay, ai_snapshot_budget_trim) all
green. **Verdict: accepted — SHIP.**
