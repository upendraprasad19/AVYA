---
adr_id: 0012
title: Derive-only AI coach tool surface (the user logs raw input; the app computes the rest)
status: accepted
date: 2026-05-31
deciders: Upendra
---

# ADR-0012: Derive-only AI coach tool surface

## Context

The AI coach (`ai-proxy` → Gemini 2.5 Flash) exposes typed tools the model can
call to act on the user's data (`_shared/tools/registry.ts`, dispatched client-side
by `lib/features/ai_coach/services/tool_dispatcher.dart`). The surface had grown to
**24 tools** across registry growth in Tests #12–#16.

A tool-surface audit through the lens "what should a user actually be allowed to
*assert* vs. what should the app *compute*?" found four tools that let the model
(or a replayed intent) assert a **derived** value or a **future** state rather than
raw, present-tense input:

1. **`logPR`** — let the AI assert a personal record. But PRs already *derive*:
   `WorkoutWriteService.logExercise` → `_rescanPrFor` stamps `is_pr` (strict `>`),
   and `WorkoutRepository.loadAllExercisePRs` computes best-per-set from `exlog_*`.
   A separate `logPR` could mint a PR with no real set behind it.
2. **`markWorkoutComplete`** — let the AI assert a day "done". Completion should
   *follow from logging*, not be declared. Asserting it decouples streak /
   deployment / rank credit from actual work — the same integrity hole as `logPR`.
3. **`adjustCaloricTarget`** — let the AI overwrite the calorie target. The target
   *derives* from the plan + profile; a chat-driven override is a silent
   progression-gaming surface.
4. **`prelog`** — let the AI log meals/sets for a *future* date. Founder direction:
   "no pre-logging — the user logs every day as they eat." Future-logging invites
   double-counting and fabricated history.

The recurring failure mode on this codebase is **writer/reader drift** (15+
instances). A tool that asserts a derived primitive is drift waiting to happen: it
creates a *second* writer for a value that already has a canonical derivation, and
the two inevitably diverge.

## Decision

**The AI coach may log only raw, present-tense input and perform confirmed
user-intent plan edits. It may never assert a value the app already derives, nor
log into the future.** Concretely:

- **Remove the 4 tools** from `registry.ts` (the single chokepoint offered to
  Gemini), retire their `_shared/tools/**` impls + Deno `__tests__`, and remove the
  client dispatch cases + `_execute*` helpers in `tool_dispatcher.dart`
  (defense-in-depth: a stale/replayed intent for a removed tool cannot dispatch).
- **Derive completion instead of asserting it.** After a coach `logSet` for a date
  that has a `schedule_*` row, the dispatcher's `_maybeCompleteScheduledDay`
  auto-calls the existing canonical `WorkoutWriteService.markCompleted` (idempotent —
  skips if already `completed`; only fires when a schedule exists for that date).
  This reuses the exact writer the UI finish button uses → feeds streak / deployment /
  rank with zero new completion logic and zero SoT drift.
- **Keep PR + calorie-target derivation untouched** — they were already correct;
  the fix is removing the tools that could override them.
- **Final surface = 20 tools (FREE 9 / PRO 11)**, down from 24.
- **Keep all 5 plan-edit tools** (`switchGoal`, `regeneratePlanBlock`,
  `rescheduleWeek`, `pausePlan`, `modifyWorkoutForInjury`) — they serve real
  life-event needs, are all destructive-confirmed via a diff sheet, and edit plan
  *intent* (not derived results). Each is verified end-to-end for cross-surface SoT
  correctness.

Principle, stated for future tool proposals: **the user logs raw input; the app
computes the rest.** Any proposed tool that would let the model write a value with
an existing canonical derivation is rejected by default.

## Alternatives considered

1. **Keep `logPR`/`markWorkoutComplete` but add server-side validation** (e.g.
   reject a PR not backed by a logged set). Rejected — that re-implements the
   derivation as a *validator*, doubling the logic that already lives in
   `_rescanPrFor`; the two would drift. Removing the tool is simpler and strictly
   safer.
2. **Keep `prelog` but cap it to "today + tomorrow".** Rejected — any future window
   invites double-counting and contradicts the founder's "log daily" model; there
   is no real user need a same-day log doesn't already cover.
3. **Keep `adjustCaloricTarget` PRO-only.** Rejected — gating doesn't remove the
   integrity hole; a PRO user can still silently desync their target from the plan.
4. **Leave the tools, document "don't use".** Rejected — the model is offered every
   tool in `ALL_TOOLS`; documentation doesn't constrain a function-caller. The
   registry is the only real chokepoint.

## Consequences

Good:
- One canonical writer per concept; the AI can't create a second writer for a
  derived primitive → closes a whole writer/reader-drift sub-class at the source.
- Completion, PR, and calorie target are provably computed from raw logs — they
  can't be gamed via chat. Streak/deployment/rank credit always traces to real work.
- Smaller, sharper tool surface (20 vs 24) → less Gemini confusion, lower
  mis-dispatch risk.

Bad / watch:
- **Platform blast radius:** removing tools changes every user's AI. Mitigated by
  the in-batch contract + behavioral tests, the live-web per-tool E2E matrix, and a
  `/code-review` B-pass before commit.
- **No "log a PR" shortcut:** a user who wants to record a max must log the set
  (which then derives the PR). This is intended — it keeps the data honest.
- **Future tool proposals must pass the derive-only test.** A reviewer must ask "is
  this value already derived?" before adding any write tool. Pinned by
  `test/contracts/derive_only_tool_surface_test.dart` (registry = 20, the 4 removed
  absent, dispatcher has no removed cases, completion-derivation wired).

## Status

Active. Shipped 2026-05-31. `ai-proxy` redeployed (v68) byte-identical via the
host-shell flow; smoke 401 (reachable + gated). Account/platform blast radius.

## Amendment — Unit 1 completion tap-card (2026-07-06, diagnose 280c4d)

The derive-only decision above (completion *follows from logging*, never
AI-asserted) is UNCHANGED and reaffirmed. This amendment refines HOW the
derivation fires, after the founder found that the original
`_maybeCompleteScheduledDay` auto-completed the WHOLE scheduled day on the FIRST
coach `logSet` — no "all exercises logged" check — inflating streak / rank /
deployment (a single set earned a full day's completion credit).

Post-fix, completion still derives from logging but only in two honest cases:

1. **All-logged auto-backstop** — the day auto-completes via the same canonical
   `WorkoutWriteService.markCompleted` (`completed_via:'auto'`) ONLY when
   `plannedCount > 0` AND EVERY planned exercise in `schedule_<date>['exercises']`
   has a log today (swap-tolerant via `swapped_from`; warmup/cooldown/finisher
   optional). An empty `exercises[]` plan-less / legacy / restored ad-hoc day is
   **NOT** auto-completed (finding-4) — with nothing planned there is no "done" to
   derive, so it falls through to the tap-card and completes only on an explicit
   tap (auto-completing it off ONE ad-hoc coach log would resurrect the founder
   bug). A fully coach-logged workout still auto-completes → no lost-streak
   footgun.
2. **User-tapped card** — a genuine partial STAYS `planned` and the chat surfaces
   a two-button completion-prompt tile ("Recruit — log more exercises? [Log more]
   · [Complete workout]"); the tap derives completion via `markCompleted`
   (`completed_via:'tap'`). The tap is the reliable fallback whenever a name
   mismatch / post-hoc edit makes the auto-check miss.

This is still **not** the model asserting completion — both paths route the
canonical writer off REAL logs / an explicit user action. The method +
`markCompleted` call + rest-guard are KEPT (so `derive_only_tool_surface_test`
stays green). The completion-prompt row is a LOCAL-ONLY coachBox action row
(`kind:'completion_prompt'`, excluded from cloud push + restore — never an
`ai_coach_interaction`). Client-only; no `ai-proxy` change. Pinned by
`test/contracts/coach_completion_prompt_test.dart`. See diagnose 280c4d.

## See also

- `supabase/functions/_shared/tools/registry.ts` (the 20-tool chokepoint)
- `lib/features/ai_coach/services/tool_dispatcher.dart` (`_maybeCompleteScheduledDay`)
- `lib/core/services/workout_write_service.dart` (`markCompleted`, `_rescanPrFor`, `logExercise`)
- `lib/features/train/repositories/workout_repository.dart` (`loadAllExercisePRs`)
- `test/contracts/derive_only_tool_surface_test.dart`
- `test/contracts/coach_derived_pr_and_completion_test.dart`
- `test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart`
- `docs/architecture/ai.md` (tool-calling section) + `docs/architecture/functionality-flow.md` (COACH-06 / COACH-08)
- ADR-0004 (single AI coach endpoint) — the surface this prunes
