---
reviewed_at: 2026-07-25T11:40:00+05:30
staged_against: 64e6f116d820
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 4
verdict: accepted
---

# Code Review (B-pass) — hold-display — 64e6f116d820

Self-initiated per CLAUDE.md §4.3 (blast-radius `account`, verified with
`scripts/blast_radius_from_diff.dart`, not assumed). Fresh context-blind Sonnet
subagent over the staged diff; no conversation context passed. All 4 findings
were re-verified against source by the author before acceptance
(`feedback_audit_verifier_cannot_trust_own_subagent`) — every one was real.

## Finding 1 — P1 — writer_reader_drift / display-correctness
- **file:line:** lib/features/train/widgets/week_selector.dart:136,183 → lib/core/services/workout_schedule_read_service.dart `_holdDatesByOrdinal`
- **claim:** `_holdDatesByOrdinal()` scanned EVERY `is_hold` row ever written, with no date or phase bound, while the chip group's header label used the user's LIVE `currentPhase`. Hold rows are deliberately never re-stamped with `phase` (an explicit stamp trips legacy `bucketPastRows` carry-forward), so nothing retired them.
- **failure scenario:** A free user takes 2 holds on Phase 1, then converts to PRO and advances to Phase 2 (`plan_start` moves forward). `holdWeeks()` still returns `[H1, H2]`, so `isHolding` stays true and the strip renders a **"PHASE II · HOLDING"** header over chips belonging to Phase I — while `pastPhaseBlocks()` *also* now renders those same rows correctly under Phase I. Permanent duplicated + mislabelled history, hitting exactly the converting (paying) user.
- **verification:** `grep -n "is_hold" lib/core/services/workout_schedule_read_service.dart` (no date bound pre-fix); `workout_schedule_write_service.dart:293-296` confirms `phase` is intentionally not stamped.
- **resolution:** FIXED. Both `_holdDatesByOrdinal()` and `holdOrdinalForDate()` are now bounded to `date >= plan_start` via a shared `_holdWindowStart()` — uniform across the whole hold read surface, so no entry point can resurrect a retired hold. The rows are never deleted (they are real history; `pastPhaseBlocks()` owns them once the phase moves on). Pinned by the new `hold scoping` test group, which asserts both that the strip empties AND that the underlying row survives.
- **status:** accepted

## Finding 2 — P2 — test-coverage
- **file:line:** lib/features/train/providers/train_provider.dart:825 (citation), :867 (the untested line)
- **claim:** `holdStatusProvider`'s `if (!PlanEngineFlags.holdWeeksEnabled) return HoldStatusData.empty;` — the single line carrying the entire ship-dark guarantee — was never executed by any test; every assertion went through the read service or the plain value class. The doc comment cited `hold_status_flag_off_test.dart`, **a file that does not exist**.
- **failure scenario:** The realistic rollback (flag ON → holds materialized → flag switched OFF) is the exact case that line defends. If it were removed, inverted, or reordered after the `holdWeeks()` call, stale hold UI would ship and the suite would stay green.
- **verification:** `ls test/contracts/hold_status_flag_off_test.dart` → no such file; `grep -rn holdStatusProvider test/` → 0 matches pre-fix.
- **resolution:** FIXED. Added two `ProviderContainer` tests: the rollback case (hold rows present on disk + flag OFF ⇒ provider still `empty`) and the flag-ON happy path (`isHolding`, `todayHoldOrdinal`, session tallies). Dangling citation corrected to the tests that actually exist. This is the `feedback_mistake_unverified_done_claims` class — a citation written before the artifact.
- **status:** accepted

## Finding 3 — P2 — closure-ledger accuracy
- **file:line:** docs/audit/hold-display.closure.yaml U2, U3
- **claim:** U2/U3 cited `week_selector_past_phases_test.dart` / `phase_relative_week_label_test.dart` as `verification:`, but neither file contains the word "hold" — they are pre-existing regression guards for unrelated behavior. Breaking the chip ✓ logic, the deload-preview gate, `HoldWeekSheet`, or the pill text would fail neither.
- **verification:** `grep -i hold` on both files → 0 matches.
- **resolution:** FIXED by rewording, not by fabricating coverage. Both entries now state plainly that the cited test is REGRESSION-ONLY (it pins what this batch must not break) and point to `hold_display_read_path_test.dart` for the data path. There is still no widget-level test of the hold widgets, and the ledger now says so rather than implying otherwise.
- **status:** accepted

## Finding 4 — P2 — documentation-accuracy
- **file:line:** docs/sot_registry.yaml (reader entry for `_handleRedoWeek4`)
- **claim:** Cited `line_range: 56-115`, but `_handleRedoWeek4` ends at line 99; 101-113 are the unrelated `_handleUpgrade` / `_handleTemplateBuilder`.
- **verification:** `sed -n '95,115p' lib/features/train/widgets/plan_expired_card.dart` — method closes at 99.
- **resolution:** FIXED → `56-99`. Not gate-breaking (under the file length, so the line-range gate passed) but precisely the citation drift the registry exists to prevent.
- **status:** accepted

## Lens coverage (clean lenses, with evidence)

- **writer_reader_drift** — Not clean (Finding 1). Otherwise verified: every consumed field (`is_hold`, `hold_ordinal`, `status`, `type`, `workout_name`) matches the writer at `workout_schedule_write_service.dart:235-353`. `hold_ordinal` is always written `int` (from `_nextHoldOrdinal()`), matching the reader's `is! int` guards — no num/double drift. `isDeloadHold(n) = n % 4 == 0` confirmed byte-identical to the writer's `final deload = n % 4 == 0`, and additionally proven by a behavioral test that drives the REAL writer. `HoldChipGroup.holds.last` proven unreachable on empty (`build()` returns `SizedBox.shrink()` on `holds.isEmpty` first, and the sole call site gates on `isHolding`).
- **function_exception_swallow** — Clean. `grep -n "functions.invoke\|FunctionException"` over the staged diff → 0 matches; no Edge Function calls in this batch.
- **blast_radius_mismatch** — Clean, independently recomputed: `git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart` → `account`. `lib/features/train/**` is `feature`; the tier comes solely from `lib/core/services/**`. No `platform` glob touched — `lib/features/train/CLAUDE.md` is a NESTED CLAUDE.md (feature-tier), not the root-exact-match platform rule.
- **secrets_in_tree** — Clean. `grep -nE "sk-[A-Za-z0-9]|rzp_live_|AKIA[A-Z0-9]{16}|-----BEGIN"` over the full staged diff → 0 matches.
- **unawaited_no_error_sink** — Clean. `grep -n "unawaited("` over the staged diff → 0 matches. (The `unawaited(ErrorTelemetry.recordNonFatal(...))` in the write service is pre-existing Slice-1 code; that file is untouched here, per `git diff --cached --stat`.)

### Targeted checks that returned clean
- **Null-safety across all 7 touched widget files** (read in full, not diff hunks): no force-unwraps, no unguarded `.first`/`.last`, no divide-by-zero. `HoldStatusData.sessionProgress` explicitly guards `sessionsTotal == 0`.
- **`_roman()` / phase math past 12** (`hold_roadmap_strip.dart`): `_roman(13)` falls back to `'13'`; `phaseName(13)` cycles via `(phase-1) % 3`. Neither crashes. Unreachable in practice — every hold surface is Phase-1-only today.
- **Flag-OFF byte-identical**: traced all five changed widget files. `hero_cards` (`if (isHolding)`, default false), `plan_header` (ternaries on `isHolding`, always false since the provider returns the `const` empty singleton), `screen.dart` and `week_selector` (`if` blocks), `plan_expired_card` (true if/else preserving the original three-link layout verbatim in the `else`). Confirmed identical when OFF.
- **`week_selector` watching `holdStatusProvider`**: no circular dependency and no rebuild loop — `holdStatusProvider` watches `currentPlanProvider`, which the parent already watches independently; nothing in that chain watches `holdStatusProvider`.
- **`hero_cards` parameter reassignment**: the reassigned `todayWorkout` is only consumed after the reassignment; no stale read.

## Founder triage notes

All 4 accepted and fixed in-batch (§4.2 no-deferrals) — 1 P1 behavioral fix
(hold-window scoping) plus 3 P2 accuracy/coverage fixes. Re-ran the suite after
fixes: `hold_display_read_path_test.dart` 13/13 green, and the pinned neighbours
(`phase_relative_week_label`, `week_selector_past_phases`,
`hold_week_mechanic_behavioral`, `week_completion_check`,
`phase_unlock_card_thursday_gate`) all green. Closure ledger extended to 10/10
terminal with B1/B2 recording the review-driven fixes.

The P1 is the notable catch: the batch's own tests all passed before it, because
none of them modelled a phase ADVANCE — the failure only appears for a user who
converts to PRO after holding, which is the commercially important path.
