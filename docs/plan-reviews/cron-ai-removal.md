---
branch: cron-ai-removal
date: 2026-09-16
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/247d945d1ba0-review.md
---

# Plan-review record — cron AI-copy removal (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Platform-tier
(touches `_shared/**` plus `streak-guardian/**`, `morning-alert/**`,
`proactive-coach-promotion/**` — all explicitly platform-tier per `docs/blast_radius.yaml`), so it
carries a B-pass. Not catastrophic → no Hermes.

## Scope

Remove Gemini AI calls from 9 Supabase Edge Functions, all identified as contributors to a
production 429 quota-exhaustion incident: 8 cron-dispatched notification functions
(`pr-detection`, `streak-guardian`, `plateau-alert`, `protein-gap-alert`, `re-engagement`,
`workout-window-closing`, `morning-alert`, `proactive-coach-promotion`) converted to deterministic
copy templates, and `future-prediction` converted from a Gemini-forecast prompt to real trend math
over the user's own weight/lift/adherence history. Spec:
`docs/superpowers/specs/2026-09-16-proactive-cron-ai-removal-design.md`. Plan:
`docs/superpowers/plans/2026-09-16-proactive-cron-ai-removal.md` (10 tasks, executed inline per
founder's explicit choice to save tokens over subagent-driven execution).

## Root cause (why this exists)

7 of the 9 functions called Gemini only to phrase a push/chat message whose underlying send
decision was already computed deterministically in SQL, and 6 of the 7 already shipped a working
hardcoded fallback template that ran today whenever Gemini failed — the AI call was adding shared
project-wide rate-limit pressure (the same quota live user chat/food-log traffic draws from) for
no product value beyond copy variation the fallback already approximated. `future-prediction` was
a related but distinct problem: it asked Gemini to forecast raw numeric values instead of computing
them, an accuracy issue independent of the quota incident. `proactive-coach-promotion` additionally
had NO fallback at all (a Gemini hiccup silently dropped a user's promotion — no chat message, no
push, bare 500) and bypassed the shared `_shared/gemini.ts` retry helper via raw `fetch` — a
standalone reliability bug, fixed as part of this batch (diagnose `b7c9e2`).

## Review arc (4 rounds + self-triggered B-pass; §4.12)

All four review rounds dispatched via `Agent({subagent_type: 'general-purpose', model: 'sonnet', ...})`
per standing founder instruction ("run the review, but don't use Opus or higher, to save tokens").
Every finding from every round was independently re-verified against live code before acting — never
trusted from subagent prose — per this repo's own standing discipline.

- **Round 1 — context-blind review of the initial 10-task implementation.** Found **P1**: the new
  `future-prediction` real-trend-math path (Task 10) fed `completionRateOverWindow`'s return value
  straight into `predictStreakWeeks` without distinguishing "brand-new user, zero schedule history"
  from "a real 0%-completion week" — both return `0.0` from the shared helper, so every new user's
  90-day forecast card silently showed "0 weeks" instead of the intended flat fallback. Fixed:
  a schedule-row existence probe at the call site (`593094e3`, `closes-diagnose: 9c3d7a`). The same
  fix commit also folded in two smaller review-surfaced doc-drift findings: `docs/architecture/ai.md`'s
  Model matrix still listing `morning-alert`/`future-prediction` as Gemini callers, and stale line
  numbers in the `b7c9e2` diagnose-doc's own impact analysis.

- **Round 2 — dispatched on the post-Round-1-fix state, specifically to check whether the Round 1
  fix itself introduced a new defect (§4.12 point 1).** It had: **P1** `e5c9b2` — the 9c3d7a fix's
  own schedule-existence probe used `istDateStr()` (IST-shifted) while `completionRateOverWindow`,
  the function it's meant to mirror, uses a raw-UTC cutoff for the same instant — the two could
  disagree by up to a day near the UTC day boundary, narrowly reopening the exact bug class 9c3d7a
  had just closed. Fixed by extracting a single shared `windowSinceDateUtc(windowWeeks)` helper into
  `_shared/rank_engine.ts` so the two callers can never independently drift again (`0f9033f3`) — a
  pure refactor, proven zero-behavior-change by `unit_c_read_hardening_test.ts` staying green
  unmodified. Also found: `a1f7d3` — `proactive-coach-promotion`'s `ai_coach_interactions.model_used`
  still hardcoded `"gemini-2.5-flash"` after the congrats rewrite, mislabeling the exact ledger a
  post-429-incident batch should want accurate (`5a21eebd`); and 6 stale `llm_prompt_input_sanitization`
  SoT-registry entries plus 4 stale "Gemini fallback" comments describing an architecture this batch
  had already removed (`bd543f34`).

- **Round 3 — dispatched with an explicit instruction to actually RUN the Flutter contract test
  suite, not only read source, since neither Round 1 nor Round 2 had been asked to.** Found **P1**
  `c4e8a1`: `test/contracts/proactive_coach_promotion_test.dart` had gone stale when an earlier
  commit in this same batch (`f4d771d2`) extracted `RANK_LABELS`/`composeCongrats` into a new sibling
  file, `congrats.ts` — 3 assertions became false statements about the current code. This repo's
  pre-commit hook deliberately skips `flutter test` (ADR-0018) and the branch hadn't been pushed, so
  nothing had caught it. Fixed (`97fc6594`) — and while mutation-proving the repointed test, also
  discovered and fixed a latent PRE-EXISTING vacuity in the original assertions (bare `'LS:'`/`'PO:'`
  substring checks that nested inside unrelated text and would stay green even if that rank's entry
  were deleted).

- **Proactive follow-up (same review cycle as Round 3, executor-initiated rather than waiting for a
  4th dispatch to find these one at a time).** Grepped every `test/contracts/*.dart` referencing any
  of this batch's 9 touched functions and ran them all. Found 2 more instances of the exact same
  class: `streak_guardian_eligibility_test.dart`'s milestone/goal-weight assertions still read
  `index.ts` after that logic moved to a new `message.ts` (this batch's own Task 2), and
  `docs/snapshot_contract.yaml`'s `future_prediction`/`morning_alert` reader-line citations had drifted
  from this batch's own Gemini-removal edits shifting lines above them. Both fixed (`f57e8339`,
  `closes-diagnose: f8a3c6`). This recurring class (3rd instance in one batch — CLAUDE.md §4.9's
  "extraction breaks source-grep contracts" pitfall) was recorded in the debugging skill
  (`dc1332f6`, bug-class 2.66) and the CLAUDE.md pitfall table (`247d945d`), noting explicitly that
  two full review rounds missed it because neither ran `flutter test`.

- **Round 4 — dispatched on the fully-converged state (post-`f8a3c6`, full `deno test` 513/513 and
  full `flutter test` 5736/5736 green).** Returned no material findings — the signal per §4.12 point 1
  to stop reviewing rather than dispatch a 5th round.

- **Self-triggered `/code-review` B-pass (CLAUDE.md §4.3), dispatched on the FULL branch diff before
  merge** — a distinct lens set from the 4 plan-review rounds above, run fresh. 6 findings (2 P1,
  1 P2, 3 P3), 0 false_alarm, all independently re-verified (the two P1 fixtures reproduced exactly
  via `deno run`/`deno test` before any fix was written). Full detail and per-finding disposition:
  `docs/reviews/247d945d1ba0-review.md`.
  - **Finding 2 (P1, fixed)** — `trend.ts`'s `predictWeight`/`predictLift` had no sanity clamp on
    their linear-regression output: a plausible short weight history could forecast 32.2kg, a
    plausible short lift history could forecast -145kg. Clamped both to a factor of the last observed
    value (`2d6738c7`, `closes-diagnose: b2f7c4`).
  - **Finding 1 (P1, not a code defect — a scope question)** — `future-prediction` has no confirmed
    live caller anywhere in the shipped app (no client call site, no cron schedule, not in
    `CRON_REGISTRY.md`); the actual live prediction surface calls a separate, untouched, still-Gemini-
    calling `ai-proxy` path. Presented to the founder with 4 options; founder chose to leave this
    batch's `future-prediction` work as-is (real, harmless improvement regardless of reachability)
    and defer the wire-up-vs-delete decision. Tracked as **OI-210**, not fixed in this batch.
  - **Finding 4 (P3, partially fixed)** — `check_sot_registry_parity.dart`'s line-range parser is
    blind to bare (non-dash) `line_range: N` entries; the one concretely-verified-stale entry this
    finding named (`streak-guardian/index.ts`, `214`→`264`) was corrected directly. The parser-widening
    half was drafted, found to surface 14 MORE stale citations in subsystems this batch never touched
    (auth, sync, notification-inbox, day-rollover) against a gate that runs unconditionally on every
    commit repo-wide — landing it half-done would have failed pre-commit for every future commit.
    Reverted; filed as **OI-209** instead (precedent: OI-207, same shape).
  - **Findings 3, 5, 6 (P2/P3, fixed)** — stale documentation/comments, no behavioral change: a
    `sot_registry.yaml` concept still described streak-guardian's removed Gemini flow; a
    `congrats.ts` comment overclaimed retry-stability; a `morning-alert` comment said "Parallel AI
    calls" after the only AI call was removed. All corrected (`2f0203d1`).

## Convergence

Every finding across all 4 review rounds and the B-pass was fixed in the same batch that found it,
except the two the B-pass itself determined were genuinely out of this batch's scope (a
product-reachability decision, and a repo-wide gate change touching unrelated subsystems) — both
resolved via an explicit founder decision and a filed OI rather than silently dropped. After the
final fix commit (`2f0203d1`, plus the OI filings and this record): full `deno test` 515/515, full
`flutter test` 5736 passed / 0 failed (7 pre-existing unrelated skips) — re-run fresh after this
session's final round of fixes, not carried over from an earlier run. `check_sot_registry_parity.dart`
PASS, 0 errors (unwidened parser, unaffected by this batch's registry edits). Round 4 and the B-pass
both returned with no unresolved material issue — the §4.12 point 1 signal to stop, not split further.

**Verdict: converged.**
