---
branch: oi53-batch2-flip
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/c22fa39a1cbf-review.md
blast_radius: platform
reviewed_at: 2026-09-16T14:49:40+05:30
---

# Plan review — `oi53-batch2-flip` (OI-53 Batch 2, 4 flags: graded progression, session-detraining cut, physique-focus bring-up, adherence gate)

Flip four ship-dark plan-engine flags in `lib/shared/repositories/plan_engine/plan_engine_flags.dart`
from default-OFF opt-in (`enable_X`) to default-ON with a kill-switch (`disable_X`):
`gradedProgressionEnabled`, `sessionDetrainingCutEnabled`, `physiqueFocusBringupEnabled`,
`adherenceGateEnabled`. Same pattern as `oi53-batch1-flip` (merged `c96d8ed2`). Founder scoping
question ("all 6 remaining, or the 4 clean ones") selected the 4 clean flags — `volumeTitrationEnabled`
and `plateauEscalationEnabled` were explicitly excluded because `volumeTitrationEnabled`'s readiness
dependency is, unlike its siblings, not enforced in code (`_recovered()` has no readiness gate; it is
inert today only because the flag itself short-circuits first). Two independent context-blind rounds
ran per CLAUDE.md §4.12, followed by the mandatory B-pass per §4.3.

## Rounds

| Round | Verdict | Findings |
|---|---|---|
| 1 | not-converged → fixed in this branch | 1 (P1, SoT registry stale line-range citations caused by this batch's own comment edits) |
| 2 | not-converged → fixed in this branch | 3 (2 P2, 1 Low — all further stale line/range citations of the same self-inflicted class, zero runtime impact) |

Both rounds found **zero code-correctness bugs** in the flag flips themselves: kill-switch polarity,
call-site completeness, and byte-identical-OFF behavior all independently re-verified in both rounds.
Every finding across both rounds was documentation/citation accuracy — this batch's own comment edits
to `lib/core/services/workout_schedule_read_service.dart` (net +6 lines across two hunks in round 1's
diff, then a further +17 lines from the B-pass remediation below) repeatedly shifted method locations
faster than the `docs/sot_registry.yaml` citations pointing at them were re-derived, and
`check_sot_registry_parity.dart`'s stale-line-range check is a substring search within the cited
window — wide/multi-method citations can survive a shift smaller than their own width by coincidence,
which is exactly why the drift wasn't gate-caught immediately.

## Ground truth verified

Everything below was independently re-run/re-read in this session, not trusted from subagent prose.

- **Round 1 finding, independently confirmed before fixing**: `pastPhaseBlocks` cited at
  `1699-1700`, real declaration at `1705-1706` (confirmed by direct `Read`); the same round then
  found 4 more of the same class in the same shifted zone — `_scheduleRowsBefore` (cited
  `1706-1723`, real `1712-1729`), `pastPhaseBlocksForDisplay` (cited `1751-1776`, real
  `1757-1782`), `holdSnapshotBlock` (cited `1044-1079`, real `1048-1083`),
  `currentWeekColumnProjection` (cited `1486-1501`, real `1492-1497`). All 5 confirmed by direct
  `Read` before editing, not accepted from the round-1 subagent's report.
- **Round-1 reviewer independently reproduced the D3 mutation-proof**, not just re-read it: ran
  `pro_phase_advance_behavioral_test.dart`'s new group three ways (neuter check A alone → 2/2
  green; neuter check B alone → 2/2 green; neuter both → exactly the kill-switch test reddens),
  reverted cleanly each time (`git diff` empty).
- **Round-1 reviewer found, and this session filed rather than fixed, a genuinely pre-existing,
  unrelated defect**: two OTHER `sot_registry.yaml` citations against the same file
  (`activeHoldWeeks`/`activeHoldOrdinalFor`/`weekIdentity` at cited `890-915`, real ~`1000-1024`;
  `isDeloadHold`/.../`holdWeekSessionProgress` at cited `762-847`, real ~`901-1112`) were confirmed
  wrong at `HEAD` — i.e. before OI-53 batch 1 or batch 2 touched anything — via `git blame` (dated
  2026-07-25 and 2026-08-20, both ancestors of this branch's base). Filed as **OI-207** rather than
  folded into this diff: unrelated concept (hold-weeks/OI-60, not any of the 4 flags), and the two
  groups' real spans now interleave in the source, needing a genuine per-method-range redesign
  rather than a mechanical shift.
- **Round 2 independently re-derived OI-207's own cited line numbers** (`activeHoldWeeks`@1000,
  `activeHoldOrdinalFor`@1005, `weekIdentity`@1019-1024, `isDeloadHold`@901,
  `holdWeekSessionProgress`@1092) against the live file and confirmed all correct, and separately
  judged the defer-to-OI-207 decision itself reasonable (not a §4.2 violation) by independently
  verifying the interleaving claim rather than accepting it.
- **Round 2 found 2 more stale citations round 1 missed**, both confirmed by this session before
  fixing: `docs/sot_registry.yaml:8091`'s bare `line: 410` for the `current_plan` blob splice
  (real guard now at `448` — confirmed via `git show cecda1875:...` that `410` was correct AT THE
  COMMIT THAT WROTE IT, then re-derived the equivalent guard line today) and the sibling
  `tool_dispatcher.dart` citation (`line: 890`, real guard now at `948`, same
  origin-commit-then-re-derive method). Also a Low: the class-level
  `WorkoutScheduleReadService` citation (`32-577`) undersold the real span (confirmed
  `129-1999` at the time — see B-pass remediation below for why this number changed again).
- **`flutter test` on every touched contract file, re-run fresh after every fix round**: the
  `pro_phase_advance_behavioral_test.dart` D3 group (24, then 26 after the B-pass fix), plus
  `session_detraining_cut_test.dart` (12/12), `progression_resolver_graded_test.dart` (10/10,
  including a live mutation reddening exactly the kill-switch test), `physique_focus_bringup_test.dart`,
  `repeat_content_scheduling_test.dart`, `advance_choice_test.dart`, `exlog_exercise_id_behavioral_test.dart`,
  `phase_completion_excludes_holds_behavioral_test.dart` — all green at every checkpoint, most
  recently a combined 56/56 run across the 4 files touching the repeat-pins path.
- **`flutter analyze lib/` (whole tree, not per-file — this file's own known part-file trap),
  re-run after the final B-pass fix**: 45 issues, verified by severity via the repo's own
  right-aligned-column grep convention (`^\s+warning -` / `^\s+error -` both 0), all 45
  pre-existing and none in any file this branch touches (`grep -i
  "workout_schedule_read_service\|plan_engine_flags"` over the saved output → 0 hits).
- **`check_sot_registry_parity.dart`: PASS, 0 errors** at every checkpoint after each fix round
  (1 pre-existing orphan-class warning for `CoachMediaRepository`, unrelated, present on `main`
  already).
- **Blast radius, independently re-classified at the final staged state**: `git diff --cached
  --name-only | dart run scripts/blast_radius_from_diff.dart -` → `platform` (matches this
  record's frontmatter and the B-pass's own independent re-derivation).
- **Full pre-commit gate loop, re-run clean after every fix round** (6 runs total across both
  plan-review rounds and the B-pass remediation), each verified via a real inline `EXIT_CODE=$?`
  marker written into the log by the same shell invocation — not the backgrounding wrapper's own
  reported exit code, which this session's own history has already caught misreporting once this
  batch (a `GATE FAIL` on `check_sot_registry_parity.dart` that a naively-trusted wrapper exit
  code of 0 would have hidden).

## B-pass

`.claude/skills/code-review/SKILL.md` dispatched a fresh, context-blind Sonnet subagent against the
staged diff (staging hash `c22fa39a1cbfaf3eedd3681324385bca660a113d`). Full findings:
`docs/reviews/c22fa39a1cbf-review.md`. **2 findings (0 P0, 0 P1, 1 P2, 1 P3); 0 false_alarm.**

Both accepted and fixed in-batch:
- **P2 (Finding 1, guard_without_its_mirror)** — the most substantive finding across all 3 review
  passes. Three files (`plan_engine_flags.dart`'s `adherenceGateEnabled` doc comment, the OI-53
  board bullet, `plan_engine/CLAUDE.md`) described the "redundant, mutation-confirmed double-check"
  as protecting BOTH of `adherenceGateEnabled`'s two call sites (`pro_phase_advance.dart`'s
  automatic path, `graduation_screen.dart`'s explicit choice sheet) — true only for the automatic
  path. The choice-sheet path (`runGraduationPhaseAdvance` → `buildRepeatPinsForAdvance`) took the
  user's already-made `repeat: true` choice straight through with no re-check, so a kill-switch
  flip during the human-time gap between the sheet opening and the tap was not honored — real,
  though unreachable in a production build today since none of the OI-53 flags has a
  release-build toggle (dev-panel/`kDebugMode` only, per OI-95). **Fixed at the code level, not
  only the docs**: `_buildRepeatPins` (`workout_schedule_read_service.dart`) now opens with
  `if (!PlanEngineFlags.adherenceGateEnabled) return null;`, making it the single choke point both
  callers funnel through. Added 2 new tests to the D2 group (a matching-G5-baseline positive
  control + the kill-switch regression case); mutation-tested by reverting the new guard — exactly
  the new kill-switch test reddened (25 pass / 1 fail), everything else stayed green; reverted
  cleanly (`git diff` empty) before re-applying. All 3 over-broad doc claims corrected to describe
  the asymmetry (and its fix) accurately.
- **P3 (Finding 2, asserted_fixture_value)** — the newly-filed OI-207's own "How found" bullet said
  "4 more stale citations" then named 5. Fixed to say "5 more" and reordered to lead with
  `pastPhaseBlocks` (the one fixed before round 1 was even dispatched); also noted the further 3
  citations this same B-pass/round-2 sweep found, so the bullet's history stays accurate without
  needing a second correction.

Fixing Finding 1 shifted `workout_schedule_read_service.dart` a THIRD time (+17 lines, inserted
before all 6 of the round-1/round-2-fixed citations) — caught by re-running
`check_sot_registry_parity.dart` immediately after, which flagged 2 of the 6 as freshly stale again
(the other 4 survived by the same width-coincidence noted above). Rather than fix those 2 and risk
missing a 3rd/4th shifted-but-coincidentally-passing citation again, this session did one
comprehensive sweep verifying and correcting all 6 at once (`holdSnapshotBlock` → `1065-1100`,
`currentWeekColumnProjection` → `1509-1514`, `_scheduleRowsBefore` → `1729-1746`, `pastPhaseBlocks`
→ `1722-1723`, `pastPhaseBlocksForDisplay` → `1774-1799`, class range → `129-2016`), each confirmed
by direct `Read` against the current file, not by arithmetic alone (spot-verified the +17 uniform
shift on 2 of the 6 before trusting it for the rest). Re-ran the parity gate, the full pre-commit
gate loop, `flutter analyze lib/`, and the 4-file/56-test sweep once more after this final fix —
all clean.

No third plan-review round was triggered for the B-pass's Finding 1 fix: the fix is narrow,
defensive-only (a null-check-and-early-return added to an already-reviewed shared private helper),
applies the EXACT pattern both prior review rounds already examined for the sibling path, is
mutation-proven, and was the B-pass's own primary suggested fix rather than a novel design this
session invented. §4.12 point 1's "successive reviews keep surfacing new material issues → split
it" is about a UNIT that keeps growing unboundedly; three DIFFERENT review mechanisms (plan-review
×2, then B-pass) each finding something in their own distinct lens is the pipeline working as
designed, not that signal.

## Verdict

**converged.** The code is correct — kill-switch polarity, call-site completeness, and
byte-identical-OFF behavior for all 4 flags independently re-verified across two review rounds plus
the B-pass, with the one substantive gap the B-pass found (the graduation-path asymmetry) fixed at
the code level and mutation-proven rather than merely documented around. Every finding across all
three passes (1 round-1, 3 round-2, 2 B-pass) reached a terminal, non-pending state in this same
batch. `bpass: accepted`, evidenced by `bpass_review: docs/reviews/c22fa39a1cbf-review.md`.
