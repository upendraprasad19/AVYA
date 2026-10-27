---
branch: coach-completion-tap-card
date: 2026-07-06
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
hermes: not_required
---

# Plan-review record — coach-completion-tap-card (Unit 1 of the coach-UX batch)

Keystone record for the §4.12 merge gate. Unit 1 of the coach-UX batch (founder live-test 2026-07-06):
the coach's derived completion is fixed so a single `logSet` no longer completes a whole multi-exercise
scheduled day — completion now requires ALL planned exercises logged (auto-backstop) OR an explicit
user tap on a new completion-prompt card. Diagnose-doc: `280c4d`.

## Design review arc (context-blind; every claim verified against live code)
- **Round 1 (×2, design):** correctness + bug-introduction lenses. Surfaced the derive_only-test +
  ADR/SoT consequences of user-initiated completion, the real surgery behind the "history seam"
  (deferred to Unit 2), and the completion consumers (streak/rank/deployment/snapshot). Hardened.
- **Round 2 (design, hardened):** the "ephemeral card" version returned NEEDS-WORK — the chat thread
  renders only persisted `coachBox` rows (no ephemeral slot) and decoupling completion leaves
  `status='planned'` for downstream readers. Triggered the redesign (persisted `completion_prompt_<date>`
  row + all-logged backstop).
- **Round 3 (×2 confirming, redesign):** feasibility CONVERGED (`exlogKey` deterministic, rest-guard
  wired, `derive_only_tool_surface_test` stays green); bug-introduction enumerated 8 backstop edge cases
  (swaps / empty / warmup scope / name↔key / prompt-row lifecycle) — all folded in as guards.
- **§4.12 split discipline:** three review passes surfacing new material issues each time was the signal
  to split. Unit 1 ships first (client-only); Units 2 (memory, EF+Hermes) + 3 (snapshot trim) follow
  with their own reviews.

## B-pass (implementation adversarial review — Workflow, 5 fresh-context Opus reviewers)
- **Implement→verify:** bugs / spec-compliance / brand+a11y on the diff. bugs → NEEDS-WORK (3; 2 material:
  `chatHistoryProvider` never refreshed → the card wouldn't surface; `DateTime.parse` timezone
  double-shift east of UTC+5:30). spec + brand → CONVERGED with polish.
- **Fix→re-verify:** all 6 findings fixed (no deferrals) + flow/widget tests added; a bonus latent
  double-shift in the dispatcher auto-complete path also fixed. Independent bug-lens re-verify →
  **CONVERGED**. Detail: `docs/reviews/coach-completion-tap-card-bpass.md`.
- **Ground-truth (main agent):** both material fixes confirmed in source
  (`tool_dispatcher.dart:181` refresh gated on `log_set`; `ai_coach_provider.dart:277` UTC-midnight);
  **18/18 Unit-1 tests pass**, `flutter analyze` clean, 242 ai_coach tests green, SoT-parity +
  nested-CLAUDE.md gates PASS.

## Convergence
No deferrals. Diagnose-doc `280c4d` (validator-OK) + behavioral tests (`coach_completion_prompt_test.dart`
contract + `completion_prompt_card_test.dart` widget) + SoT (`coach_derived_completion`) +
`ai_coach/CLAUDE.md` + ADR-0012 amendment. Hermes not required — client-only, non-catastrophic, no
cron/Edge-Function fan-out. **CONVERGED → merged to main.**
