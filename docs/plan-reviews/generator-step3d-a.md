---
branch: generator-step3d-a
blast_radius: platform
review_rounds: 5
ground_truth_verified: true
verdict: converged
bpass: pending
bpass_review: docs/reviews/generator-step3d-a-bpass.md
---

# Plan review: generator-step3d-a (Unit 3D-a, the server's hold-week copy, FOB-4 / OI-175)

- **Plan:** `docs/plans/2026-11-16-generator-step3d-hold-weeks.md` (rev 5), section 2.3 (the server) and section 4
  (the 3D-a landing).
- **Founder basis:** d57 (switch "Keep training Phase 1" to the Monday-aligned holdWeek; the marker follows the
  cycle), d80 (hold weeks keep Peak, Peak, Peak, Deload; only the "you are here" marker changes).
- **Tier and blast radius:** tier L (Edge Functions), blast radius platform. No kill switch: the texts change only for
  a Phase-I user with a hold row, and holds reach users only when `enable_hold_weeks` flips (3D-b). The two deploys
  need the founder's go (`ship_dark_pending_review.yaml` FOB-4 `deploy_pending`).

## Review rounds

Fresh, context-blind Sonnet seats, each verifying claims against the code and live read-only state.

- **Rounds 1-3 (the combined 3D plan).** Not converged. Each round surfaced new P1s on the app half (the double tap,
  the covered rule, a completed day on a target date, the outcome enum, the refresh). On the server half: the IST
  week bounds (round 2 B-F3, round 3 B-F7), the Peak / Deload claim removed (round 2), the phase filter moved into a
  testable helper (round 3 B-F3), a read that never throws (round 3 B-F1). Under section 4.12.1 the plan split into 3D-a
  (server, first) and 3D-b (app).
- **Round 4 (3D-a only).** Not converged: a-F1 (P1) a missing progress row or a null phase must not read as Phase I,
  so the helper fails closed; a-F3 the recap's progress read must select `current_phase`, and the read must stay
  inside the try. A reviewer's claim that phase 2+ rows carry weeks 5-12 was checked live (read-only GROUP BY
  2026-11-16: phases 2 / 3 / 5 hold week_number 1-4 only). The claim was false, but the fail-closed gate was adopted.
- **Round 5 (3D-a, post round 4).** Converged. P2 / P3 folded in: F3 `fetchHoldOrdinals` returns `{map, failed}` so
  "no holders" and "read failed" differ, and the recap reports `hold_read_failed`; F4 states that the cloud has no
  `is_hold` column, so `week_number > 4` is the only server mark.

## Build verification

- `deno check --node-modules-dir=none` on both functions: clean. `deno test` on `_shared/hold_week_test.ts` (15),
  `weekly-recap-ready/index_test.ts` (4) and `weekly-report/index_test.ts`: green.
- Ten mutants A1-A10, all red (diagnose `docs/diagnoses/2026-11-16-hold-week-server-copy-c4e8b1.md`).

## B-pass

Pending.
