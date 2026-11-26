# Plan v3 — flip `enable_phase_arc` live, STRIP ONLY (OI-53, flag 1 of 10)

**Branch:** `phase-arc-flip` · **Blast radius:** `platform`
(`lib/shared/repositories/plan_engine/**` → `docs/blast_radius.yaml:67`)

**v3 is a SPLIT, on founder decision 2026-09-05, reversing the earlier "ship both surfaces in
one flip".** Two context-blind rounds produced 13 then 20 findings, and round 2's headline was
that round 1's own correction was defective. §4.12.1: *"When successive reviews keep surfacing
new material issues, that is the signal the unit is too large — split it and ship the smallest
converged piece."*

- **Unit A (this plan):** the wave strip goes live. Display-only, no engine coupling.
- **Unit B (separate, own ×2):** the week-4 deload-reason line goes live, after R5's
  stale-reason bug is fixed. Nothing in Unit A depends on Unit B.

## 1. How the reason line stays dark

**A new ship-dark flag, not a deletion.** `enable_deload_reason_line`, `== true`, default OFF
(§4.6). `PhaseArcStrip` reads it alongside the existing `currentWeek == 4` condition. The reason
code and its tests stay intact and inert; Unit B flips this flag after fixing R5. Deleting the
block instead would discard working, tested code and make Unit B a re-write.

New ledger entry in `ship_dark_pending_review.yaml` `pending:` for this flag. Its BUILD qualifies
for §4.12.4's `ship_dark_build` tier (default OFF, byte-identical when off, behavioural test) —
but that tier applies only to this new flag's build. **The `enable_phase_arc` FLIP still requires
the full ×2 + `bpass: accepted`.**

## 2. Findings that MOVE to Unit B — not deferred, re-scoped with the surface they belong to

- **R5 (P1) — the stamped reason outlives the blob.** `deload_reason_phase_<P>` is never deleted
  anywhere in `lib/` (verified: grep for delete/remove returns nothing), and
  `workout_schedule_read_service.dart:388` rewrites the blob unconditionally on regen while only
  `plan_start`/`plan_end` are gated on `isFirstGeneration` (`:382-387`). After a mid-phase
  Edit-Profile regen, week 4 is `'deload'` again while the reason still says "Working week — you've
  recovered", and `deload_evaluator.dart:79`'s idempotency flag blocks any correction. Reachable
  and permanent. **This is the bug F2 was reaching for.**
- **R1/R2 — Task 4 is DROPPED, not moved.** It would have changed live `enable_triggered_deload`
  behaviour to fix a contradiction that §3's Tasks 2+3 already make unreachable, and in the one
  case it newly covered it would have emitted "Recovery week logged — you're recovered" over rows
  stamped `week_character: 'working'`. Verified wrong; no part of it survives.
- **R14** — the four doc contracts describing `liftedAny` stay accurate precisely because Task 4
  is dropped. Nothing to change.
- **F14** — the reason persisting for a user clamped at week 4. Belongs with the reason line.

With the reason line dark, **none of the above is reachable in Unit A.**

## 3. Tasks

1. **Invert the flag** (`e6a8a8ae` precedent, shape confirmed at `plan_engine_flags.dart:169-177`):
   `enable_phase_arc` → `disable_phase_arc`, `== true` → `!= true`, catch default `false` → `true`.
   Both halves together.
2. **New ship-dark flag** `enable_deload_reason_line` (`== true`, catch → `false`); the strip's
   reason block reads it (§1).
3. **Label handling, normalised ONCE (R10).** Currently the lookup trims but the fallback does not,
   so `'  '` misses `_labels`, falls back untrimmed, and `'  '.isEmpty` is false — a blank node
   that an `isEmpty` floor would not catch. Use:
   `final t = waves[i].toLowerCase().trim();`
   `final label = _labels[t] ?? (t.isEmpty ? '—' : t.toUpperCase());`
   plus `'working': 'WORKING'` in `_labels` (the fifth token, written by
   `deload_evaluator.dart:231`, live since 2026-09-01).
4. **Length guard — `>= 4`, rendering the first 4 (R11).** v2's `== 4` guarded a state with no
   identified producer and diverged from the evaluator's own `weeks.length >= 4`
   (`deload_evaluator.dart:228`). Render `waves.take(4)`; `< 4` → null. This never hides a
   legitimate strip and matches the evaluator.
   WARNING: the telemetry clause first drafted for this task was WRONG and is corrected here. It
   said "emit a recordNonFatal when the guard fires". The guard fires at `length == 0`, which is
   the NORMAL no-plan state (`currentWaveCharacters()` returns `const []` for an absent blob,
   `workout_schedule_read_service.dart:1225-1227`), and `PhaseArcStrip` is mounted unconditionally
   on the Train tab — so every pre-onboarding and expired-plan user would emit on every
   `currentPlanProvider` rebuild. `error_telemetry.dart:241` says in its own comment that
   `recordNonFatal` "is reserved for actual exceptions" and treats it as HIGH-priority, bypassing
   the cooldown. Correct form: emit only for a genuinely TRUNCATED blob (`1 <= length < 4`), via
   `logEvent`, with a SPECIFIC reason string — Gate 15 (`check_generic_error_telemetry.dart`) bans
   generic numbered labels. I added a guard without asking what its normal case looked like, which
   is the same mirror failure this repo already tracks at ~20 instances.
5. **Tests.** Update `phase_arc_reader_behavioral_test.dart` to the new key; ADD the kill-switch
   mirror (`disable_phase_arc = true` → renders nothing) — the existing tests only prove ON works
   and the kill-switch is the whole rollback path. Add the phase-arc case to
   `readiness_flag_no_hive_default_test.dart` (the catch-block half). Add a whitespace-token case
   and a short-blob case. Add a test proving the reason stays dark with the new flag OFF.
6. **Mutation, file-scoped (R13).** `test/plan_engine_v4/hypertrophy_archetype_test.dart:52,67`
   already index `weeks[3]`, so mutating `List.generate(4` → `(3` reddens pre-existing tests
   regardless of any new test. Run mutations **file-scoped** and record which file reddened, or the
   proof credits this batch with other files' coverage.
7. **Doc sweep, list re-derived (R15).** v2's list was wrong: `plan_engine/CLAUDE.md:74` documents
   the `'deload'→'working'` transition and is the one doc already correct. The real sites:
   `plan_engine_flags.dart:197`, `train_provider.dart:891-892`, `models.dart:64`,
   `phase_arc_strip.dart:10`, `workout_schedule_read_service.dart:1218`, `volume_filter.dart:39`.
   Re-derive with `grep -rn "baseline.*overreach.*peak.*deload" lib/` before editing.
   ⚠ Two more sites the grep above does NOT match, because they name the flag rather than the
   four states — add them by hand: `screen.dart:362` ("renders nothing when `enable_phase_arc`
   is OFF", which the key rename falsifies) and `plan_engine_flags.dart:223` ("only the reason
   strip disappears", which the new second flag falsifies).
8. **SoT registry (R9 + split-check Q4).** Two corrections to my earlier citations, both verified:
   - The entry this batch actually invalidates is **`:8077`** in the `deload_decision_reason`
     concept — *"Rides the parent flags (enable_triggered_deload + enable_readiness for the write;
     **enable_phase_arc for the render**)"* — plus its reader block at **`:8088-8090`**. After the
     split the render is gated by `disable_phase_arc` AND the new `enable_deload_reason_line`.
     Neither v2 nor v3's first draft named this entry.
   - `:7952`'s ship-dark claim for `enable_phase_arc` still goes stale — keep that fix.
   - **Drop `:7992`.** It is the `enable_triggered_deload` ship-dark claim inside the unrelated
     `deload_working_base_stash` concept, already stale from the 2026-09-01 flip and not caused by
     this batch. Fix it anyway as a one-line correction while the file is open, and say in the
     commit that it is pre-existing — do not silently absorb it into this batch's findings.
   - Writer line `129` → `164`. ⚠ Do NOT convert to `line_range: 164-164`: `method: apply` resolves
     to `periodization_engine.dart:63`, outside that range, failing the gate as `[stale-line-range]`.
9. **`lib/features/train/CLAUDE.md`** — add the `PhaseArcStrip` row (0 hits today).
   ⚠ Gate 26 (`check_claude_md_citations.dart`) parses nested CLAUDE.md files, so the new row must
   not cite a `§N` heading that does not exist in that file.
10. **Dev-panel kill-switch toggle (R8).** F1's evidence was wrong: three sibling toggles already
    exist (`dev_panel_screen.dart:279`, `:299`, `:321`) using a local `cfg` binding, which is why a
    `configBox.put` grep missed them. Copy `_toggleReadiness` — `delete` to restore default,
    `put(true)` to kill — the correct shape for a default-ON flag. F1's conclusion stands: all of
    this is `kDebugMode`-only, so there is no release-build kill-switch.
11. **OI-60 ledger entry (R4).** The strip becomes a seventh "you are in week 4" surface:
    `train_provider.dart:906` reads `getCurrentWeekNumber()` directly, not `weekIdentityProvider`,
    and it clamps to 4 forever for a holding user. Add a `flip_on_blockers:` entry under
    `enable_hold_weeks` recording that the strip must be hold-aware before OI-60 flips. Not a
    blocker for Unit A — `enable_hold_weeks` is default OFF.
12. **OI board (R20).** OI-53 `:242`/`:253` say "10 remain"; decrement to 9 and note this flip.
    OI-95 `:1071` says "twelve OI-53 flags" — correct alongside. OI-53 stays OPEN, so
    `check_closes_oi_cited.dart` does not fire.
13. **Ledger (R16).** Move `enable_phase_arc` pending → resolved with `flip_reviewed: true`,
    `flip_commit`, `flip_review_record`. Model on `:305-312` / `:320-327` (the 2026-09-01 readiness
    and triggered-deload flips of this same wave), not the August entries.
14. **Diagnose-doc (R6).** The precedent `e6a8a8ae` is `fix(plan-engine): flip equipment exclusions
    ON` carrying `closes-diagnose: e2d6b8`. Tasks 3 and 4 are genuine fixes to a widget going live.
    Write and validate one, with `touched_layers_checked` (§6) and rule 21 mutation evidence.
15. **Closure ledger (R7).** ≥4 findings ⇒ §4.2's structural invariant applies:
    `docs/audit/phase-arc-flip.closure.yaml`, per-entry `terminal_state:` for every finding across
    both rounds. Create it only once every entry is terminal — Gate 40 validates repo-wide on every
    commit, so a half-filled ledger blocks other sessions too.
16. **Skill tuning entry (R3).** `check_skill_tuning_history.dart:93` fires on **any** `.md` added
    under `docs/reviews/` (its own comment at `:78` says so). Committing the B-pass file without a
    same-dated bullet in `.claude/skills/code-review/SKILL.md` naming it is a hard pre-commit
    failure. Same commit (§5.1).
17. **Plan-review record (R12, F5).** `---` frontmatter — the gate parses `^key:` against
    `recordFrontmatter(content)` and rejects on a missing `branch:` first
    (`check_plan_review_record_exists.dart:807-812`). Fields: `branch: phase-arc-flip`,
    `review_rounds: 2`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`,
    `bpass_review: docs/reviews/phase-arc-flip-bpass.md` — and that file committed carrying a
    line-anchored `verdict: accepted`, or CI fails at the merge commit where it cannot be fixed
    without an unwind.

18. **Context-artifact budget re-baseline (§5 row, split-check Q4).** Task 12 edits
    `docs/audit/open_issues.md`, one of the three artifacts tracked by
    `scripts/check_context_artifact_budget.dart`. Current size 229,997 B against a
    221,012 B baseline (+4.1%, inside the 15% soft band), so it will not fail today — but the
    §5 checklist row is the ONLY trigger and nothing else fires it. Run the gate, then `--record`
    if the growth is intended. ⚠ The soft band is invisible locally (`pre-commit.sh` runs gates
    to `/dev/null`), so an unrecorded drift first shows up as a HARD block on every commit in the
    repo.
## 4. Corrections to my own earlier claims, recorded so they are not re-inherited

- **F1's evidence was wrong** (R8) — three dev-panel flag writers were missed by a
  `configBox.put` grep because they bind `cfg` locally. The conclusion survived; the evidence did
  not.
- **F3's "no node is ever `isCurrent`" was unconditional and should not have been** (R17). It holds
  only when `currentWeek > waves.length`; a 3-week blob highlights nodes 1-3 normally for the first
  three weeks.
- **F8's site list named a file that was already correct** and missed three that were not (R15).
- **F9 stated the parity gate's mechanism backwards** (R9) — it does range-check the block form,
  but only for `line_range:` immediately after `file:`.
- **§2's line-shift note said "by one"** (R19); Tasks 3 and 4 both edit below `_labels`, so it is
  "by at least one — re-derive, never add one."

## 5. Rollback

No in-app kill-switch exists in a release build: every flag toggle lives in the `kDebugMode`-gated
dev panel and there is no RemoteConfig. Reverting means a code revert, a rebuild and a store
round-trip. OI-95 records this as accepted risk across all OI-53 flags; this plan does not change
it and does not pretend otherwise. Task 10 makes the switch exercisable in debug/QA only.

Both surfaces are pure reads — no write in `currentWaveCharacters()` or `currentDeloadReason()` —
so a revert leaves no data residue. Task 5's mirror test proves the code path works; the
limitation is reachability, not correctness.
