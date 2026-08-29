# Exercise plates — spec

> **Status:** DESIGN CONVERGED, awaiting one input. Written 2026-08-29 on branch
> `exercise-plates`, based on `main` @ `d5ca2917`.
>
> Every number below was measured against the working tree at that commit, or against the
> upstream asset repo over the network. Where a claim is unverified it says so.
>
> ⚠ **The library is 292 rows, not 259.** An earlier pass of this design was built on a stale
> working copy read before the OI-89 bodyweight work landed (`a7c2d194`, `7543a4df`,
> 2026-08-28, +33 exercises). Re-read `assets/data/exercise_library.json` and check the row
> count before trusting any figure here.

---

## Why this exists

When a recruit starts a workout they see an exercise **name** and nothing else. A beginner —
our wedge user, a 22–35 desk worker in their first months of lifting — cannot always tell what
"Barbell Bent Over Row" looks like, and the cost of guessing is bad form or a skipped exercise.

The text half of the answer already ships: `CoachingContentPanel`
(`lib/features/train/screens/active_workout/coaching_content_panel.dart`) renders
`coaching_cues`, `common_mistakes`, `breathing_cue` and `warmup_protocol` in a collapsed
FORM & CUES panel, free to every tier. **The missing half is the picture.**

The data model already anticipated it and is entirely dead:

| field | rows populated | state |
|---|---|---|
| `image_start_url` | 249 / 292 | 112 real URLs, **all HTTP 404** (they use `free-exercise-db`'s pre-restructure path layout); the rest are the literal string `PENDING` |
| `image_end_url` | 249 / 292 | same |
| `gif_url` | 292 / 292 | 286 are `PENDING`; the other 6 point at **wger JSON API endpoints**, not images |

Nothing renders them. The only reader in `lib/` is
`lib/core/services/swap_service.dart:294-295`, which *copies* the fields through an exercise
swap. Written, never read.

---

## Source

**`github.com/bryllim/workout-guide`** — 302 exercises × 3 frames = 906 transparent 512×512
SVGs, each a single path filled `#fff`. Artwork **CC BY-SA 4.0**, package code MIT,
vector-traced from **Everkinetic** (also CC BY-SA 4.0). Raw URL shape:

```
https://raw.githubusercontent.com/bryllim/workout-guide/main/packages/workout-guide/assets/<slug>/frame-N.svg
```

The single-white-path property is why this works: one `colorFilter` tints every drawing to
Campaign Gold `#D4B270`, so visual consistency is a property of the file format rather than a
curation problem. `flutter_svg ^2.3.0` is already a dependency (`pubspec.yaml:84`). Verified on
sampled files: exactly one `<path>`, one `fill` attribute, no `<style>`, gradients, masks,
filters or embedded raster — nothing `flutter_svg` struggles with.

**Rejected: `free-exercise-db`** (the source our dead URLs point at). The repo is Unlicense but
its *images* have unanswered provenance — GitHub issues #2 (closed, no maintainer reply), #12
and #13. Not defensible in a paid app.

**Rejected: stock photo sites.** No per-exercise start/end taxonomy exists, consistency is
structurally impossible across different models and lighting, and their licences grant photo
rights but not likeness rights — a recognisable person in a commercial fitness app needs a
model release the stock site does not provide.

---

## Asset treatment — three findings that shaped it

### 1 · Frame 2 is an artifact, not a third position

At 430 px, `push-up/frame-2` is the *same pose* as `frame-1` with every line double-stroked.
Measured across 23 exercises, frame 2's ink coverage runs **0.65× to 2.69×** frame 1's (median
1.46×). Any animation cycling all three frames pulses in thickness.

**Only frames 1 and 3 are real poses.** Excluding frame 2 also drops the fattest files (mean
43.6 KB vs 26.9 KB for frames 1 and 3).

### 2 · Frame order is not start → end

The upstream README calls them "three consistent frames" — it is an **animation loop**, and a
loop has no canonical first frame. What frame 1 actually is, is *the pose that identifies the
exercise*; frame 3 is the contrasting one. For Bench Press and Squat that coincides with
start → end. For holds and stretches it does not: Wall Sit, Superman, Child's Pose and Dead Bug
are all **reversed**, and for Standing Quad Stretch and Cross-Body Shoulder Stretch frame 3 is
*a figure standing still doing nothing*.

Resolved by the plate-shape rule below, at zero runtime cost.

### 3 · Thickening the line makes it worse; cropping makes it better

The median line is 3–4 units on a 512 canvas — **0.97 px** in a 165 px plate, which is what
"blurry" looks like. Two fixes were tested at matched display size:

- **Stroke thickening — REJECTED.** In this artwork the line and the gap between two lines are
  the same size, so a stroke adds to the ink *and subtracts from the gap*. Measured on Wall
  Sit: median interior gap falls 17 → 13 units at `stroke-width=4`, and **6 % of gaps close
  completely**. That is detail deleted.
- **Crop — ADOPTED.** A crop scales ink and gaps together, so nothing merges.

⚠ **The crop must be the union of both frames of a pair, never per-frame.** Bench Press start
is 390×444 and end is 431×397; cropping each to its own bounds makes the body visibly change
size between START and END. The union (451×484 with 10 units of padding) keeps the figure
locked. **Single-plate exercises use the frame's own bounds.**

⚠ Judge nothing about sharpness at 1×. A phone runs at DPR 2.5–3, so a 44 px thumbnail is
110–132 physical pixels. **Ship 44 px with the crop, then look on a handset** before deciding
whether `fill-rule="nonzero"` (a one-attribute change that fills the enclosed regions) is
needed. That decision is blocked on a device and cannot honestly be made from a desktop page.

---

## The plate-shape rule

Driven by `logging_type`, which is already on every row and already decides which inputs the
Active Workout screen shows (`lib/features/train/CLAUDE.md`, logging-types table).

| `logging_type` | n | What frames 1 and 3 are | Plate |
|---|---|---|---|
| `weight_reps` | 115 | genuine top and bottom of the rep | **two images**, START + END |
| `bodyweight_reps` | 102 | same | **two images**, START + END |
| `timed` | 65 | frame 1 is the hold; frame 3 is entry, neutral, or nothing | **one image** |
| `cardio` / `distance` | 10 | not a rep at all | **one image** |

**217 two-image, 75 single-image.** Verified across 17 `timed` exercises; the pattern held
every time.

A hand-curated exception list covers dynamic-`timed` movements that genuinely do have two
positions — Cat-Cow, Flutter Kick, Bear Crawl, Crab Walk, Jump Rope, Mountain Climber. It lives
in Dart beside the rule, not in the library JSON, because it is a rendering decision rather
than exercise data.

The failure modes are asymmetric and that is why `timed` defaults to one image: showing a pair
when only one pose is meaningful looks broken; showing one when two would help is merely less
informative.

---

## Data contract

### New field: `demo_slug`

One nullable string per exercise row in `assets/data/exercise_library.json`, naming the
workout-guide slug. Absent or null ⇒ the monogram empty state.

The slug — not a pair of URLs — because the file paths are derivable (`<slug>/frame-1`,
`<slug>/frame-3`) and a single field cannot drift out of sync with itself. This also lets the
dead `image_start_url` / `image_end_url` / `gif_url` fields be removed rather than leaving two
competing sets of image columns.

### Existing users get it with a one-line change

`lib/core/services/seed_service.dart:95` holds `_exerciseLibraryVersion = 10` — the OI-89 re-seed already consumed 10. **Bump to 11.**

⚠ Writing "bump to 10" would be a silent no-op: `seed_service.dart:128` re-seeds only when `storedExVersion < _exerciseLibraryVersion`, so an unchanged constant means no existing install ever picks up `demo_slug`. **Read the constant, do not assume its value.**
On next launch every install re-seeds through an idempotent `putAll`
(`_seedExercises`, the `putAll` + version stamp at `seed_service.dart:192`), so a new field reaches everyone. No migration, no data loss.

### The second writer is already safe

`lib/core/services/sync/sync_community.dart:502` guards its write with
`exerciseBox.get(id) == null`, so it can only *add* rows — it cannot overwrite a seeded row and
strip the new field. **This closes the writer/reader drift risk before it opens**, and is worth
an explicit assertion in the contract test so a future relaxation of that guard fails loudly.

### Postgres

`supabase/migrations/074_seed_exercise_library.sql` also carries the library. If `demo_slug`
is added there, `backups/live_schema_columns.json` is regenerated **in the same commit** (root
CLAUDE.md §7 pointer row). If the field stays client-only, the migration is untouched and this
paragraph is the record of that decision.

---

## Matching: use the upstream manifest, not exercise names

`packages/workout-guide/manifest.json` (302 entries, 567 KB) carries per-exercise
`equipment`, `exerciseType`, `primaryMuscle`, `secondaryMuscles`, `isStretch`, and **per-frame
attribution including the exact Everkinetic source URL and licence**. Matching on names alone
ignores all of it.

**The gate that matters: reject any drawing that adds load-bearing kit the exercise does not
use.** Load-bearing means `Barbell`, `Dumbbell`, `Kettlebell`, `Plate`, `Cable`, `Machine`,
`Resistance Band`. It is deliberately one-directional — *ours having more* never rejects, and
**their `Bodyweight` never rejects**, because their `Bodyweight` is a superset of ours: it
covers Pull Up, Chin Up, Chest Dip, Hanging Leg Raise and Ab Wheel Rollout, which our data
files under `pull-up bar`, `parallel bars` and `ab wheel`. A symmetric class-equality gate
wrongly rejected all six; this one does not.

**What it caught: 18 of 145 automatic matches carried the wrong equipment**, in the tier no
human was going to review:

| our exercise | `equipment_needed` | auto-matched drawing | drawing's equipment |
|---|---|---|---|
| Walking Lunge | `bodyweight` | `walking-lunge` | Dumbbell |
| Split Squat | `bodyweight` | `split-squat` | Dumbbell |
| Reverse Lunge | `bodyweight` | `reverse-lunge` | Dumbbell |
| Deficit Reverse Lunge | `bodyweight` | `deficit-reverse-lunge` | Dumbbell |
| Reverse Nordic Curl | `bodyweight` | `reverse-curl` | Barbell — **a different exercise** |
| Egyptian Lateral Raise | `cables` | `lateral-raise` | Dumbbell |
| Overhead Tricep Extension | `dumbbells` | `overhead-tricep-extension` | Cable |

Muscle and type agreement are **tie-breakers only**, never promoters: weighting them at 0.20
let `bodyweight-squat` outrank everything for *Bodyweight Good Morning* on shared-muscle alone,
and pushed the review queue from 62 rows to 111. At 0.05 behind a name floor of 0.34 they
order equals without inventing matches.

**Consequence for the licence:** the manifest's per-frame `attribution` block gives the exact
creator, licence URL and Everkinetic source for every asset, so the credit surface can be
generated rather than hand-written.

---

## Placement

**The number badge becomes the plate.** The badge carries almost nothing — position in a
vertical list is already obvious and the active card is marked in gold — so replacing it costs
**zero new elements**, keeping Hick's Law neutral on a header row that is already at five.

⚠ **Tapping the exercise name is not available.** `exercise_card.dart:429-433` wraps the whole
header row in a `GestureDetector` whose `onTap` is `widget.onFocus` (expand/collapse, Bug #15b)
and whose `onLongPress` is `widget.onLongPressHeader` (superset grouping). Both are load-bearing.

**Size: 44 px, not 38.** This also lifts the target to the minimum touch size — one change,
two fixes.

Three sites render a numbered badge, all near-identical `accentSoft` squares/circles holding
`${index + 1}`:

| surface | site | badge today |
|---|---|---|
| Active Workout card | `exercise_card.dart:447` | 24 px circle |
| Train tab · day card | `expandable_day_card.dart:236` | 24 px square |
| Home · day detail sheet | `day_detail_sheet.dart:256` | 28 px square |

A second, quieter entry rides the existing FORM & CUES bar (`FORM & CUES · VIEW PLATE`), so
each of the two moments of doubt — *"what is this movement?"* while scanning, and *"am I doing
it right?"* at the rep — has a door, with no new chrome in either state.

**The set-position number is not lost:** the expanded set table already prints 1, 2, 3 down its
left edge. If it is wanted in the collapsed state, the meta line takes it as
`EX 1 OF 6 · 4 SETS · 8-12 REPS`, which also adds a goal-gradient signal the card lacks today.

### Performance constraints, both already learned in this file's neighbourhood

- **Resolve the slug in `initState`, never in `build()`.** The Active Workout card rebuilds
  roughly once a second off the workout timer; `coaching_content_panel.dart:40-58` documents
  exactly this and resolves in `initState` / `didUpdateWidget`.
- **Cache the parsed picture.** Six to eight thumbnails per screen. Parsed once, nothing;
  parsed per frame, a jank source.

---

## The empty state

**A monogram** — the exercise's initials in Wardroom mono, dim gold on a recessed ground inside
the same plate frame, so the slot reads as *a plate not yet issued* rather than as a failure.

Three populations need it, and they are not edge cases:

1. **Custom exercises** the user creates — no library row at all.
2. **Community exercises** pulled by `sync_community.dart:508` from `user_custom_exercises`.
3. **The 85 library rows with no equivalent**, until they are shot.

**Swapped exercises are not on this list** — a swap picks from the library, so it arrives with
a plate.

⚠ **The monogram does not identify and is not meant to.** Measured across the library, a
three-letter code collides for 33 % of exercises and two letters for 62 % — `SC` is Skull
Crusher, Suitcase Carry, Spider Curl *and* Sandbag Clean. The exercise name is printed
alongside; the monogram's only job is to make the slot look deliberate. Rejected alternatives:
falling back to the number (a column mixing engravings and bare numerals reads as *some of
these are missing*), a category glyph (nine glyphs to design, and a triangle beside an
engraving is two visual languages), and an empty frame (reads as a loading state that never
resolves).

---

## Licence obligations

Artwork is CC BY-SA 4.0. Attribution to **Everkinetic** and **Bryl Lim** is owed, and an
indication that changes were made.

The only edit is the `viewBox` crop. Whether a mechanical crop rises to *Adapted Material* and
pulls in ShareAlike is arguable; cropping usually counts. **The cheap answer is to treat the
processed set as adapted and publish it under CC BY-SA 4.0** rather than litigate the edge.
This never reaches the app's own code — CC BY-SA has no copyleft effect on separately-licensed
software that merely displays the work.

Open: where the credit surface lives in the app, and whether the processed assets sit in their
own public repo or beside this one. Flutter's `showLicensePage` / `LicenseRegistry` is the
conventional mechanism; whether this app already uses one is **unverified**.

---

## Delivery

**Bundled, not fetched.** Root CLAUDE.md coding rule 1 is Hive-first and never block UI on the
network, and a gym basement with no signal must still show the plate.

Measured across 60 real frame-1 and frame-3 files: median **18.1 KB**, mean **26.9 KB**,
deflate ratio **0.41**.

| set | exercises | plate files | raw | in-APK |
|---|---|---|---|---|
| mapped today | 124 | 219 | 5.8 MB | **2.4 MB** |
| plus the review set | 181 | 323 | 8.5 MB | **3.5 MB** |
| full 292 coverage | 292 | 509 | 13.4 MB | **5.5 MB** |

⚠ `pubspec.yaml:129` declares assets **per directory**, so `assets/exercise_plates/` needs a new
entry — and `pubspec.yaml` is pinned `platform` in `docs/blast_radius.yaml:324`. **That single
line sets the whole batch's blast radius**, and it is not worth gaming.

---

## What this batch removes

`image_start_url`, `image_end_url` and `gif_url` from `assets/data/exercise_library.json`, plus
the copy-through at `swap_service.dart:294-295`. They are 100 % dead — every populated URL
404s — and leaving them beside `demo_slug` would ship two competing sets of image fields, which
is the writer/reader drift shape this repo has hit repeatedly. Migration 074's column list is
updated in the same commit if the columns exist server-side.

---

## Not in this batch, and why

Both are separate work items with their own triggers, not parts of this one held back.

- **`breathing_cue` holds a number on 136 of 292 rows.** A column shift in the original
  spreadsheet import put `met_value` into `breathing_cue` — exactly 136 rows have a numeric
  cue, exactly 136 have a null `met_value`, intersection 136, zero on either side.
  `coaching_content_panel.dart:143` renders it verbatim, so a Plank shows `BREATHING / 5` in
  the shipped app today. `met_value` is read nowhere in `lib/`, so no calorie maths is wrong,
  and the repair is data-only. **Owner: its own OI board entry.** It touches this batch only
  because the plate reuses the same text.
- **`fill-rule="nonzero"` at thumbnail size.** Blocked on a real handset — it cannot be judged
  at 1× and the page says so. One attribute when the answer is known.

---

## Verification

| what | how |
|---|---|
| plate-shape rule | behavioral test: every `timed` / `cardio` / `distance` row renders one plate, every rep row renders two; the dynamic-`timed` exception list is asserted by name |
| union crop | behavioral test: for a paired exercise, both frames resolve to the **same** viewBox — the assertion that catches a regression to per-frame cropping |
| `demo_slug` reaches existing users | behavioral test over a seeded box at version 9 → re-seed → field present |
| `sync_community` cannot strip the field | contract test asserting the `get(id) == null` guard, so relaxing it fails loudly |
| empty state | behavioral test: null / absent `demo_slug` renders the monogram, never a broken image |
| no dead URL fields remain | source-grep contract test over `lib/` **and** the JSON asset |

SoT registry (`docs/sot_registry.yaml`) gains a concept for the plate read path with a real
`behavioral_test_path:` — rule 21 is strict and a bare registry entry blocks the commit.

---

## Process weight

**Blast radius: `platform`**, driven by `pubspec.yaml` (verified:
`dart run scripts/blast_radius_from_diff.dart pubspec.yaml` → `Blast-radius: platform`).

Consequently: a plan-review record at `docs/plan-reviews/exercise-plates.md` with
`review_rounds: >= 2`, `ground_truth_verified: true`, `verdict: converged` **and
`bpass: accepted`** (§4.12.3, required at ≥platform); a self-initiated `/code-review` B-pass
before the `--no-ff` merge (§4.3); the full suite at pre-push; and the §5 checklist at batch
end.

This is **not** ship-dark tiering (§4.12.4) — the feature is visible the moment it ships, so
the lighter single-round build tier does not apply.

---

## Inputs still open

1. **The 57-row name→slug review** — live at the review artifact. 124 map automatically, 57
   need a human eye, 111 have no usable drawing. This is the only genuinely manual step, and
   the spec does not depend on its *answers*, only on its existence.
2. **The 111 self-shot pairs.** The monogram covers them from day one and the pipeline takes
   them as a data change plus a `_exerciseLibraryVersion` bump — no code change. Shooting
   guidance: plain evenly-lit wall, stand a metre off it, high contrast, fitted clothing,
   side-on to match the drawings' convention, and **the phone must not move between the start
   and end shots** — the union crop depends on a shared frame.
