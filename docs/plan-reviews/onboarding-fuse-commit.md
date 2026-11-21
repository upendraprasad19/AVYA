---
branch: onboarding-fuse-commit
date: 2026-11-14
blast_radius: platform
review_rounds: 5
ground_truth_verified: true
verdict: converged
mechanical_only: true
bpass: accepted
bpass_review: docs/reviews/40877fa9d842-review.md
---

# Plan-review record: onboarding single commit (Plan + Induction fused, Muster removed)

Plan: `docs/plans/2026-11-14-onboarding-fuse-commit.md`. Founder decisions 2026-11-14 (chat): fuse Plan and Induction, button `I COMMIT →`, drop Muster, write `physique_focus: 'balanced'` at commit, no completeness nudge.

Five independent, context-blind Sonnet rounds, each verifying claims against code (read-only: cat/sed/grep/git). Every P0/P1 the main thread acted on was re-checked against the file first.

| Round | P0 | P1 | What changed |
|---|---|---|---|
| 1 | 2 | 3 | Profile has no `id` after commit, so the commitment sync was silently skipped; retry was not idempotent (cloud guard is written later in the background). |
| 2 | 1 | 4 | The retry marker (profile `onboarding_completed_at`) is written before plan generation; `already_onboarded` must stamp nothing; session must be open before reading induction getters; uid read must survive no Supabase client; wider docs/copy list. |
| 3 | 0 | 2 | Widget-sequenced commit left a window where ADJUST PLAN or an app kill lost the commitment: the stamps moved into `completeOnboarding` before `setOnboarded`, removing the retry marker; test seam added. |
| 4 | 0 | 2 | Design confirmed. Uid source switched to `HiveUserSession.currentOwnerFullId` (Supabase `currentUser` is null in every unit test); throw-injection hook for the order test; latent profile wipe in `_ensureLocalUser` found (closed by writing `id`). |
| 5 | 0 | 1 (mechanical) | Wrong test constant name; P2s applied (pure predicate for the wipe decision, try/catch around the hoisted session open, hook reset, FK race ruled out via signup trigger 039). |

Converged at round 5: no P0, the only P1 mechanical. B-pass (`/code-review`) on 40877fa9 after CI green: 2 P2, F1 fixed (registry ranges re-derived), F2 false alarm (pinned). `docs/reviews/40877fa9d842-review.md`.

## Found during execution (not in any review round)

- Hoisting `ensureOpenedForCurrentSession` above the guard emptied the profile: opening the session re-emits `authUserIdTokenProvider`, which rebuilds `OnboardingNotifier` with empty `state.answers`. The extended C1 test caught it (saved `full_name` was `''`). Fix: capture `state.answers` before the open. The same rebuild already broke `resolveStartDate()` (read after the old open position), fixed in the same batch by passing the captured answers. Diagnose d86bad, defect 3.
- The handler `_onReportForDuty` was not renamed (a dozen docs, tests and SoT entries cite it).
