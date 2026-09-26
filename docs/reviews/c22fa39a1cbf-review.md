---
reviewed_at: 2026-09-16T03:20:22+05:30
staged_against: c22fa39a1cbf
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 2
verdict: accepted
---

# Code Review — c22fa39a1cbf

Branch `oi53-batch2-flip` (OI-53 Batch 2): flips `gradedProgressionEnabled`,
`sessionDetrainingCutEnabled`, `physiqueFocusBringupEnabled`, `adherenceGateEnabled` from
ship-dark default-OFF (`enable_X`) to default-ON-with-kill-switch (`disable_X`) in
`lib/shared/repositories/plan_engine/plan_engine_flags.dart`. Dispatched as the mandatory
B-pass per CLAUDE.md §4.3, fresh/context-blind, after 2 converged plan-review rounds.

**Pre-flight, independently re-derived (not trusted from the dispatch brief):**
- `git status --porcelain | grep -E '^(MM|AM|MD|AD) '` → no output. Index and working tree agree.
- Blast radius via `git diff --cached --name-only -- ':(top)' ':(top,exclude)docs/reviews'
  ':(top,exclude).claude/skills/code-review/SKILL.md' | dart run scripts/blast_radius_from_diff.dart -`
  → **platform**. Matches the brief.
- Staging hash via `git diff --cached -- ':(top)' ':(top,exclude)docs/reviews'
  ':(top,exclude).claude/skills/code-review/SKILL.md' | git hash-object --stdin` →
  `c22fa39a1cbfaf3eedd3681324385bca660a113d` → truncated `c22fa39a1cbf`. Matches the brief.

## Finding 1 — P2 — guard_without_its_mirror

- **file:line:** `lib/shared/repositories/plan_engine/plan_engine_flags.dart` (the
  `adherenceGateEnabled` doc comment, "the flag is re-checked a second time immediately
  before `_buildRepeatPins`"); mirrored in `docs/audit/open_issues.md` (new OI-53 bullet,
  "the flag is re-checked a SECOND, redundant time immediately before `_buildRepeatPins`");
  mirrored in `lib/shared/repositories/plan_engine/CLAUDE.md` ("two independent trigger
  computations, a redundant flag re-check"); code sites `lib/shared/services/pro_phase_advance.dart:169`
  + `lib/core/services/workout_schedule_read_service.dart:659` (the ONE path that actually has
  the second check) vs. `lib/features/train/screens/graduation_screen.dart:376-384` +
  `lib/shared/services/pro_phase_advance.dart:569-577` +
  `lib/core/services/workout_schedule_read_service.dart:740-753` (the path that does NOT).

- **claim:** The batch's documentation (3 files, listed above) describes `adherenceGateEnabled`
  as protected by a redundant, mutation-confirmed double-check across **both** of its two named
  call sites — `pro_phase_advance.dart`'s automatic low-adherence repeat (3-a2) **and**
  `graduation_screen.dart`'s explicit choice sheet (3-b). This is only true for 3-a2. Traced the
  actual call graph for 3-b:
  1. `graduation_screen.dart:376`: `offerChoice = PlanEngineFlags.adherenceGateEnabled &&
     shouldOfferAdvanceChoice(...)` — the ONLY flag read on this path.
  2. `graduation_screen.dart:382`: `choice = await showAdvanceChoiceSheet(context) ?? ...` — a
     genuine, unbounded **human-time `await`** sits between the flag read above and everything
     that follows (this is the file's own documented point: the comment at `:398-407` explicitly
     says this hoisted check "is load-bearing only across the choice-sheet await").
  3. `graduation_screen.dart:429-435` calls `runGraduationPhaseAdvance(repeat: choice ==
     AdvanceChoice.repeat, ...)`.
  4. `pro_phase_advance.dart:569-577` (`runGraduationPhaseAdvance`): `pins = repeat ?
     scheduleSvc.buildRepeatPinsForAdvance(...) : null` — **zero references to
     `PlanEngineFlags` anywhere in this function** (confirmed by `grep -c
     "adherenceGateEnabled" lib/shared/services/pro_phase_advance.dart` inside the function
     body — the only hit in the whole file is line 169, inside the *other* function,
     `runProPhaseAdvance`).
  5. `workout_schedule_read_service.dart:740-753` (`buildRepeatPinsForAdvance`, whose own doc
     comment says "graduation calls the read service DIRECTLY, not the facade + not
     autoGenerate") delegates straight to the private `_buildRepeatPins` — again with no flag
     check. The `(repeatContent && PlanEngineFlags.adherenceGateEnabled)` re-check at `:659`
     that the docs describe lives inside `autoGenerateNextPhaseIfNeeded`, which the graduation
     path never calls.

  So the 3-b (graduation) path has exactly **one** flag read, taken before an await of arbitrary
  human duration, with no re-verification after. If the kill-switch (`disable_adherence_gate`)
  is set while the choice sheet is open and the user then taps "repeat," a pin is still built and
  applied — contradicting the flag's own stated guarantee ("Kill-switch...restores the verbatim
  path...`repeatContent` inert everywhere → byte-identical"). On the 3-a2 path this genuinely
  cannot happen: there is no `await` anywhere between `pro_phase_advance.dart:169`'s read and
  `workout_schedule_read_service.dart:659`'s read (confirmed by re-reading both function bodies —
  `isPhaseExpired()` and `currentPhase + 1` are synchronous, so the whole span is one
  uninterruptible synchronous stretch), which is exactly what makes the 3-a2 "redundant check"
  claim correct and the mutation test meaningful *for that path only*.

  Notably, `docs/sot_registry.yaml`'s own `repeat_phase_pinned_selection` concept entry gets this
  right and should be the template for the others: "the flag is checked TWICE on the **3-a2
  path** (`pro_phase_advance.dart:168` AND this file's `autoGenerateNextPhaseIfNeeded` call site
  immediately above `_buildRepeatPins`)" — correctly scoped to one path, not generalized. The new
  test comment in `pro_phase_advance_behavioral_test.dart` ("the flag is checked TWICE on **this
  path**") is similarly correctly scoped. Only the flags-file doc comment, the OI board entry,
  and the nested CLAUDE.md generalize it to both call sites.

  **Coverage gap this leaves:** grepped the whole test tree
  (`grep -rln "runGraduationPhaseAdvance" test/`) — the only test that drives `repeat: true`
  through this function (`pro_phase_advance_behavioral_test.dart`'s pre-existing "repeat: true
  with NO repeatable content flags no nudge" test, D2 group) never touches
  `PlanEngineFlags.adherenceGateEnabled`/`disable_adherence_gate` at all, so nothing in the repo
  would catch a regression here — including someone "simplifying" the genuinely-redundant
  `:659` check on the belief (per the over-broad doc claim) that the graduation path already
  has equivalent protection.

- **severity rationale (why P2, not P0/P1):** per `phaseArcEnabled`'s doc comment (same file,
  unchanged by this diff) and OI-95, none of the OI-53 flags has a release-build toggle — "every
  flag toggle lives in the `kDebugMode`-gated dev panel and there is no RemoteConfig." So the
  race window (flag flipped while a choice sheet is open) is unreachable in a production build
  today; it is a real gap in a `kDebugMode`/QA context and a real inaccuracy in 3 documentation
  sites, not a live production defect.

- **verification:**
  - `grep -n "adherenceGateEnabled" lib/shared/services/pro_phase_advance.dart` → one hit,
    line 169, inside `runProPhaseAdvance` only.
  - `grep -n "adherenceGateEnabled" lib/core/services/workout_schedule_read_service.dart` →
    lines 245 (unrelated `last_phase_profile` write-gate, shared by both paths via
    `generateAndSchedule`), 659 (the 3-a2-only re-check), 1298 (doc comment) — none inside
    `_buildRepeatPins`/`buildRepeatPinsForAdvance` (lines 714-753).
  - `sed -n '369,384p' lib/features/train/screens/graduation_screen.dart` shows the single
    `offerChoice` read followed by the `await showAdvanceChoiceSheet(context)`.
  - `grep -n "test('pins built ONLY on an explicit repeat choice'" -A 6
    test/contracts/advance_choice_test.dart` — the pre-existing source-anchored test asserts
    `final pins = repeat[\s\S]{0,120}?buildRepeatPinsForAdvance` with no flag term in between,
    independently corroborating there is no second check on this path.

- **suggested-fix:** move the `PlanEngineFlags.adherenceGateEnabled` check into
  `_buildRepeatPins`/`buildRepeatPinsForAdvance` itself (return null / never build when the
  kill-switch is set), rather than relying on each caller to have pre-checked it. This closes
  the gap for the graduation path, makes the "redundant re-check" story literally true and
  symmetric for both call sites (single source of truth instead of one caller duplicating it and
  the other omitting it), and would let the existing `pro_phase_advance_behavioral_test.dart` D3
  group's mutation methodology extend to 3-b with one more test. Cheapest alternative if the
  code is intentionally left as-is: narrow the 3 over-broad doc claims (flags file, OI board,
  nested CLAUDE.md) to explicitly say the redundant check protects **only** the 3-a2/automatic
  path, matching the SoT registry's and the test's own correctly-scoped wording, so a future
  reader does not assume the graduation path is equivalently protected.

- **status:** accepted — fixed in-batch via the primary suggested fix, not the cheaper doc-only
  alternative. `_buildRepeatPins` (`workout_schedule_read_service.dart:731-732`) now opens with
  `if (!PlanEngineFlags.adherenceGateEnabled) return null;`, making it the single choke point both
  `autoGenerateNextPhaseIfNeeded` (3-a2) and `buildRepeatPinsForAdvance` (3-b) funnel through — the
  3-a2 caller's own pre-check at `:659` is now genuinely redundant (as originally claimed), and the
  3-b path gets its first-ever re-check at the point pins are actually built, closing the human-time
  await gap this finding identified. Added 2 new tests to `pro_phase_advance_behavioral_test.dart`'s
  D2 group (a matching-G5-baseline positive control + the kill-switch regression case) —
  mutation-tested by reverting the new guard: exactly the new kill-switch test reddened (25 pass /
  1 fail), everything else stayed green; reverted cleanly (`git diff` empty) before re-applying.
  Corrected the 3 over-broad doc claims (`plan_engine_flags.dart`'s `adherenceGateEnabled` comment,
  the OI-53 board bullet, `plan_engine/CLAUDE.md`) to describe the asymmetry accurately instead of
  generalizing the redundant-check claim to both paths.

## Finding 2 — P3 — asserted_fixture_value (extended to a prose count, not a test literal)

- **file:line:** `docs/audit/open_issues.md`, new `## OI-207` entry, "How found" bullet
  (~line 4484-4490 post-diff).

- **claim:** The bullet says "**4 more** stale citations in the SAME file were found and fixed
  there" and then names five: `` `_scheduleRowsBefore`, `pastPhaseBlocks`,
  `pastPhaseBlocksForDisplay`, `holdSnapshotBlock`, `currentWeekColumnProjection` ``. The stated
  count (4) does not match its own enumeration (5). Cross-checked against the actual
  `docs/sot_registry.yaml` diff for `workout_schedule_read_service.dart`, which shows exactly
  five method-level `line_range:` corrections matching those five names (plus a sixth,
  unrelated, class-level range for `WorkoutScheduleReadService` itself, 32-577→129-1999, which
  isn't one of the five named methods) — so 5 is the correct count, not 4.
  All five corrected ranges were independently re-verified against the live file by `Read`
  (not trusted from the diff or the OI text) and are byte-exact:
  `holdSnapshotBlock` 1048-1083, `currentWeekColumnProjection` 1492-1497, `_scheduleRowsBefore`
  1712-1729, `pastPhaseBlocks` 1705-1706, `pastPhaseBlocksForDisplay` 1757-1782 — all confirmed
  correct against the current file content, so this finding is purely about the "4" vs. the
  5 names listed, not about any of the corrected citations themselves being wrong.
  Separately, OI-207's own new-defect claims (`activeHoldWeeks` at 1000, `activeHoldOrdinalFor`
  at 1005, `weekIdentity` at 1019, `isDeloadHold` at 901, `holdWeekSessionProgress` at 1092) were
  also independently re-verified against the live file and are all correct.

- **verification:** `grep -n "activeHoldWeeks(\|activeHoldOrdinalFor(\|weekIdentity(\|isDeloadHold(\|holdWeekSessionProgress(" lib/core/services/workout_schedule_read_service.dart`
  and direct `Read` of lines 1048-1083, 1492-1497, 1705-1782, 1712-1729 to confirm the five
  corrected spans; `git diff --cached -- docs/sot_registry.yaml` shows the 5 method-level
  `line_range:` edits for this file.

- **suggested-fix:** change "4 more" to "5 more" in the OI-207 bullet (or drop the number and
  let the list speak for itself). Zero functional impact — informational miscount in a
  freshly-filed backlog entry, not a defect in the corrections themselves, which are all
  verified accurate.

- **status:** accepted — fixed in-batch. Changed "4 more" to "5 more" in the OI-207 bullet and
  reordered the name list to lead with `pastPhaseBlocks` (the one fixed before round 1 was even
  dispatched) so the count and the enumeration agree; also noted the further 3 corrections this
  same B-pass/round-2 sweep found (the class-level range, the `tool_dispatcher.dart` sibling, and
  the two test-file inline citations) so the bullet's own history stays accurate rather than
  needing a second correction later.

## Clean / verified areas (no finding)

- **`plan_engine_flags.dart` flag-getter mechanics** — all 4 flipped getters
  (`gradedProgressionEnabled`, `sessionDetrainingCutEnabled`, `physiqueFocusBringupEnabled`,
  `adherenceGateEnabled`) correctly invert polarity: `get('enable_X') == true` →
  `get('disable_X') != true`, and the catch-branch default flips `false` → `true`. No
  copy-paste residue (each of the 4 diffs was read in full). `volumeTitrationEnabled` and
  `plateauEscalationEnabled` are byte-for-byte untouched (confirmed by reading the full current
  file) — still `enable_X == true` / catch → `false`.
- **writer_reader_drift (lens 1)** — grepped the whole repo (`lib/`, `test/`, `supabase/`,
  `scripts/`, `docs/`) for the 4 retired key names (`enable_graded_progression`,
  `enable_session_detraining_cut`, `enable_physique_focus_bringup`, `enable_adherence_gate`).
  Every hit is in `docs/` (historical plan-review records, diagnose-docs, plans,
  `docs/ship_dark_pending_review.yaml`) — zero hits in `lib/`, `test/`, or
  `supabase/functions/`. No stale code reader of the old keys.
- **blast_radius_mismatch (lens 3)** — `docs/blast_radius.yaml` pins
  `lib/shared/repositories/plan_engine/**` to `platform` (the tier driving this diff's overall
  classification), `lib/shared/services/pro_phase_advance.dart` and
  `lib/features/train/screens/graduation_screen.dart` to `account`, and
  `lib/features/{train,home,profile}/**` to `feature` by default — all ≤ the platform ceiling
  the computed blast radius already reflects. No under-classified file found.
- **secrets_in_tree / function_exception_swallow / unawaited_no_error_sink (lenses 2, 4, 5)** —
  no `.functions.invoke(`, no new `unawaited(`, no credential-shaped literal
  (`sk-`/`rzp_live_`/`AKIA`/`-----BEGIN`) anywhere in the staged diff.
- **missing_input (lens 7)** — no new vendored path/asset/package assumed present; the one new
  import (`workout_schedule_read_service.dart` in the new test file) resolves to a real,
  already-existing file.
- **asserted_fixture_value (lens 8) spot-checks, per the dispatch brief** —
  `progression_resolver_graded_test.dart`'s `98.8` (two-consecutive-below-range back-off,
  `100 - 1.25 = 98.75`) was verified against a live Dart run (`98.75.toStringAsFixed(1) ==
  '98.8'`, confirmed empirically, not assumed) rather than trusted from the rounding rule in
  prose; all its other assertions (`102.5` = `100 + 2.5`, `100.0` holds) check out against
  `progression_resolver.dart`'s actual `_gradedSuggestion`/`_backOff` logic.
  `session_detraining_cut_test.dart`'s `0.825` for a 25-day gap matches the documented band
  table (22-35d → -17.5%) directly. None of these numeric literals were introduced or altered by
  this batch — only the enabling/disabling plumbing around them changed — so this batch did not
  introduce a new wrong fixture value.
- **`exlog_exercise_id_behavioral_test.dart`'s "graded union" test** — removing the now-redundant
  explicit `enableGraded()` call (graded progression now defaults ON) is safe: this file's
  `setUp` deletes and reopens `configBoxName` from disk before every test, so there is no
  cross-test Hive-flag leakage from an earlier test's explicit flag mutation.
- **OI board hygiene** — the new `OI-207` entry (a genuinely pre-existing, unrelated stale
  `sot_registry.yaml` citation for hold-weeks, correctly scoped OUT of this batch) has a real
  reservation: `git show-ref | grep refs/remotes/origin/oi/207` resolves, confirming it was
  minted via `mint_oi.sh` rather than picked by hand; no duplicate `## OI-207` heading exists in
  either `open_issues.md` or `closed_issues.md`. OI-53's "2 remain" (`volumeTitrationEnabled`,
  `plateauEscalationEnabled`) was independently recomputed from the actual flag getters in
  `plan_engine_flags.dart` (not from the title's "was 13" backstory, whose arithmetic has a
  pre-existing, unrelated-to-this-diff inconsistency that predates this batch and was not
  touched by it) and holds.
- **Deferred flags untouched** — `volumeTitrationEnabled` and `plateauEscalationEnabled` are
  confirmed byte-identical to `HEAD` in this diff (not present in the `plan_engine_flags.dart`
  hunk at all).

## Founder triage notes

Both findings accepted and fixed in-batch under this batch's standing execution authorization
(OI-53 flag-flip plan, founder-selected "4 clean flags only"). Finding 1 was the substantive one —
a real, if production-unreachable (no release-build flag toggle exists per OI-95), asymmetry
between the two `adherenceGateEnabled` call sites; fixed at the code level (shared choke point)
rather than only correcting the docs, since the review's own primary suggested fix was better than
its "cheapest alternative." Finding 2 was a one-word prose miscount, fixed to match its own
enumeration. No re-review round triggered — both fixes are narrow, defensive-only (Finding 1) or
prose-only (Finding 2), with zero behavior change on any already-green path (confirmed by the full
D2/D3 group re-run: 26/26 green before and after, plus the mutation proof).
