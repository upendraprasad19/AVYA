---
branch: exercise-plates
date: 2026-08-29
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/exercise-plates-bpass.md
---

# Plan review record — exercise-plates

Exercise plates: tapping an exercise opens the movement drawn at its start and end
(one drawing for a static hold) with the form cues underneath. 165 of 292 exercises
ship with artwork; 127 show a monogram. Free to every tier.

Three independent context-blind rounds, each on the plan as hardened by the one
before, plus a fresh-subagent B-pass on the built code.

## Round 1 — 7 BLOCKER / 15 MAJOR / 16 MINOR

All seven blockers verified real against the files before acting. The two worth
recording:

- **The mapping file existed nowhere.** The plan instructed an executor to
  `git add docs/plans/exercise-plates-mapping.json`, and its provenance was two
  agent runs whose output lived in a session scratchpad. Six of ten tasks consumed
  it. Recovered and committed (`864ca93e`).
- **`exercise_library_schema_contract_test.dart` pins a CLOSED key set** containing
  all three fields the batch deletes, with an exact per-row match — so both the
  additions and the removals turned it red, and nothing repaired it.

Also: `Hive.initFlutter()` needs a `path_provider` mock; `day_detail_sheet.dart` has
no `BuildContext` in scope at the badge (a compile error, not a test failure);
`monogramFor` returned `CSC` where the test asserted `CCL`.

Two design changes came out of it, both improvements rather than patches:
**`demo_pair` moved into the library data** (the pair-vs-single rule lived only in
Dart, invisible to the Python pipeline, which therefore unioned every slug —
cropping a Wall Sit plate around a standing figure that never renders), and
**flat asset paths** (Flutter does not recurse, so directory-per-slug needs a
`pubspec.yaml` line each, and `pubspec.yaml` is platform-tier — every future
photograph batch would have become a platform-tier change).

## Round 2 — 5 BLOCKER / 11 MAJOR / 17 MINOR — verdict `not converged`

**Four of five blockers were defects introduced by round 1's own fixes.** That is
§4.12.1's split signal, and it was taken.

- Widening the dead-field scan from `lib/` to `lib/`+`test/` made the test **scan
  itself** and fail permanently.
- The schema-contract repair fixed the key set, miscounted the file as four tests
  when it has five, and missed a `rows.length == 292` assertion — while the
  "38 → 37" instruction contradicted the optional-key instruction four lines below.
- The `monogramFor` fix **degraded 9 names to fix 3** (`V-Up`→`U`, `Z Press`→`P`,
  `Prone Y/T/W Raise` all collapsing to `PR`). The signal is the possessive, not word
  length.
- The `didUpdateWidget` test was **unfalsifiable** — both fixtures artwork-less, so
  the monogram read `widget.exerciseName` and deleting the method still passed.

**THE SPLIT (founder decision, 2026-08-29):** three of the five blockers came from
one orthogonal change — removing `Donkey Calf Raise` — which is not part of this
feature at all. A one-row deletion turns out to touch the schema contract's 292-row
assertion, the cloud seed-parity test, a newly-minted seed migration, the
`applied_migrations` ledger, a live prod apply, and the frozen 606-persona generator
baseline, which shows the generator picking that very row and for which it is the
library's **only bodyweight-tier calf isolation option**. Split to **OI-147**; the
library stays at 292 rows and all three blockers dissolved.

## Round 3 — 5 BLOCKER / 6 MAJOR / 11 MINOR — `not converged`, but **"the unit is now the right size; do not split again"**

The round-2 pattern stopped: only one blocker was a failed round-2 correction, and it
failed *mechanically* — markdown ate two backslashes in a Dart string literal.

- Two blockers were **lint levels** that would have refused the push with nothing but
  `error: failed to push some refs` to go on: `avoid_dynamic_calls` on
  `box.get(id)['k']` (`exerciseBox` is an untyped `Box`) and `unawaited_futures` on a
  `Box.put` in an async body. Both are WARNING in `analysis_options.yaml`, and
  `--no-fatal-infos` suppresses infos, not warnings.
- The closure ledger was specified as a three-column table that **Gate 40 rejects
  outright** — it requires per-state fields (`blocker`+`reopen_when`, `reason`,
  `evidence`).
- The `breathing_cue` repair was parked `upstream_blocked` **against an OI that did
  not exist**: a deferral wearing a terminal state, which is the §4.2 case where the
  ban is on the semantic. Now OI-149, `blocked_on_user`, because the cues are provably
  unrecoverable — absent from all 20 columns of both seed migrations, and all 19 git
  revisions of the library carry the numeric value.

## Ground truth verified

Every numeric claim re-derived from the files rather than carried forward. The
material ones:

| claim | how |
|---|---|
| 292 rows / 165 artwork / 127 monogram / 153 slugs / 139 pair + 14 single / 292 files | Python over the library and the committed mapping |
| cue shapes 84 / 100 / 108 | counted; sums to 292 |
| 136 numeric `breathing_cue` = 136 null `met_value`, intersection 136 | counted; the coincidence is what identifies it as a column shift |
| `monogramFor` on all 292 names | executed both variants and diffed — 9 worse / 3 fixed |
| the upstream catalogue | **cloned** (`aac59922`): manifest shape, all 153 slugs present, every viewBox `0 0 512 512`, zero transforms, zero non-path primitives |

**The finding no review could have produced, because the catalogue had never been
fetched into this repo:** the pipeline hard-failed on SVG path commands `A`/`S`/`T`
on the theory they were rare. **All 292 shipping files use them**, `s` alone 20,917
times — it would have produced zero drawings while reading as a careful, well-guarded
tool. Bounding an arc by its chord box expanded by its radii was tried next and is
worthless: a near-straight arc carries an enormous radius, blowing `bench-press` to
59637×59602 on a 512 canvas and putting 199 of 292 files off the artboard. The
shipped implementation uses the W3C endpoint→centre conversion, validated against the
rasters from the founder review to **0.9 units of slack**.

## B-pass — accepted

`docs/reviews/exercise-plates-bpass.md`. Fresh context-blind subagent. 3 findings
(0 P0), all fixed in-batch: the missing platform-tier kill switch, a generator still
emitting the dead fields with a closure claim wider than its check, and two glossary
rows placed where GFM would not render them as a table.

One finding was **partly rejected on verification** — it claimed the branch is
platform *"solely because it edits `CLAUDE.md`"* and recommended splitting the doc
rows out. Classifying each path alone showed `pubspec.yaml` and `CLAUDE.md` are
independently platform-tier, so the split would have moved nothing. The real gap
(no `feature_flag`) was closed with a kill switch instead.

## Verdict: converged

Full suite **5105 passed / 0 failed / 7 skipped**, run twice — the second against a
verified-clean tree at HEAD, because the first ran while commits were landing
underneath it and its input set was therefore not exactly what merges.
`flutter analyze --no-fatal-infos` exits 0 with zero warnings.

**Outstanding, and not closable by any static check:** the badge grew 24→44 px in a
header Row at three sites. The card height wants a look on a real device.
