---
branch: oi53-batch1-flip
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/1cadbcd1d01f-review.md
blast_radius: platform
reviewed_at: 2026-09-16T21:34:28+05:30
---

# Plan review — `oi53-batch1-flip` (OI-53, 3 flags: W3.3 ID-keyed history, ①.1d injury-substitute preference, W3.4 cross-phase variety)

Flip three ship-dark plan-engine flags in `lib/shared/repositories/plan_engine/plan_engine_flags.dart`
from default-OFF opt-in (`enable_X`) to default-ON with a kill-switch (`disable_X`):
`exerciseIdHistoryEnabled`, `injurySubstitutePreferenceEnabled`, `crossPhaseVarietyEnabled`. Two
independent context-blind rounds ran per CLAUDE.md §4.12.

## Rounds

| Round | Verdict | Findings |
|---|---|---|
| 1 | not-converged → fixed in this branch | 3 (P2, all documentation staleness) |
| 2 | not-converged → fixed in this branch (see Remediation) | 1 new (P2, documentation staleness) |

Round 1 found zero code-correctness bugs (kill-switch polarity, call-site completeness, old-path
reachability all verified; 51/51 tests green) and 3 documentation gaps, all fixed in this branch:
a stale `enable_cross_phase_variety` cross-reference in `lib/shared/repositories/plan_engine/CLAUDE.md`'s
Batch 12-B paragraph; `docs/sot_registry.yaml` untouched by the original diff (3 concept entries +
1 cross-reference still said `enable_*`/DEFAULT OFF); and `docs/ship_dark_pending_review.yaml` still
listing all 3 flags under `pending:` (deliberately left for a follow-up records commit, per this
repo's established precedent — verified below, not just repeated).

## Ground truth verified

Everything below was re-run/re-read directly in this session, independent of round 1's own report.

- **Kill-switch polarity, re-derived from source** (`plan_engine_flags.dart:346-434`): all three
  getters read `HiveService.instance.configBox.get('disable_X') != true`, catch-fallback `true`.
  Byte-for-byte the same shape as this file's 9 other default-ON siblings
  (`injuryUniversalFilterEnabled`, `warmupInjuryFilterEnabled`, `detrainingDecayEnabled`,
  `cardioGoalDefaultEnabled`, `equipmentExclusionsEnabled`, `readinessEnabled`, `phaseArcEnabled`,
  `deloadReasonLineEnabled`, `triggeredDeloadEnabled`, `equipmentCapabilityFloorEnabled`). Correct.
- **Full call-site grep, re-run**: `exerciseIdHistoryEnabled` → 1 production read
  (`progression_resolver.dart:63`); `injurySubstitutePreferenceEnabled` → 2 production reads
  (`plan_generator.dart:195-196` pinned path, `:210-211` fresh-pick path — both the SAME `generateV4`
  call, one per branch of the pins-null ternary, matching the doc's "resolved once in generateV4");
  `crossPhaseVarietyEnabled` → 1 production read, the service-layer gate
  (`workout_schedule_read_service.dart:824`). No orphaned or missed call sites. `git grep` (not a
  glob-filtered grep) repo-wide for the 3 old `enable_*` names, excluding nothing but reading every
  hit, turned up only: `docs/ship_dark_pending_review.yaml` (deliberate, see below),
  `docs/plan-reviews/`, `docs/plans/`, `docs/reviews/` (all pre-date this branch, historical), and 2
  deliberate "X flipped to Y" transition-prose comments in
  `cross_phase_variety_behavioral_test.dart:3` / `injury_substitute_preference_behavioral_test.dart:3`.
  Nothing else, anywhere, in any tracked file.
- **`flutter test` on all 5 named files: 51/51 passed** (`00:09 +51: All tests passed!`), run fresh
  in this session, not read off a prior report.
- **`flutter analyze lib/`: 45 issues, re-verified by SEVERITY, not just by count** — the analyzer
  right-aligns its severity column to a fixed width, so a naive `grep` can be blind to exactly
  `warning` (CLAUDE.md's own documented trap, common-pitfalls table). Stripped leading whitespace
  and matched `^(warning|error|info) -`: **0 warning, 0 error, 45 info** — all 45 pre-existing and
  none in any file this branch touches (`grep -i "plan_engine\|progression_resolver\|workout_schedule_read_service\|plan_generator"` over the saved analyze output → 0 hits).
- **Mutation-tested `injurySubstitutePreferenceEnabled`** (`!=` → `==`, confirmed applied via
  `grep -c`): re-ran `injury_substitute_preference_behavioral_test.dart` → **exactly test (1) reddens**
  (`Expected: true, Actual: <false>` at line 162, the directional rank-order assertion), tests
  (2)(3)(4) stay green for principled reasons (injury-safety is a separate always-on filter
  independent of the preference re-rank; no-injury and uncurated-injury cases are no-ops under
  either polarity). Independently confirmed the file's own claim that the WEAKER checks earlier in
  the same test (line 125 `isNot(equals)`, line 132 bare membership) do **not** catch the inversion —
  both stayed satisfied under the mutation; only the first-divergence rank comparison
  (`onRank < offRank`) does. Reverted; `git diff` on the file was 0 lines after revert.
- **Also mutation-tested `crossPhaseVarietyEnabled`** (not required by the brief, but its own new
  tests carry an analogous self-attested mutation claim — "verified live: inverting the flag
  comparison left this test green until seeded data was added" — which deserved the same
  skepticism as the injury-sub claim rather than being taken on faith). Confirmed both new tests in
  `cross_phase_variety_behavioral_test.dart` redden correctly under `!=`→`==`: the default-ON test
  fails (`Expected: non-empty, Actual: {}`) and the kill-switch test fails
  (`Expected: empty, Actual: {0: (a: [barbell bench press], b: [])}`), proving the kill-switch test
  genuinely exercises suppression of real data rather than mere absence of data. Reverted; 0-line
  diff confirmed.
- **`docs/sot_registry.yaml` structural validity**: ran this repo's own registry-parity gate,
  `dart run scripts/check_sot_registry_parity.dart` → **PASS — 0 errors** (1 pre-existing orphan-class
  warning for `CoachMediaRepository`, confirmed present on `main` already, unrelated to this diff).
  That script does not import `package:yaml` (confirmed by reading it) — it is not a strict-YAML
  parser, so I additionally attempted a true `package:yaml` `loadYaml` parse of the whole file. It
  fails, but at **line 437** and **line 1095** — both confirmed present verbatim on `main` (pre-existing,
  unrelated to this branch's edits: a 29-site file-wide convention of non-standard backslash escapes
  inside `forbidden_legacy_patterns` regex strings, and an unquoted-bracket flow-sequence item — this
  8,500-line file has never been strict YAML and the repo's real tooling tolerates it). All 4 of this
  branch's edited hunks are pure in-place text substitutions inside pre-existing `notes: >-` folded
  blocks, at unchanged indentation, introducing no new structurally-significant characters (no bare
  `: `, no new quotes, no dedent) — structurally safe by inspection, and consistent with the gate's
  clean PASS.
- **Old-path byte-identical claim, traced in actual source (not accepted from comments):**
  - `exerciseIdHistoryEnabled` OFF → `progression_resolver.dart:63,71,78` → `idMatch=false` →
    `lastSessionById=null`, `allById=null` → the id-keyed indices are never populated → only the
    pre-existing name-keyed `lastSession`/`allByExercise` maps fill → verbatim name-only match.
  - `injurySubstitutePreferenceEnabled` OFF → `exercise_selector.dart:1060-1084`
    (`_selectCandidate`) → `applyInjurySubstitutePreference=false` → `pool = candidates` unchanged →
    falls straight to `_preferNovel(pool, avoidNames)`, which returns `pool.first` when `avoidNames`
    is also empty (`:1096`) — i.e. `candidates.first`, verbatim.
  - `crossPhaseVarietyEnabled` OFF → `workout_schedule_read_service.dart:821-826`
    (`previousPhaseNamesByDay`) → returns `const {}` on the FIRST line, before either `getWeek(1)` or
    `getWeek(2)` is ever called → avoidNames empty everywhere, byte-identical.
- **Blast radius, independently re-classified**: `git diff --staged --name-only | dart run
  scripts/blast_radius_from_diff.dart -` → `Blast-radius: platform` (matches this record's
  frontmatter — not copied without checking).
- **Ninth-angle sweep** (beyond round 1's 8 categories): `docs/audit/GATE_INDEX.md`,
  `docs/audit/gate_test_ledger.yaml`, `docs/naming_conventions.md`, `integration_test/flows/` —
  grepped for all 3 old and new flag names/getters, zero hits in any of them (no gate references
  these flags by name, no new domain term needs a glossary entry, no integration test touches
  them). `git status --porcelain=v1 --untracked-files=all` showed exactly the 7 originally-staged
  files and nothing else stray **at this point in round 2, before P2-1's fix below added
  `docs/audit/open_issues.md` + `docs/audit/OPEN_INDEX.md`** — the staged count grew to 10 by the
  time of the B-pass (`docs/reviews/1cadbcd1d01f-review.md` Finding 2), and to 11 once this
  file's own bpass-triage edits and that review file are staged. Not stray in either case — every
  addition is accounted for in this record's own Remediation/Rounds history.

## Findings (round 2 — new, not found by round 1)

### P2-1 — `docs/audit/open_issues.md`'s OI-53 entry (+ its generated mirror `OPEN_INDEX.md`) is stale; this branch breaks a 4-for-4 precedent of updating it in the same flip

- **File:line**: `docs/audit/open_issues.md:253` (heading) and `:269` ("**8 remain.**" inside the
  `Blocked on` bullet); mirrored at `docs/audit/OPEN_INDEX.md:11`.
- **Claim**: this branch flips 3 more OI-53 flags live (2026-09-16) but the OI-53 tracking entry
  still reads *"Flip the remaining 8 workout-generator ship-dark flags (was 13; ...; deload-reason-line
  flipped 2026-09-06)"* and *"8 remain"* — no mention of 2026-09-16 or these 3 flags anywhere in the
  entry, and no other tracked file references this branch name at all
  (`git grep -ln "oi53-batch1-flip"` → 0 hits outside this new record).
- **Verification**: `git log -L253,253:docs/audit/open_issues.md` shows the heading line was edited
  in-branch, in the SAME unit of work as each prior flip, every single time: `c22e12c2` (deload-reason-line,
  2026-09-06), `55035cd7` (phase-arc, 2026-09-05), `17e1f05e` (readiness+triggered-deload,
  2026-09-01). `git show --stat <sha> -- docs/audit/open_issues.md` confirms `e6a8a8ae`
  (equipment-exclusions, 2026-08-05) also touched it directly (151 insertions). That is 4 of 4
  traceable precedents. This is a **different** convention from `docs/ship_dark_pending_review.yaml`,
  which genuinely IS deferred to a separate later "records" commit (confirmed:
  `dabe2013`/`2fca4c12` — the commits that filled in that ledger's `resolved:` entries — never touch
  `docs/audit/open_issues.md` at all). The task's own framing of round 1's finding #3 correctly
  invoked that ship-dark-ledger precedent; it does not extend to the OI board, and nothing in this
  branch documents an intent to update the board later. Left as-is, `open_issues.md` would
  undercount "remaining" by 3 and a future reader would not know these 3 flags are no longer dark —
  exactly the staleness class CLAUDE.md §7 already names as a recurring risk for this file ("the
  board went 70 days unread because nothing referenced it").
- **Severity**: P2 — documentation/audit-trail freshness only, no code/test/runtime impact. Same
  tier as round 1's 3 findings, all of which were real and worth fixing before merge, none of which
  indicated a code-correctness problem.
- **Suggested fix**: on this branch, before the `--no-ff` merge to `main`, update
  `docs/audit/open_issues.md`'s OI-53 entry to match the established shape of its 4 prior updates:
  (a) heading — decrement "remaining 8" → "remaining 5" and append "; exercise_id_history +
  injury_substitute_pref + cross_phase_variety flipped 2026-09-16" to the parenthetical; (b) the
  `Blocked on` bullet — add a new "⚠ **DATED FOUNDER DECISION 2026-09-16: ... approved and flipped**"
  line pointing at this record (`docs/plan-reviews/oi53-batch1-flip.md`) and update "8 remain" →
  "5 remain"; (c) add a new "✅ `exerciseIdHistoryEnabled` + `injurySubstitutePreferenceEnabled` +
  `crossPhaseVarietyEnabled` — FLIPPED 2026-09-16." bullet in the same style as the existing
  readiness/phase-arc/deload-reason-line bullets. `docs/audit/OPEN_INDEX.md` regenerates
  automatically from this on the next commit that touches the board (`scripts/build_oi_index.dart`,
  wired into `pre-commit.sh`) — no separate manual edit needed there.

## Remediation (post round-2, same branch, main-thread self-check — not a 3rd independent round)

P2-1 fixed: `docs/audit/open_issues.md`'s OI-53 heading, `Blocked on` bullet, and a new ✅ FLIPPED
bullet now cite 2026-09-16 and this branch/record, matching the 4-for-4 prior-flip style exactly.

**⚠ The reviewer's own suggested-fix number was wrong, and it was NOT applied verbatim.** Round 2
computed "8 remain" → "5 remain" by subtracting this batch's 3 flags from the board's own
pre-existing (already-stale) "8" figure — arithmetic on a stale input, not a re-derivation. This
session independently re-grepped `plan_engine_flags.dart` for every live `.get('enable_*')` call
site: `enable_graded_progression`, `enable_session_detraining_cut`, `enable_physique_focus_bringup`,
`enable_adherence_gate`, `enable_volume_titration`, `enable_plateau_escalation` — **six** OI-53
flags remain (`enable_hold_weeks` also matches the grep but is OI-60, correctly excluded). The board
now reads **6**, not the reviewer's suggested 5. This matches this same session's own independent
count taken BEFORE round 2 ran (from the original "list open items" pass earlier in this
conversation, which found the board's pre-existing "8" was already wrong for the identical reason —
it had miscounted `enable_deload_reason_line`, a split-out child flag, as one of the original 12).
No gate catches this class of error (a subagent's arithmetic on a number it did not itself
re-derive) — it was caught only by independently re-running the source grep rather than trusting
the suggested-fix text.

Confirmed no other file needed the same count correction: `git grep -n "remain\b" docs/audit/` for
any OTHER stale count outside the OI-53 entry just edited → no hits.

## B-pass

`.claude/skills/code-review/SKILL.md` dispatched a fresh, context-blind Sonnet subagent against
the staged diff (staging hash `1cadbcd1d01fb676a8fb3a661c75197dfd6f2a33`). Full findings:
`docs/reviews/1cadbcd1d01f-review.md`. **3 findings (0 P0, 0 P1, 1 P2, 2 P3); 0 false_alarm.**
The code itself was found correct across all 10 lenses (8 named + the 2 established extensions,
`modelled_on_is_a_checkable_claim` and `self_attesting_artifact`) — every one of its "verified
clean" claims was independently re-spot-checked against real git/file state by this session before
being trusted (mutation results, the dev-panel-absence claim, the ship-dark-ledger commit history,
the OI-53 arithmetic re-confirmed a third time) rather than accepted on the subagent's prose alone.

All 3 findings accepted:
- **P2 (Finding 1)** — this record's own claim that leaving `docs/ship_dark_pending_review.yaml`
  untouched is "established convention" overstated the precedent (2 of 5 prior flips did this
  cleanly; 3 sat wrong for 27/5/1 days until a dedicated cleanup commit fixed them). Fixed by doing
  the follow-up records commit on this same branch before merge, rather than leaving another
  unenforced intention in a file with exactly that failure history.
- **P3 (Finding 2)** — this record's own "7 originally-staged files" line went stale the moment
  round 2's P2-1 fix added 2 more files. Fixed with an explicit time-scope qualifier.
- **P3 (Finding 3)** — none of the 3 flags got a dev-panel debug toggle, unlike 4/4 true
  shipped-dark-then-later-flipped precedents. Accepted, no code fix in this batch: OI-95 already
  tracks this exact gap architecturally across all 13 OI-53/OI-60 flags, and the dev panel compiles
  out of release builds regardless, so no production capability is affected either way.

## Verdict

**converged.** The code is correct — every claim independently re-derived across two review rounds
plus the B-pass (kill-switch polarity, call-site completeness, byte-identical OFF paths, test
results, analyze results, mutation coverage, registry-gate parity) checks out. All findings across
all three passes (3 round-1, 1 round-2, 3 B-pass) reached a terminal, non-pending state in this same
batch. `bpass: accepted`, evidenced by `bpass_review: docs/reviews/1cadbcd1d01f-review.md`.
