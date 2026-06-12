---
hermes_pass_id: 2026-06-13-hermes-e2e-obs-fixes
ran_at: 2026-06-13T01:30:00+05:30
batch_scope: main..HEAD (e2e-obs-fixes — 8 commits: delete-account EF + 2 gates + 9 obs)
lens_set: [auth_token_freshness, exception_control_flow_lifecycle, writer_reader_value_drift, dpdp_delete_blast_radius, regression_test_gate_adequacy]
agents_dispatched: 5
findings_by_severity: { P0: 0, P1: 2, P2: 5, false_alarm: many }
verdict: accepted
---

# Hermes Pass — e2e-obs-fixes (catastrophic-tier batch)

5 fresh context-blind Opus reviewers, one lens each, over `git diff main..HEAD`.

## Summary
- **0 P0.** The catastrophic paths are clean: delete is JWT-scoped to the token's own user; the confirmation gate is intact; the client wipes local data ONLY on a true 200 (callFunction rethrows any non-2xx before the success block); auth.users delete is error-checked BEFORE the audit step; the audit catch never rethrows; realtime self-cancel-from-onError is safe; the boot backfill runs only post-openForUser in both paths; the kIsWeb wrap doesn't break Android control flow.
- **2 P1 — both FIXED in-batch (this is what the Hermes pass is for):**
  - **P1-a (writer/reader): Obs#6 fix was INCOMPLETE.** The preview read `widget.data['lifestyle_activity']` — a key NO stepped screen writes (always `desk_job`) — while the commit DERIVES it from `activity_level` (`_onReportForDuty` switch). A moderate/4-day user still drifted (1.55 vs 1.725 ≈ 11%). FIXED: extracted the switch to shared `BmrCalculator.lifestyleFromActivityLevel()`; both the preview (`_computeTargets`) and commit-prep (`_onReportForDuty`) now derive via it → preview == saved by construction.
  - **P1-b (test adequacy, same root): the parity test pinned arg-NAMES, not VALUES** (why the drift shipped). FIXED: added a behavioral value-level test (`lifestyleFromActivityLevel('moderate')→'lightly_active'`, `resolveActivityLevel(...,4)→'active'`) + an anti-regression assertion that the preview does NOT read the never-written key.
- **5 P2 — fixed or annotated:**
  - **P2 (delete UX, flagged by 3 lenses): FIXED.** The "session_expired" message only caught a `FunctionException` 401, not callFunction's plain `Exception('No active session')` (the common backgrounded-web logged-out case) → showed the opaque generic. Now matches both.
  - P2 (gate breadth): `check_edge_function_auth_pattern` misses a JWT under an out-of-allowlist identifier (`jwtFromHeader`). ANNOTATED — the dominant `authHeader.replace("Bearer")` signature (what delete-account shipped) IS caught; residual surface, broaden later.
  - P2 (retry-guard 600-char window): a re-invoke >600 chars below a `status == 401` escapes. ANNOTATED — the canonical compounding-retry sits within a few lines; the refinement is a net improvement.
  - P2 (legacy/deep-link default skew): preview weight default 75.0 vs commit 0.0, days literal 4 vs goal-switch — only bites legacy-chat/deep-link users (stepped flow supplies all fields). ANNOTATED — a shared input-resolver would close it; out of scope for the drift fix.
  - P2 (arg-name-vs-value ceiling): addressed by the new behavioral test (P1-b).

## Founder triage
Accepted. Both P1s fixed in-batch (Obs#6 now actually closes the founder-reported 2867≠3200 drift); the delete-UX P2 fixed; remaining P2s are residual-surface ceilings annotated for follow-up, none re-open a fixed bug.

## Action items
- [x] P1-a — shared lifestyleFromActivityLevel; preview derives it (commit `<hermes-fix>`).
- [x] P1-b — behavioral value-level parity test.
- [x] P2 — delete session_expired also matches 'No active session'.
- [ ] P2 (follow-up, surfaced not deferred) — broaden the EF-auth gate key-slot detection; a shared onboarding input-resolver to kill the legacy default skew; whether the SAVED calc should honour stats activity_level + body_fat (founder calc-accuracy decision, broad blast).
