---
reviewed_at: 2026-08-29T16:17:34+05:30
staged_against: 2bcaa14f774c7eb64f5f30c2e3dc855d43748e50
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 3
verdict: accepted
---

# Code Review — exercise-plates

Dispatched as a fresh, context-blind Sonnet subagent per §3 of the skill — **not**
run inline by the author, unlike the 2026-08-28 pass whose record flags that
deviation. 3 findings: 0 P0, 1 P1, 1 P2, 1 P3. All fixed in-batch (§4.2).

## Finding 1 — P1 — blast_radius_mismatch

- **file:line:** `docs/blast_radius.yaml:25` (platform `requires:`) vs the whole diff
- **claim:** This batch classifies `platform`, and platform tier's `requires:` list
  includes `feature_flag`. The diff shipped no kill switch: the plate UI reached every
  user unconditionally, with a code revert as the only rollback.
- **⚠ PARTLY REJECTED — the reviewer's causal claim was wrong, and it changed the fix.**
  It asserted the branch is platform *"solely because it edits `CLAUDE.md`"* and
  recommended splitting the two doc rows into their own commit to drop the tier. Checked
  by classifying each path alone rather than reading the registry:
  `printf 'pubspec.yaml\n' | dart run scripts/blast_radius_from_diff.dart -` → **platform**
  (`blast_radius.yaml:324`), and `CLAUDE.md` alone → **platform** (`:68`). Either is
  sufficient, so the proposed split would not have moved the tier at all — it would have
  produced a second commit and the same requirement, unmet.
- **verification:** `printf 'pubspec.yaml\n' | dart run scripts/blast_radius_from_diff.dart -`
- **fix applied:** `lib/shared/widgets/exercise_plate/plate_flags.dart` —
  `configBox['disable_exercise_plates']`. Guarded at the **sinks**
  (`ExercisePlateThumb.build` and `ExercisePlateSheet.show`), not per call site, because
  three screens construct the thumb and a per-site check is one forgotten site from
  useless (`feedback_pause_flag_guard_the_sink`).
  **It is a KILL switch, not a ship-dark flag, and that is deliberate.** The repo's other
  flags (`plan_engine_flags.dart`) default OFF because each can change a prescription
  unsafely. A plate is additive, cosmetic, free-tier, and already degrades per-exercise to
  a monogram; shipping it inert would force a flip-on commit carrying the full §4.12.4 ×2
  review for a feature whose worst failure is a drawing not appearing. Defaults ON,
  fails-open on a missing box, and the flag turns it OFF.
  Proven behaviourally, both directions, in
  `test/contracts/exercise_plate_widgets_test.dart` — asset renders with the flag unset,
  `findsNothing` once set, monogram in its place.
- **status:** accepted

## Finding 2 — P2 — guard_without_its_mirror

- **file:line:** `scripts/add_new_exercises.py` (30 template blocks) vs
  `test/contracts/exercise_plate_library_data_test.dart:99-118`
- **claim:** The batch declares the three `image_*_url` fields dead and strips them from
  the library and `swap_service.dart`, and the closure ledger's P5 entry claimed they were
  *"pinned absent across lib/ and test/"*. That test's scan is `.dart`-only, so it
  structurally cannot see `scripts/add_new_exercises.py` — a live authoring tool still
  hardcoding all three into every exercise template.
- **verification:** `grep -c '"image_start_url"' scripts/add_new_exercises.py`
- **fix applied:** removed all 30 blocks from the generator (verified: 0 references
  remain), and **narrowed the P5 evidence** to say what is actually pinned — `.dart` files
  only, with the closed-schema contract as the real downstream catch. The overstatement
  was the more dangerous half: an evidence claim wider than the check behind it reads as
  coverage.
- **status:** accepted

## Finding 3 — P3 — writer_reader_drift (docs)

- **file:line:** `docs/naming_conventions.md:230-231`
- **claim:** The two new glossary rows were inserted under the `## 8.` heading but
  **before** the table's header and delimiter rows, so GFM renders them as raw text with
  literal pipes rather than as table rows. The guard test does a bare
  `n.contains('demo_slug')`, so it passes regardless of placement.
- **verification:** `sed -n '226,240p' docs/naming_conventions.md`
- **fix applied:** moved into the real table as ordinary rows, with the third column the
  table actually has (`What it is NOT`) — which turned out to be worth more than the
  placement fix: both entries now carry the trap that motivated them (`demo_slug` is not
  unique per exercise; `demo_pair` is not derivable from `logging_type`, which was the
  first design and is exactly what put the rule where the Python pipeline could not read
  it).
- **status:** accepted

## Lenses that returned clean

Recorded because an unstated input set is worthless.

- **function_exception_swallow** — 0 `.functions.invoke(` in the diff; no Edge Function touched.
- **secrets_in_tree** — 0 credential-shaped literals; the only "token" hits are prose about text tokenization.
- **unawaited_no_error_sink** — 0 `unawaited(` added.
- **writer_reader_drift (code)** — `plate_resolver` reads Hive-any-type fields via `is String`/`== true`, never `as`, consistent with the community-row hazard at `sync_community.dart:502` (confirmed add-only, no update path). The five SoT citations of `day_detail_sheet.dart` were correctly recalculated to `:452-470`; `resolvePlate` and `_exerciseLibraryVersion` citations resolve exactly; OI-145→149 all exist at their claimed anchors.
- **guard_without_its_mirror — the SVG bbox.** The strongest part of this pass. The reviewer independently re-implemented the arc math with an **analytic extrema solver** and ran it over all 292 shipped SVGs, then re-ran the pipeline's own sampling at 24 / 240 / 2400 / 24000 samples on the 7 files whose ink pokes outside `[0,512]`. Byte-identical at every sample count — so the discrepancy is not a sampling artifact, and `union()`'s clamp is discarding ink that the source frame's own `viewBox` already clipped. **The crop is never too small.** That is the one defect in this batch a green suite could not have caught.
- **guard_without_its_mirror — slug dedup.** The mapping is keyed by library `id`, so there is no fuzzy-matching step where two exercises could contend for one slug; the 12 shared slugs are spelling-variant pairs.
- **guard_without_its_mirror — `didUpdateWidget` staleness.** Traced to the write paths: library rows change only via the startup version check (pre-mount), community rows are add-only. No live path to a stale render, and deleting the re-resolve IS caught by the opposite-sides-of-`hasArtwork` test.
- **`_cues` / `breathing_cue` against real data** — `coaching_cues` is a List on all 292 rows, split 84/108/100 exactly as commented; `breathing_cue` is a String on all 292 with exactly 136 numeric, matching OI-149.
- **Row overflow at the three 24→44 px sites** — all three absorb the growth via `Expanded`/intrinsic sizing.
- **`LicenseRegistry` failure mode** — the async generator body runs only when something drains `LicenseRegistry.licenses`, which happens on tapping the new Profile row, not at startup.

## Founder triage notes

All three accepted and fixed in-batch. The one thing this review could not settle, and
the author had already self-flagged in the widget's own header: the badge grew 24→44 px in
a header Row, and **the card height wants a look on a real device**. Static review cannot
close that.

Correction worth keeping for the next pass: the reviewer's blast-radius causal claim was
wrong in a way that would have produced a useless fix. `pubspec.yaml` and `CLAUDE.md` are
*independently* platform-tier, so "split the doc rows out" moves nothing. **Classify each
path alone rather than reasoning about which edit "caused" the tier** — the classifier
answers it in one command.
