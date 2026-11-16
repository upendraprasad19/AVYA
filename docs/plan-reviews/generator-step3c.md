---
branch: generator-step3c
blast_radius: platform
review_rounds: 6
ground_truth_verified: true
verdict: converged
bpass: pending
bpass_review: docs/reviews/generator-step3c-bpass.md
---

# Plan review: generator-step3c (Unit 3C, the cardio finisher shown, injury-safe and timed, OI-396)

- **Plan:** `docs/plans/2026-11-16-generator-step3c-cardio-finisher.md` (rev 7, built).
- **Founder basis:** 2026-10-22 (show it after the main lifts, injury-safe); d56 (decided before sizing, rule-14
  waiver), d61 (the time comes from the finisher days), d74 (any injury), d75 (the `hasGymOverride` block moved),
  d76 (under 60 minutes the 4-minute finisher), d77 (a coach injury is saved to the profile), d78 (the profile is the
  only signal; nearest joint), d79 (shortening drops the finisher first).
- **Tier and blast radius:** tier L (plan engine, coach, EF tool text), blast radius platform. Kill switch
  `disable_cardio_finisher_shown` (default ON; deletion OI-516); the model-facing tool descriptions ship with the
  ai-proxy deploy (founder go).

## Review rounds

Fresh, context-blind Sonnet seats (two per round), each verifying claims against the code and the real engine.

- **Round 1:** not converged; 4 P1 (the kill-switch goldens, the cost at 30 / 45 minutes unmeasured, a stored
  finisher shown to a user injured later, `shortenDay`). The cost was measured; the founder chose d76.
- **Round 2:** not converged; 2 P1 (seven more digests embed the finisher; timed finisher rows would show wrong
  durations) and the attribution oracle, the sweeps' finisher scan, the pricing parity test.
- **Round 3:** not converged; 2 P1, both the injured signal (`['none']` counted as injured; the coach's injury lived
  in coach memory only).
- **Round 4:** seat B converged, seat A not: P1 the coach-memory signal is not durable -> d77.
- **Round 5:** not converged; the coach-memory leg kept producing P1s and was removed (d78: the profile is the only
  signal); `shortenDay` drops the finisher first (d79).
- **Round 6:** converged, both seats no P0 / P1; rev 7 settled the P2s / P3s in text.

Ground truth: the cost table re-run on the built tree (equal to the prototype the founder chose from), the OFF golden
equal to main 862f0bc2 over 1,010 personas, the attribution test (410 keys, all Cut / Maintain), the mutation table in
diagnose `f3c9a6`, `deno check` of the two tool files and ai-proxy plus the 290 `_shared/tools` Deno tests.
