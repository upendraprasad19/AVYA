---
branch: oi204-delta-sync
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi204-delta-sync-bpass.md
tier: standard
date: 2026-09-19
---

# Plan review — `oi204-delta-sync` (OI-204: full-rescan sync timeout)

Batch B of the 2026-09-19 sequence A (gate-integrity) → B (this batch) → C (OI-154 profile
tombstone, not yet started). Extends the existing, already-proven `_syncScheduledWorkouts`
fingerprint-skip pattern (H1b Part A, 2026-06-27) to `_syncExerciseLogs` and
`_syncNutritionLogs`, so a full nightly re-sync stops re-pushing every row on every pass and
stops routinely tripping `restoreOpTimeout` (34-45 trips / 25h on the founder's own account as
of 2026-09-16). Spec: `docs/superpowers/specs/2026-09-19-oi204-delta-sync-design.md`. Plan:
`docs/superpowers/plans/2026-09-19-oi204-delta-sync.md` (4 tasks: gate-before-refactor checker,
exlog fix, nlog fix, docs). Diagnose: `docs/diagnoses/2026-09-19-full-rescan-sync-timeout-d3f8a6.md`.

## Review rounds (context-blind, `docs/agent_brief_preamble.md` prefixed)

| Round | Scope | Findings | Material | Result |
|---|---|---|---|---|
| 1 | plan v1, two reviewers (independent, no cross-visibility) + coordinator's own direct-trace re-verification of every claim before adoption | ~24 (7 critical-tier, ~10 important, ~7 minor) | Yes — root design held, but every execution-detail defect was real | `not converged` → hardened plan v2 (~25 targeted edits) |
| 2 | hardened plan v2, two reviewers: C (mechanical/static — gate regex vs all fixtures + real Task 2/3 code, ledger accepted-forms, e2e subprocess mechanics, diagnose-id/commit-gate compliance) / D (runtime/behavioral — control flow, cross-file `part of` privacy, kill-switch state machine, cross-task sequencing) | 2 (both by C; D found 0 material, 2 harmless self-healing minors) | Yes — 1 critical (YAML indentation), 1 important (prose-only test-repoint) | Both fixed same session, re-verified directly by coordinator → `converged` |

**Round-1 headline findings (all independently re-verified by the coordinator via direct file
read/trace before being trusted, per `feedback_audit_verifier_cannot_trust_own_subagent.md` —
none accepted on subagent prose alone):**
- **C1 (both reviewers + coordinator).** The gate's atomicity checker matched a bare substring
  (`.contains('exlogHashIndex[')`) that also matched the index-hydration preamble and the
  skip-check's own read — it would have false-positived on Task 2's first commit. Fixed: a
  `fingerprintVarName` field on `HashSkipDomainSpec`, store-regex requires
  `<prefix>[^\]]*\]\s*=\s*<fingerprintVarName>\s*;`.
- **C2.** The gate's own mutation-proof test used `expect(v, isNotNull)`, matching none of
  `check_gate_test_ledger.dart`'s 3 accepted red-path forms, and never named the gate literally
  — would have blocked the commit on rule-24 grounds. Fixed: added
  `test/scripts/sync_hash_skip_atomicity_e2e_test.dart` spawning the real gate + asserting exit
  code, mirroring the repo's established lib-test+e2e-test pairing.
- **C3.** Task 2's inline-map→named-var restructure breaks 2 pre-existing contract tests that
  source-slice on `}, onConflict:` — the exact "extraction breaks a source-grep contract"
  recurring class this repo's own CLAUDE.md §4.9 already documents. Fixed: pre-edit grep +
  repoint both at a stronger `final summaryPayload = <String, dynamic>{` anchor, in the same
  task/commit as the restructure (not a follow-up).
- **C4.** The diagnose slug (`full-rescan-sync-timeout-oi204`) fails
  `check_bugfix_commits_have_diagnose.dart`'s `[0-9a-f]{6,}` id pattern. Fixed: minted real id
  `d3f8a6`.
- **C5.** Both new test files used the wrong package name (`fitness_app`, real: `icanbefitter`)
  and were missing a `dart:io` import — would not compile. Fixed.
- **B-C3 (one reviewer only; coordinator independently confirmed via grep that the OTHER
  reviewer's clean-bill for a different guard-scan test doesn't contradict this — that test only
  scans `.upsert(`/`.delete()` sinks, not the new Hive `.put()` this batch adds).** The nlog
  postamble's new hash-index `.put()` has no `ownerChangedSince` guard immediately before it,
  breaking that function's own established per-sink idiom (diagnose e5c2d1 CLASS 1). Coordinator
  checked `sync_workout.dart` for comparison — zero `ownerChangedSince` calls anywhere in that
  file, confirming the guard is nutrition-specific, not a repo-wide norm the sched/exlog fixes
  also needed. Fixed: guard added, scoped to Task 3 only.
- **B-C4 (both reviewers).** `simulation_service.dart`'s `resetJourney` prefix-clear lists don't
  cover the two new hash-index Hive keys — the exact failure mode the file's own comment already
  documents for the sibling sched key. Fixed: both keys added to the respective
  `_clearKeysWithPrefixes` calls, with regression tests.

Importants folded in: spec-mandated per-domain behavioral atomicity test (was missing from the
plan), exact-call-site-count test, gate contract-overclaim corrected in spec prose (can detect a
*changed* store count, not a specifically-missing `=false`), mutation-red count corrected 2→3
(a Hive round-trip test was also sensitive to the `==`→`!=` mutation, missed in the original
trace), SoT registry `line_range:` re-derive step added per task, nlog kill-switch now clears
the stale index instead of leaving it booby-trapped when `disable_nutrition_slot_merge` reverts,
§4.12.7 execution-mode declaration added to the plan header (was ambiguous "recommended...or"),
silent fingerprint-exception catch given telemetry.

Minors adopted: test mirror-gaps, Hive test setup matches the sched template's
createTemp/full-teardown shape, spec migration-count correction (057's DELETEs),
`exlogShouldSkipUpsert`/`nlogShouldSkipUpsert` (byte-identical) extracted to one shared private
`_fingerprintMatchesStored`. Minors explicitly rejected: `@visibleForTesting` placement asymmetry
— the existing sched trio already does the same thing and ships clean; touching it risks a new
`invalid_use_of_visible_for_testing_member` warning on legitimate call sites for no behavioral
gain.

**Round-2 findings, both introduced while fixing round-1 findings** — exactly the §4.12 founding
incident class the ×2-round process exists to catch:
- **C (critical).** Task 1's ledger YAML entry for the new gate was indented 2 spaces instead of
  column-0; the real `gate_test_ledger_lib.dart` parser never recognizes an indented key as a
  new entry — it would have silently merged into the preceding gate's entry and thrown a
  `FormatException` naming the WRONG gate on Task 1's own commit. Coordinator re-verified by
  reading both the plan's literal text (confirmed the indent) and the real
  `docs/audit/gate_test_ledger.yaml` (confirmed every existing entry sits at column 0). Fixed:
  dedented.
- **Important.** Task 2's test-repoint fix for C3 above was prose-only ("repoint the anchor")
  where the rest of the plan gives literal code — mechanically sound per the reviewer's own
  trace, but risky to leave inferred given this is precisely the silently-vacuous-test class the
  fix exists to prevent. Fixed: coordinator read both real test files' current content and wrote
  the literal replacement Dart for each, confirming the `summaryPayload` map literal has no
  nested braces so `indexOf('};', payloadStart)` is a safe close-anchor.
- Reviewer D (runtime/behavioral) independently re-traced the gate regex against the REAL Task
  2/3 code (not just plan fixtures), confirmed the `_fingerprintMatchesStored` cross-file privacy
  works because `sync_workout.dart`/`sync_nutrition.dart` are `part of '../sync_service.dart'`
  (Dart privacy is library-scoped — the identical pattern already ships for
  `_schedHashIndexKey`), confirmed the kill-switch clear/rebuild state machine is safe across
  repeated passes, confirmed Task 2→3 sequencing is unambiguous, and found 0 material issues — 2
  harmless self-healing minors only (a narrowed failure boundary in exlog's set-row ordering,
  already covered by the outer retry; nlog's postamble pruning against the loop-start snapshot
  rather than a fresh rescan, matching the spec's own deliberate choice).

## Ground truth

Every writer/reader file:line cited above was read directly from the worktree by the coordinator
before being adopted, not trusted from reviewer prose (`feedback_source_of_truth_audit.md`).
Specific live checks: `SyncService._schedHashIndexKey` reference from `sync_workout.dart:1512`
confirmed live (precedent for the new cross-file private access); `sync_workout.dart` grepped for
`ownerChangedSince` — 0 hits, confirming the guard's scope; `pubspec.yaml` read directly to
confirm the real package name; `docs/audit/gate_test_ledger.yaml` read directly to confirm
column-0 indentation on every existing entry; both stranded contract tests' real current content
read in full before writing their literal replacements.

## Execution (§4.12.7 — decided at batch start: subagent-driven-development, inline coordinator)

One implementer subagent per task (4 tasks), fresh dispatch each, task-reviewer dispatched after
each report, coordinator integrating directly (not via forked worktrees — this batch's 4 tasks
are sequential with real interfaces between them: Task 2/3 both consume Task 1's
`HashSkipDomainSpec`/gate, Task 3 explicitly reuses Task 2's `_fingerprintMatchesStored`, Task 4
documents all three, so parallel forks were not applicable here the way gate-integrity's 4
zero-overlap units were). Both Task 2 and Task 3 implementers independently found and fixed
issues beyond their literal briefs during a self-directed wide-sweep (additional stranded
contract tests measured and repointed with real character-count slack, not guessed); both
deviations were flagged for extra task-reviewer scrutiny and both task-reviewers approved.

## Tests

Task 1: 13/13 lib + 3/3 e2e, mutation-proof clean (2 mutations, both reds on the intended
assertions). Task 2: 28/28 targeted, mutation-proof matched the 3 hand-traced tests exactly.
Task 3: full `flutter test` run locally — 6046/6046 green (exceeds what the task required;
explicitly NOT a substitute for pre-push/CI, which have not run against any of these commits
yet since nothing has been pushed) — mutation-proof reddened 3 tests in nlog's own file AND 3 in
Task 2's exlog file, since both domains delegate to the shared `_fingerprintMatchesStored`
(itself evidence the sharing is real, not merely asserted). Full-suite pre-push (≥account tier)
and CI are the outstanding full-suite gates, to run at push time.

## B-pass

`docs/reviews/oi204-delta-sync-bpass.md` — two fresh context-blind Sonnet reviewers against the
three-dot `main...HEAD` diff (23 files; two-dot `main..HEAD` is a trap on this branch — `main`
independently gained 8 unrelated gates from the sibling `discipline-gates-tier12` branch after
this worktree forked, so two-dot showed them as deleted). Blast radius confirmed **platform**.
Lens set split (>15 files, per this skill's own 2026-09-08 tuning default): reviewer A lenses
1-5, reviewer B lenses 6-8. **4 findings (1 P1, 1 P2, 2 P3); 0 false_alarm; `verdict: accepted`.**

- **F1 (P1)** — the gate-before-refactor atomicity checker's own guard-scan silently passed an
  UNGUARDED store statement wrapped across two lines (a plausible `dart format` output; a naive
  whole-file existence check and a per-line follow-up scan disagreed on what counts as a match).
  Reproduced live against the real gate with a positive control. Fixed: `storeLineIdxs` now
  derives from the same whole-text match set `hasStore` uses, mapped to line indices by match
  offset. 2 new fixtures added; reverted the fix and confirmed the new FAIL fixture reddens
  exactly as predicted, restored, re-confirmed 15/15 lib + 3/3 e2e green + the real gate still OK
  against production code. Ledger evidence extended. Full trace: diagnose `d3f8a6`'s new
  "B-pass remediation" section (third commit on this branch).
- **F2 (P2)** — a second, different blind spot in the same gate (a new swallowing catch that
  forgets to flip its flag false defeats the aggregate flag-false COUNT check) was already
  accurately disclosed in `docs/architecture/sync.md`, confirmed by reading the cited section
  directly — but the wording undersold the severity. Strengthened to name the false-skip
  consequence explicitly; the heavier structural fix (per-catch-block enumeration) remains
  out of scope, matching the reviewer's own recommendation not to force it into this pass.
- **F3 (P3)** — `docs/sot_registry.yaml`'s `class_constraints:` documented the
  `weeklyFullSync`-bypasses-coalescer race for exlog only, not nlog, though the same race
  applies identically and is safe for the same reason. Mirrored the disclosure.
- **F4 (P3)** — `_resolveCompletedAt`'s `DateTime.now()` last-resort fallback (pre-existing,
  unmodified by this diff) feeds the new fingerprint mechanism a non-deterministic
  `completed_at` for any row that exhausts all 6 earlier resolution tiers, permanently
  defeating the skip for that one row. Fails safe (no data loss, just a missed optimization for
  a rare row); already telemetry-flagged. Documented as a new Known Limitations bullet in the
  diagnose-doc.

Every finding independently re-verified against the real files/code before being accepted (regex
traced by hand for F1; both cited doc sections read in full for F2/F3; the fallback→fingerprint
data flow traced line-by-line for F4) — none accepted on reviewer prose alone.
