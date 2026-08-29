# Exercise Plates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping an exercise opens a plate — the movement drawn at its start and end (or one drawing for a hold), with the form cues underneath — for the 165 exercises that have artwork, and a monogram for the 126 that do not.

**Architecture:** A build-time Python script crops the upstream SVGs and writes them to `assets/exercise_plates/<slug>/{1,3}.svg`; a new `demo_slug` field on each library row names the slug; a pure Dart resolver turns an exercise name into asset paths plus a plate shape; three widgets render it. The app never crops, never fetches, and never touches the network.

**Tech Stack:** Flutter, `flutter_svg ^2.3.0` (already a dependency), Hive, Riverpod, Python 3 for the one-time asset pipeline.

**Spec:** `docs/plans/exercise-plates-spec.md` — read it first. This plan argues from it.

## Global Constraints

- **Branch `exercise-plates`, worktree `.claude/worktrees/exercise-plates`.** Never commit from the primary worktree (§4.13). Commit via `sh scripts/safe_commit.sh "<message>"` — one positional argument, no flags. Never `git commit`.
- **Blast radius `platform`**, driven by `pubspec.yaml` (`docs/blast_radius.yaml:324`). Requires `docs/plan-reviews/exercise-plates.md` with `review_rounds: >= 2`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted` (§4.12.3), and a self-initiated `/code-review` before the `--no-ff` merge (§4.3).
- **Wardroom palette only.** Campaign Gold `AppColors.accent` = `#D4B270`; card `AppColors.cardHi` = `#0A1828`; border `AppColors.border` = `#1A2C40`; dim `AppColors.textDim`; mute `AppColors.textMute`. Dark theme only (rule 12).
- **DM Sans everywhere** via `AppTypography` (rule 10). Never a raw `TextStyle(fontFamily:)`.
- **FREE tier.** No `subscription.gate()` call anywhere in this feature.
- **Import paths:** `package:` for `shared/` and `core/`, relative within a feature (rule 15).
- **Never resolve library data in `build()`.** The Active Workout card rebuilds ~1×/sec off the workout timer; resolve in `initState` / `didUpdateWidget` exactly as `coaching_content_panel.dart:40-58` does.
- **`ExerciseData` carries no id** — every lookup is by EXACT name via `ExerciseRepository.instance.getByExactName(name)`. Never `search()`, which is substring: "Push Up" would resolve to "Pike Push Up".
- **No deferrals** (§4.2). Every task ends in a terminal state.

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/build_exercise_plates.py` | **Create.** One-time asset pipeline: read `demo_slug`, compute each pair's union ink bbox from the SVG path data, rewrite `viewBox`, emit cropped SVGs. Dev tool, never shipped. |
| `docs/plans/exercise-plates-manifest.json` | **Create.** The upstream 302-entry manifest, committed as the provenance record and as the check that the vendored source still matches what the mapping was adjudicated against. |
| `.gitignore` | **Modify.** Ignore `/vendor/` — the cloned upstream catalogue. Only the cropped output ships. |
| `assets/exercise_plates/<slug>/{1,3}.svg` | **Create (generated).** 293 files. Committed. |
| `pubspec.yaml` | **Modify.** One asset directory entry. This line is what makes the batch `platform`. |
| `assets/data/exercise_library.json` | **Modify.** Add `demo_slug`; remove `image_start_url`, `image_end_url`, `gif_url`. |
| `lib/core/services/seed_service.dart:95` | **Modify.** `_exerciseLibraryVersion` 10 → 11. |
| `lib/core/services/swap_service.dart:294-295` | **Modify.** Delete the dead image-URL copy-through. |
| `lib/shared/widgets/exercise_plate/plate_resolver.dart` | **Create.** Pure. Name → slug, asset paths, plate shape. No Flutter imports. |
| `lib/shared/widgets/exercise_plate/exercise_monogram.dart` | **Create.** The no-artwork fallback. |
| `lib/shared/widgets/exercise_plate/exercise_plate_thumb.dart` | **Create.** The 44 px tappable badge replacement. |
| `lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart` | **Create.** The bottom sheet: plates + cues. |
| `lib/features/train/screens/active_workout/exercise_card.dart` (badge at `:447`) | **Modify.** Badge → thumb. |
| `lib/features/train/widgets/expandable_day_card.dart` (badge at `:236`) | **Modify.** Badge → thumb. |
| `lib/features/home/widgets/day_detail_sheet.dart` (badge at `:256`) | **Modify.** Badge → thumb. |
| `lib/features/train/screens/active_workout/coaching_content_panel.dart` | **Modify.** The FORM & CUES bar becomes the second door. |
| `docs/sot_registry.yaml` | **Modify.** One concept with a real `behavioral_test_path`. |

New widgets live in `lib/shared/` — not in `train/` — because three different features consume them.

---

### Task 1: Vendor the artwork, crop it, ship 293 SVGs

**Files:**
- Create: `scripts/build_exercise_plates.py`
- Create: `docs/plans/exercise-plates-manifest.json` (the upstream 302-entry manifest, committed as the provenance record)
- Create: `assets/exercise_plates/<slug>/{1,3}.svg` (generated, 293 files)
- Create: `assets/exercise_plates/ATTRIBUTION.md`
- Modify: `pubspec.yaml` (asset entries), `.gitignore` (the vendored source)
- Test: `test/contracts/exercise_plate_assets_present_test.dart`

**Interfaces:**
- Consumes: `demo_slug` from Task 2 — **do Task 2 first**, then return here.
- Produces: `assets/exercise_plates/<slug>/1.svg` and `3.svg`. Each is one `<path fill="currentColor">` inside `<svg viewBox="X Y W H">` with no `width`/`height`. A paired exercise's two frames share a byte-identical `viewBox`.

> **Two things about this task were wrong in the first draft and are corrected here.** The upstream
> catalogue is **not vendored anywhere in this repo** — a session-temp directory held 94 sample
> SVGs and nothing else, so "run the pipeline" had no source to run against. And the upstream
> ships **SVG only**: all 906 frames in the manifest are `"format": "svg"`, there is not one PNG,
> so the original plan's Pillow alpha-bbox could never have executed. Both are fixed below.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/exercise_plate_assets_present_test.dart
//
// Pins the three properties the runtime depends on and cannot check itself:
//   • every demo_slug in the library has both frames on disk;
//   • a PAIRED exercise's two frames share an identical viewBox, or the figure
//     visibly changes size between START and END (spec, "Asset treatment §3");
//   • every frame is tintable and unsized.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
      as List).cast<Map<String, dynamic>>();
  final slugs = lib
      .map((e) => e['demo_slug'])
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .toSet();

  test('every demo_slug has both frames on disk', () {
    expect(slugs, isNotEmpty, reason: 'library carries no demo_slug at all');
    final missing = <String>[];
    for (final s in slugs) {
      for (final f in const ['1', '3']) {
        if (!File('assets/exercise_plates/$s/$f.svg').existsSync()) {
          missing.add('$s/$f.svg');
        }
      }
    }
    expect(missing, isEmpty, reason: 'missing plate assets: $missing');
  });

  test('paired frames share one viewBox', () {
    final vb = RegExp(r'viewBox="([^"]+)"');
    final drift = <String>[];
    for (final s in slugs) {
      final a = File('assets/exercise_plates/$s/1.svg').readAsStringSync();
      final b = File('assets/exercise_plates/$s/3.svg').readAsStringSync();
      final va = vb.firstMatch(a)?.group(1);
      final vbb = vb.firstMatch(b)?.group(1);
      expect(va, isNotNull, reason: '$s/1.svg has no viewBox');
      expect(vbb, isNotNull, reason: '$s/3.svg has no viewBox');
      if (va != vbb) drift.add('$s ($va vs $vbb)');
    }
    expect(drift, isEmpty, reason: 'frames would jump size: $drift');
  });

  test('every frame is currentColor and carries no fixed size', () {
    for (final s in slugs) {
      for (final f in const ['1', '3']) {
        final t = File('assets/exercise_plates/$s/$f.svg').readAsStringSync();
        expect(t.contains('fill="currentColor"'), isTrue,
            reason: '$s/$f.svg is not tintable');
        expect(RegExp(r'<svg[^>]*\swidth=').hasMatch(t), isFalse,
            reason: '$s/$f.svg pins a width and will not scale');
      }
    }
  });

  test('every generated slug is one the committed manifest actually contains', () {
    final man = (jsonDecode(
            File('docs/plans/exercise-plates-manifest.json').readAsStringSync())
        as List).cast<Map<String, dynamic>>();
    final upstream = man.map((e) => e['slug'] as String).toSet();
    final invented = slugs.difference(upstream);
    expect(invented, isEmpty,
        reason: 'demo_slug values with no upstream drawing: $invented');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_assets_present_test.dart`
Expected: FAIL — `library carries no demo_slug at all`.

- [ ] **Step 3: Vendor the upstream catalogue**

The artwork is [workout-guide](https://github.com/bryllim/workout-guide) by Bryl Lim, CC BY-SA 4.0,
vector-traced from [Everkinetic](https://github.com/everkinetic/data). **302 exercises × 3 frames =
906 SVGs**, laid out as `assets/<slug>/frame-{1,2,3}.svg`, with `manifest.json` beside them.

```bash
mkdir -p vendor
git clone --depth 1 https://github.com/bryllim/workout-guide vendor/workout-guide
git -C vendor/workout-guide rev-parse HEAD    # RECORD this sha in ATTRIBUTION.md
```

Add to `.gitignore`:

```
# Upstream plate artwork — cloned by scripts/build_exercise_plates.py, not committed.
# Only the CROPPED output under assets/exercise_plates/ ships.
/vendor/
```

Then find the manifest and the assets root, and **verify the vendored copy is the one the mapping
was adjudicated against** — this is the whole reason the manifest is committed:

```bash
find vendor/workout-guide -name manifest.json
# copy it to the provenance path, then confirm nothing moved upstream:
cp <found-path> docs/plans/exercise-plates-manifest.json
python -c "
import json,io
m=json.load(io.open('docs/plans/exercise-plates-manifest.json',encoding='utf-8'))
print('entries:', len(m))
print('frames :', sum(len(e['frames']) for e in m))
print('formats:', {f['format'] for e in m for f in e['frames']})
"
```

Expected: `entries: 302`, `frames: 906`, `formats: {'svg'}`.

> **If the counts differ, STOP.** The mapping in Task 2 was adjudicated against a 302-entry
> catalogue; a different upstream means some `demo_slug` values may name drawings that no longer
> exist, and Step 1's fourth test is what will catch it. Reconcile before generating anything.

- [ ] **Step 4: Write the pipeline**

```python
# scripts/build_exercise_plates.py
"""Crop the vendored workout-guide SVGs into app plate assets.

Run once after vendoring; the OUTPUT is committed, the vendored source is not.
Reads demo_slug from the exercise library and emits
assets/exercise_plates/<slug>/{1,3}.svg.

WHY the bbox is computed from the PATH DATA and not from a raster: the upstream
ships SVG only -- all 906 frames in the manifest are format "svg", there is no
PNG to read an alpha bbox from, and no rasterizer is installed here. Parsing the
path is also the better answer: pure stdlib, no native Cairo dependency, and it
reproduces in CI.

WHY the CONTROL POINTS are enough: a bezier segment lies inside the convex hull
of its control points, so the bbox over on-curve AND control points is a
SUPERSET of the true ink bbox. It can be marginally loose; it can never crop
into the drawing. Measured against the rasters used for the founder review
(2026-08-29): bench-press frame 1 gave 389x445 against the raster's 390x444, and
frame 3 gave 430x397 against 431x397 -- agreement within ~1 unit on a 512
canvas, and the same figures the spec argues the union crop from.

WHY the crop is the UNION of both frames: cropping each frame to its own bounds
makes the body visibly change size between START and END. Bench Press start is
390x444 and end is 431x397 (spec, "Asset treatment 3").

WHAT THE CROP BUYS: run over 25 real pairs (2026-08-29), the cropped viewBox is
a median 59% of the 512 canvas area (min 32%, max 92%), so the figure renders
about 1.3x larger in the same display box -- which is the entire fix for the
"looks blurry at plate size" complaint, achieved without touching a path.

WHY no stroke is added: at matched display size a stroke closes the interior
gaps -- median gap 17 -> 13 units at width 4, 6% of gaps closed outright. The
crop is the whole fix.
"""
import json, io, os, re, sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "vendor/workout-guide/assets"
OUT = "assets/exercise_plates"
PAD = 10          # user units of breathing room around the ink
CANVAS = 512      # the upstream artboard

NUM = re.compile(r"[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?")
CMD = re.compile(r"([MmZzLlHhVvCcSsQqTtAa])")


def path_points(d):
    """Every on-curve point plus every control point of one `d` attribute."""
    toks = [t for t in CMD.split(d) if t.strip()]
    pts = []
    cx = cy = sx = sy = 0.0
    cmd = None
    i = 0
    while i < len(toks):
        t = toks[i]
        if CMD.fullmatch(t):
            cmd = t
            i += 1
            if cmd in "Zz":
                cx, cy = sx, sy
            continue
        nums = [float(x) for x in NUM.findall(t)]
        j = 0
        c = cmd
        while j < len(nums):
            rel = c.islower()
            C = c.upper()
            if C == "M":
                x, y = nums[j:j + 2]; j += 2
                cx, cy = (cx + x, cy + y) if rel else (x, y)
                sx, sy = cx, cy
                pts.append((cx, cy))
                c = "l" if rel else "L"          # implicit lineto after moveto
            elif C == "L":
                x, y = nums[j:j + 2]; j += 2
                cx, cy = (cx + x, cy + y) if rel else (x, y)
                pts.append((cx, cy))
            elif C == "H":
                x = nums[j]; j += 1
                cx = cx + x if rel else x
                pts.append((cx, cy))
            elif C == "V":
                y = nums[j]; j += 1
                cy = cy + y if rel else y
                pts.append((cx, cy))
            elif C == "C":
                a = nums[j:j + 6]; j += 6
                p = [(cx + a[k], cy + a[k + 1]) if rel else (a[k], a[k + 1])
                     for k in (0, 2, 4)]
                pts.extend(p); cx, cy = p[-1]
            elif C in ("S", "Q"):
                a = nums[j:j + 4]; j += 4
                p = [(cx + a[k], cy + a[k + 1]) if rel else (a[k], a[k + 1])
                     for k in (0, 2)]
                pts.extend(p); cx, cy = p[-1]
            elif C == "T":
                a = nums[j:j + 2]; j += 2
                cx, cy = (cx + a[0], cy + a[1]) if rel else (a[0], a[1])
                pts.append((cx, cy))
            elif C == "A":
                a = nums[j:j + 7]; j += 7
                cx, cy = (cx + a[5], cy + a[6]) if rel else (a[5], a[6])
                pts.append((cx, cy))
            else:
                j = len(nums)
        i += 1
    return pts


def ink_bbox(svg_path):
    t = io.open(svg_path, encoding="utf-8").read()
    pts = []
    for d in re.findall(r'\sd="([^"]+)"', t):
        pts += path_points(d)
    if not pts:
        raise ValueError("no path data: %s" % svg_path)
    xs = [q[0] for q in pts]
    ys = [q[1] for q in pts]
    return min(xs), min(ys), max(xs), max(ys)


def union(boxes):
    x0 = max(0, min(b[0] for b in boxes) - PAD)
    y0 = max(0, min(b[1] for b in boxes) - PAD)
    x1 = min(CANVAS, max(b[2] for b in boxes) + PAD)
    y1 = min(CANVAS, max(b[3] for b in boxes) + PAD)
    return round(x0), round(y0), round(x1 - x0), round(y1 - y0)


def crop_svg(text, view_box):
    t = re.sub(r"<\?xml[^>]*\?>", "", text)
    t = re.sub(r'\swidth="\d+"', "", t, count=1)
    t = re.sub(r'\sheight="\d+"', "", t, count=1)
    t, n = re.subn(r'viewBox="[^"]*"', 'viewBox="%d %d %d %d"' % view_box,
                   t, count=1)
    if n != 1:
        raise ValueError("no viewBox to rewrite")
    for lit in ('fill="#fff"', 'fill="#FFF"', 'fill="#ffffff"', 'fill="#FFFFFF"'):
        t = t.replace(lit, 'fill="currentColor"')
    if 'fill="currentColor"' not in t:
        raise ValueError("no white fill found to convert")
    return t.strip()


def main():
    lib = json.load(io.open("assets/data/exercise_library.json", encoding="utf-8"))
    slugs = sorted({e["demo_slug"] for e in lib if e.get("demo_slug")})
    if not slugs:
        raise SystemExit("no demo_slug in the library -- run Task 2 first")
    written = 0
    for slug in slugs:
        srcs = [os.path.join(SRC, slug, "frame-%s.svg" % f) for f in ("1", "3")]
        for f in srcs:
            if not os.path.exists(f):
                raise SystemExit("missing upstream frame: %s" % f)
        vb = union([ink_bbox(f) for f in srcs])
        os.makedirs(os.path.join(OUT, slug), exist_ok=True)
        for src, name in zip(srcs, ("1", "3")):
            text = io.open(src, encoding="utf-8").read()
            io.open(os.path.join(OUT, slug, "%s.svg" % name), "w",
                    encoding="utf-8").write(crop_svg(text, vb))
            written += 1
    print("wrote %d files for %d slugs" % (written, len(slugs)))


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Generate, then declare the assets**

Run: `python scripts/build_exercise_plates.py`
Expected: `wrote 293 files for 165 slugs`. A missing upstream frame is a hard stop, not a skip —
a silently-skipped slug would ship a `demo_slug` pointing at nothing.

Flutter does **not** recurse into subdirectories, so each `<slug>/` needs its own `pubspec.yaml`
line. Generate them and paste the block under the existing `assets:` key:

```bash
python -c "
import json, io
lib = json.load(io.open('assets/data/exercise_library.json', encoding='utf-8'))
slugs = sorted({e['demo_slug'] for e in lib if e.get('demo_slug')})
print('\n'.join('    - assets/exercise_plates/%s/' % s for s in slugs))
"
```

Create `assets/exercise_plates/ATTRIBUTION.md`, filling in the sha recorded in Step 3:

```markdown
# Exercise plate artwork

Derived from [workout-guide](https://github.com/bryllim/workout-guide) by Bryl Lim
(commit `<sha from Step 3>`), itself vector-traced from
[Everkinetic](https://github.com/everkinetic/data).

Both are licensed **CC BY-SA 4.0** — https://creativecommons.org/licenses/by-sa/4.0/

**Changes made:** each `viewBox` was cropped to the union of the two frames' ink
bounds, and the fill was changed from `#fff` to `currentColor` so the app can tint
it. No path data was altered.

These adapted files are redistributed under the same licence. The per-frame
creator and Everkinetic source for every drawing is preserved in
`docs/plans/exercise-plates-manifest.json`.
```

- [ ] **Step 6: Run the test**

Run: `flutter test test/contracts/exercise_plate_assets_present_test.dart`
Expected: all 4 PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/build_exercise_plates.py assets/exercise_plates pubspec.yaml .gitignore docs/plans/exercise-plates-manifest.json test/contracts/exercise_plate_assets_present_test.dart
sh scripts/safe_commit.sh "feat(plates): vendor the artwork and ship 293 cropped plate SVGs

Crops each frame to the UNION of frame 1 and frame 3 ink bounds so the figure
cannot change size between START and END, and converts the white fill to
currentColor so the app tints at render time. No stroke is added: at matched
display size a stroke closes the interior gaps (median 17 -> 13 units at width
4, 6% closed outright) and the crop is the whole fix.

The bbox comes from the SVG path data, not a raster. Upstream ships SVG only --
all 906 frames are format 'svg' -- so there is no alpha channel to measure and
no rasterizer installed. A bezier lies inside the hull of its control points, so
the bbox over on-curve plus control points is a superset of the ink bbox: it can
be marginally loose, never tight enough to clip. Checked against the rasters
used for the founder review: 389x445 vs 390x444, and 430x397 vs 431x397.

The upstream catalogue is cloned into gitignored vendor/ and only the cropped
output ships. Its manifest is committed so the mapping's provenance stays
checkable and a moved upstream fails a test instead of silently generating
against different drawings.

Artwork CC BY-SA 4.0 from workout-guide via Everkinetic; changes recorded in
assets/exercise_plates/ATTRIBUTION.md and the adapted set redistributed under
the same licence."
```

### Task 2: `demo_slug` on the library, and the version bump that delivers it

**Files:**
- Modify: `assets/data/exercise_library.json` (add `demo_slug` to 165 rows)
- Modify: `lib/core/services/seed_service.dart:95`
- Test: `test/contracts/demo_slug_reaches_existing_users_test.dart`

**Interfaces:**
- Consumes: nothing. **This task runs BEFORE Task 1** — the pipeline reads `demo_slug` to know which drawings to crop.
- Produces: `demo_slug` — a nullable `String` on every library row. Absent or `null` means no artwork.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/demo_slug_reaches_existing_users_test.dart
//
// The version constant is the ONLY thing that delivers a new library field to
// an install that already seeded. seed_service.dart:128 re-seeds iff
// stored < constant, so shipping a new field WITHOUT bumping it is a silent
// no-op: no existing user ever receives demo_slug and nothing fails loudly.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the seed version was bumped past the last shipped value', () {
    final src = File('lib/core/services/seed_service.dart').readAsStringSync();
    final m = RegExp(r'_exerciseLibraryVersion\s*=\s*(\d+)').firstMatch(src);
    expect(m, isNotNull, reason: 'version constant not found');
    final v = int.parse(m!.group(1)!);
    expect(v, greaterThanOrEqualTo(11),
        reason: 'v10 shipped with the OI-89 re-seed; demo_slug needs 11 or higher');
  });

  test('demo_slug is present, non-empty, and on the expected number of rows', () {
    final lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
        as List).cast<Map<String, dynamic>>();
    final withSlug = lib.where((e) {
      final s = e['demo_slug'];
      return s is String && s.isNotEmpty;
    }).toList();
    expect(withSlug.length, 165,
        reason: 'the agreed shipping set is 165 exercises with artwork');
    for (final e in withSlug) {
      expect(e['demo_slug'], isNot(contains('/')),
          reason: '${e['name']}: demo_slug is a slug, not a path');
    }
  });

  test('no row carries an empty-string demo_slug', () {
    final lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
        as List).cast<Map<String, dynamic>>();
    final blanks = lib.where((e) => e['demo_slug'] == '').map((e) => e['name']).toList();
    expect(blanks, isEmpty,
        reason: 'use null or omit the key; "" reads as present-but-broken');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/demo_slug_reaches_existing_users_test.dart`
Expected: FAIL on all three — version is 10, no `demo_slug` anywhere.

- [ ] **Step 3: Apply the mapping**

The agreed mapping is `docs/plans/exercise-plates-mapping.json` (commit it in this task — it is the output of the adjudication and the record of what was decided). Apply it:

```python
# run from the worktree root
import json, io
lib = json.load(io.open("assets/data/exercise_library.json", encoding="utf-8"))
mapping = json.load(io.open("docs/plans/exercise-plates-mapping.json", encoding="utf-8"))
by_id = {m["id"]: m.get("slug") for m in mapping}
n = 0
for e in lib:
    slug = by_id.get(e["id"])
    if slug:
        e["demo_slug"] = slug
        n += 1
json.dump(lib, io.open("assets/data/exercise_library.json", "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
print("demo_slug set on %d rows" % n)
```

Expected: `demo_slug set on 165 rows`.

- [ ] **Step 4: Bump the version**

In `lib/core/services/seed_service.dart`, immediately above line 95, add a comment line in the existing style and change the constant:

```dart
  // v11 (exercise plates): demo_slug added to 165 rows; the three dead image
  // URL fields removed. Re-seed rewrites every row in place via putAll.
  static const int _exerciseLibraryVersion = 11;
```

- [ ] **Step 5: Run the test**

Run: `flutter test test/contracts/demo_slug_reaches_existing_users_test.dart`
Expected: all 3 PASS.

- [ ] **Step 6: Commit**

```bash
git add assets/data/exercise_library.json lib/core/services/seed_service.dart docs/plans/exercise-plates-mapping.json test/contracts/demo_slug_reaches_existing_users_test.dart
sh scripts/safe_commit.sh "feat(plates): demo_slug on 165 rows, seed version 10 -> 11

The version bump is what actually delivers the field: seed_service.dart:128
re-seeds only when stored < constant, so adding demo_slug without it would be a
silent no-op and no existing install would ever receive it.

The mapping itself is committed at docs/plans/exercise-plates-mapping.json as
the record of the adjudication."
```

---

### Task 3: Remove the dead image URL fields

**Files:**
- Modify: `assets/data/exercise_library.json` (drop three keys from every row)
- Modify: `lib/core/services/swap_service.dart:294-295`
- Test: `test/contracts/no_dead_image_url_fields_test.dart`

**Interfaces:**
- Consumes: Task 2's edited library.
- Produces: nothing. Removal only.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/no_dead_image_url_fields_test.dart
//
// image_start_url / image_end_url / gif_url are 100% dead — every populated URL
// 404s. Leaving them beside demo_slug ships two competing sets of image fields,
// which is the writer/reader drift shape this repo has hit repeatedly.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _dead = ['image_start_url', 'image_end_url', 'gif_url'];

void main() {
  test('the dead fields are gone from the library', () {
    final lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
        as List).cast<Map<String, dynamic>>();
    for (final f in _dead) {
      final hits = lib.where((e) => e.containsKey(f)).map((e) => e['name']).take(3).toList();
      expect(hits, isEmpty, reason: '$f still on rows: $hits');
    }
  });

  test('no Dart source reads them', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      // Strip comments first — a mention in prose is not a read.
      final src = f.readAsStringSync()
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          .replaceAll(RegExp(r'//.*'), '');
      for (final d in _dead) {
        if (src.contains(d)) offenders.add('${f.path} -> $d');
      }
    }
    expect(offenders, isEmpty, reason: 'still referenced: $offenders');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/no_dead_image_url_fields_test.dart`
Expected: FAIL — both tests; `swap_service.dart` still copies them.

- [ ] **Step 3: Strip the fields from the library**

```python
import json, io
lib = json.load(io.open("assets/data/exercise_library.json", encoding="utf-8"))
dead = ("image_start_url", "image_end_url", "gif_url")
n = 0
for e in lib:
    for d in dead:
        if d in e:
            del e[d]
            n += 1
json.dump(lib, io.open("assets/data/exercise_library.json", "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
print("removed %d dead keys" % n)
```

- [ ] **Step 4: Delete the copy-through**

In `lib/core/services/swap_service.dart`, delete lines 294-297 — the four lines that read:

```dart
      if (newLib['image_start_url'] != null)
        'image_start_url': newLib['image_start_url'],
      if (newLib['image_end_url'] != null)
        'image_end_url': newLib['image_end_url'],
```

Nothing replaces them. A swapped exercise picks up its plate the same way any other does — by name, through the resolver in Task 4.

- [ ] **Step 5: Run the tests**

Run: `flutter test test/contracts/no_dead_image_url_fields_test.dart test/contracts/demo_slug_reaches_existing_users_test.dart`
Expected: all 5 PASS. The second file is re-run because both tasks edit the same JSON.

- [ ] **Step 6: Commit**

```bash
git add assets/data/exercise_library.json lib/core/services/swap_service.dart test/contracts/no_dead_image_url_fields_test.dart
sh scripts/safe_commit.sh "refactor(plates): remove the three dead image URL fields

image_start_url, image_end_url and gif_url are 100% dead — every populated URL
404s, and the only reader was a copy-through in swap_service that nothing then
rendered. Leaving them beside demo_slug would ship two competing sets of image
fields, which is the writer/reader drift shape this repo has hit repeatedly.

A swapped exercise now resolves its plate by name like any other."
```

---

### Task 4: The plate resolver

**Files:**
- Create: `lib/shared/widgets/exercise_plate/plate_resolver.dart`
- Test: `test/contracts/exercise_plate_resolver_test.dart`

**Interfaces:**
- Consumes: `ExerciseRepository.instance.getByExactName(String)` returning `Map<String, dynamic>?`.
- Produces:
  - `class ExercisePlate { final String? slug; final List<String> assetPaths; final bool isPair; final String monogram; bool get hasArtwork; }`
  - `ExercisePlate resolvePlate(String exerciseName)` — the only entry point.
  - `String monogramFor(String name)` — exposed for the monogram widget.
  - `const kDynamicTimedSlugs` — the exception list.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/exercise_plate_resolver_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('plate_resolver');
    Hive.init(tempDir.path);
    await HiveService.instance.init();
    final lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
        as List).cast<Map<String, dynamic>>();
    await HiveService.instance.exerciseBox
        .putAll({for (final e in lib) e['id'] as String: e});
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      try { tempDir.deleteSync(recursive: true); } catch (_) {}
    }
  });

  test('a rep-based exercise resolves to a PAIR of asset paths', () {
    final p = resolvePlate('Barbell Bench Press');
    expect(p.hasArtwork, isTrue);
    expect(p.isPair, isTrue);
    expect(p.assetPaths.length, 2);
    expect(p.assetPaths[0], 'assets/exercise_plates/${p.slug}/1.svg');
    expect(p.assetPaths[1], 'assets/exercise_plates/${p.slug}/3.svg');
  });

  test('a timed hold resolves to ONE asset path', () {
    final p = resolvePlate('Wall Sit');
    expect(p.hasArtwork, isTrue);
    expect(p.isPair, isFalse);
    expect(p.assetPaths.length, 1);
    expect(p.assetPaths.single, endsWith('/1.svg'));
  });

  test('a dynamic-timed movement on the exception list resolves to a PAIR', () {
    final p = resolvePlate('Jump Rope');
    if (p.hasArtwork) {
      expect(p.isPair, isTrue,
          reason: 'jump rope genuinely has two positions; it is on the exception list');
    }
  });

  test('an exercise with no demo_slug has no artwork and a monogram instead', () {
    final p = resolvePlate('Surya Namaskar');
    expect(p.hasArtwork, isFalse);
    expect(p.assetPaths, isEmpty);
    expect(p.monogram, isNotEmpty);
  });

  test('an unknown name never throws and never claims artwork', () {
    final p = resolvePlate('Totally Invented Exercise');
    expect(p.hasArtwork, isFalse);
    expect(p.monogram, 'TIE');
  });

  test('lookup is EXACT, never substring', () {
    // ExerciseRepository.search is substring; getByExactName must not be.
    final push = resolvePlate('Push Up');
    final pike = resolvePlate('Pike Push Up');
    expect(push.slug, isNot(equals(pike.slug)),
        reason: 'Push Up must not resolve to Pike Push Up artwork');
  });

  group('monogramFor', () {
    test('takes the first letter of up to three significant words', () {
      expect(monogramFor('Barbell Bench Press'), 'BBP');
      expect(monogramFor('Push Up'), 'PU');
      expect(monogramFor('Squat'), 'S');
    });
    test('drops stop words and punctuation', () {
      expect(monogramFor("Captain's Chair Leg Raise"), 'CCL');
      expect(monogramFor('Dip (Parallel Bars)'), 'DPB');
    });
    test('never returns empty for a non-empty name', () {
      expect(monogramFor('   '), isNotEmpty);
      expect(monogramFor('123'), isNotEmpty);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_resolver_test.dart`
Expected: FAIL — `plate_resolver.dart` does not exist.

- [ ] **Step 3: Write the resolver**

```dart
// lib/shared/widgets/exercise_plate/plate_resolver.dart
//
// Name -> plate. Pure apart from the Hive read; NO Flutter imports, so it is
// unit-testable without a widget harness.
//
// Plate SHAPE is keyed on logging_type, the same field that already decides
// which inputs the Active Workout screen shows. Two images for a rep, one for a
// hold — because frame 3 of a hold is the entry or neutral position, not the end
// of a movement (spec, "Asset treatment §2"). For Wall Sit and Superman frame 3
// is literally the athlete standing still.
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

/// `timed` movements that genuinely DO have two distinct positions, and so take
/// a pair despite their logging type. Hand-curated and deliberately short —
/// this is a rendering decision, not exercise data, so it lives beside the rule
/// rather than in the library JSON.
const Set<String> kDynamicTimedSlugs = {
  'cat-cow-stretch',
  'flutter-kick',
  'bear-crawl',
  'crab-walk',
  'jump-rope',
  'mountain-climber',
};

const Set<String> _pairedLoggingTypes = {
  'weight_reps',
  'bodyweight_reps',
  'weighted_bodyweight',
};

const Set<String> _monogramStopWords = {'the', 'a', 'of', 'with', 'to', 'and'};

class ExercisePlate {
  final String? slug;
  final List<String> assetPaths;
  final bool isPair;
  final String monogram;

  const ExercisePlate({
    required this.slug,
    required this.assetPaths,
    required this.isPair,
    required this.monogram,
  });

  bool get hasArtwork => assetPaths.isNotEmpty;
}

/// Up to three initials from the significant words of [name]. Never empty.
///
/// It does NOT identify — a three-letter code collides for a third of the
/// library ('SC' is Skull Crusher, Suitcase Carry, Spider Curl and Sandbag
/// Clean). Its only job is to make an artwork-less slot look deliberate; the
/// exercise name is rendered beside it.
String monogramFor(String name) {
  final words = name
      .replaceAll(RegExp(r"[^A-Za-z0-9\s]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_monogramStopWords.contains(w.toLowerCase()))
      .toList();
  if (words.isEmpty) return '?';
  return words.take(3).map((w) => w[0].toUpperCase()).join();
}

ExercisePlate resolvePlate(String exerciseName) {
  final mono = monogramFor(exerciseName);
  // EXACT name, never search() — that is substring, and "Push Up" would
  // resolve to "Pike Push Up".
  final row = ExerciseRepository.instance.getByExactName(exerciseName);
  final slug = (row?['demo_slug'] as String?)?.trim();

  if (slug == null || slug.isEmpty) {
    return ExercisePlate(
        slug: null, assetPaths: const [], isPair: false, monogram: mono);
  }

  final loggingType = (row?['logging_type'] as String?) ?? '';
  final isPair = _pairedLoggingTypes.contains(loggingType) ||
      kDynamicTimedSlugs.contains(slug);

  final paths = isPair
      ? <String>[
          'assets/exercise_plates/$slug/1.svg',
          'assets/exercise_plates/$slug/3.svg',
        ]
      : <String>['assets/exercise_plates/$slug/1.svg'];

  return ExercisePlate(
      slug: slug, assetPaths: paths, isPair: isPair, monogram: mono);
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/contracts/exercise_plate_resolver_test.dart`
Expected: all 9 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/exercise_plate/plate_resolver.dart test/contracts/exercise_plate_resolver_test.dart
sh scripts/safe_commit.sh "feat(plates): the plate resolver — name to assets and shape

Plate shape keys on logging_type: two images for a rep, one for a hold, because
frame 3 of a hold is the entry or neutral position rather than the end of a
movement. For Wall Sit and Superman frame 3 is the athlete standing still.

A short hand-curated exception list covers the dynamic-timed movements that do
have two positions. It lives beside the rule, not in the library JSON, because
it is a rendering decision rather than exercise data.

Lookup is getByExactName, never search — search is substring and Push Up would
resolve to Pike Push Up."
```

---

### Task 5: The monogram

**Files:**
- Create: `lib/shared/widgets/exercise_plate/exercise_monogram.dart`
- Test: `test/contracts/exercise_plate_widgets_test.dart` (created here, extended in Tasks 6-7)

**Interfaces:**
- Consumes: `monogramFor(String)` from Task 4.
- Produces: `class ExerciseMonogram extends StatelessWidget { const ExerciseMonogram({super.key, required this.name, required this.size}); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/exercise_plate_widgets_test.dart
//
// Hive is opened for the whole FILE, not just the thumb group: ExercisePlateThumb
// resolves in initState, and resolvePlate -> getByExactName reads
// `_hive.exerciseBox.values`, which THROWS when no box is open. The monogram
// tests below are pure and would pass without this; the thumb tests would not.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_monogram.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_thumb.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('plate_widgets');
    Hive.init(tempDir.path);
    await HiveService.instance.init();
    final lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
        as List).cast<Map<String, dynamic>>();
    await HiveService.instance.exerciseBox
        .putAll({for (final e in lib) e['id'] as String: e});
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      try { tempDir.deleteSync(recursive: true); } catch (_) {}
    }
  });

  testWidgets('the monogram renders initials, never a broken image', (t) async {
    await t.pumpWidget(_host(
        const ExerciseMonogram(name: 'Barbell Bench Press', size: 44)));
    expect(find.text('BBP'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('the monogram honours its size', (t) async {
    await t.pumpWidget(_host(const ExerciseMonogram(name: 'Wall Sit', size: 44)));
    final box = t.widget<SizedBox>(find.byType(SizedBox).first);
    expect(box.width, 44);
    expect(box.height, 44);
  });

  testWidgets('an empty name still renders something', (t) async {
    await t.pumpWidget(_host(const ExerciseMonogram(name: '', size: 44)));
    expect(find.byType(ExerciseMonogram), findsOneWidget);
    expect(tester_hasText(t), isTrue);
  });
}

bool tester_hasText(WidgetTester t) =>
    t.widgetList<Text>(find.byType(Text)).any((w) => (w.data ?? '').isNotEmpty);
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_widgets_test.dart`
Expected: FAIL — `exercise_monogram.dart` does not exist.

> The file also imports `exercise_plate_thumb.dart`, which Task 6 creates. Until
> then this file will not compile at all. That is intentional — the two widgets
> share one test file — so run Task 5's three tests by temporarily commenting the
> thumb import and its three tests, or simply write Task 5 and Task 6 back to back
> and run the file once.

- [ ] **Step 3: Write the widget**

```dart
// lib/shared/widgets/exercise_plate/exercise_monogram.dart
//
// Shown wherever an exercise has no artwork. Three populations reach it: user
// custom exercises, community exercises synced from user_custom_exercises, and
// the library rows still awaiting a photograph.
//
// It reads as "a plate not yet issued" rather than as a failure. Rejected
// alternatives: falling back to the index number (a column mixing engravings and
// bare numerals reads as "some of these are missing"), a category glyph (nine
// glyphs to design, and a triangle beside an engraving is two visual languages),
// and an empty frame (reads as a loading state that never resolves).
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_resolver.dart';

class ExerciseMonogram extends StatelessWidget {
  final String name;
  final double size;

  const ExerciseMonogram({super.key, required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bgRaise,
          borderRadius: BorderRadius.circular(size * 0.22),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.28),
          ),
        ),
        child: Center(
          child: Text(
            monogramFor(name),
            style: AppTypography.monoXs.copyWith(
              color: AppColors.accent.withValues(alpha: 0.72),
              fontSize: size * 0.30,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/contracts/exercise_plate_widgets_test.dart`
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/exercise_plate/exercise_monogram.dart test/contracts/exercise_plate_widgets_test.dart
sh scripts/safe_commit.sh "feat(plates): the monogram for exercises with no artwork

Three populations reach it: custom exercises, community exercises synced from
user_custom_exercises, and the library rows awaiting a photograph.

It does not identify and is not meant to — a three-letter code collides for a
third of the library. Its job is to make the slot look deliberate; the exercise
name renders beside it."
```

---

### Task 6: The thumbnail

**Files:**
- Create: `lib/shared/widgets/exercise_plate/exercise_plate_thumb.dart`
- Modify: `test/contracts/exercise_plate_widgets_test.dart`

**Interfaces:**
- Consumes: `resolvePlate(String)` (Task 4), `ExerciseMonogram` (Task 5), `ExercisePlateSheet.show()` (Task 7 — wire the callback in Task 7, leave `onTap` a parameter here).
- Produces: `class ExercisePlateThumb extends StatefulWidget { const ExercisePlateThumb({super.key, required this.exerciseName, this.size = 44, this.onTap}); }`

- [ ] **Step 1: Write the failing test**

Append to `test/contracts/exercise_plate_widgets_test.dart`:

```dart
  testWidgets('the thumb falls back to the monogram when there is no artwork',
      (t) async {
    await t.pumpWidget(_host(const ExercisePlateThumb(
        exerciseName: 'Totally Invented Exercise', size: 44)));
    await t.pump();
    expect(find.byType(ExerciseMonogram), findsOneWidget);
  });

  testWidgets('the thumb exposes a 44 px minimum tap target', (t) async {
    var tapped = false;
    await t.pumpWidget(_host(ExercisePlateThumb(
        exerciseName: 'Totally Invented Exercise',
        size: 44,
        onTap: () => tapped = true)));
    await t.pump();
    final size = t.getSize(find.byType(ExercisePlateThumb));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    await t.tap(find.byType(ExercisePlateThumb));
    expect(tapped, isTrue);
  });

  testWidgets('the thumb re-resolves when the exercise name changes', (t) async {
    await t.pumpWidget(_host(const ExercisePlateThumb(
        exerciseName: 'First Exercise', size: 44)));
    await t.pump();
    expect(find.text('FE'), findsOneWidget);
    await t.pumpWidget(_host(const ExercisePlateThumb(
        exerciseName: 'Second Exercise', size: 44)));
    await t.pump();
    expect(find.text('SE'), findsOneWidget,
        reason: 'a swap reuses the State; didUpdateWidget must re-resolve');
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_widgets_test.dart`
Expected: FAIL — `exercise_plate_thumb.dart` does not exist.

- [ ] **Step 3: Write the widget**

```dart
// lib/shared/widgets/exercise_plate/exercise_plate_thumb.dart
//
// Replaces the numbered badge at the three sites that render one. The badge
// carried almost nothing — position in a vertical list is already obvious and
// the active card is marked in gold — so this costs ZERO new elements in a
// header row that is already at five (Hick's Law stays neutral).
//
// 44 px, not 38: that is also the minimum touch target, so one change fixes two
// things.
//
// WHY initState and not build(): the Active Workout card rebuilds ~1x/second off
// the workout timer. Resolving in build() would re-read Hive sixty times a
// minute. coaching_content_panel.dart:40-58 learned this first.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_monogram.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_resolver.dart';

class ExercisePlateThumb extends StatefulWidget {
  final String exerciseName;
  final double size;
  final VoidCallback? onTap;

  const ExercisePlateThumb({
    super.key,
    required this.exerciseName,
    this.size = 44,
    this.onTap,
  });

  @override
  State<ExercisePlateThumb> createState() => _ExercisePlateThumbState();
}

class _ExercisePlateThumbState extends State<ExercisePlateThumb> {
  late ExercisePlate _plate;

  @override
  void initState() {
    super.initState();
    _plate = resolvePlate(widget.exerciseName);
  }

  @override
  void didUpdateWidget(covariant ExercisePlateThumb old) {
    super.didUpdateWidget(old);
    // A swap reuses this State when the card is keyed by index rather than name.
    if (old.exerciseName != widget.exerciseName) {
      _plate = resolvePlate(widget.exerciseName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget face = _plate.hasArtwork
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.cardHi,
              borderRadius: BorderRadius.circular(widget.size * 0.22),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: EdgeInsets.all(widget.size * 0.06),
              child: SvgPicture.asset(
                _plate.assetPaths.first,
                colorFilter: const ColorFilter.mode(
                  AppColors.accent,
                  BlendMode.srcIn,
                ),
              ),
            ),
          )
        : ExerciseMonogram(name: widget.exerciseName, size: widget.size);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: face,
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/contracts/exercise_plate_widgets_test.dart`
Expected: 6 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/exercise_plate/exercise_plate_thumb.dart test/contracts/exercise_plate_widgets_test.dart
sh scripts/safe_commit.sh "feat(plates): the 44 px thumbnail that replaces the numbered badge

Zero new elements in a header row already at five, because the badge it
replaces carried almost nothing. 44 px rather than 38 is also the minimum touch
target, so one change fixes two things.

Resolves in initState and didUpdateWidget, never in build: the Active Workout
card rebuilds about once a second off the workout timer."
```

---

### Task 7: The plate sheet

**Files:**
- Create: `lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart`
- Modify: `test/contracts/exercise_plate_widgets_test.dart`
- Test: `test/contracts/exercise_plate_shape_behavioral_test.dart`

**Interfaces:**
- Consumes: `resolvePlate(String)`, `ExerciseMonogram`, `ExerciseRepository.getByExactName`.
- Produces: `static Future<void> ExercisePlateSheet.show(BuildContext, String exerciseName)`.

- [ ] **Step 1: Write the failing behavioural test**

```dart
// test/contracts/exercise_plate_shape_behavioral_test.dart
//
// The SHAPE rule, asserted through the rendered widget rather than through the
// resolver — a resolver unit test passes even if the sheet ignores isPair.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('plate_shape');
    Hive.init(tempDir.path);
    await HiveService.instance.init();
    final lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
        as List).cast<Map<String, dynamic>>();
    await HiveService.instance.exerciseBox
        .putAll({for (final e in lib) e['id'] as String: e});
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      try { tempDir.deleteSync(recursive: true); } catch (_) {}
    }
  });

  Future<void> open(WidgetTester t, String name) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => ExercisePlateSheet.show(ctx, name),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('a rep-based exercise shows TWO plates labelled START and END',
      (t) async {
    await open(t, 'Barbell Bench Press');
    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(find.text('START'), findsOneWidget);
    expect(find.text('END'), findsOneWidget);
  });

  testWidgets('a timed hold shows ONE plate and never says END', (t) async {
    await open(t, 'Wall Sit');
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('END'), findsNothing);
    expect(find.text('HOLD THIS POSITION'), findsOneWidget);
  });

  testWidgets('an exercise with no artwork shows the monogram, not a broken box',
      (t) async {
    await open(t, 'Surya Namaskar');
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.textContaining('SN'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_shape_behavioral_test.dart`
Expected: FAIL — `exercise_plate_sheet.dart` does not exist.

- [ ] **Step 3: Write the sheet**

```dart
// lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart
//
// The plate. Two images for a rep, one for a hold — see plate_resolver.dart for
// why. Free to every tier, matching the FORM & CUES panel it sits beside.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_monogram.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_resolver.dart';

class ExercisePlateSheet extends StatelessWidget {
  final String exerciseName;

  const ExercisePlateSheet({super.key, required this.exerciseName});

  static Future<void> show(BuildContext context, String exerciseName) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => ExercisePlateSheet(exerciseName: exerciseName),
    );
  }

  /// Cues arrive in three shapes across the 292 library rows, counted
  /// 2026-08-29: a single string packed with semicolons (84), a real array
  /// (100), or one plain cue (108). Splitting on ';' renders all three as lines.
  List<String> _cues(Map<String, dynamic>? row) {
    final raw = row?['coaching_cues'];
    if (raw is! List) return const [];
    return raw
        .expand((c) => c.toString().split(';'))
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList(growable: false);
  }

  /// Returns an UNSIZED column — each branch below wraps it, because the pair
  /// and the single hold want different widths.
  Widget _plateBox(String assetPath, String caption) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.cardHi,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: SvgPicture.asset(
                assetPath,
                colorFilter: const ColorFilter.mode(
                  AppColors.accent,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          caption,
          style: AppTypography.monoXs.copyWith(
            color: AppColors.accent,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final plate = resolvePlate(exerciseName);
    final row = ExerciseRepository.instance.getByExactName(exerciseName);
    final cues = _cues(row);
    final breathing = (row?['breathing_cue'] as String?)?.trim();
    // 136 of the library rows carry a bare number here — a spreadsheet column
    // shift that put met_value into breathing_cue. Suppress those rather than
    // print "BREATHING / 5". The data repair is its own OI.
    final showBreathing = breathing != null &&
        breathing.isNotEmpty &&
        !RegExp(r'^\d+(\.\d+)?$').hasMatch(breathing);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              exerciseName.toUpperCase(),
              style: AppTypography.mono.copyWith(
                color: AppColors.textPrimary,
                letterSpacing: 2.2,
              ),
            ),
            const SizedBox(height: 14),
            if (plate.hasArtwork)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: plate.isPair
                    ? [
                        Expanded(child: _plateBox(plate.assetPaths[0], 'START')),
                        const SizedBox(width: 8),
                        Expanded(child: _plateBox(plate.assetPaths[1], 'END')),
                      ]
                    // A single hold gets half the width (1:2:1), not the third
                    // it would get by reusing the pair's sizing.
                    : [
                        const Spacer(),
                        Expanded(
                          flex: 2,
                          child: _plateBox(
                              plate.assetPaths.single, 'HOLD THIS POSITION'),
                        ),
                        const Spacer(),
                      ],
              )
            else
              Center(
                child: Column(
                  children: [
                    ExerciseMonogram(name: exerciseName, size: 96),
                    const SizedBox(height: 8),
                    Text(
                      'NO DRAWING YET',
                      style: AppTypography.monoXs
                          .copyWith(color: AppColors.textMute, letterSpacing: 2),
                    ),
                  ],
                ),
              ),
            if (cues.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('FORM',
                  style: AppTypography.monoXs.copyWith(
                      color: AppColors.textMute, letterSpacing: 2)),
              const SizedBox(height: 6),
              ...cues.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('–  ',
                            style: AppTypography.bodySm
                                .copyWith(color: AppColors.accent)),
                        Expanded(
                          child: Text(c,
                              style: AppTypography.bodySm
                                  .copyWith(color: AppColors.textPrimary)),
                        ),
                      ],
                    ),
                  )),
            ],
            if (showBreathing) ...[
              const SizedBox(height: 14),
              Text('BREATHING',
                  style: AppTypography.monoXs.copyWith(
                      color: AppColors.textMute, letterSpacing: 2)),
              const SizedBox(height: 4),
              Text(breathing,
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.textPrimary)),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/contracts/exercise_plate_shape_behavioral_test.dart`
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart test/contracts/exercise_plate_shape_behavioral_test.dart
sh scripts/safe_commit.sh "feat(plates): the plate sheet — diptych for reps, single plate for holds

The shape rule is asserted through the rendered widget, not just the resolver:
a resolver unit test passes even if the sheet ignores isPair.

Cues arrive in three shapes across the library — packed with semicolons on 84
rows, a real array on 100, a single cue on 108 — so they are split on ';'.

A numeric breathing_cue is suppressed rather than printed. 136 rows carry a
bare number there from a spreadsheet column shift that put met_value into the
field; the data repair is its own OI, but the plate must not render 'BREATHING
/ 5' in the meantime."
```

---

### Task 8: Wire the three badge sites

**Files:**
- Modify: `lib/features/train/screens/active_workout/exercise_card.dart:437-460`
- Modify: `lib/features/train/widgets/expandable_day_card.dart:226-245`
- Modify: `lib/features/home/widgets/day_detail_sheet.dart:246-263`
- Modify: `lib/features/train/screens/active_workout/screen.dart` (one import)
- Test: `test/contracts/exercise_plate_badge_sites_test.dart`

**Interfaces:**
- Consumes: `ExercisePlateThumb`, `ExercisePlateSheet.show`.
- Produces: nothing.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/exercise_plate_badge_sites_test.dart
//
// A source-grep contract. It cannot prove the widget renders — the behavioural
// tests do that — but it CAN prove no site silently reverts to the numeric
// badge, which is the regression a widget test on one screen would miss.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _sites = [
  'lib/features/train/screens/active_workout/exercise_card.dart',
  'lib/features/train/widgets/expandable_day_card.dart',
  'lib/features/home/widgets/day_detail_sheet.dart',
];

String _stripComments(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//.*'), '');

void main() {
  test('all three badge sites render the plate thumb', () {
    for (final p in _sites) {
      final src = _stripComments(File(p).readAsStringSync());
      expect(src.contains('ExercisePlateThumb'), isTrue,
          reason: '$p no longer renders the plate thumb');
    }
  });

  test('no site still renders a bare index badge', () {
    for (final p in _sites) {
      final src = _stripComments(File(p).readAsStringSync());
      final hasBadge = RegExp(r"\$\{\s*(widget\.)?(exerciseIndex|index)\s*\+\s*1\s*\}")
          .hasMatch(src);
      expect(hasBadge, isFalse,
          reason: '$p still renders the numeric badge the thumb replaced');
    }
  });

  test('each site opens the plate sheet', () {
    for (final p in _sites) {
      final src = _stripComments(File(p).readAsStringSync());
      expect(src.contains('ExercisePlateSheet.show'), isTrue,
          reason: '$p renders a thumb that does not open anything');
    }
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_badge_sites_test.dart`
Expected: FAIL on all three.

- [ ] **Step 3: Replace the badge in the Active Workout card**

In `exercise_card.dart`, find the number-badge `Container` — its `Text` is at **line 447**, `'${widget.exerciseIndex + 1}'` (verified 2026-08-29; grep for it rather than trusting the line). Replace that whole `Container(...)` with:

```dart
                              ExercisePlateThumb(
                                exerciseName: widget.exercise.name,
                                size: 44,
                                onTap: () => ExercisePlateSheet.show(
                                    context, widget.exercise.name),
                              ),
```

`exercise_card.dart` is `part of 'screen.dart'`, so add the imports to **`screen.dart`** instead, beside the other `package:` imports:

```dart
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_sheet.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_thumb.dart';
```

Keep the `const SizedBox(width: 10)` that follows it.

> The exercise NAME is not available as a tap target: `exercise_card.dart:429-433` wraps the whole header row in a `GestureDetector` whose `onTap` is `widget.onFocus` (expand/collapse, Bug #15b) and whose `onLongPress` is `widget.onLongPressHeader` (superset grouping). Both are load-bearing. The thumb's own `GestureDetector` sits inside that row and wins the hit test for its own 44 px.

- [ ] **Step 4: Replace the badge in the Train day card**

In `expandable_day_card.dart`, the badge `Text` is at **line 236**, `'${index + 1}'`. Replace its enclosing `Container` with the same widget, using that file's local variables:

```dart
              ExercisePlateThumb(
                exerciseName: name,
                size: 44,
                onTap: () => ExercisePlateSheet.show(context, name),
              ),
```

Add both `package:` imports at the top of the file. If the local variable holding the exercise name is not called `name`, use whatever that scope calls it — do not introduce a new one.

- [ ] **Step 5: Replace the badge in the Home day-detail sheet**

In `day_detail_sheet.dart`, the badge `Text` is at **line 256**, `'${index + 1}'`. Replace its enclosing `Container` the same way, and add both imports.

- [ ] **Step 6: Run the tests and analyze**

Run: `flutter test test/contracts/exercise_plate_badge_sites_test.dart`
Expected: 3 PASS.

Run: `flutter analyze lib/features/train/screens/active_workout/ lib/features/train/widgets/expandable_day_card.dart lib/features/home/widgets/day_detail_sheet.dart lib/shared/widgets/exercise_plate/`
Expected: **zero warnings**. `--no-fatal-infos` suppresses infos, not warnings, and one warning fails the push (§0).

- [ ] **Step 7: Commit**

```bash
git add lib/features/train/screens/active_workout/ lib/features/train/widgets/expandable_day_card.dart lib/features/home/widgets/day_detail_sheet.dart test/contracts/exercise_plate_badge_sites_test.dart
sh scripts/safe_commit.sh "feat(plates): the numbered badge becomes the plate at all three sites

Tapping the exercise NAME was unavailable — exercise_card.dart:429-433 already
owns both the tap (expand/collapse, Bug #15b) and the long-press (superset
grouping). The thumb's own gesture detector sits inside that row.

The source-grep contract pins all three sites together: a widget test on one
screen would not notice another silently reverting to the numeric badge."
```

---

### Task 9: The second door, and the SoT registry

**Files:**
- Modify: `lib/features/train/screens/active_workout/coaching_content_panel.dart`
- Modify: `docs/sot_registry.yaml`
- Test: `test/contracts/exercise_plate_badge_sites_test.dart` (extend)

**Interfaces:**
- Consumes: `ExercisePlateSheet.show`, `resolvePlate`.
- Produces: nothing.

- [ ] **Step 1: Write the failing test**

Append to `test/contracts/exercise_plate_badge_sites_test.dart`:

```dart
  test('the FORM & CUES bar offers the plate as a second door', () {
    final src = _stripComments(File(
            'lib/features/train/screens/active_workout/coaching_content_panel.dart')
        .readAsStringSync());
    expect(src.contains('ExercisePlateSheet.show'), isTrue,
        reason: 'the expanded card has no route to the plate');
  });

  test('the SoT registry carries the plate read path with a behavioural test', () {
    final y = File('docs/sot_registry.yaml').readAsStringSync();
    expect(y.contains('concept: exercise_plate_read_path'), isTrue,
        reason: 'the new writer/reader contract is unregistered');
    final i = y.indexOf('concept: exercise_plate_read_path');
    final window = y.substring(i, (i + 600).clamp(0, y.length));
    expect(window.contains('behavioral_test_path:'), isTrue,
        reason: 'rule 21 is strict — a bare registry entry blocks the commit');
    expect(window.contains('exercise_plate_shape_behavioral_test.dart'), isTrue);
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_badge_sites_test.dart`
Expected: FAIL on the two new tests.

- [ ] **Step 3: Add the second door**

In `coaching_content_panel.dart`, in the collapsed header row that renders the `FORM & CUES` label, wrap that row in a `GestureDetector` that opens the sheet, and append a trailing affordance:

```dart
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ExercisePlateSheet.show(context, widget.exerciseName),
          child: Text(
            'VIEW PLATE',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.accent,
              letterSpacing: 2,
            ),
          ),
        ),
```

Place it at the end of the existing header `Row`, after the section label, so the panel's own expand/collapse tap is untouched.

The import already reaches this file through `screen.dart` (Task 8 added it) — this file is `part of 'screen.dart'`.

- [ ] **Step 4: Register the SoT concept**

Append to `docs/sot_registry.yaml`:

```yaml
  - concept: exercise_plate_read_path
    domain: workout
    behavioral_test_path: test/contracts/exercise_plate_shape_behavioral_test.dart
    contract_test_path: test/contracts/exercise_plate_assets_present_test.dart
    description: |
      Exercise plates. WRITER: `assets/data/exercise_library.json` `demo_slug`
      (one nullable slug per row, 165 populated), delivered to existing installs
      by `_exerciseLibraryVersion` (`seed_service.dart:95`) — a bump is the ONLY
      thing that ships a new library field, since `:128` re-seeds iff
      stored < constant.

      READER: `resolvePlate()` in
      `lib/shared/widgets/exercise_plate/plate_resolver.dart`, the SOLE entry
      point. It keys on EXACT name (`getByExactName`, never `search` — that is
      substring and "Push Up" would resolve to "Pike Push Up"), and derives the
      plate SHAPE from `logging_type`: two images for
      weight_reps / bodyweight_reps / weighted_bodyweight, one for timed /
      cardio / distance, because frame 3 of a hold is the entry or neutral
      position rather than the end of a movement. `kDynamicTimedSlugs` is the
      short exception list for timed movements that genuinely have two.

      ⚠ `equipment_tier` is NOT consulted anywhere in this path. See
      `equipment_capability_floor` for why that field can never be a gate.
    writers:
      - file: assets/data/exercise_library.json
        method: demo_slug field (nullable String per row)
      - file: lib/core/services/seed_service.dart
        method: _exerciseLibraryVersion, line 95
    readers:
      - file: lib/shared/widgets/exercise_plate/plate_resolver.dart
        method: resolvePlate
      - file: lib/shared/widgets/exercise_plate/exercise_plate_thumb.dart
        method: initState / didUpdateWidget
      - file: lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart
        method: build
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/contracts/exercise_plate_badge_sites_test.dart`
Expected: 5 PASS.

Run: `dart run scripts/check_sot_behavioral_test_paths.dart`
Expected: PASS — the entry names a behavioural test that exists.

- [ ] **Step 6: Commit**

```bash
git add lib/features/train/screens/active_workout/coaching_content_panel.dart docs/sot_registry.yaml test/contracts/exercise_plate_badge_sites_test.dart
sh scripts/safe_commit.sh "feat(plates): FORM & CUES becomes the second door, and register the SoT

Two doors, one per moment of doubt: the thumb answers 'what is this movement?'
while scanning, the FORM & CUES bar answers 'am I doing it right?' at the rep.
Neither adds chrome to a header row already at five elements.

The SoT entry records the one trap that would otherwise be re-derived: the
version constant is the only thing that delivers a new library field, and
equipment_tier is deliberately absent from this path."
```

---

### Task 10: Full-suite green, then the review record

**Files:**
- Create: `docs/plan-reviews/exercise-plates.md`
- Test: the whole suite

**Interfaces:**
- Consumes: everything above.
- Produces: the record `scripts/check_plan_review_record_exists.dart` requires at the merge.

- [ ] **Step 1: Run the full suite**

Run: `flutter test`
Expected: green. A red `main` is a P0 and "pre-existing failure" is a banned label (rule 20).

> If a newly-added test file spawns subprocesses, give it a file-level
> `@Timeout(Duration(minutes: N))` + `library;` annotation. None of this plan's
> tests do — but a targeted run is a DIFFERENT input set from the suite, so run
> the suite once before believing any of them.

- [ ] **Step 2: Run analyze over everything touched**

Run: `flutter analyze --no-fatal-infos`
Expected: zero warnings. Infos are suppressed; warnings are not, and one warning fails the push with no useful message from git.

- [ ] **Step 3: Self-initiate the B-pass**

Run: `/code-review`
Required at ≥`account` before the `--no-ff` merge, and this batch is `platform`. Do not wait to be asked (§4.3).

- [ ] **Step 4: Write the plan-review record**

Create `docs/plan-reviews/exercise-plates.md` with `---` frontmatter — the gate parses `^key:` line-anchored, and a bullet header yields null fields and a CI hard-fail:

```markdown
---
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
---

# exercise-plates — plan review record

## Round 1
[findings and what changed]

## Round 2 (on the hardened plan)
[findings and what changed]

## Ground truth verified
[what was checked against live code/data, with file:line]
```

Round 2 runs on the **post-round-1** plan; the corrections themselves can introduce defects (§4.12.1).

- [ ] **Step 5: Walk the §5 close-out**

Diagnose-doc (n/a — feature, not a fix), contract tests (added), SoT registry (Task 9), `backups/applied_migrations.json` (n/a — no migration), root CLAUDE.md (no new invariant), `lib/features/train/CLAUDE.md` (add a plate row to the SoT table), `docs/architecture/` (n/a), feedback memory, project retrospective, worktree retirement.

- [ ] **Step 6: Merge and push**

```bash
# from the PRIMARY worktree — integration only
cd "C:/Upendra/Claude Code/Fitness App"
sh scripts/safe_merge.sh exercise-plates
sh scripts/safe_push.sh
```

`safe_push.sh` has THREE outcomes: `0` LANDED, `1` FAILED, `2` UNVERIFIED. Treating `2` as either is a misreport.

---

## Self-Review

**Spec coverage.** Source and licence → Task 1 (ATTRIBUTION.md). Frames 1 and 3 only → Task 1. Union crop, no stroke → Task 1. Plate-shape rule → Tasks 4 and 7. `demo_slug` and the version bump → Task 2. `sync_community` guard → no code needed; the guard already holds and Task 9's SoT entry records it. Postgres → no migration; the field is client-only, recorded in Task 9. Placement at three sites → Task 8. Performance constraints → Task 6. Monogram → Task 5. Licence obligations → Task 1. Delivery/bundled → Task 1 (pubspec). Removals → Task 3. Verification table → Tasks 1-9. Process weight → Task 10.

**Two spec rows deliberately have no task**, and both are terminal rather than dropped: the **23 new exercises** belong to OI-145 and must not ship until the selection-skew question is answered; the **126 photographs** are the founder's camera and arrive later as a data change plus a version bump, needing no code from this plan.

**Placeholder scan.** No TBD/TODO. Every code step carries real code. Task 8's "use whatever that scope calls it" is a deliberate instruction about an unread local variable, not a placeholder — the two files' badge blocks are cited by line.

**Type consistency.** `resolvePlate` returns `ExercisePlate` in Tasks 4, 6, 7. `monogramFor` is used in Tasks 4 and 5. `ExercisePlateThumb({exerciseName, size, onTap})` matches in Tasks 6 and 8. `ExercisePlateSheet.show(BuildContext, String)` matches in Tasks 7, 8, 9. Asset paths are `assets/exercise_plates/<slug>/{1,3}.svg` throughout.

**What this review actually caught** — each verified against the file, not recalled:

1. **`AppRadius.cardS` is a legacy alias**, remapped to `card` (6) at `spacing.dart:80`. It resolves, so nothing would have failed — it would just have quietly used a deprecated name. Now `AppRadius.card`.
2. **Task 6's widget test would have thrown, not failed.** `resolvePlate` runs in `initState` and `getByExactName` reads `_hive.exerciseBox.values` (`exercise_repository.dart:46`), which needs an open box. The test file now opens Hive in `setUpAll`. Deliberately NOT fixed by wrapping the resolver in a `try`: a swallowed box error would render monograms everywhere and read as "no artwork yet" rather than "the box never opened" — bad news collapsing into no news.
3. **`_plateBox` returned an `Expanded`**, so the single-hold branch nested `Expanded > Row > Expanded` and would have drawn a hold plate at a third of the width. It now returns a plain `Column`, and each branch sizes it — 1:1 for a pair, 1:2:1 for a hold.
4. **The badge line numbers were ranges I had not re-read.** Replaced with the verified `Text` lines (447 / 236 / 256) plus an instruction to grep, since these files move.

5. **Task 1 could not have run at all**, for two independent reasons. The upstream catalogue is vendored nowhere in this repo — a session-temp directory held 94 sample SVGs, not the 906-frame source — so "run the pipeline" had no input. And the pipeline read `frame-N.png` to get an alpha bbox, but upstream ships **SVG only**: all 906 manifest frames are `"format": "svg"` and there is no PNG anywhere, nor a rasterizer installed. Task 1 now clones the source at a recorded sha into gitignored `vendor/`, commits the manifest as the provenance record, and computes the bbox from the path data instead — pure stdlib, and verified against the rasters the founder review used (389×445 vs 390×444; 430×397 vs 431×397).

**Verified rather than assumed:** every `AppColors` member used (`accent`, `card`, `cardHi`, `bgRaise`, `border`, `textPrimary`, `textMute`); every `AppTypography` member (`mono`, `monoXs`, `bodySm`); `HiveService.instance.exerciseBox` (`hive_service.dart:211`); `withValues(alpha:)` as the repo idiom (374 uses, zero `withOpacity`); and the cue-shape counts 84 / 100 / 108, which sum to 292.
