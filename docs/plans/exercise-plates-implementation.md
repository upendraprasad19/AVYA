# Exercise Plates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping an exercise opens a plate — the movement drawn at its start and end (or one drawing for a hold), with the form cues underneath — for the 165 exercises that have artwork, and a monogram for the 126 that do not.

**Architecture:** The adjudicated mapping is committed data (`docs/plans/exercise-plates-mapping.json`). A build-time Python script reads it, crops the vendored upstream SVGs, and writes `assets/exercise_plates/<slug>-{1,3}.svg`. Two new library fields — `demo_slug` and `demo_pair` — carry the drawing and its shape. A pure Dart resolver turns an exercise name into asset paths; three widgets render them. The app never crops, never fetches, and never touches the network.

**Tech Stack:** Flutter, `flutter_svg ^2.3.0` (already a dependency), Hive, Riverpod, Python 3 stdlib for the one-time asset pipeline.

**Spec:** `docs/plans/exercise-plates-spec.md` — read it first. This plan argues from it.

**Review:** round 1's findings are incorporated throughout (7 BLOCKER, 15 MAJOR, 16 MINOR). See "What round 1 changed" at the foot of this document.

## Global Constraints

- **Branch `exercise-plates`, worktree `.claude/worktrees/exercise-plates`.** Never commit from the primary worktree (§4.13). Commit via `sh scripts/safe_commit.sh "<message>"` — **one positional argument, no flags**; a flag becomes the message. Never raw `git commit`.
- **Blast radius `platform`**, driven by `pubspec.yaml` (`docs/blast_radius.yaml:324`; confirmed by `dart run scripts/blast_radius_from_diff.dart`). Requires `docs/plan-reviews/exercise-plates.md` (§4.12.3) and a self-initiated `/code-review` before the `--no-ff` merge (§4.3).
- **Wardroom palette, by NAME only.** `AppColors.accent` (Campaign Gold `#D4B270`), `AppColors.card`, `AppColors.cardHi`, `AppColors.bgRaise`, `AppColors.border`, `AppColors.textPrimary`, `AppColors.textMute`. Never a hex literal — several values differ from what prose elsewhere records (`cardHi` is `#0B172A`, and `border` is a translucent warm white, not an opaque navy), so the constant is the only safe reference.
- **Type through `AppTypography`** (rule 10) — never a raw `TextStyle(fontFamily:)`. Note `AppTypography.mono`/`monoXs` are **JetBrains Mono**, not DM Sans; `body`/`bodySm` are DM Sans; `h1`–`h3` are Fraunces. Rule 10's "DM Sans everywhere" means "go through `AppTypography`", not "every style is DM Sans".
- **Dark theme only** (rule 12). **FREE tier** — no `subscription.gate()` anywhere in this feature.
- **Import paths:** `package:` for `shared/` and `core/`, relative within a feature (rule 15).
- **Never resolve library data in `build()`.** The Active Workout card rebuilds ~1×/sec off the workout timer; resolve in `initState`/`didUpdateWidget` as `coaching_content_panel.dart:40-58` does, and for the reason its own comment gives.
- **`ExerciseData` carries no id** — every lookup is by EXACT name via `ExerciseRepository.instance.getByExactName` (`exercise_repository.dart:43`). Never `search()`, which is substring: "Push Up" would resolve to "Pike Push Up".
- **Never hard-cast a value out of `exerciseBox`.** The same box holds community rows written verbatim from Postgres (`sync_community.dart:499-514`), so any field can be any JSON type. Use `is String` tests, exactly as `coaching_content_panel.dart:73-77` does and for the reason at its `:63-64` — *"Never hard-cast to a typed string list (that cast throws + red-screens)"*.
- **Every Hive test needs the `path_provider` mock.** `HiveService.init()` calls `Hive.initFlutter()` (`hive_service.dart:76`), which resolves through `path_provider` and **ignores** the path `Hive.init()` just set. Without the mock you get `MissingPluginException` in `setUpAll` — an error, not a failure. All 7 repo tests that call it register the mock; copy `equipment_owned_widens_test.dart:63-70`.
- **No deferrals** (§4.2). Every task ends in a terminal state.

## Settled numbers

Every count below is derived from the committed mapping and the library, not recalled.

| | |
|---|---|
| library rows today | **292** |
| removed this batch (founder: *"not feasible generally"*) | **1** — Donkey Calf Raise, 0 references in `lib/` |
| library rows after | **291** |
| exercises with a drawing | **165** (148 pair + 17 single) |
| exercises showing a monogram | **126** |
| **distinct slugs** | **153** (139 pair + 14 single) |
| **SVG files generated** | **292** (139×2 + 14×1) |

> ⚠ **165 exercises share 153 slugs** — 12 drawings are referenced by two exercises each (`pull-up` by both Pull Up and Chest to Bar Pull Up, `close-grip-bench-press` by the E016/E241 pair, and 10 more). That is correct sharing, not duplication. **A per-exercise count and a per-slug count are different numbers**; the first draft conflated them and every file count in it was wrong. All 12 shared slugs agree on pair-vs-single, so the per-slug asset is unambiguous.
>
> ⚠ **292 files is a coincidence, not a derivation** — it happens to equal today's library row count. They are unrelated.

---

## File Structure

| File | Responsibility |
|---|---|
| `docs/plans/exercise-plates-mapping.json` | **Committed already** (`864ca93e`). 165 entries: `{id, name, slug, pair}`. The adjudication's output and this batch's only input. |
| `assets/data/exercise_library.json` | **Modify.** Add `demo_slug` + `demo_pair`; drop `image_start_url`/`image_end_url`/`gif_url`; remove the Donkey Calf Raise row. |
| `test/contracts/exercise_library_schema_contract_test.dart` | **Modify.** Its closed key set goes 38 → 37 (−3 dead, +2 new). |
| `lib/core/services/seed_service.dart:95` | **Modify.** `_exerciseLibraryVersion` 10 → 11. |
| `lib/core/services/swap_service.dart:294-297` | **Modify.** Delete the dead image-URL copy-through. |
| `scripts/build_exercise_plates.py` | **Create.** Reads the library, crops, emits. Dev tool, never shipped. |
| `assets/exercise_plates/<slug>-{1,3}.svg` | **Create (generated).** 292 files, **flat** — see Task 2. |
| `pubspec.yaml` | **Modify.** **One** asset line. |
| `.gitignore` + `scripts/retire_worktree_lib.dart` | **Modify.** Ignore `/vendor/`, and register it as regenerable or the worktree becomes unretirable. |
| `lib/shared/widgets/exercise_plate/plate_resolver.dart` | **Create.** Pure. No Flutter imports. |
| `lib/shared/widgets/exercise_plate/exercise_monogram.dart` | **Create.** |
| `lib/shared/widgets/exercise_plate/exercise_plate_thumb.dart` | **Create.** |
| `lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart` | **Create.** |
| `lib/features/train/screens/active_workout/exercise_card.dart` | **Modify.** Badge (`Text` at `:447`) → thumb. |
| `lib/features/train/widgets/expandable_day_card.dart` | **Modify.** Badge (`Text` at `:236`) → thumb. |
| `lib/features/home/widgets/day_detail_sheet.dart` | **Modify.** Badge (`Text` at `:256`) → thumb, **and thread `BuildContext`** — it has none in scope. |
| `lib/features/train/screens/active_workout/coaching_content_panel.dart` | **Modify.** Second door + the numeric-`breathing_cue` guard. |
| `lib/main.dart` + `lib/features/profile/**` | **Modify.** The CC BY-SA attribution surface. |
| `docs/sot_registry.yaml`, `docs/naming_conventions.md`, `docs/audit/open_issues.md` | **Modify.** Registry, glossary, parked-work tracking. |

New widgets live in `lib/shared/` — not `train/` — because three features consume them.

---

### Task 1: The library data, in one commit

Everything touching `exercise_library.json` lands together. Splitting the field additions from the removals would leave `exercise_library_schema_contract_test.dart` red in between, and rule 20 makes a red intermediate state a P0.

**Files:**
- Modify: `assets/data/exercise_library.json`, `test/contracts/exercise_library_schema_contract_test.dart`, `lib/core/services/seed_service.dart:95`, `lib/core/services/swap_service.dart:294-297`
- Test: `test/contracts/exercise_plate_library_data_test.dart` (new)

**Interfaces:**
- Consumes: `docs/plans/exercise-plates-mapping.json` (already committed).
- Produces: `demo_slug` (nullable `String`) and `demo_pair` (nullable `bool`) on library rows. Both absent ⇒ no artwork.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/exercise_plate_library_data_test.dart
//
// The version constant is the ONLY thing that delivers a new library field to an
// install that already seeded: seed_service.dart:128 re-seeds iff
// stored < constant, so shipping demo_slug WITHOUT bumping it is a silent no-op
// -- no existing user ever receives the field and nothing fails loudly.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _dead = ['image_start_url', 'image_end_url', 'gif_url'];

void main() {
  final lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
      as List).cast<Map<String, dynamic>>();
  final mapping = (jsonDecode(
          File('docs/plans/exercise-plates-mapping.json').readAsStringSync())
      as List).cast<Map<String, dynamic>>();

  test('the seed version was bumped past the last shipped value', () {
    final src = File('lib/core/services/seed_service.dart').readAsStringSync();
    final m = RegExp(r'_exerciseLibraryVersion\s*=\s*(\d+)').firstMatch(src);
    expect(m, isNotNull, reason: 'version constant not found');
    expect(int.parse(m!.group(1)!), greaterThanOrEqualTo(11),
        reason: 'v10 shipped with the OI-89 re-seed; new fields need 11+');
  });

  test('the library is 291 rows and Donkey Calf Raise is gone', () {
    expect(lib.length, 291);
    expect(lib.where((e) => e['name'] == 'Donkey Calf Raise'), isEmpty);
  });

  test('every mapping entry landed on its row, with its pair flag', () {
    final byId = {for (final e in lib) e['id'] as String: e};
    for (final m in mapping) {
      final row = byId[m['id']];
      expect(row, isNotNull, reason: '${m['id']} (${m['name']}) not in library');
      expect(row!['demo_slug'], m['slug'], reason: '${m['name']} slug drift');
      expect(row['demo_pair'], m['pair'], reason: '${m['name']} pair drift');
    }
  });

  test('exactly 165 rows carry artwork and 126 do not', () {
    final withArt = lib.where((e) {
      final s = e['demo_slug'];
      return s is String && s.isNotEmpty;
    }).toList();
    expect(withArt.length, 165);
    expect(lib.length - withArt.length, 126);
    for (final e in withArt) {
      expect(e['demo_pair'], isA<bool>(),
          reason: '${e['name']}: demo_slug without demo_pair');
      expect(e['demo_slug'], isNot(contains('/')),
          reason: '${e['name']}: demo_slug is a slug, not a path');
    }
  });

  test('a row without artwork carries neither key, not an empty one', () {
    final bad = lib
        .where((e) =>
            (e.containsKey('demo_slug') && e['demo_slug'] is! String) ||
            (e.containsKey('demo_pair') && e['demo_pair'] is! bool))
        .map((e) => e['name'])
        .toList();
    expect(bad, isEmpty, reason: 'omit the keys; "" or null reads as broken');
  });

  test('the dead image fields are gone from the library', () {
    for (final f in _dead) {
      final hits = lib.where((e) => e.containsKey(f)).map((e) => e['name']).take(3).toList();
      expect(hits, isEmpty, reason: '$f still on rows: $hits');
    }
  });

  test('no Dart source in lib/ or test/ reads the dead fields', () {
    // BOTH trees: the first draft scanned lib/ only, which is structurally
    // blind to exercise_library_schema_contract_test.dart -- the file that
    // actually breaks when the fields are removed.
    final offenders = <String>[];
    for (final root in const ['lib', 'test']) {
      for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync()
            .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
            .replaceAll(RegExp(r'//.*'), '');
        for (final d in _dead) {
          if (src.contains(d)) offenders.add('${f.path} -> $d');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'still referenced: $offenders');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_library_data_test.dart`
Expected: FAIL on all seven — version is 10, 292 rows, no `demo_slug`, dead fields present.

- [ ] **Step 3: Apply the mapping, remove the row, strip the dead fields**

```bash
python - <<'EOF'
import json, io
LIB = "assets/data/exercise_library.json"
lib = json.load(io.open(LIB, encoding="utf-8"))
mapping = json.load(io.open("docs/plans/exercise-plates-mapping.json", encoding="utf-8"))
by_id = {m["id"]: m for m in mapping}

# founder: "not feasible generally" -- 0 references in lib/, verified
before = len(lib)
lib = [e for e in lib if e["name"] != "Donkey Calf Raise"]
assert len(lib) == before - 1, "Donkey Calf Raise not found"

dead = ("image_start_url", "image_end_url", "gif_url")
art = 0
for e in lib:
    for d in dead:
        e.pop(d, None)
    m = by_id.get(e["id"])
    if m:
        e["demo_slug"] = m["slug"]
        e["demo_pair"] = m["pair"]
        art += 1

json.dump(lib, io.open(LIB, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("rows %d -> %d, artwork on %d" % (before, len(lib), art))
EOF
```

Expected: `rows 292 -> 291, artwork on 165`.

- [ ] **Step 4: Update the schema contract**

`test/contracts/exercise_library_schema_contract_test.dart:5-20` holds a **closed** 38-key set and asserts every row matches it exactly (`:22-37`). Remove the three dead keys from `_canonicalKeys`, add `'demo_slug'` and `'demo_pair'`, and change the count assertion and both test names from 38 to **37**.

> Round 1 caught this as a BLOCKER: without it, `demo_slug` lands in that test's `extra` set on 165 rows and the dead fields land in `missing` on all 291, turning two of its four tests red — through the merge, past pre-push and CI, against rule 20.

The two new keys are **optional** — 126 rows carry neither. Read `:26-37` and extend the comparison to treat `demo_slug`/`demo_pair` as permitted-but-not-required, rather than adding them to the required set. Do not assume the existing shape accommodates optional keys; it asserts an exact per-row match today.

- [ ] **Step 5: Bump the version and delete the copy-through**

In `seed_service.dart`, above line 95, in the existing comment style:

```dart
  // v11 (exercise plates): demo_slug + demo_pair added to 165 rows; the three
  // dead image URL fields removed; Donkey Calf Raise removed. Re-seed rewrites
  // every row in place via putAll.
  static const int _exerciseLibraryVersion = 11;
```

> ⚠ `putAll` replaces values; it **never deletes rows**. Donkey Calf Raise therefore survives in every already-seeded box even after this bump. Acceptable — one unreachable row with no drawing — but it is not a clean removal, and Task 9 files it so nobody re-derives the discrepancy.

In `swap_service.dart`, delete lines 294-297 — the four lines copying `image_start_url`/`image_end_url` through a swap. Nothing replaces them; a swapped exercise resolves its plate by name like any other.

- [ ] **Step 6: Run the tests**

Run: `flutter test test/contracts/exercise_plate_library_data_test.dart test/contracts/exercise_library_schema_contract_test.dart`
Expected: all green — 7 new plus the schema contract's 4.

- [ ] **Step 7: Commit**

```bash
git add assets/data/exercise_library.json test/contracts/ lib/core/services/seed_service.dart lib/core/services/swap_service.dart
sh scripts/safe_commit.sh "feat(plates): demo_slug + demo_pair on 165 rows, seed version 10 -> 11

The version bump is what actually delivers the fields: seed_service.dart:128
re-seeds only when stored < constant, so adding them without it would be a
silent no-op and no existing install would ever receive them.

demo_pair carries the plate SHAPE in the data rather than in a Dart constant, so
the Python asset pipeline and the Dart renderer read one field instead of
duplicating a rule across a language boundary with nothing keeping them in sync.

Removes Donkey Calf Raise (founder: not feasible generally; 0 references in
lib/) and the three dead image URL fields, whose only reader was a copy-through
in swap_service that nothing then rendered. Leaving them beside demo_slug would
ship two competing sets of image fields.

exercise_library_schema_contract_test's closed key set goes 38 -> 37 in the same
commit; it asserts an exact per-row key match, so any of these changes alone
turns it red."
```

---

### Task 2: Vendor the artwork, crop it, ship 292 SVGs

**Files:**
- Create: `scripts/build_exercise_plates.py`, `assets/exercise_plates/*.svg`, `assets/exercise_plates/ATTRIBUTION.md`, `docs/plans/exercise-plates-manifest.json`
- Modify: `pubspec.yaml`, `.gitignore`, `scripts/retire_worktree_lib.dart`
- Test: `test/contracts/exercise_plate_assets_present_test.dart`

**Interfaces:**
- Consumes: `demo_slug` + `demo_pair` from Task 1.
- Produces: `assets/exercise_plates/<slug>-1.svg` (always) and `<slug>-3.svg` (pair slugs only). Each is one `<path fill="currentColor">` in an `<svg viewBox="X Y W H">` with no `width`/`height`. A pair's two frames share a byte-identical `viewBox`.

> **Assets are FLAT, not one directory per slug.** Flutter does not recurse into subdirectories, so a directory-per-slug scheme needs one `pubspec.yaml` line **per slug** — and `pubspec.yaml` is `platform`-tier. That would make every future photograph batch a platform-tier change requiring a ×2 plan review and a B-pass, contradicting the spec's own plan that the 126 photographs arrive as *"a data change plus a version bump, no code"*. Flat means one `- assets/exercise_plates/` line, touched once, ever.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/exercise_plate_assets_present_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
      as List).cast<Map<String, dynamic>>();

  // slug -> isPair, DEDUPED: 165 exercises share 153 slugs.
  final slugs = <String, bool>{};
  for (final e in lib) {
    final s = e['demo_slug'];
    if (s is String && s.isNotEmpty) slugs[s] = e['demo_pair'] == true;
  }

  test('the shipping set is 153 slugs, 139 of them pairs', () {
    expect(slugs.length, 153);
    expect(slugs.values.where((p) => p).length, 139);
    expect(slugs.values.where((p) => !p).length, 14);
  });

  test('every slug has exactly the frames its shape calls for', () {
    final wrong = <String>[];
    for (final entry in slugs.entries) {
      final one = File('assets/exercise_plates/${entry.key}-1.svg');
      final three = File('assets/exercise_plates/${entry.key}-3.svg');
      if (!one.existsSync()) wrong.add('${entry.key}-1.svg missing');
      if (entry.value && !three.existsSync()) {
        wrong.add('${entry.key}-3.svg missing (pair)');
      }
      if (!entry.value && three.existsSync()) {
        wrong.add('${entry.key}-3.svg present but the exercise is a hold');
      }
    }
    expect(wrong, isEmpty, reason: 'asset shape drift: $wrong');
  });

  test('exactly 292 SVGs ship — no orphans left by a rename', () {
    final files = Directory('assets/exercise_plates')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.svg'))
        .toList();
    expect(files.length, 292);
  });

  test('paired frames share one viewBox', () {
    final vb = RegExp(r'viewBox="([^"]+)"');
    final drift = <String>[];
    for (final entry in slugs.entries.where((e) => e.value)) {
      final a = File('assets/exercise_plates/${entry.key}-1.svg').readAsStringSync();
      final b = File('assets/exercise_plates/${entry.key}-3.svg').readAsStringSync();
      final va = vb.firstMatch(a)?.group(1);
      final vbb = vb.firstMatch(b)?.group(1);
      expect(va, isNotNull, reason: '${entry.key}-1.svg has no viewBox');
      if (va != vbb) drift.add('${entry.key} ($va vs $vbb)');
    }
    expect(drift, isEmpty, reason: 'frames would jump size: $drift');
  });

  test('every frame is tintable and unsized', () {
    for (final entry in slugs.entries) {
      final names = ['${entry.key}-1.svg', if (entry.value) '${entry.key}-3.svg'];
      for (final n in names) {
        final t = File('assets/exercise_plates/$n').readAsStringSync();
        expect(t.contains('fill="currentColor"'), isTrue, reason: '$n not tintable');
        expect(RegExp(r'<svg[^>]*\swidth=').hasMatch(t), isFalse,
            reason: '$n pins a width and will not scale');
      }
    }
  });

  test('every shipped slug exists in the upstream manifest', () {
    final man = (jsonDecode(
            File('docs/plans/exercise-plates-manifest.json').readAsStringSync())
        as List).cast<Map<String, dynamic>>();
    final upstream = man.map((e) => e['slug'] as String).toSet();
    expect(slugs.keys.toSet().difference(upstream), isEmpty,
        reason: 'demo_slug values with no upstream drawing');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_assets_present_test.dart`
Expected: the slug-count test PASSES (Task 1 landed the data); every file test FAILS — nothing generated yet.

- [ ] **Step 3: Vendor the upstream catalogue**

Artwork: [workout-guide](https://github.com/bryllim/workout-guide) by Bryl Lim, CC BY-SA 4.0, vector-traced from [Everkinetic](https://github.com/everkinetic/data). **302 exercises × 3 frames = 906 SVGs.**

```bash
mkdir -p vendor
git clone --depth 1 https://github.com/bryllim/workout-guide vendor/workout-guide
git -C vendor/workout-guide rev-parse HEAD              # RECORD this sha
find vendor/workout-guide -name manifest.json           # note the path
find vendor/workout-guide -name 'frame-1.svg' | head -1 # note the assets root
```

The spec records the layout as `packages/workout-guide/assets/<slug>/frame-N.svg`, with `manifest.json` one level **above** the assets — not beside them. Confirm against what `find` returns; do not assume.

Add to `.gitignore`:

```
# Upstream plate artwork — cloned by scripts/build_exercise_plates.py.
# Only the cropped output under assets/exercise_plates/ is committed.
/vendor/
```

**Then register `vendor/` as regenerable** in `scripts/retire_worktree_lib.dart`'s `regenerableIgnoredPaths` (`:236-270`), beside its siblings:

```dart
  'vendor/',   // .gitignore: cloned upstream plate artwork, re-clonable
```

> ⚠ **Without this the worktree becomes permanently unretirable.** Leg 3 of the four-leg predicate keeps any worktree holding a non-regenerable ignored file, and `:281-284` treats anything not on the list — *including anything nested under a listed name* — as precious. This is the exact recurrence CLAUDE.md §5 warns about (diagnose `b4d7e9`, OI-128 before it): *"Any future tool that WRITES a gitignored file into a worktree owes that list an entry."*

Copy the manifest in as the provenance record and verify it is the catalogue the mapping was adjudicated against:

```bash
cp <manifest-path> docs/plans/exercise-plates-manifest.json
python -c "
import json, io
m = json.load(io.open('docs/plans/exercise-plates-manifest.json', encoding='utf-8'))
print('entries:', len(m))
print('frames :', sum(len(e['frames']) for e in m))
print('formats:', {f['format'] for e in m for f in e['frames']})
"
```

Expected: `entries: 302`, `frames: 906`, `formats: {'svg'}`.

> **If the counts differ, STOP.** The mapping was adjudicated against a 302-entry catalogue; a moved upstream means some `demo_slug` may name a drawing that no longer exists. Step 1's last test is what catches it.

- [ ] **Step 4: Write the pipeline**

```python
# scripts/build_exercise_plates.py
"""Crop the vendored workout-guide SVGs into app plate assets.

Run once after vendoring; the OUTPUT is committed, the vendored source is not.
Reads demo_slug + demo_pair from the exercise library and emits
assets/exercise_plates/<slug>-1.svg (always) and -3.svg (pairs only).

WHY the bbox comes from PATH DATA and not a raster: upstream ships SVG only --
all 906 frames in its manifest are format "svg", there is no alpha channel to
measure, and no rasterizer is installed here. Parsing is also the better answer:
pure stdlib, no native Cairo dependency, reproducible in CI.

WHY CONTROL POINTS SUFFICE: a bezier segment lies inside the convex hull of its
control points, so the bbox over on-curve AND control points is a SUPERSET of
the true ink bbox -- marginally loose at worst, never clipping. Measured against
the rasters used for the founder review (2026-08-29): bench-press frame 1 gave
389x445 vs the raster's 390x444; frame 3 gave 430x397 vs 431x397.

  LIMITS OF THAT GUARANTEE, stated because the first draft claimed it
  unconditionally: it holds for M/L/H/V/C/Q/Z. It does NOT hold for
    - A (arc): only the endpoint is recorded; an arc bulges outside its chord.
    - S/T: the REFLECTED control point is never computed and can lie outside
      every recorded point.
    - transform= on a <path> or a wrapping <g>: coordinates would be in the
      wrong space entirely.
  The parser HARD-FAILS on all four rather than silently clipping artwork. If
  upstream ever introduces them that is a real porting job, not a warning.

WHY a PAIR is cropped to the UNION and a SINGLE to its own bounds: cropping each
frame of a pair separately makes the body change size between START and END
(bench press is 390x444 then 431x397). But a HOLD renders frame 1 alone, so
unioning it with an unrendered frame 3 pollutes the viewBox -- for Wall Sit,
frame 3 is the athlete standing up, and the union would shrink the actual seated
pose to a fraction of the plate. demo_pair is what tells them apart.

WHY no stroke: at matched display size a stroke closes the interior gaps --
median gap 17 -> 13 units at width 4, 6% closed outright. The crop is the fix.
Measured over 25 real pairs, the cropped viewBox is a median 59% of the 512
canvas area, so the figure renders about 1.3x larger in the same box.
"""
import json, io, os, re, sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "vendor/workout-guide/packages/workout-guide/assets"
OUT = "assets/exercise_plates"
PAD = 10
CANVAS = 512

NUM = re.compile(r"[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?")
CMD = re.compile(r"([MmZzLlHhVvCcSsQqTtAa])")
UNSUPPORTED = set("AaSsTt")


def path_points(d, where):
    toks = [t for t in CMD.split(d) if t.strip()]
    pts = []
    cx = cy = sx = sy = 0.0
    cmd = None
    i = 0
    while i < len(toks):
        t = toks[i]
        if CMD.fullmatch(t):
            if t in UNSUPPORTED:
                raise ValueError(
                    "%s: command '%s' breaks the control-hull bbox guarantee; "
                    "flatten it properly before trusting the crop" % (where, t))
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
            elif C == "Q":
                a = nums[j:j + 4]; j += 4
                p = [(cx + a[k], cy + a[k + 1]) if rel else (a[k], a[k + 1])
                     for k in (0, 2)]
                pts.extend(p); cx, cy = p[-1]
            else:
                raise ValueError("%s: unhandled command '%s'" % (where, c))
        i += 1
    return pts


def ink_bbox(svg_path):
    t = io.open(svg_path, encoding="utf-8").read()
    if re.search(r"\stransform=", t):
        raise ValueError("%s: has a transform= attribute; the bbox would be "
                         "computed in the wrong coordinate space" % svg_path)
    pts = []
    for d in re.findall(r'\sd="([^"]+)"', t):
        pts += path_points(d, svg_path)
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
    t, n = re.subn(r'viewBox="[^"]*"', 'viewBox="%d %d %d %d"' % view_box, t, count=1)
    if n != 1:
        raise ValueError("no viewBox to rewrite")
    for lit in ('fill="#fff"', 'fill="#FFF"', 'fill="#ffffff"', 'fill="#FFFFFF"'):
        t = t.replace(lit, 'fill="currentColor"')
    if 'fill="currentColor"' not in t:
        raise ValueError("no white fill found to convert")
    return t.strip()


def main():
    lib = json.load(io.open("assets/data/exercise_library.json", encoding="utf-8"))
    # 165 exercises share 153 slugs -- dedupe, carrying the shape with each.
    slugs = {}
    for e in lib:
        s = e.get("demo_slug")
        if not s:
            continue
        pair = bool(e.get("demo_pair"))
        if s in slugs and slugs[s] != pair:
            raise SystemExit("slug %s is claimed as both pair and single" % s)
        slugs[s] = pair
    if not slugs:
        raise SystemExit("no demo_slug in the library -- run Task 1 first")

    if not os.path.isdir(SRC):
        raise SystemExit("upstream assets not found at %s\n"
                         "clone it (Task 2 Step 3) or pass the root as argv[1]" % SRC)

    os.makedirs(OUT, exist_ok=True)
    written = 0
    for slug, pair in sorted(slugs.items()):
        frames = ["1", "3"] if pair else ["1"]
        srcs = [os.path.join(SRC, slug, "frame-%s.svg" % f) for f in frames]
        for f in srcs:
            if not os.path.exists(f):
                raise SystemExit("missing upstream frame: %s" % f)
        vb = union([ink_bbox(f) for f in srcs])
        for src, f in zip(srcs, frames):
            text = io.open(src, encoding="utf-8").read()
            io.open(os.path.join(OUT, "%s-%s.svg" % (slug, f)), "w",
                    encoding="utf-8").write(crop_svg(text, vb))
            written += 1
    print("wrote %d files for %d slugs (%d pair, %d single)"
          % (written, len(slugs),
             sum(1 for v in slugs.values() if v),
             sum(1 for v in slugs.values() if not v)))


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Generate and declare**

Run: `python scripts/build_exercise_plates.py`
Expected: `wrote 292 files for 153 slugs (139 pair, 14 single)`. A missing upstream frame is a hard stop, not a skip — a silently-skipped slug would ship a `demo_slug` pointing at nothing.

In `pubspec.yaml`, under `assets:` (currently line 129), add **one** line:

```yaml
    - assets/exercise_plates/
```

Create `assets/exercise_plates/ATTRIBUTION.md` with the sha from Step 3:

```markdown
# Exercise plate artwork

Derived from [workout-guide](https://github.com/bryllim/workout-guide) by Bryl Lim
(commit `<sha>`), itself vector-traced from
[Everkinetic](https://github.com/everkinetic/data).

Both are licensed **CC BY-SA 4.0** — https://creativecommons.org/licenses/by-sa/4.0/

**Changes made:** each `viewBox` was cropped to the ink bounds — the union of both
frames for a two-position movement, the frame's own bounds for a static hold — and
the fill was changed from `#fff` to `currentColor` so the app can tint it. No path
data was altered.

These adapted files are redistributed under the same licence. The per-frame creator
and Everkinetic source for every drawing is preserved in
`docs/plans/exercise-plates-manifest.json`.

⚠ This file documents the obligation. It does not DISCHARGE it — a markdown file in
the repo reaches no user. Task 8 is what puts the attribution in front of a person.
```

- [ ] **Step 6: Run the test**

Run: `flutter test test/contracts/exercise_plate_assets_present_test.dart`
Expected: all 6 PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/build_exercise_plates.py scripts/retire_worktree_lib.dart assets/exercise_plates pubspec.yaml .gitignore docs/plans/exercise-plates-manifest.json test/contracts/exercise_plate_assets_present_test.dart
sh scripts/safe_commit.sh "feat(plates): vendor the artwork and ship 292 cropped plate SVGs

A PAIR is cropped to the union of both frames so the figure cannot change size
between START and END. A HOLD is cropped to frame 1's own bounds, because it
renders frame 1 alone and unioning it with an unrendered frame 3 pollutes the
viewBox -- for Wall Sit frame 3 is the athlete standing up, which would shrink
the seated pose to a fraction of the plate. demo_pair tells them apart, in the
data, so Python and Dart read one field rather than duplicating a rule.

The bbox comes from the SVG path data, not a raster: upstream ships SVG only and
no rasterizer is installed. A bezier lies inside the hull of its control points,
so the bbox over on-curve plus control points is a superset of the ink bbox --
loose at worst, never clipping. Checked against the rasters used for the founder
review: 389x445 vs 390x444, 430x397 vs 431x397. That guarantee does NOT cover
arcs, smooth curves or transforms, so the parser hard-fails on all four instead
of silently clipping.

Assets are FLAT, one pubspec line. Flutter does not recurse, so a directory per
slug would need a line each -- and pubspec.yaml is platform-tier, which would
make every future photograph batch a platform-tier change requiring a x2 review.

vendor/ is registered as regenerable in retire_worktree_lib, or leg 3 of the
retirement predicate would keep this worktree forever (diagnose b4d7e9).

Artwork CC BY-SA 4.0 from workout-guide via Everkinetic."
```

---

### Task 3: The plate resolver

**Files:**
- Create: `lib/shared/widgets/exercise_plate/plate_resolver.dart`
- Test: `test/contracts/exercise_plate_resolver_test.dart`

**Interfaces:**
- Consumes: `ExerciseRepository.instance.getByExactName(String) → Map<String, dynamic>?`.
- Produces: `ExercisePlate` (`slug`, `assetPaths`, `isPair`, `monogram`, `hasArtwork`), `resolvePlate(String)`, `monogramFor(String)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/exercise_plate_resolver_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late List<Map<String, dynamic>> lib;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('plate_resolver');
    // REQUIRED: HiveService.init() calls Hive.initFlutter(), which resolves
    // through path_provider and IGNORES Hive.init()'s path. Without this the
    // suite throws MissingPluginException in setUpAll -- an error, not a
    // failure, so "run it to see it fail" would show the wrong thing.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    await HiveService.instance.init();
    lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
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

  // ---- ENUMERATED, not sampled. The spec asks that EVERY row obey the shape
  // rule; three hand-picked exercises would prove almost nothing. ----
  test('every row with artwork resolves to the frames its demo_pair declares', () {
    final bad = <String>[];
    for (final e in lib) {
      final slug = e['demo_slug'];
      if (slug is! String || slug.isEmpty) continue;
      final p = resolvePlate(e['name'] as String);
      if (!p.hasArtwork) { bad.add('${e['name']}: no artwork'); continue; }
      if (p.slug != slug) bad.add('${e['name']}: slug ${p.slug} != $slug');
      if (p.isPair != (e['demo_pair'] == true)) bad.add('${e['name']}: pair drift');
      final want = e['demo_pair'] == true ? 2 : 1;
      if (p.assetPaths.length != want) {
        bad.add('${e['name']}: ${p.assetPaths.length} paths, wanted $want');
      }
      if (p.assetPaths.first != 'assets/exercise_plates/$slug-1.svg') {
        bad.add('${e['name']}: bad path ${p.assetPaths.first}');
      }
    }
    expect(bad, isEmpty, reason: 'shape drift on ${bad.length} rows: ${bad.take(5)}');
  });

  test('every row WITHOUT artwork resolves to a monogram and no paths', () {
    for (final e in lib) {
      if (e.containsKey('demo_slug')) continue;
      final p = resolvePlate(e['name'] as String);
      expect(p.hasArtwork, isFalse, reason: '${e['name']} claims artwork');
      expect(p.assetPaths, isEmpty);
      expect(p.monogram, isNotEmpty);
    }
  });

  test('an unknown name never throws and never claims artwork', () {
    final p = resolvePlate('Totally Invented Exercise');
    expect(p.hasArtwork, isFalse);
    expect(p.monogram, 'TIE');
  });

  test('lookup is EXACT, never substring', () {
    // Both rows must exist or this passes vacuously on null == null.
    final names = lib.map((e) => e['name']).toSet();
    expect(names, containsAll(<String>['Push Up', 'Pike Push Up']));
    expect(resolvePlate('Push Up').slug,
        isNot(equals(resolvePlate('Pike Push Up').slug)));
  });

  test('a non-String demo_slug is ignored, not cast', () {
    // Community rows are written verbatim from Postgres (sync_community.dart:499)
    // and can carry any JSON type. A hard cast here red-screens the sheet.
    HiveService.instance.exerciseBox.put('ZTEST', {
      'id': 'ZTEST', 'name': 'Ztest Bogus Row', 'demo_slug': 42, 'demo_pair': 'yes',
    });
    expect(resolvePlate('Ztest Bogus Row').hasArtwork, isFalse);
  });

  group('monogramFor', () {
    test('takes the initial of up to three significant words', () {
      expect(monogramFor('Barbell Bench Press'), 'BBP');
      expect(monogramFor('Push Up'), 'PU');
      expect(monogramFor('Squat'), 'S');
    });
    test('drops possessives, stop words and punctuation', () {
      // "Captain's" must not contribute a bare "s" -- that yielded CSC.
      expect(monogramFor("Captain's Chair Leg Raise"), 'CCL');
      expect(monogramFor('Dip (Parallel Bars)'), 'DPB');
    });
    test('never returns empty for any library name', () {
      for (final e in lib) {
        expect(monogramFor(e['name'] as String), isNotEmpty, reason: '${e['name']}');
      }
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
// Plate SHAPE comes from the library's `demo_pair` field, NOT from a constant
// here. It used to be a logging_type rule plus a hand-curated exception list,
// which meant the asset pipeline (Python) and the renderer (Dart) each held
// half of one decision with nothing keeping them in sync.
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

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
/// It does NOT identify — a three-letter code collides across a third of the
/// library ('SC' is Skull Crusher, Suitcase Carry, Spider Curl and Sandbag
/// Clean). Its only job is to make an artwork-less slot look deliberate; the
/// exercise name renders beside it.
String monogramFor(String name) {
  final words = name
      .replaceAll(RegExp(r"[^A-Za-z0-9\s]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_monogramStopWords.contains(w.toLowerCase()))
      .toList();
  // Drop one-letter fragments: stripping the apostrophe from "Captain's" leaves
  // a bare "s", which made "Captain's Chair Leg Raise" read CSC instead of CCL.
  // Keep them only when nothing else survives, so "V Up" still works.
  final significant = words.where((w) => w.length > 1).toList();
  final use = significant.isNotEmpty ? significant : words;
  if (use.isEmpty) return '?';
  return use.take(3).map((w) => w[0].toUpperCase()).join();
}

ExercisePlate resolvePlate(String exerciseName) {
  final mono = monogramFor(exerciseName);
  // EXACT name, never search() — that is substring, and "Push Up" would
  // resolve to "Pike Push Up".
  final row = ExerciseRepository.instance.getByExactName(exerciseName);

  // `is String`, never `as String?` — this box also holds community rows
  // written straight from Postgres, where any field can be any JSON type.
  final rawSlug = row?['demo_slug'];
  final slug = rawSlug is String ? rawSlug.trim() : '';

  if (slug.isEmpty) {
    return ExercisePlate(
        slug: null, assetPaths: const [], isPair: false, monogram: mono);
  }

  final isPair = row?['demo_pair'] == true;
  final paths = isPair
      ? <String>[
          'assets/exercise_plates/$slug-1.svg',
          'assets/exercise_plates/$slug-3.svg',
        ]
      : <String>['assets/exercise_plates/$slug-1.svg'];

  return ExercisePlate(
      slug: slug, assetPaths: paths, isPair: isPair, monogram: mono);
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/contracts/exercise_plate_resolver_test.dart`
Expected: all 8 PASS. The two enumerated tests cover all 291 rows, not a sample.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/exercise_plate/plate_resolver.dart test/contracts/exercise_plate_resolver_test.dart
sh scripts/safe_commit.sh "feat(plates): the plate resolver — name to assets and shape

Shape comes from the library's demo_pair field, not a constant here. It used to
be a logging_type rule plus a hand-curated exception list, so the Python asset
pipeline and the Dart renderer each held half of one decision with nothing
keeping them in sync.

Lookup is getByExactName, never search — search is substring and Push Up would
resolve to Pike Push Up. Fields are read with 'is String' rather than cast: the
same Hive box holds community rows written verbatim from Postgres, where a hard
cast red-screens the sheet.

The shape tests ENUMERATE all 291 rows rather than sampling three."
```

---

### Task 4: The monogram and the thumbnail

One task, one test file. They were split in the first draft and the test file imported both, so neither could compile alone.

**Files:**
- Create: `lib/shared/widgets/exercise_plate/exercise_monogram.dart`, `exercise_plate_thumb.dart`
- Test: `test/contracts/exercise_plate_widgets_test.dart`

**Interfaces:**
- Consumes: `resolvePlate`, `monogramFor`.
- Produces: `ExerciseMonogram({name, size})`, `ExercisePlateThumb({exerciseName, size = 44, onTap})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/exercise_plate_widgets_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
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
    final box = t.widget<SizedBox>(find.descendant(
        of: find.byType(ExerciseMonogram), matching: find.byType(SizedBox)).first);
    expect(box.width, 44);
    expect(box.height, 44);
  });

  testWidgets('the thumb falls back to the monogram when there is no artwork',
      (t) async {
    await t.pumpWidget(_host(const ExercisePlateThumb(
        exerciseName: 'Totally Invented Exercise', size: 44)));
    await t.pump();
    expect(find.byType(ExerciseMonogram), findsOneWidget);
  });

  testWidgets('the thumb exposes a 44 px tap target that fires', (t) async {
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

  testWidgets('a slug with no bundled asset degrades to the monogram', (t) async {
    HiveService.instance.exerciseBox.put('ZGHOST', {
      'id': 'ZGHOST', 'name': 'Zghost Exercise',
      'demo_slug': 'no-such-drawing', 'demo_pair': true,
    });
    await t.pumpWidget(_host(
        const ExercisePlateThumb(exerciseName: 'Zghost Exercise', size: 44)));
    await t.pumpAndSettle();
    expect(find.byType(ExerciseMonogram), findsOneWidget,
        reason: 'an unbundled slug must not render an error box');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_widgets_test.dart`
Expected: FAIL — neither widget file exists.

- [ ] **Step 3: Write the monogram**

```dart
// lib/shared/widgets/exercise_plate/exercise_monogram.dart
//
// Shown wherever an exercise has no artwork. Three populations reach it: user
// custom exercises, community exercises synced from user_custom_exercises, and
// the 126 library rows awaiting a photograph.
//
// It reads as "a plate not yet issued" rather than as a failure. Rejected:
// falling back to the index number (a column mixing engravings and bare
// numerals reads as "some of these are missing"), a category glyph (nine glyphs
// to design, and a triangle beside an engraving is two visual languages), and an
// empty frame (reads as a loading state that never resolves).
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_resolver.dart';

/// The plate corner radius scales with the plate, so a 44 px thumb and a 96 px
/// empty state read as the same object at two sizes. Deliberately NOT an
/// `AppRadius` addition: those are fixed Wardroom radii (2 / 4 / 6), and this is
/// proportional to one widget family. Promote it if a second family needs it.
double plateRadiusFor(double size) => size * 0.14;

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
          borderRadius: BorderRadius.circular(plateRadiusFor(size)),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
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

- [ ] **Step 4: Write the thumbnail**

```dart
// lib/shared/widgets/exercise_plate/exercise_plate_thumb.dart
//
// Replaces the numbered badge at the three sites that render one. The badge
// carried almost nothing — position in a vertical list is already obvious — so
// this costs ZERO new elements in a header row already at five (Hick's Law
// stays neutral). 44 px rather than 38 is also the minimum touch target, so one
// change fixes two things.
//
// WHY initState and not build(): the Active Workout card rebuilds ~1x/second off
// the workout timer, so resolving in build() would re-read Hive sixty times a
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
  bool _assetFailed = false;

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
      _assetFailed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showArt = _plate.hasArtwork && !_assetFailed;
    final Widget face = showArt
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.cardHi,
              borderRadius: BorderRadius.circular(plateRadiusFor(widget.size)),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: EdgeInsets.all(widget.size * 0.06),
              child: SvgPicture.asset(
                _plate.assetPaths.first,
                colorFilter:
                    const ColorFilter.mode(AppColors.accent, BlendMode.srcIn),
                // A demo_slug naming an unbundled drawing must degrade, not
                // render an error box. Reachable via community rows, which sync
                // writes verbatim from Postgres.
                errorBuilder: (_, __, ___) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _assetFailed = true);
                  });
                  return ExerciseMonogram(
                      name: widget.exerciseName, size: widget.size);
                },
              ),
            ),
          )
        : ExerciseMonogram(name: widget.exerciseName, size: widget.size);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: SizedBox(width: widget.size, height: widget.size, child: face),
    );
  }
}
```

> `errorBuilder` is **confirmed present** — `flutter_svg-2.2.4/lib/svg.dart:94`, resolved in the pub cache 2026-08-29 (the lock resolves `^2.3.0` to 2.2.4; read `pubspec.lock` if that looks wrong). `placeholderBuilder` sits beside it at `:89` if a loading state is ever wanted.

- [ ] **Step 5: Run the test**

Run: `flutter test test/contracts/exercise_plate_widgets_test.dart`
Expected: all 6 PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/shared/widgets/exercise_plate/ test/contracts/exercise_plate_widgets_test.dart
sh scripts/safe_commit.sh "feat(plates): the monogram and the 44 px thumbnail

Zero new elements in a header row already at five, because the badge the thumb
replaces carried almost nothing. 44 px rather than 38 is also the minimum touch
target, so one change fixes two things.

Resolves in initState and didUpdateWidget, never in build: the Active Workout
card rebuilds about once a second off the workout timer.

A demo_slug naming an unbundled drawing degrades to the monogram rather than
rendering an error box — reachable through community rows, which sync writes
verbatim from Postgres."
```

---

### Task 5: The plate sheet

**Files:**
- Create: `lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart`
- Test: `test/contracts/exercise_plate_sheet_test.dart`

**Interfaces:**
- Consumes: `resolvePlate`, `ExerciseMonogram`, `ExerciseRepository.getByExactName`.
- Produces: `static Future<void> ExercisePlateSheet.show(BuildContext, String)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/exercise_plate_sheet_test.dart
//
// The shape rule asserted through the RENDERED widget, not the resolver — a
// resolver unit test passes even if the sheet ignores isPair.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('plate_sheet');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
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

  Future<void> open(WidgetTester t, String name, {Size? surface}) async {
    if (surface != null) await t.binding.setSurfaceSize(surface);
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

  testWidgets('a pair shows TWO plates labelled START and END', (t) async {
    await open(t, 'Barbell Bench Press');
    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(find.text('START'), findsOneWidget);
    expect(find.text('END'), findsOneWidget);
  });

  testWidgets('a hold shows ONE plate and never says END', (t) async {
    await open(t, 'Wall Sit');
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('END'), findsNothing);
    expect(find.text('HOLD THIS POSITION'), findsOneWidget);
  });

  testWidgets('no artwork shows the monogram, not a broken box', (t) async {
    await open(t, 'Surya Namaskar');
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.textContaining('SN'), findsWidgets);
  });

  testWidgets('a REAL breathing cue renders', (t) async {
    // Barbell Bench Press carries "Inhale down, exhale on press" -- verified
    // 2026-08-29. This is the positive half; without it the suppression test
    // below would pass on a sheet that never renders BREATHING at all.
    await open(t, 'Barbell Bench Press');
    expect(find.text('BREATHING'), findsOneWidget);
  });

  testWidgets('a NUMERIC breathing_cue is suppressed, never printed', (t) async {
    // Surya Namaskar's breathing_cue is the string "12" -- one of the 136 rows
    // where a spreadsheet column shift put met_value into the field.
    await open(t, 'Surya Namaskar');
    expect(find.text('BREATHING'), findsNothing,
        reason: 'a bare number reached the sheet as a breathing cue');
  });

  testWidgets('the sheet scrolls rather than overflowing on a small screen',
      (t) async {
    // Worst case measured: 6 cue lines after the ';' split, longest cue 91 chars.
    await open(t, "Captain's Chair Leg Raise", surface: const Size(320, 480));
    expect(t.takeException(), isNull, reason: 'a RenderFlex overflow was thrown');
    expect(find.byType(SingleChildScrollView), findsWidgets);
    await t.binding.setSurfaceSize(null);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_sheet_test.dart`
Expected: FAIL — the sheet does not exist.

- [ ] **Step 3: Write the sheet**

```dart
// lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart
//
// The plate. Two images for a movement that cycles, one for a hold — see
// plate_resolver.dart. Free to every tier, matching the FORM & CUES panel it
// sits beside.
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

  /// Cues arrive in three shapes across the library, counted 2026-08-29: a
  /// single string packed with semicolons (84), a real array (100), or one
  /// plain cue (108). Splitting on ';' renders all three as lines.
  List<String> _cues(Map<String, dynamic>? row) {
    final raw = row?['coaching_cues'];
    if (raw is! List) return const [];
    return raw
        .expand((c) => c.toString().split(';'))
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList(growable: false);
  }

  /// `is String`, never a cast — community rows carry arbitrary JSON types.
  String? _clean(Object? v) {
    final s = v is String ? v.trim() : '';
    return s.isEmpty ? null : s;
  }

  Widget _plateBox(String assetPath, String caption, String name) {
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
                colorFilter:
                    const ColorFilter.mode(AppColors.accent, BlendMode.srcIn),
                errorBuilder: (_, __, ___) =>
                    ExerciseMonogram(name: name, size: 64),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(caption,
            style: AppTypography.monoXs
                .copyWith(color: AppColors.accent, letterSpacing: 2)),
      ],
    );
  }

  Widget _label(String text) => Text(text,
      style: AppTypography.monoXs
          .copyWith(color: AppColors.textMute, letterSpacing: 2));

  @override
  Widget build(BuildContext context) {
    final plate = resolvePlate(exerciseName);
    final row = ExerciseRepository.instance.getByExactName(exerciseName);
    final cues = _cues(row);
    final breathing = _clean(row?['breathing_cue']);
    // 136 rows carry a bare number here — a spreadsheet column shift that put
    // met_value into breathing_cue. Suppress rather than print "BREATHING / 5".
    // coaching_content_panel applies the identical guard; the data repair is
    // tracked on the OI board.
    final showBreathing =
        breathing != null && !RegExp(r'^\d+(\.\d+)?$').hasMatch(breathing);

    return SafeArea(
      child: SingleChildScrollView(
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
            Text(exerciseName.toUpperCase(),
                style: AppTypography.mono.copyWith(
                    color: AppColors.textPrimary, letterSpacing: 2.2)),
            const SizedBox(height: 14),
            if (plate.hasArtwork)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: plate.isPair
                    ? [
                        Expanded(
                            child: _plateBox(
                                plate.assetPaths[0], 'START', exerciseName)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _plateBox(
                                plate.assetPaths[1], 'END', exerciseName)),
                      ]
                    // A single hold gets half the width (1:2:1), not the third
                    // it would get by reusing the pair's sizing.
                    : [
                        const Spacer(),
                        Expanded(
                          flex: 2,
                          child: _plateBox(plate.assetPaths.single,
                              'HOLD THIS POSITION', exerciseName),
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
                    _label('NO DRAWING YET'),
                  ],
                ),
              ),
            if (cues.isNotEmpty) ...[
              const SizedBox(height: 18),
              _label('FORM'),
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
              _label('BREATHING'),
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

Run: `flutter test test/contracts/exercise_plate_sheet_test.dart`
Expected: all 6 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart test/contracts/exercise_plate_sheet_test.dart
sh scripts/safe_commit.sh "feat(plates): the plate sheet — diptych for a cycle, one plate for a hold

The shape rule is asserted through the rendered widget, not just the resolver: a
resolver unit test passes even if the sheet ignores isPair.

Scrolls rather than overflowing. Worst case measured across the library: six cue
lines after the ';' split, longest single cue 91 characters, which wraps on a
phone and overflows a 568 dp screen or any device at text scale 1.4.

A numeric breathing_cue is suppressed rather than printed. 136 rows carry a bare
number there from a spreadsheet column shift that put met_value into the field."
```

---

### Task 6: Wire the three badge sites

**Files:**
- Modify: `exercise_card.dart`, `screen.dart` (imports), `expandable_day_card.dart`, `day_detail_sheet.dart`
- Test: `test/contracts/exercise_plate_badge_sites_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/exercise_plate_badge_sites_test.dart
//
// A source-grep contract. It cannot prove the widget renders — the widget tests
// do that — but it CAN prove no site silently reverts to the numeric badge,
// which a widget test on one screen would miss.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _sites = [
  'lib/features/train/screens/active_workout/exercise_card.dart',
  'lib/features/train/widgets/expandable_day_card.dart',
  'lib/features/home/widgets/day_detail_sheet.dart',
];

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//.*'), '');

void main() {
  test('all three badge sites render the plate thumb and open the sheet', () {
    for (final p in _sites) {
      final src = _strip(File(p).readAsStringSync());
      expect(src.contains('ExercisePlateThumb'), isTrue, reason: '$p: no thumb');
      expect(src.contains('ExercisePlateSheet.show'), isTrue,
          reason: '$p: thumb opens nothing');
    }
  });

  test('no site still renders a bare index badge', () {
    for (final p in _sites) {
      final src = _strip(File(p).readAsStringSync());
      final hasBadge =
          RegExp(r"\$\{\s*(widget\.)?(exerciseIndex|index)\s*\+\s*1\s*\}")
              .hasMatch(src);
      expect(hasBadge, isFalse, reason: '$p still renders the numeric badge');
    }
  });

  test('the FORM & CUES bar offers the plate as a second door', () {
    final src = _strip(File(
            'lib/features/train/screens/active_workout/coaching_content_panel.dart')
        .readAsStringSync());
    expect(src.contains('ExercisePlateSheet.show'), isTrue,
        reason: 'the expanded card has no route to the plate');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_badge_sites_test.dart`
Expected: FAIL on all three.

- [ ] **Step 3: Active Workout card**

`exercise_card.dart` is `part of 'screen.dart'`, so add the imports to **`screen.dart`**:

```dart
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_sheet.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_thumb.dart';
```

Replace the number-badge `Container` — its `Text` is at **`:447`**, `'${widget.exerciseIndex + 1}'`; grep for it rather than trusting the line — with:

```dart
                              ExercisePlateThumb(
                                exerciseName: widget.exercise.name,
                                size: 44,
                                onTap: () => ExercisePlateSheet.show(
                                    context, widget.exercise.name),
                              ),
```

Keep the `const SizedBox(width: 10)` that follows.

> The exercise NAME is not available as a tap target: `:429-433` wraps the header row in a `GestureDetector` whose `onTap` is `widget.onFocus` (expand/collapse, Bug #15b) and `onLongPress` is `widget.onLongPressHeader` (superset grouping). Both are load-bearing. The thumb's own detector sits inside that row and wins the tap arena for its 44 px; long-press still reaches the outer one, which is desirable.
>
> ⚠ **The badge also carried the active-card gold signal** (`:440` fill, `:449` text colour, both keyed on `widget.isActive`). The card border keeps a gold tint at 0.35 alpha (`:398-399`), so the signal weakens rather than disappears — but confirm on a real device that the active card is still obvious, and if not, tint the thumb's border on `isActive`.

- [ ] **Step 4: Train day card**

`expandable_day_card.dart:236` is the badge `Text`. Its enclosing `Container` sits inside `Consumer(builder: (context, ref, _) {` at `:215-216`, so `context` resolves. Replace with:

```dart
              ExercisePlateThumb(
                exerciseName: exercise.name,
                size: 44,
                onTap: () => ExercisePlateSheet.show(context, exercise.name),
              ),
```

Read `:207-250` and use whatever that scope actually calls the exercise — it is `exercise`, not `name`. Add both `package:` imports.

- [ ] **Step 5: Home day-detail sheet — thread the context first**

`day_detail_sheet.dart:256` is the badge `Text`, but **`context` is not in scope**: the class is a `StatelessWidget` (`:16`), `_buildWorkoutBody()` takes no `BuildContext` (`:193`), and the builder discards it (`:216`, `itemBuilder: (_, index)`). Using `context` here is a compile error, not a test failure.

Change `:216` to `itemBuilder: (ctx, index) {` and use `ctx`:

```dart
              ExercisePlateThumb(
                exerciseName: name,
                size: 44,
                onTap: () => ExercisePlateSheet.show(ctx, name),
              ),
```

(`:225` genuinely does define `name` in this file.) Add both imports.

- [ ] **Step 6: Analyze and test**

Run: `flutter analyze lib/features/train/screens/active_workout/ lib/features/train/widgets/expandable_day_card.dart lib/features/home/widgets/day_detail_sheet.dart lib/shared/widgets/exercise_plate/`
Expected: **zero warnings.** `--no-fatal-infos` suppresses infos, not warnings, and one warning fails the push with no useful message from git.

Run: `flutter test test/contracts/exercise_plate_badge_sites_test.dart`
Expected: the first two PASS; the third still fails until Task 7.

- [ ] **Step 7: Commit**

```bash
git add lib/features/ test/contracts/exercise_plate_badge_sites_test.dart
sh scripts/safe_commit.sh "feat(plates): the numbered badge becomes the plate at all three sites

Tapping the exercise NAME was unavailable — exercise_card.dart:429-433 already
owns both the tap (expand/collapse, Bug #15b) and the long-press (superset
grouping). The thumb's own gesture detector sits inside that row.

day_detail_sheet needed BuildContext threaded before it could open anything:
_buildWorkoutBody takes none and its itemBuilder discarded it, so the obvious
edit would not have compiled.

The source-grep contract pins all three sites together: a widget test on one
screen would not notice another reverting to the numeric badge."
```

---

### Task 7: The second door, the breathing guard, and the SoT registry

**Files:**
- Modify: `coaching_content_panel.dart`, `docs/sot_registry.yaml`, `docs/naming_conventions.md`
- Test: extend `exercise_plate_badge_sites_test.dart`; new `breathing_cue_numeric_suppressed_test.dart`

- [ ] **Step 1: Write the failing tests**

Append to `exercise_plate_badge_sites_test.dart`:

```dart
  test('the SoT registry carries the plate read path with a behavioural test', () {
    final y = File('docs/sot_registry.yaml').readAsStringSync();
    expect(y.contains('concept: exercise_plate_read_path'), isTrue,
        reason: 'the new writer/reader contract is unregistered');
    final i = y.indexOf('concept: exercise_plate_read_path');
    final window = y.substring(i, (i + 800).clamp(0, y.length));
    expect(window.contains('behavioral_test_path:'), isTrue,
        reason: 'rule 21 is strict — a bare registry entry blocks the commit');
  });

  test('demo_slug and demo_pair are in the naming glossary (§4.7)', () {
    final n = File('docs/naming_conventions.md').readAsStringSync();
    expect(n.contains('demo_slug'), isTrue);
    expect(n.contains('demo_pair'), isTrue);
  });
```

New file:

```dart
// test/contracts/breathing_cue_numeric_suppressed_test.dart
//
// 136 of 292 rows carry a bare number in breathing_cue — a spreadsheet column
// shift that put met_value into the field, live in the shipped app. BOTH
// surfaces that render it must suppress a numeric value; shipping the guard in
// only the new sheet would leave two surfaces disagreeing about one field.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//.*'), '');

void main() {
  const surfaces = [
    'lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart',
    'lib/features/train/screens/active_workout/coaching_content_panel.dart',
  ];

  test('both breathing_cue surfaces guard against a numeric value', () {
    for (final p in surfaces) {
      final src = _strip(File(p).readAsStringSync());
      expect(src.contains(r'^\d+(\.\d+)?$'), isTrue,
          reason: '$p renders breathing_cue without the numeric guard');
    }
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/contracts/exercise_plate_badge_sites_test.dart test/contracts/breathing_cue_numeric_suppressed_test.dart`
Expected: FAIL — no registry entry, no glossary terms, `coaching_content_panel` unguarded.

- [ ] **Step 3: Add the second door**

In `coaching_content_panel.dart`, at the end of the header `Row` that renders the `FORM & CUES` label — after the section label, so the panel's own expand/collapse tap is untouched:

```dart
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ExercisePlateSheet.show(context, widget.exerciseName),
          child: Text(
            'VIEW PLATE',
            style: AppTypography.monoXs
                .copyWith(color: AppColors.accent, letterSpacing: 2),
          ),
        ),
```

The import already reaches this file — it is `part of 'screen.dart'` and Task 6 added it there. Confirm the field holding the name in this class (per `:40-58`) before using it.

- [ ] **Step 4: Apply the same breathing guard here**

`:143` renders `_lineSection('BREATHING', _breathing!)`. Where `_breathing` is assigned in `initState`, suppress a numeric value exactly as the sheet does:

```dart
    final b = _cleanString(raw['breathing_cue']);
    // 136 of the library rows carry a bare number here — a spreadsheet column
    // shift that put met_value into breathing_cue. Suppress rather than render
    // "BREATHING / 5". Mirrored in exercise_plate_sheet.dart; the data repair is
    // tracked on the OI board.
    _breathing = (b != null && RegExp(r'^\d+(\.\d+)?$').hasMatch(b)) ? null : b;
```

> This is §4.2, not scope creep: the batch is already editing this file, it renders the same field as the new sheet, and shipping the guard on one of two surfaces is the writer/reader drift class this repo has hit 15+ times.

- [ ] **Step 5: Register the SoT concept and the glossary terms**

Append to `docs/sot_registry.yaml`:

```yaml
  - concept: exercise_plate_read_path
    domain: workout
    behavioral_test_path: test/contracts/exercise_plate_resolver_test.dart
    contract_test_path: test/contracts/exercise_plate_assets_present_test.dart
    description: |
      Exercise plates. WRITER: `assets/data/exercise_library.json` — `demo_slug`
      (nullable, 165 populated) and `demo_pair` (nullable bool, the plate SHAPE),
      both sourced from `docs/plans/exercise-plates-mapping.json`. Delivered to
      existing installs ONLY by `_exerciseLibraryVersion` (`seed_service.dart:95`):
      `:128` re-seeds iff stored < constant, so a bump is the only thing that
      ships a new library field.

      READER: `resolvePlate()` in
      `lib/shared/widgets/exercise_plate/plate_resolver.dart`, the SOLE entry
      point. Keys on EXACT name (`getByExactName` — never `search`, which is
      substring: "Push Up" would resolve to "Pike Push Up"). Reads both fields
      with `is String` / `== true`, never a cast, because this box also holds
      community rows written verbatim from Postgres (`sync_community.dart:499`).

      ⚠ `demo_pair` is in the DATA deliberately. The pair-vs-single rule is read
      by BOTH the Dart renderer and the Python asset pipeline
      (`scripts/build_exercise_plates.py`), which crops a pair to the union of
      both frames and a hold to frame 1's own bounds. Moving it back into a Dart
      constant re-creates a cross-language drift with no gate.

      ⚠ 165 exercises share 153 slugs — a per-exercise count and a per-slug count
      are different numbers.

      ⚠ `equipment_tier` is NOT consulted anywhere in this path. See
      `equipment_capability_floor` for why that field can never be a gate.
    writers:
      - file: assets/data/exercise_library.json
        method: demo_slug + demo_pair fields
      - file: lib/core/services/seed_service.dart
        method: _exerciseLibraryVersion, line 95
    readers:
      - file: lib/shared/widgets/exercise_plate/plate_resolver.dart
        method: resolvePlate
      - file: scripts/build_exercise_plates.py
        method: main
      - file: lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart
        method: build
```

Append `demo_slug` and `demo_pair` to the reserved-domain glossary in `docs/naming_conventions.md` (§4.7 requires this for any new domain term).

- [ ] **Step 6: Run the tests**

Run: `flutter test test/contracts/exercise_plate_badge_sites_test.dart test/contracts/breathing_cue_numeric_suppressed_test.dart`
Expected: all green.

Run: `dart run scripts/check_sot_behavioral_test_paths.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/train/screens/active_workout/coaching_content_panel.dart docs/sot_registry.yaml docs/naming_conventions.md test/contracts/
sh scripts/safe_commit.sh "feat(plates): FORM & CUES becomes the second door; guard breathing_cue on BOTH surfaces

Two doors, one per moment of doubt: the thumb answers 'what is this movement?'
while scanning, the FORM & CUES bar answers 'am I doing it right?' at the rep.
Neither adds chrome to a header row already at five elements.

The numeric-breathing_cue guard lands in coaching_content_panel too, not only in
the new sheet. 136 of 292 rows carry a bare number there from a spreadsheet
column shift, live in the shipped app, and shipping the guard on one of two
surfaces that render the same field is the writer/reader drift class this repo
has hit 15+ times. The batch was already editing this file."
```

---

### Task 8: The attribution surface

The artwork is CC BY-SA 4.0. A markdown file in the repo satisfies no obligation on distribution — it reaches no user. `grep -rn "showLicensePage\|LicenseRegistry\|AboutDialog" lib/` returns **zero hits**, so the app has no credit surface at all today.

**Files:**
- Modify: `lib/main.dart`, a Profile settings screen
- Create: `assets/exercise_plates/LICENSE-CC-BY-SA-4.0.txt`
- Test: `test/contracts/plate_attribution_surface_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/plate_attribution_surface_test.dart
//
// CC BY-SA 4.0 requires attribution to reach the recipient of the work. A
// repo-side ATTRIBUTION.md does not ship. This pins that the licence is
// registered with Flutter's own registry and reachable from the UI.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//.*'), '');

void main() {
  test('the plate artwork licence is registered at startup', () {
    final src = _strip(File('lib/main.dart').readAsStringSync());
    expect(src.contains('LicenseRegistry.addLicense'), isTrue,
        reason: 'CC BY-SA artwork ships with no licence registered');
    expect(src.contains('workout-guide') || src.contains('Everkinetic'), isTrue,
        reason: 'the registered licence does not name the source');
  });

  test('the licence text ships as an asset', () {
    expect(File('assets/exercise_plates/LICENSE-CC-BY-SA-4.0.txt').existsSync(),
        isTrue);
  });

  test('a user can reach the credits from the Profile tab', () {
    final hits = Directory('lib/features/profile')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => _strip(f.readAsStringSync()).contains('showLicensePage'))
        .toList();
    expect(hits, isNotEmpty,
        reason: 'the licence page exists but nothing opens it');
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/contracts/plate_attribution_surface_test.dart`
Expected: FAIL on all three.

- [ ] **Step 3: Ship the licence text and register it**

Save the full CC BY-SA 4.0 legal text to `assets/exercise_plates/LICENSE-CC-BY-SA-4.0.txt` (covered by the single pubspec line from Task 2).

In `lib/main.dart`, before `runApp()`:

```dart
  // CC BY-SA 4.0 requires attribution to reach the recipient. The exercise
  // plate artwork is adapted from workout-guide (Bryl Lim), itself traced from
  // Everkinetic. Registering here feeds Flutter's own showLicensePage.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Exercise plate artwork'],
      await rootBundle
          .loadString('assets/exercise_plates/LICENSE-CC-BY-SA-4.0.txt'),
    );
  });
```

Imports: `package:flutter/foundation.dart` (`LicenseRegistry`, `LicenseEntryWithLineBreaks`) and `package:flutter/services.dart` (`rootBundle`).

- [ ] **Step 4: Add the Profile row**

Add a settings row in the Profile tab — matching the existing row widget and Wardroom styling — that calls:

```dart
showLicensePage(
  context: context,
  applicationName: 'ICANBEFITTER',
  applicationLegalese: 'Exercise artwork CC BY-SA 4.0 — workout-guide (Bryl Lim), '
      'traced from Everkinetic.',
);
```

Label it in the Wardroom register — `CREDITS & LICENCES` — not "Open source licenses".

- [ ] **Step 5: Run the test**

Run: `flutter test test/contracts/plate_attribution_surface_test.dart`
Expected: all 3 PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/features/profile/ assets/exercise_plates/LICENSE-CC-BY-SA-4.0.txt test/contracts/plate_attribution_surface_test.dart
sh scripts/safe_commit.sh "feat(plates): ship the CC BY-SA attribution to the user

292 CC BY-SA 4.0 assets were about to ship inside a paid app with no attribution
reaching anyone. The plan claimed Task 1's ATTRIBUTION.md covered the
obligation; a markdown file in the repo is not distributed and discharges
nothing. The app had no credit surface at all — zero hits for showLicensePage,
LicenseRegistry or AboutDialog across lib/.

Registers the licence with Flutter's own registry at startup and adds a Profile
row that opens showLicensePage, so the credit travels with the artwork."
```

---

### Task 9: Track what this batch does not ship

**Files:** `docs/audit/open_issues.md`, `docs/plans/exercise-plates-spec.md`

Terminal states with real numbers, not prose.

- [ ] **Step 1: File the parked work**

- **The 23 split-rule exercises** (`EZ Bar Curl`, `Seated Dumbbell Shoulder Press`, `Weighted Russian Twist`, `Dumbbell Sumo Squat`, and the rest). The spec attributes them to OI-145 — **wrong OI**: `open_issues.md:4334` scopes OI-145 to *34 licence-clean drawings depicting bodyweight exercises the library does not have*, whose enumerated slugs (`clamshell`, `fire-hydrant`, `bird-dog`…) contain none of these. These are equipment variants of rows that already exist. File a new OI citing the selection-skew blocker: a dumbbell user would see both rows of every split pair, doubling that movement's slot probability — OI-146's defect, reproduced 23×.
- **`breathing_cue` numeric on 136 rows.** Both render surfaces are now guarded (Task 7), but the **data** is still wrong. File it with the evidence: exactly 136 rows carry a numeric `breathing_cue` and exactly 136 carry a null `met_value`, intersection 136, zero either side — a spreadsheet column shift. `met_value` is read nowhere in `lib/`.
- **`Donkey Calf Raise` survives in existing installs.** `putAll` never deletes, so the row remains in every already-seeded box after the v11 re-seed. One unreachable row with no drawing; file it so nobody re-derives the discrepancy.
- **The 126 photographs.** Confirm the existing spec section is reflected on the board.

- [ ] **Step 2: Correct the spec's OI citation**

Fix `docs/plans/exercise-plates-spec.md` where it says the 23 belong to OI-145, and note that `Barbell Curl` keeps its name and its `ez-bar-curl` drawing (founder decision, 2026-08-29: renaming would orphan `exlog_*` history, which hashes the exercise name).

- [ ] **Step 3: Commit**

```bash
git add docs/audit/ docs/plans/exercise-plates-spec.md
sh scripts/safe_commit.sh "docs(board): file the plate batch's parked work under real numbers

The spec attributed the 23 split-rule exercises to OI-145, which scopes 34
drawings of bodyweight exercises the library lacks — a different set entirely,
sharing none of these slugs. Naming a real-but-wrong OI reads as tracked and is
worse than naming none.

Also files the numeric breathing_cue data defect (136 rows, exactly matching the
136 with a null met_value — a column shift), and the note that putAll never
deletes, so Donkey Calf Raise survives in already-seeded boxes.

Records the founder decision that Barbell Curl keeps its name and its
ez-bar-curl drawing: renaming would orphan exlog_* history, which hashes the
exercise name."
```

---

### Task 10: Full suite, review, merge

- [ ] **Step 1: Run the full suite**

Run: `flutter test`
Expected: green. Rule 20 makes a red `main` a P0 and bans the label "pre-existing failure".

> A targeted run is a DIFFERENT input set from the suite, not a subset — it cannot create contention. Run the suite once before believing any of these tests. None spawn subprocesses, so none needs a file-level `@Timeout`.

- [ ] **Step 2: Analyze**

Run: `flutter analyze --no-fatal-infos`
Expected: zero warnings. Infos are suppressed; warnings are not, and one fails the push with no useful message from git.

- [ ] **Step 3: Self-initiate the B-pass**

Run: `/code-review`. Required at ≥`account` before the `--no-ff` merge; this batch is `platform`. Do not wait to be asked (§4.3).

**The commit carrying its output needs a same-dated Tuning history bullet in `.claude/skills/code-review/SKILL.md`** — `scripts/check_skill_tuning_history.dart` blocks any commit adding a `docs/reviews/**.md` without one.

- [ ] **Step 4: Write the plan-review record**

`docs/plan-reviews/exercise-plates.md`, with `---` frontmatter (the gate parses `^key:` line-anchored; a bullet header yields null fields and a CI hard-fail):

```markdown
---
branch: exercise-plates
date: <YYYY-MM-DD>
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/exercise-plates-bpass.md
---
```

> ⚠ **`bpass_review:` is mandatory and was missing from the first draft.** `check_plan_review_record_exists.dart:842-865` requires `bpass: accepted` to name a file under `docs/reviews/` that **exists at the merge rev** (`git show <rev>:<path>`, not the working tree) and contains line-anchored `^verdict:\s*accepted$`. Without it the merge fails CI.

- [ ] **Step 5: Walk the §5 close-out — every row, out loud**

Diagnose-doc (n/a, feature not fix) · contract tests (added) · SoT registry (Task 7) · `applied_migrations.json` (n/a, no migration) · root CLAUDE.md (state your answer) · `lib/features/train/CLAUDE.md` (add a plate row) · `docs/architecture/` (state your answer) · feedback memory · project retrospective · harness `MEMORY.md` · **worktree retirement** (`dart run scripts/retire_worktree.dart`, dry-run first, from the PRIMARY worktree) · **skill self-evolution** (§5.1 — the row the first draft omitted).

- [ ] **Step 6: Merge and push**

```bash
cd "C:/Upendra/Claude Code/Fitness App"       # PRIMARY — integration only
sh scripts/safe_merge.sh exercise-plates
sh scripts/safe_push.sh
```

`safe_push.sh` has THREE outcomes: `0` LANDED, `1` FAILED, **`2` UNVERIFIED**. Treating `2` as either is a misreport.

---

## What round 1 changed

A context-blind review of the first draft returned 7 BLOCKER, 15 MAJOR, 16 MINOR. Every claim below was re-verified against the file before acting on it.

**The seven blockers, all real:**

1. **`docs/plans/exercise-plates-mapping.json` existed nowhere.** The plan told an executor to `git add` it; its provenance was two agent fleets whose output lived in a session scratchpad. Every task depended on it. Recovered and committed (`864ca93e`).
2. **Three test files would have thrown, not failed** — `HiveService.init()` calls `Hive.initFlutter()` (`hive_service.dart:76`), which needs the `path_provider` channel mock. All 7 repo tests that call it register one.
3. **`exercise_library_schema_contract_test.dart` pins a closed 38-key set** including all three fields Task 3 removed, with an exact per-row match. Both the additions and the removals turned it red, and nothing repaired it.
4. **`context` is not in scope at `day_detail_sheet.dart:256`** — `_buildWorkoutBody()` takes no `BuildContext` and `itemBuilder: (_, index)` discards it. A compile error.
5. **The pipeline wrote two files per slug unconditionally** — and my own count was wrong in the other direction. Settled: 165 exercises, **153 slugs**, **292 files**.
6. **`monogramFor("Captain's Chair Leg Raise")` returned `CSC`, not `CCL`** — the apostrophe leaves a bare `s`. Fixed in the implementation, not the expectation.
7. **The plan-review record omitted `bpass_review:`**, which the keystone gate hard-requires.

**Two design changes, both improvements rather than patches:**

- **`demo_pair` moved into the library data.** The pair-vs-single rule lived only in Dart, invisible to the Python pipeline, which therefore unioned both frames even for a static hold — cropping a Wall Sit plate to include a standing figure that is never rendered. One field, read by both sides, and the hand-curated exception list becomes data.
- **Assets are flat.** Flutter does not recurse, so a directory-per-slug needs one `pubspec.yaml` line each — and `pubspec.yaml` is `platform`-tier, which would have made every future photograph batch a platform-tier change requiring a ×2 review, contradicting the spec's own "no code" plan for the 126 photographs.

**Three things the plan claimed were covered and were not:** the CC BY-SA attribution never reached a user (Task 8 now exists); `Donkey Calf Raise`'s founder-approved removal had no step (Task 1); the 23 split-rule exercises were attributed to an OI covering a different set (Task 9).

**One §4.2 violation fixed rather than tracked:** the numeric-`breathing_cue` guard now lands in `coaching_content_panel.dart` too — the batch was already editing that file, and shipping a guard on one of two surfaces rendering the same field is the drift class this repo has hit 15+ times.

**Verification widened where round 1 showed it was too narrow:** the shape tests enumerate all 291 rows instead of naming three exercises; the dead-field scan covers `test/` as well as `lib/`; the resolver is tested against a non-String field; the sheet is tested for overflow at 320×480; the thumb is tested with a slug that has no bundled asset.

**Round 1 findings NOT acted on, and why:** the `weighted_bodyweight` logging type matching 0 rows (m12) is moot — shape now comes from `demo_pair`, and the type is never consulted. `backups/gate19_drift_baseline.txt`'s stale entries (m11) and migrations `074`/`125` plus the two seed scripts still naming the dead fields (MAJOR 15) are real; `backups/live_schema_columns.json` holds no `exercise_library` key at all, so nothing server-side breaks. Task 9 files them rather than widening this batch into the seed-generator surface.

## Self-Review

**Spec coverage.** Source and licence → Tasks 2, 8. Frames 1 and 3 only → Task 2. Union crop for pairs, own bounds for holds, no stroke → Task 2. Plate-shape rule → Tasks 1, 3, 5. `demo_slug` delivery → Task 1. `sync_community` guard → recorded in the SoT entry; the guard is add-only and already holds. Placement at three sites → Task 6. Performance → Task 4. Monogram → Task 4. Licence obligations → Task 8. Delivery/bundled → Task 2. Removals → Task 1. Verification table → Tasks 1–7. Process weight → Task 10.

**Deliberately not shipped, each with an owner (Task 9), none of it a deferral:** the 126 photographs (founder's camera; arrive as data plus a version bump), the 23 split-rule exercises (blocked on the selection-skew question), the `breathing_cue` data repair (both render surfaces guarded; the data is a separate fix), and the dead-field references in the seed generators and migrations.

**Placeholder scan.** No TBD/TODO. Every code step carries real code. Four steps deliberately instruct the executor to read a scope before editing (`expandable_day_card`'s exercise variable, `coaching_content_panel`'s name field, the schema test's key-set shape, the Profile row widget) rather than guessing an identifier — instructions, not placeholders.

**Type consistency.** `resolvePlate → ExercisePlate` in Tasks 3, 4, 5. `monogramFor` in Tasks 3, 4. `plateRadiusFor` in Task 4 (both widgets). `ExercisePlateThumb({exerciseName, size, onTap})` in Tasks 4, 6. `ExercisePlateSheet.show(BuildContext, String)` in Tasks 5, 6, 7. Asset paths are `assets/exercise_plates/<slug>-{1,3}.svg` throughout — flat, no directory segment.

**Two of the three claims I had flagged as unverified are now settled**, and one of them was wrong:

- `errorBuilder` **exists** — `flutter_svg-2.2.4/lib/svg.dart:94`. No fallback needed.
- `Barbell Bench Press` does **NOT** have a numeric `breathing_cue` — it reads *"Inhale down, exhale on press"*. The suppression test I had written against it would have failed. `Surya Namaskar` is the numeric row (`"12"`), and the test is now a falsifiable pair: BREATHING renders for the real cue, and does not for the numeric one. Without the positive half, a sheet that never rendered BREATHING at all would have passed.

**The one claim a round-2 reviewer should attack first:** that `exercise_library_schema_contract_test`'s exact-match assertion can accommodate two optional keys without a structural change. Task 1 Step 4 instructs the executor to read `:26-37` rather than assume, but I have not read it closely enough to know what shape the accommodation takes.
