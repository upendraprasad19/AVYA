---
branch: oi468-spawn-status
date: 2026-11-06
blast_radius: feature
review_rounds: 4
ground_truth_verified: true
verdict: converged
---

# Plan-review record: OI-468 / OI-311, the test spawn helper contains the `dart run` native-assets race and an impossible exit status (feature)

**Tier `feature`, M (test infrastructure):** `test/helpers/spawn.dart`, `test/contracts/spawn_retry_test.dart` (new),
`test/contracts/spawn_helper_test.dart` (two pins repointed), `test/contracts/sot_registry_citations_test.dart` (report-count pins),
docs, the board, one bug class. No `lib/`, no Hive key, no cloud column, no Edge Function. A B-pass is not required at this tier
(code-review skill, "Skip: feature"); one voluntary fresh Sonnet diff review of the final change is recorded below. Execution mode: INLINE.
Founder go: "Oi 468 now." (2026-11-06), the same autonomous pipeline as OI-454 earlier in the session.

## What this branch is

The helper's three result-returning entry points (`runSpawn`, `runSpawnAsync`, `runSpawnWithInput`) run a child again in two cases
where the HARNESS lost its answer: a dart child that exits exactly 254 with `File not formatted as yaml` on stderr (cause measured:
`dart run` rewrites `.dart_tool/native_assets.yaml` in place and every dart child reads it at start-up; a reader inside the 0.3 ms
empty-file window dies before `main`), at most twice; and any child with an impossible status (outside -255..255, never on Windows), once.
Every attempt is reported and one `[spawn-retry]` line with the failed attempt's output is printed before each retry. Plan
`docs/plans/2026-11-06-oi468-spawn-status.md` (v5), diagnose `docs/diagnoses/2026-11-06-spawn-status-native-assets-race-b7e2d9.md`.

## Rounds

Seven fresh context-blind Sonnet passes in four rounds (two lenses in rounds 1 to 3, one narrow pass in round 4). Each re-ran
measurements or read the code; none was told another's findings.

| Round | Plan | P0/P1 | Outcome |
|---|---|---|---|
| #1 | v1 | 0 P0, 3 P1 (+13 P2) | (mechanism) the "cannot repeat a side effect" claim held only for the dart process itself, not a wrapper; the family-B wording over-claimed for the very sighting that motivated D2; (scope) the retry dropped the failed attempt's output (the OI-311 hazard) and the test list did not kill Task 4's own mutants; the hook-site race was filed with deferral wording. Folded: the dart-exe scope, the printed note, per-reason budgets, mirrors, the hook sites scope. |
| #2 | v2 | 0 P0, 5 P1 | (design) counter logic duplicated across two loops, the exe scope almost untested; (facts) the mechanism is keyed on the cwd package and two sightings did not match it, the residue had no ledger rows, D7 had no founder scope answer. Folded: one pure decision, a pure note formatter, an exe table with mutants, residue rows. |
| #3 | v3 | 0 P0, 3 P1 | (facts) the model was wrong on the READER side: the writer follows the cwd, the reader follows the SCRIPT's package, so the 10-04 sot sighting is a reader-only victim (re-measured by me: 8 of 8, empty stdout) and only a7f3d1 stays unexplained; the OI-311 archive must not depend on the hook-race OI existing; (design) the new real-child tests must not themselves be victims. Folded. |
| #4 | v4 | 0 P0, 2 P1 | the sot filter had to keep the LAST attempt and strip the suffix (already implemented as `finalAttempts`, positional, with its own unit test; the plan text said "first attempts"); the hook-race wording read as a deferral menu (now: it is filed as OI-482 and starts next, no ledger row, the OI is the tracker). Folded in v5. No round 5: both P1s were corrected in the plan and verified in the tree, and the design did not change in any round. |

## Voluntary diff review (after the code and the full local suite)

One fresh context-blind Sonnet reader of the final diff plus `spawn_retry_test.dart` (read-only, commands listed, nothing run): no P0, no P1,
verdict accept, nine P2. Folded in the same change: the sot `finalAttempts` helper now finds the suffix at the end of the label (a multi-line
label collapses; a suffix-looking first line of a longer label does not) and the raw-list pin covers any member but `add`, an index and
`expect(reports`; a comment that contradicted the code and two doc comments that omitted `note` are corrected; the note's documented limits
(UTF-16 units, backslash and U+2028/U+0085 not escaped, a cut inside a surrogate pair) are stated; the test header no longer over-claims
(the spawns without a `note` seam are named); every async real-child call carries a 90 s `.timeout`; the stdin String payload is ASCII on
Windows. The two design notes (a Dart script forwarding a nested dart's status; a stdin write that fails on a child that died early) are
stated in the helper header and ledger row R2. Reviewer-confirmed correct: arguments of the three raw spawns are unchanged, the structural
guards still hold, `isDartExecutable` and both decision bounds, the hex values of the note. The mutation table was re-run on the final code.

## Ground truth

- Message origin, writer/reader/victim model, the marker-before-main run, `--packages`, the cwd/script cases in both directions and
  the reader-only run: measured by me and re-run by reviewers on a scratch package (SDK 3.11.1 = CI's Flutter 3.41.4).
- Natural reproduction without any truncating process: 1 of 265 and 1 of 554 `dart run` on a minimal package, 1 of 195 real gate scripts.
- Stated residue, each with a ledger row: sightings of group U (a7f3d1) and group B (impossible statuses from `git`) NOT explained;
  `startSpawn`, wrapper and nested children not retried; the note is the only record of a retry (a CI log, about 90 days). The hook
  sites carry the same race: OI-482.
- Mutation proof and the diff review: in the diagnose doc.
