---
reviewed_at: 2026-08-01T21:05:00+05:30
staged_against: 6584fc31ad5b
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 3
verdict: accepted
---

# Code Review (B-pass) — `6584fc31ad5b`

Branch `oi45-phase-advance-monotonic` (Unit 3c + task #41, closes OI-45,
diagnose `c8f3d1`). Self-triggered before the merge per §4.3.

**Note on the hash.** The pass ran against staged state `526413f544e5`. Applying
its findings moved the staged set to `0119a592b81f`, and clearing Gate 43
afterwards (allow-list entry + OI-84) moved it again to `6584fc31ad5b`, which is
what this record is named for and what the gate reads. `docs/reviews/` is
excluded from that hash, so renaming this file does not perturb it — verified by
recomputing after the rename. The three findings below were raised against
`526413f544e5` and all are resolved in the final state.

**3 findings: 2 P2, 1 P3. No P0, no P1.** The pass independently reproduced the
negative control (bypass `phaseAdvanceTarget` → D1 fails `Expected: <3> Actual:
<2>`; restore → green), which is the check that matters most for a batch whose
whole claim is "these tests discriminate".

## Finding 1 — P2 — writer_reader_drift / data_consistency

- **file:line:** `lib/features/train/screens/graduation_screen.dart:637-720`
- **claim:** When `commitPhaseAdvance` declines the counter write, the
  `schedule_*` rows and `plan_start` that `generateAndSchedule` already wrote for
  `nextPhase` are not rolled back or reconciled. Reachable because the four
  restore-path writers filed as OI-83 bypass `withPhaseAdvanceLock` entirely, so
  one can bump `current_phase` while graduation is mid-generation inside the
  lock. The counter is correct; the schedule content can be stale. Neither review
  round had named this — OI-83 discussed the demotion, not the surviving rows.
- **verification:** read `_onPro` `:588-720` in full and `commitPhaseAdvance`
  (`pro_phase_advance.dart:266-303`); confirmed the commit only ever guards the
  `progress` map, never the schedule write that already ran.
- **status:** accepted — fixed, both halves:
  1. **Narrowed in code.** Graduation re-reads the live phase *inside* the lock,
     immediately before generating. The pre-lock check cannot see a bump landing
     between it and acquisition, and the OI-83 writers never take the lock. One
     Hive read replaces a wasted full generation. Its own event,
     `phase_unlock_preempted_before_generate`, distinct from the post-generate
     decline so the two are not conflated.
  2. **Named in OI-83** for the window this does not close (a bump landing
     *during* generation) — written into that entry as a "second-order effect"
     rather than left to be rediscovered as a fresh incident.

## Finding 2 — P2 — blast_radius_mismatch

- **file:line:** diagnose-doc frontmatter vs `docs/blast_radius.yaml:25`
- **claim:** Frontmatter self-declared `account`; the classifier measures the
  staged set as `platform`. Driven entirely by this batch editing
  `docs/blast_radius.yaml`, which the registry makes platform-tier by its own
  self-referential rule — every `lib/` file here is individually `account`. That
  tier's `requires:` is
  `[regression_test, behavioral_test_path, code_review_b_pass, feature_flag]`,
  and no flag gated the new code.
- **verification:** `git diff --cached --name-only | dart run
  scripts/blast_radius_from_diff.dart -` → `platform`; per-file loop showing only
  `docs/blast_radius.yaml` resolves platform; grep of the diff for
  `kill.?switch|FeatureFlag|PlanEngineFlags|configBox.get\(` finding no new flag.
- **status:** accepted — fixed. Frontmatter → `platform`. Added
  `configBox['disable_phase_advance_lock']`, gating **the lock only**, in the
  established default-OFF-means-active `disable_*` shape
  (`disable_phase_reconciler`, `disable_bg_restore`). The split is deliberate and
  documented in the code: the lock is the risky new primitive — round-2 review
  already found one starvation bug in it — so a runtime escape hatch has real
  value; the monotonic guard is pure, cannot wedge anything, and a switch whose
  only effect is to re-enable the demotion bug is not a safety valve. Covered by
  a new test that fails if the switch stops working.
  **Own-error note:** the earlier `account` measurement was mine, and the cause
  was classifying a hand-typed list of four `lib/` paths instead of the actual
  staged set. Classify `git diff --cached --name-only`, never a remembered list.

## Finding 3 — P3 — restore-path latency

- **file:line:** `lib/core/services/phase_progress_reconciler.dart:69-112`;
  callsite `lib/features/auth/screens/restoring_screen.dart:384`
- **claim:** The retry loop added by round 2 lands on the **foreground-awaited**
  restore path, not the background twin at `:696`, so a contended boot pays the
  full retry budget before /home renders.
- **verification:** read `restoring_screen.dart:375-394` — the callsite is
  `await`ed and its own comment says the corrected counter must land before
  /home reads `currentPlanProvider`; cross-checked the 15 s CONTINUE escape
  hatch in `lib/features/auth/CLAUDE.md`.
- **status:** accepted — fixed. Retry gap 1.5 s → 1 s, worst case **2 s**.
  The reviewer quoted ~4.5 s; the arithmetic is 2 gaps for 3 attempts, not 3, so
  the original was 3 s — corrected here and in the code comment rather than
  carried forward.

## Lenses checked clean

- **function_exception_swallow** — `git diff --cached | grep "functions.invoke"`
  → zero (client-only change). All three entry points
  (`splash_screen.dart:255-262`, `phase_generating_card.dart:50-71`,
  `graduation_screen._onPro`'s pre-existing `try/catch` at `:565-796`) still
  wrap the new code; a throw from `commitPhaseAdvance` lands where it did before.
- **unawaited_no_error_sink** — every new `unawaited(` wraps
  `ErrorTelemetry.logEvent`, the designated sink, which has its own internal
  try/catch (`error_telemetry.dart:263-278`).
- **secrets_in_tree** —
  `git diff --cached | grep -inE "sk-[a-z0-9]{10,}|rzp_live_|AKIA[0-9A-Z]{10,}|-----BEGIN|eyJhbGciOi"`
  → zero matches.
- **writer_reader_drift (beyond F1)** — `rank_service.dart:424` reads a
  same-named `phase_started_at`, but from the **profile** map (onboarding tenure
  clock), not `progress`; confirmed by reading it and `rank_ladder_data.dart:49`.
  Unrelated field, no drift.

## Gate results

| gate | result |
|---|---|
| `blast_radius_from_diff.dart -` (staged set) | `platform` |
| `flutter analyze --no-fatal-infos lib/` | 43 issues, all pre-existing info-level in untouched files; `No issues found!` on the 4 touched lib files |
| Gate 42 `check_sot_behavioral_test_paths.dart` | PASS — all 106 SoT concepts have `behavioral_test_path` |
| `validate_diagnose_doc.dart c8f3d1` | OK |
| `build_oi_index.dart` then diff | regenerates byte-identical (no stale hand-edit) |
| `flutter test pro_phase_advance_behavioral_test.dart` | +15 all passed (14 at review time, +1 kill-switch test added by F2's fix) |
| negative control (bypass `phaseAdvanceTarget`) | D1 FAILS `Expected: <3> Actual: <2>`; restored → green |
