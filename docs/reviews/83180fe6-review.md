---
reviewed_at: 2026-07-19T00:00:00+05:30
staged_against: 83180fe6
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, plateau_specific]
findings_count: 2
verdict: accepted
---

# Code Review — 83180fe6

> **Triage (self, 12-A author):** both findings ACCEPTED + FIXED in-batch (§4.2). P0 — the
> plan-review record was rewritten to a `---`-fenced bare-`key: value` frontmatter (parseable
> by `check_plan_review_record_exists.dart`) with `bpass_review: docs/reviews/83180fe6-review.md`;
> this file now carries `verdict: accepted`. P1 — two end-to-end `generateV4(applyPlateauEscalation:…)`
> tests added (ON adds volume vs OFF through the real Stage-4.5 entry point; kill-switch OFF → inert),
> closing the orchestration-coverage gap. Both re-verified green.

Commit: `feat(train): W3.5 plateau escalation rung-2 (+sets) — Batch 12-A (ship-dark)`.
Diff assembled via `git show 83180fe6 --stat` + `git diff 83180fe6~1 83180fe6`. Every
finding below was checked against the ACTUAL file content at HEAD (or the pre-image
via `git show 83180fe6~1:<path>`), not against the commit message's prose. Both new
test files were executed (not just read); the two refactored files' pre-existing
behavioral suites were re-run to confirm the extraction is truly behavior-preserving.

## Finding 1 — P0 — blast_radius_mismatch (plan-review-record format)

- file:line: `docs/plan-reviews/workout-plateau-12.md:1-11` (the whole "frontmatter" block)
- claim: The plan-review record for this exact branch is in the wrong format and
  will FAIL the merge-to-main CI gate (`scripts/check_plan_review_record_exists.dart`,
  wired as the dedicated `plan-review-record` job in `.github/workflows/test.yml:162-179`,
  `push` to `refs/heads/main`, `fetch-depth: 0`, invoked WITHOUT `--warn-only`) — even
  though blast-radius here is `platform` (confirmed ≥ `account`, `docs/blast_radius.yaml:67`
  pins `lib/shared/repositories/plan_engine/**` to `platform`), so the gate is
  unambiguously in scope. The gate's `field(k)` parser is
  `RegExp('^$k:\s*(.+)$', multiLine: true)` (`check_plan_review_record_exists.dart:181-182`)
  — it requires each key to appear bare, at the START of its own line (a raw YAML-ish
  `key: value`, normally inside a `---`-fenced frontmatter block). Every OTHER
  plan-review record in the repo uses exactly that shape — e.g. `workout-titration-9.md`,
  `workout-idkey-variety-11.md`, `workout-variety-11b.md`,
  `workout-variety-injurysub-11bc.md`, `workout-explainability-10.md` all open with
  `---\nbranch: ...\nblast_radius: ...\nreview_rounds: ...\nground_truth_verified: ...\n
  verdict: ...\nbpass: ...\nbpass_review: ...\n---`. `workout-plateau-12.md` instead opens
  directly with an `# Plan-review record — ...` H1 and states the same facts as a
  markdown BULLET list with BOLD field names (`- **review_rounds:** 2`,
  `- **bpass:** accepted`, etc.) — no `---` fence at all, and every field line is
  prefixed with `- **`, so the gate's line-anchored regex cannot match any of them.
- verification: Ran the gate's exact regex against the actual file content (Node,
  mirroring the Dart `RegExp('^$k:\s*(.+)$','m')`):
  ```
  review_rounds => null
  ground_truth_verified => null
  verdict => null
  bpass => null
  bpass_review => null
  blast_radius => null
  branch => null
  ```
  Every single field the gate needs comes back `null`. Per
  `check_plan_review_record_exists.dart:184-186`: `rounds =
  int.tryParse(field('review_rounds') ?? '') ?? 0` → `rounds = 0` → the FIRST check
  (`if (rounds < 2)`) fails and the job dies with
  `'docs/plan-reviews/workout-plateau-12.md: review_rounds=0 (need >= 2).'` — this
  would happen on the actual merge-to-main push, blocking `main`, DESPITE the document's
  prose correctly stating 2 rounds / ground-truth-verified / converged. Cross-checked
  against 5 sibling records in the same arc (`workout-titration-9.md`,
  `workout-idkey-variety-11.md`, `workout-variety-11b.md`,
  `workout-variety-injurysub-11bc.md`, `workout-explainability-10.md`) — all 5 use the
  correct `---`-fenced bare-`key: value` shape and would all parse cleanly; only this
  commit's new file deviates.
  - Folded-in sub-issue: independent of the format bug, `bpass_review:` (once
    parseable) currently holds the literal placeholder string
    `docs/reviews/<hash>-review.md  <!-- filled at B-pass -->`, which does not exist on
    disk. The anti-fabrication check at `check_plan_review_record_exists.dart:208-223`
    requires — whenever `bpass: accepted` is claimed — that `bpass_review:` name a
    file that (a) exists and (b) contains a line-anchored `verdict: accepted`. This
    review is presumably meant to fill that slot (`docs/reviews/83180fe6-review.md`),
    but note this review's OWN frontmatter above is `verdict: pending` (per this
    skill's fixed output template) — pointing `bpass_review:` at this file does NOT
    by itself satisfy the gate until/unless this file's `verdict:` line is later
    updated to `accepted`. Whoever finalizes the merge needs to reconcile both the
    frontmatter format AND this verdict-value handoff deliberately, not by accident.
- suggested-fix: Add a proper frontmatter block at the top of
  `docs/plan-reviews/workout-plateau-12.md`, mirroring `workout-variety-11b.md`'s shape,
  e.g.:
  ```
  ---
  branch: workout-plateau-12
  blast_radius: platform
  review_rounds: 2
  ground_truth_verified: true
  verdict: converged
  bpass: accepted
  bpass_review: docs/reviews/83180fe6-review.md
  ---
  ```
  and keep the existing rich prose body below the fence as supporting narrative (it is
  good material — this is a format fix, not a content rewrite). Then confirm
  `docs/reviews/83180fe6-review.md` itself carries a line-anchored `verdict: accepted`
  before attempting the `--no-ff` merge + push to `main`.
- status: accepted — FIXED. `docs/plan-reviews/workout-plateau-12.md` now opens with a
  `---`-fenced frontmatter (branch/blast_radius/review_rounds:2/ground_truth_verified:true/
  verdict:converged/bpass:accepted/bpass_review:docs/reviews/83180fe6-review.md); this review
  file's `verdict:` is now `accepted` (line-anchored). The prose body was retained below the fence.

## Finding 2 — P1 — plateau_specific / test-adequacy (rule 21)

- file:line: `lib/shared/repositories/plan_engine/plan_generator.dart:261-274` (the new
  `if (applyVolumeTitration || applyPlateauEscalation) { ... }` Stage-4.5 merge block)
- claim: The new composition logic in `plan_generator.dart` — which decides, per call,
  whether to call `VolumeTitration.resolveDeltas`, whether to additionally run it
  through `PlateauScan.mergePlateauSetDeltas`, and which map ultimately reaches
  `VolumeTitration.applyToWeeks` — is never exercised by any test through its real
  entry points (`PlanGenerator.generate` / `.generateV4` / 
  `WorkoutScheduleReadService.generateAndSchedule`). `docs/sot_registry.yaml`'s new
  `plateau_escalation` concept explicitly lists this exact file/method as a writer
  ("Stage 4.5 merges mergePlateauSetDeltas into the titration base map then applies
  ONCE via VolumeTitration.applyToWeeks..."), but the concept's own
  `behavioral_test_path` (`plateau_escalation_behavioral_test.dart`) never calls
  `generateV4`/`.generate()` — every assertion in that file operates one layer below,
  directly against `PlateauScan.plateauedGroups` / `mergePlateauSetDeltas` /
  `VolumeTitration.applyToWeeks`. A regression introduced directly in the new
  ternary/composition (e.g. an inverted condition, the wrong variable used as `base`,
  or applying `applyToWeeks` twice) would ship silently — no test would go red. This is
  not brand-new to this commit: the SAME gap already existed for the pre-existing
  `applyVolumeTitration`-only branch since Batch 9 (W2.7) and was not caught by that
  batch's own B-pass (`docs/reviews/workout-titration-9-bpass.md` verified the
  threading by manually reading callers, not via a test invoking `generateV4`) — but
  12-A adds a SECOND, more complex condition to that exact same untested block without
  closing the gap, compounding the risk on a `platform`-tier, PRO-paid-feature file
  that CLAUDE.md rule 14 singles out for extra caution ("Never modify
  `plan_generator.dart` without explicit instruction").
- verification:
  - `grep -rn "applyPlateauEscalation" test/` → 0 matches anywhere in the test suite.
  - `grep -rn "applyVolumeTitration" test/` → 0 matches anywhere in the test suite
    (confirms the pre-existing W2.7 gap is real too, not just a 12-A omission).
  - Manually traced `plan_generator.dart:261-274` line-by-line against
    `volume_titration.dart:156` (`applyToWeeks` returns the SAME `weeks` reference when
    `deltas.isEmpty`) and `plateau_scan.dart:62-73` (`mergePlateauSetDeltas` returns the
    SAME `existing` reference when `plateauedGroups` is empty) — the composition IS
    correct today (byte-identical-when-off holds), confirmed by hand, but this is a
    paper proof, not a test-enforced one; the same paper-proof style is exactly what
    `docs/plan-reviews/workout-plateau-12.md` §2.3 ("Byte-identical proof") also relies
    on — no one closed the loop with an actual `generateV4(applyPlateauEscalation:
    true)` call.
  - Ran the actual new/existing tests to confirm what IS covered:
    `flutter test test/contracts/plateau_escalation_behavioral_test.dart
    test/plan_generator/plateau_scan_test.dart` → 23/23 passed (detector gates,
    no-double-bump, declining∧flat safety, MRV clamp, byte-identical-off — all at the
    `PlateauScan`/`VolumeTitration` layer, never `generateV4`).
- suggested-fix: Add one test (in `plateau_escalation_behavioral_test.dart` or a new
  `plan_generator_plateau_wiring_test.dart`) that seeds a Hive plateau + a real
  exercise-library profile, then calls `PlanGenerator.instance.generateV4(...,
  phase: 2, applyVolumeTitration: false, applyPlateauEscalation: true)` directly and
  asserts the returned `Phase.weekPlans` sets reflect the +1 bump — plus a companion
  assertion that `applyPlateauEscalation: false` (or the flag OFF) yields week-plans
  equal to a plain baseline call. This closes the gap for BOTH the new plateau
  composition and (as a side effect) the 2-batch-old titration-only branch.
- status: accepted — FIXED. Added group `end-to-end: generateV4 entry-point (Stage 4.5 glue)`
  to `plateau_escalation_behavioral_test.dart`: (1) seed one flat plateau per major group +
  `generateV4(phase:2, applyPlateauEscalation:true)` asserts total `weekPlans` sets STRICTLY
  GREATER than `:false` (proves the +sets flows through the real Stage-4.5 composition);
  (2) with the kill-switch OFF, `gen(true)` set totals EQUAL `gen(false)` (param inert
  end-to-end). Both green (19/19 in the file).

## Lenses that returned clean

- **writer_reader_drift**: Checked both Hive contracts the diff touches. (1) exlog:
  `e1rm_history.dart buildE1rmByDate` reads `date`/`exercise_name`/`sets` via the
  UNCHANGED `sessionMaxE1rm` (`lib/core/utils/e1rm.dart`, not touched by this diff),
  which reads `sets[].weight_kg`/`sets[].reps_completed` — matches the writer
  (`workout_write_service.dart:175-182`, `'sets': cleanedSets.map((s) =>
  s.toMap())...`). Confirmed the extraction is behavior-preserving both by diffing
  `git show 83180fe6~1:lib/core/services/deload_e1rm_scan.dart` /
  `...:lib/shared/repositories/plan_engine/volume_titration.dart` against the new
  shared helper (only cosmetic difference: a combined `||` null/cutoff guard vs. two
  sequential `if`s — semantically identical) AND by re-running
  `flutter test test/contracts/deload_eval_behavioral_test.dart
  test/contracts/volume_titration_behavioral_test.dart` post-refactor → 37/37 passed.
  (2) readiness: `PlateauScan._fatiguePresent` reads `healthBox` keys prefixed
  `readiness_` via `ReadinessCheckin.fromMap` — matches the writer
  (`health_write_service.dart:124`, `'readiness_$dateStr'`) and is consistent with the
  two OTHER readers of the same rows (`HealthReadService.readinessHistory`,
  `VolumeTitration._recovered`). 0 findings.
- **function_exception_swallow**: `git diff 83180fe6~1 83180fe6 | grep '^\+' | grep -i
  'functions\.invoke'` → 0 matches. This is a pure local plan-engine change; no Edge
  Function calls added. 0 findings.
- **secrets_in_tree**: `git diff 83180fe6~1 83180fe6 | grep '^\+' | grep -iE
  'sk-|rzp_live_|AKIA|-----BEGIN|api[_-]?key|secret'` → 0 matches. 0 findings.
- **unawaited_no_error_sink**: `git diff 83180fe6~1 83180fe6 | grep '^\+' | grep
  'unawaited('` → 0 matches — no `unawaited(` calls added by this commit. 0 findings.
- **plateau_specific / A (byte-identical when OFF)**: Traced
  `plan_generator.dart:261-274` — both flags OFF ⇒ block not entered at all (verbatim
  pre-12-A code path); flag ON but `enable_plateau_escalation` OFF ⇒
  `mergePlateauSetDeltas` returns `existing` unchanged (same ref) ⇒ `applyToWeeks`
  hits `deltas.isEmpty` ⇒ returns the SAME `weeks` list reference. Confirmed the two
  production advance call sites (`workout_schedule_read_service.dart:517,520`,
  `graduation_screen.dart:662,664`) always pass the IDENTICAL value (`pins == null`)
  to BOTH `applyVolumeTitration` and `applyPlateauEscalation`, so the "one true, one
  false" combination is structurally unreachable in production — it only matters for
  direct unit tests (see Finding 2). Clean.
- **plateau_specific / B (mergePlateauSetDeltas mutation safety)**:
  `plateau_scan.dart:62-73` — the empty-groups branch returns `existing` directly
  (zero copies, zero mutation); the non-empty branch first `Map<String,
  int>.from(existing)` (a fresh mutable `LinkedHashMap`) and only THEN calls
  `putIfAbsent` on the COPY. Safe even when `existing` is a `const {}` (which would
  throw on direct mutation but is only ever read via `.from()`). Clean.
- **plateau_specific / E (detector crash-safety)**: `plateauedGroups`'s entire body
  (`plateau_scan.dart:80-115`), including the synchronous `byExercise.forEach`
  callback that calls `DateTime.parse`, is inside one `try {} catch (_) { return const
  <String>{}; }` — a malformed `date` on any one exlog row fails the WHOLE scan safe
  to `{}` (matches the established "crash → no-escalation" pattern used by
  `DeloadE1rmScan.scan` / `VolumeTitration.resolveDeltas`/`_recovered`).
  `dates.last`/`.first`/`dated[d]!` are guarded by the preceding `≥_minSessions` /
  own-keys invariants. `isFlat` guards empty/all-≤0 input. `ReadinessCheckin.fromMap`
  is independently crash-safe (coerces/clamps/defaults, `readiness.dart:49-59`).
  Cross-checked the "rung-1 (deload) is provably dead code, no `deload_evaluator.dart`
  change needed" claim against `deload_evaluator.dart:117-181` — the plan-review
  doc's own Round-1/Round-2 analysis already explicitly enumerated the shared
  "sparse/exact-half" edge case (both `readiness.good` and `_fatiguePresent` false
  there — not a literal boolean complement in that one corner) and correctly noted it
  doesn't matter because 12-A never touches that file. Clean.
- **plateau_specific / F (test execution, partial)**: Ran
  `flutter test test/contracts/plateau_escalation_behavioral_test.dart
  test/plan_generator/plateau_scan_test.dart` → 23/23 passed. Confirmed the
  "no-double-bump" + "respect decline" pair of tests, TOGETHER, would catch a
  `putIfAbsent`→`[]=` regression (the decline case `{-1}→merge→{-1}` would flip to
  `{1}` under that bug and fail — the "existing +1 stays +1" case alone would NOT
  catch it, since `1` overwritten with `1` is indistinguishable, but the suite as a
  whole does). Confirmed the "isolation (non-compound) lift" test is NOT vacuous — a
  direct scan of `assets/data/exercise_library.json` found 153 non-compound rows with
  populated `primary_muscles`, so the test's discovery loop reliably finds a
  candidate rather than silently `return`-ing. `flutter analyze` on all 5 touched
  `lib/` files → "No issues found!". The one real gap found here (orchestration-level
  coverage) is written up as Finding 2, not filed here.

## Overall

2 findings: 1×P0 (plan-review-record format — will hard-fail the merge-to-main CI gate
as currently written), 1×P1 (no test drives `plan_generator.dart`'s new Stage-4.5
composition through its real entry point, extending a pre-existing Batch-9 gap).
Everything else checked — the ship-dark inertness, the `putIfAbsent` no-double-bump
merge, the byte-identical extraction (diffed AND re-tested), the PRO/phase gating, and
crash-safety of the new detector — traced clean against the actual code and, where
possible, the actual test run output, not just the commit message's prose.
