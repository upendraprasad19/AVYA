---
branch: claude/oi-batching-strategy-e5e359
date: 2026-09-22
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/d2ce94ab0a72-review.md
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

Full detail: `docs/reviews/d2ce94ab0a72-review.md` (renamed twice — once
after the fixes above were staged, from the hash the B-pass was originally
dispatched against; once more after rebasing this branch onto a moved
`origin/main`, per this record's own "Residual" section below — the
standard hash-fixed-point rename this skill's own tuning history
documents; `docs/reviews/` is hash-excluded so neither rename moved the
hash a further time).

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
  pre-commit.sh` gate loop re-run green after every round of fixes
  (initial implementation, the Gate 19 false-positive fix, the B-pass
  remediation, and the post-rebase conflict resolution below), each run's
  real exit code captured to a log file rather than trusted through a
  pipe (`feedback_git_landing_verification.md` — "exit codes lie").

## Verification

- `flutter test test/ai_coach/snapshot_keys_test.dart
  test/ai_coach/initial_scroll_to_bottom_test.dart
  test/widgets/log_workout_sheet_completed_day_test.dart`: 57/57 green,
  run together as one set (not just individually) after all B-pass fixes
  landed.
- `docs/reviews/d2ce94ab0a72-review.md` — `verdict: accepted`, all 3
  findings `status: fixed`.
- OI board internally consistent post-rebase: OI-230/OI-232 closed
  (`closed_issues.md`), OI-227/OI-228/OI-229/OI-231/OI-233/OI-238/OI-240
  open (`open_issues.md`), `OPEN_INDEX.md` regenerated (137 open issues
  indexed — up from 134 pre-rebase: origin/main's OI-227/229/233 merged
  in, netted against this batch's own OI-230/232 closures).
- **Rebased onto `origin/main` twice (PR #31, then PR #34, both merged
  mid-batch — see Residual below) and re-committed as `29425fa8` (code)
  + `5e4348bb` (this record) + `cf7d9c11` (the first rebase's repoint
  fixup, carried through unchanged) — superseding the first-rebase
  `f4ff083b`/`ef295a63`/`bfa921da` shas, which themselves superseded the
  original `7af6123c`/`1c6b3941`.** Pushed and opened as PR #33 after the
  first rebase (founder-approved); the second rebase (below) updates that
  same open PR. Not yet merged or built into an APK — per CLAUDE.md §4.3,
  each of those two remaining gated actions requires its own explicit,
  separate founder approval, which this record does not carry.

## Residual, stated rather than hidden

- **OI-231** (root-cause half) — stays open pending live verification;
  the hygiene fix shipped in this batch does not by itself explain the
  reported stale-rank-address symptom.
- **OI-228 Bug B** (`shortenWorkout` stuck at `status:queued`) — unrelated
  to Bug A, stays open.
- **OI-240** (officer/MCPO `completionRateMinimum` gate-modeling gap) —
  filed as its own, materially larger unit of work rather than absorbed
  into this batch.
- **Cross-branch OI-number collision — REALIZED and RESOLVED, not merely
  risked.** `claude/food-logging-observations-126ab3` (PR #31) merged to
  `origin/main` mid-batch, bringing its own independently-authored copies
  of OI-227/228/229/230/231/232/233 (all still OPEN there — that branch
  filed/re-verified these numbers but fixed none of them). Discovered via
  a pre-push `git fetch origin main` check (founder asked how to handle
  it; chose "rebase then push"), confirmed identical underlying diagnosis
  for OI-230 (no conflicting investigation, just unfixed) before
  resolving. Rebased this branch onto `origin/main` (`ad88e668`) and
  hand-resolved the resulting 3-file conflict (`.claude/skills/code-review
  /SKILL.md`, `docs/audit/OPEN_INDEX.md` — regenerated rather than
  hand-merged — and `docs/audit/open_issues.md`, the substantive one:
  reconstructed by hand rather than trusting git's line-based 3-way merge,
  since the interleaved prose made hunk-level resolution unreliable).
  Post-resolution board state independently re-verified (grep-confirmed
  OI-227/228/229/231/233/238/240 open, OI-230/232 closed, no duplication
  in either file). The same collision shape already realized once before
  for OI-226 (from the same original reservation batch, resolved via
  `be63f5cf`'s merge-integration review, per this repo's own
  `.claude/skills/code-review/SKILL.md` tuning history) — this is the
  second occurrence, now also closed. Captured as its own feedback memory
  (`feedback_oi_adoption_content_collision.md`, harness-local) since it is
  a distinct class from mint_oi.sh's number-only uniqueness guarantee.
- **Second, unrelated collision: PR #34 merged to `origin/main` after
  this branch's first push, moving GitHub's mergeability check to
  CONFLICTING.** Founder-approved rebase again (same per-action-approval
  pattern as the first). Verified the overlap was narrow before touching
  anything: `git diff --name-only` on both sides showed PR #34 touched
  only `tool_dispatcher.dart` + its own diagnose-doc/review/test files —
  zero overlap with this batch's `ai_snapshot_builder.dart`/`screen.dart`/
  `log_workout_sheet.dart`. Of the two files that DID appear on both
  sides, `git merge-tree` (dry-run, no working-tree changes) showed
  `.claude/skills/code-review/SKILL.md` auto-merges cleanly (each
  branch's dated tuning-history entry landed in a different spot) and
  only `docs/diagnoses/INDEX.md` conflicted — expected, since it is
  auto-generated and both branches regenerated it independently from
  different diagnose-doc sets. Resolved by regenerating (`dart run
  scripts/build_bug_index.dart`, via `. scripts/_dart_bin.sh &&
  DART_BIN="$(resolve_dart_bin)"` — not `"$DART_BIN" run` directly off a
  bare `source`, which sets no variable), not hand-merging — confirmed
  all 4 new entries (this batch's 3 + PR #34's `tool_dispatcher` one)
  present post-regeneration. Ordinary concurrent-edit conflict, not the
  OI-adoption class above — no new feedback memory needed for this one.
