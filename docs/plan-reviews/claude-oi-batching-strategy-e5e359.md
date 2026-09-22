---
branch: claude/oi-batching-strategy-e5e359
date: 2026-09-22
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/5ebf78e29706-review.md
---

# Plan-review record — Batch A (OI-230, OI-232, OI-228 Bug A)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).
Account-tier (`ai_coach` is explicitly account-tier per CLAUDE.md §4.12.6, not
S-eligible) — requires `review_rounds >= 2` + `bpass: accepted`, not `hermes`
(catastrophic-only).

## Scope

Three independent, founder-filed AI-coach bugs, grouped into one batch
("Batch A") at the founder's explicit request, run autonomously from fix
through to this record per that request:

- **OI-230** — `ai_snapshot_builder.dart`'s `_getEtaNextPromotion()` branched
  on a hardcoded `remaining['workouts']` lookup that is permanently dead (no
  `kRankGate` entry ever sets `totalWorkoutsAtLeast`), so every user with a
  next rank saw a fabricated "promotion today".
- **OI-232** — AI coach chat left at whatever scroll position it happened to
  land on after switching from Telegram back to in-app chat; the existing
  `_initialScrollDone` gate is a one-shot first-paint-only guard.
- **OI-228 Bug A** — the "Log Workout" sheet's empty state didn't distinguish
  a completed day from a genuinely empty one (Bug B, `shortenWorkout` stuck
  at `status:queued`, is unrelated and stays open).
- Plus, found and fixed while implementing OI-230: a dead Hive key
  (`current_rank_earned_at`), `remaining['streak_days']`'s `current` always
  hardcoded 0, and the code-hygiene half of OI-231 (routing through
  `RankService.getCurrentRank()` instead of duplicating its Hive read — the
  root-cause half, a possibly-stale rank address, stays open pending live
  verification). The officer/MCPO `completionRateMinimum` gate-modeling gap
  surfaced during the fix was scoped OUT and filed as **OI-240** rather than
  absorbed into this batch.

## Review rounds

**Round 1 — pre-implementation, context-blind.** Found 4 must-fix issues:
a missing guard for completion-rate-gated ranks (officer/MCPO track) that
would have let `_getEtaNextPromotion()`'s new `'weeks'` branch confidently
return a wrong deterministic answer for those ranks instead of an honest
"cannot estimate"; an incorrect OI-231 closure framing (the hygiene fix
alone does not explain the reported stale-rank-address symptom, since
`getCurrentRank()` reads the identical key/default — corrected to keep
OI-231 open pending live verification rather than closing it on the
hygiene fix's strength); 2 tests that would have silently broken against
the hardened plan; and a bug-history citation gap (§4.1.5 — no prior
diagnose-doc directly covers this constraint-selection shape). All
addressed before round 2.

**Round 2 — pre-implementation, on the round-1-hardened plan (per §4.12
point 1).** Found 2 more: OI-228 is a compound filing (Bug A + Bug B) and
the plan needed to explicitly close only Bug A, leaving Bug B open rather
than implying the whole OI was resolved; and a cross-branch OI-number
collision risk — OI-228/230/231/232 were originally reserved on a sibling
branch (`claude/food-logging-observations-126ab3`, PR #31, unmerged),
and adopting them here (verbatim text, per root CLAUDE.md §7's OI
allocator row) creates a real gate-failure collision risk when that
branch eventually merges, not just a text merge conflict — the same shape
that already fired once for OI-226 (confirmed live: `closed_issues.md`
already carries OI-226 CLOSED via the merged `observation-batch-and-
digest-redesign` PR, from the same original reservation batch as this
one). Round 2 also independently confirmed the `'workouts'` ETA branch is
permanently dead code (verified live: no `kRankGates` entry sets
`totalWorkoutsAtLeast`, `rank_ladder_data.dart:196-249`), which the
implementation kept (for the day a rank ever gates on it) but never
relies on. No material issues remained — converged.

**B-pass — self-triggered before the `--no-ff` merge, per §4.3 (not
waited for).** Run as one fresh, context-blind Sonnet subagent per
`.claude/skills/code-review/SKILL.md`, all 8 lenses, over the full
implemented diff (16 files: 6 code/test files, the rest diagnose-doc/
OI-board prose). **3 findings (0 P0, 1 P1, 1 P2, 1 P3); 0 false_alarm —
all 3 fixed in the same commit as the diff they were found in**
(`7af6123c`):
- P1 (`guard_without_its_mirror`): the OI-232 regression test was a raw
  source-presence check with no comment-stripping — mutating the fix by
  commenting it out (not deleting it) left all 5 tests in the file green.
  Fixed by adding `readScreenSourceStripped()` (wrapping the pre-existing
  private `_stripComments` helper) and switching the file's shared
  `setUpAll` to it; re-mutated post-fix, now reddens exactly the intended
  test.
- P2 (self-attesting artifact): two closure-board entries cited
  `docs/diagnoses/<pending>.md` for diagnose-docs the same diff already
  created with fully-known names. Fixed — all 5 `<pending>` sites (4 in
  `closed_issues.md`, 1 in a test's failure-reason string) replaced with
  the real identities.
- P3 (gate-blind stale citation): the new SoT registry entry's
  `line_range` was 6 lines short — missing exactly the `remaining`/
  `binding_constraint` fields this batch is about — invisible to
  `check_sot_registry_parity.dart` because a two-method `method: A / B`
  field fails its bare-identifier regex and the gate silently skips the
  check. Fixed by widening the range; independently re-confirmed the real
  span by reading the file directly rather than trusting the finding's
  numbers.

Full detail: `docs/reviews/5ebf78e29706-review.md` (renamed once, after
the fixes above were staged, from the hash the B-pass was dispatched
against — the standard hash-fixed-point rename this skill's own tuning
history documents; `docs/reviews/` is hash-excluded so the rename itself
did not move the hash again).

## Convergence

Two pre-implementation rounds, material findings in round 1 (design-level:
a missing gate, a wrong closure framing) narrowing to round 2 (compound-
filing scoping, a cross-branch collision risk already once realized
elsewhere) — the §4.12.1 convergence signal (findings narrowing in kind,
not growing). The B-pass then found a third, independent class
(test-defeatability, stale self-references) in the implemented code,
exactly the gap a plan review — which reads prose, not code — cannot see.
All three rounds' findings reached a terminal state before this record was
written.

## Ground truth verified

- Every plan-review round's claims were checked against live code, not
  subagent prose: the `totalWorkoutsAtLeast` dead-branch claim re-verified
  directly against `rank_ladder_data.dart`; the OI-231/`getCurrentRank()`
  read-equivalence claim re-verified by reading `rank_service.dart`
  directly; the OI-226 cross-branch-collision precedent re-verified by
  reading the actual `closed_issues.md` entry, not assumed.
- Every B-pass finding's `verification:` command was independently re-run
  by the implementing session before being trusted, not just read: the
  comment-out mutation reproduced live (`Expected: true / Actual: false`,
  then restored and reconfirmed 5/5 green); the `<pending>` sites
  reconfirmed via `grep -n "pending>"` before and after the fix; the real
  `line_range` span reconfirmed via a direct `Read` of
  `ai_snapshot_builder.dart:1385-1471`, not accepted from the finding's
  stated numbers.
- All 3 diagnose-docs pass `dart run scripts/validate_diagnose_doc.dart`.
  Each cites a mutation-proof that was independently executed (not merely
  described): full source revert (tests kept) reddens exactly the expected
  tests for all three fixes, 0 collateral failures each time.
- `flutter analyze lib/` clean (45 pre-existing info-level issues
  elsewhere, none in the touched files). Full local `sh scripts/
  pre-commit.sh` gate loop green, re-run 4 times across the batch (once
  per round of fixes, including the Gate 19 false-positive fix and the
  B-pass remediation), each run's real exit code captured to a log file
  rather than trusted through a pipe (`feedback_git_landing_verification.md`
  — "exit codes lie").

## Verification

- `flutter test test/ai_coach/snapshot_keys_test.dart
  test/ai_coach/initial_scroll_to_bottom_test.dart
  test/widgets/log_workout_sheet_completed_day_test.dart`: 57/57 green,
  run together as one set (not just individually) after all B-pass fixes
  landed.
- `docs/reviews/5ebf78e29706-review.md` — `verdict: accepted`, all 3
  findings `status: fixed`.
- OI board internally consistent post-commit: OI-230/OI-232 closed
  (`closed_issues.md`), OI-228/OI-231/OI-240 open (`open_issues.md`),
  `OPEN_INDEX.md` regenerated (134 open issues indexed).
- Committed as `7af6123c` on this branch. Not yet pushed, merged, or
  built into an APK — per CLAUDE.md §4.3, each of those three gated
  actions requires its own explicit, separate founder approval, which
  this record does not carry.

## Residual, stated rather than hidden

- **OI-231** (root-cause half) — stays open pending live verification;
  the hygiene fix shipped in this batch does not by itself explain the
  reported stale-rank-address symptom.
- **OI-228 Bug B** (`shortenWorkout` stuck at `status:queued`) — unrelated
  to Bug A, stays open.
- **OI-240** (officer/MCPO `completionRateMinimum` gate-modeling gap) —
  filed as its own, materially larger unit of work rather than absorbed
  into this batch.
- **Cross-branch OI-number collision risk** — OI-228/230/231/232's
  adopted text will collide with `claude/food-logging-observations-126ab3`
  (PR #31)'s own, independently-authored copies of these same numbers
  when that branch eventually merges — not a text conflict but a real
  gate-failure risk, the same shape already realized once for OI-226 from
  the same original reservation batch. Flagged here for founder awareness;
  not resolvable from this branch alone.
