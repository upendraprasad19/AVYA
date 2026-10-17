# Exercise Plates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping an exercise opens a plate — the movement drawn at its start and end (or one drawing for a hold), with the form cues underneath — for the 165 exercises that have artwork, and a monogram for the 127 that do not.

**Architecture:** The adjudicated mapping is committed data (`docs/plans/exercise-plates-mapping.json`). A build-time Python script reads it, crops the vendored upstream SVGs, and writes `assets/exercise_plates/<slug>-{1,3}.svg`. Two new library fields — `demo_slug` and `demo_pair` — carry the drawing and its shape. A pure Dart resolver turns an exercise name into asset paths; three widgets render them. The app never crops, never fetches, and never touches the network.

**Tech Stack:** Flutter, `flutter_svg 2.3.0` (already a dependency), Hive, Riverpod, Python 3 stdlib for the one-time asset pipeline.

**Spec:** `docs/plans/exercise-plates-spec.md`. Task 8 corrects three places where it now contradicts this plan — read both.

**Reviews:** rounds 1 and 2 are incorporated throughout. See "What the reviews changed" at the foot. **This batch was split after round 2** — see immediately below.

---

## ⚠ What this batch NO LONGER does

Removing `Donkey Calf Raise` was bundled here because the spec's arithmetic assumed it. **It is now OI-147**, split out on founder decision 2026-08-29 after review round 2 returned `not converged`.

Three of that round's five blockers came from that one row removal and **none** from the plates feature. A one-row deletion turns out to touch the schema contract's `292`-row assertion, the cloud seed-parity test, a newly-minted seed migration, the `applied_migrations` ledger, a live prod apply needing its own founder go, and the frozen 606-persona generator baseline — which shows the generator *picking that very row*, and for which it is the library's **only bodyweight-tier calf isolation option**.

None of those surfaces are touched by plates. Splitting dissolved all three blockers.

**Consequence for this plan:** the library stays at **292 rows**, and Donkey Calf Raise simply shows a monogram like any other artwork-less exercise. **127 monogram rows, not 126.** This is not a deferral — the removal is tracked with its own terminal outcomes at OI-147 and was never part of this feature.

---

## Global Constraints

- **Branch `exercise-plates`, worktree `.claude/worktrees/exercise-plates`.** Never commit from the primary worktree (§4.13). Commit via `sh scripts/safe_commit.sh "<message>"` — **one positional argument, no flags**; a flag becomes the message. Never raw `git commit`.
- **Blast radius `platform`**, driven by `pubspec.yaml` (`docs/blast_radius.yaml:324`). Requires `docs/plan-reviews/exercise-plates.md` (§4.12.3) and a self-initiated `/code-review` before the `--no-ff` merge (§4.3).
- **Wardroom palette, by NAME only.** `AppColors.accent`, `.card`, `.cardHi`, `.bgRaise`, `.border`, `.textPrimary`, `.textMute`. Never a hex literal — `cardHi` is `#0B172A` and `border` aliases `line2`, a translucent warm white, so prose elsewhere recording opaque navies is wrong. The constant is the only safe reference.
- **Type through `AppTypography`** (rule 10). `mono`/`monoXs` are **JetBrains Mono**; `body`/`bodySm` are DM Sans; `h1`–`h3` Fraunces. Rule 10 means "go through `AppTypography`", not "every style is DM Sans".
- **Dark theme only** (rule 12). **FREE tier** — no `subscription.gate()` anywhere.
- **Import paths:** `package:` for `shared/` and `core/`, relative within a feature (rule 15).
- **`ExerciseData` carries no id** — lookups are by EXACT name via `ExerciseRepository.instance.getByExactName` (`exercise_repository.dart:43`). Never `search()`, which is substring.
- **Never hard-cast a value out of `exerciseBox`.** It also holds community rows written verbatim from Postgres (`lib/core/services/sync/sync_community.dart:499-514`), so any field can be any JSON type. Use `is String` tests, as `coaching_content_panel.dart:73-77` does for the reason at its `:63-64`.
- **Every Hive test needs the `path_provider` mock.** `HiveService.init()` calls `Hive.initFlutter()` (`hive_service.dart:76`), which resolves through `path_provider` and **ignores** `Hive.init()`'s path. Without it you get `MissingPluginException` in `setUpAll` — an error, not a failure. Precedent: `test/rank_service/sd1_wed_joiner_unlocks_day_8_test.dart`. `exerciseBox` is a plain `Box` (`hive_service.dart:211`), not a `GuardedBox`, so no ownership bypass is needed.
- **No deferrals** (§4.2). Every task ends in a terminal state; the closure ledger in Task 9 makes that structural.

## Settled numbers

Re-derived from the committed mapping and the library — verified independently in review round 2.

| | |
|---|---|
| library rows | **292** (unchanged — see the split note above) |
| exercises with a drawing | **165** (148 pair + 17 single) |
| exercises showing a monogram | **127** |
| **distinct slugs** | **153** (139 pair + 14 single) |
| **SVG files generated** | **292** (139×2 + 14×1) |

> ⚠ **165 exercises share 153 slugs.** 12 drawings are referenced by two exercises each. All 12 agree on pair-vs-single (verified; the pipeline hard-fails if that ever stops being true), so the per-slug asset is unambiguous. **A per-exercise count and a per-slug count are different numbers** — conflating them made every file count in the first draft wrong.
>
> ⚠ **Only 4 of those 12 are genuine sharing** (`pull-up`, `hanging-leg-raise`, `cable-fly`, `prone-t-raise`). The other 8 are the duplicate *rows* already filed as **OI-146** — five of which were found by this very drawing-claim collision. Do not describe all 12 as intentional.
>
> ⚠ **292 files equalling 292 rows is a coincidence**, not a derivation.

---

## File Structure

| File | Responsibility |
|---|---|
| `docs/plans/exercise-plates-mapping.json` | **Committed** (`864ca93e`). 165 entries `{id, name, slug, pair}`. This batch's only input. |
| `assets/data/exercise_library.json` | **Modify.** Add `demo_slug` + `demo_pair`; drop the three dead image-URL fields. **No row is removed.** |
| `test/contracts/exercise_library_schema_contract_test.dart` | **Modify.** Required key set 38 → **35**, plus a new 2-key optional set. Row count stays 292. |
| `lib/core/services/seed_service.dart:95` | **Modify.** `_exerciseLibraryVersion` 10 → 11. |
| `lib/core/services/swap_service.dart:294-297` | **Modify.** Delete the dead image-URL copy-through. |
| `scripts/build_exercise_plates.py` | **Create.** Dev tool, never shipped. |
| `assets/exercise_plates/<slug>-{1,3}.svg` | **Create (generated).** 292 files, flat. |
| `pubspec.yaml` | **Modify.** **One** asset line. |
| `.gitignore` + `scripts/retire_worktree_lib.dart` | **Modify.** Ignore `/vendor/`, register it regenerable. |
| `lib/shared/widgets/exercise_plate/{plate_resolver,exercise_monogram,exercise_plate_thumb,exercise_plate_sheet}.dart` | **Create.** |
| `exercise_card.dart` (`:447`), `expandable_day_card.dart` (`:236`), `day_detail_sheet.dart` (`:256`) | **Modify.** Badge → thumb. The Home one needs `BuildContext` threaded. |
| `coaching_content_panel.dart` | **Modify.** Second door + numeric-`breathing_cue` guard. |
| `lib/main.dart` + `lib/features/profile/**` | **Modify.** CC BY-SA attribution surface. |
| `docs/sot_registry.yaml`, `docs/naming_conventions.md`, `docs/plans/exercise-plates-spec.md`, `docs/audit/exercise-plates.closure.yaml` | **Modify/Create.** Registry, glossary, spec corrections, closure ledger. |

---

### Task 1: The library data

**Files:** `assets/data/exercise_library.json`, `test/contracts/exercise_library_schema_contract_test.dart`, `seed_service.dart:95`, `swap_service.dart:294-297`; new `test/contracts/exercise_plate_library_data_test.dart`

**Interfaces:** Consumes the committed mapping. Produces `demo_slug` (`String?`) and `demo_pair` (`bool?`) — both absent ⇒ no artwork.

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/exercise_plate_library_data_test.dart
//
// The version constant is the ONLY thing that delivers a new library field to an
// install that already seeded: seed_service.dart:127-128 re-seeds iff
// stored < constant, so shipping demo_slug WITHOUT bumping it is a silent no-op.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

const _dead = ['image_start_url', 'image_end_url', 'gif_url'];

// This file NAMES the dead fields in source, so the scan below must skip it.
// Round 2 caught the first version scanning itself and failing forever.
const _selfPath = 'exercise_plate_library_data_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('the library is still 292 rows — this batch removes none', () {
    // Donkey Calf Raise stays. Its removal is OI-147, split out after review
    // round 2: it touches the cloud seed migration, a live prod apply and the
    // frozen generator baseline, none of which plates touches.
    expect(lib.length, 292);
    expect(lib.any((e) => e['name'] == 'Donkey Calf Raise'), isTrue);
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

  test('exactly 165 rows carry artwork and 127 do not', () {
    final withArt = lib.where((e) {
      final s = e['demo_slug'];
      return s is String && s.isNotEmpty;
    }).toList();
    expect(withArt.length, 165);
    expect(lib.length - withArt.length, 127);
    for (final e in withArt) {
      expect(e['demo_pair'], isA<bool>(),
          reason: '${e['name']}: demo_slug without demo_pair');
      expect(e['demo_slug'], isNot(contains('/')),
          reason: '${e['name']}: demo_slug is a slug, not a path');
    }
  });

  test('an artwork-less row carries NEITHER key — never a null or empty one', () {
    // Not vacuous: it fails if the writer emits demo_slug: null on 127 rows,
    // which is the obvious way to write the transform wrong.
    final bad = <String>[];
    for (final e in lib) {
      final hasSlug = e.containsKey('demo_slug');
      final hasPair = e.containsKey('demo_pair');
      if (hasSlug != hasPair) bad.add('${e['name']}: one key without the other');
      if (hasSlug && e['demo_slug'] is! String) bad.add('${e['name']}: non-String slug');
      if (hasPair && e['demo_pair'] is! bool) bad.add('${e['name']}: non-bool pair');
    }
    expect(bad, isEmpty, reason: 'omit BOTH keys on an artwork-less row: $bad');
    expect(lib.where((e) => e.containsKey('demo_slug')).length, 165);
  });

  test('the dead image fields are gone from the library', () {
    for (final f in _dead) {
      final hits = lib.where((e) => e.containsKey(f)).map((e) => e['name']).take(3).toList();
      expect(hits, isEmpty, reason: '$f still on rows: $hits');
    }
  });

  test('no Dart source in lib/ or test/ reads the dead fields', () {
    // BOTH trees: a lib/-only scan is structurally blind to
    // exercise_library_schema_contract_test.dart, the file that actually breaks.
    final offenders = <String>[];
    for (final root in const ['lib', 'test']) {
      for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
        final path = f.path.replaceAll(r'\', '/');
        if (!path.endsWith('.dart')) continue;
        if (path.endsWith(_selfPath)) continue;   // this file names them itself
        final src = f.readAsStringSync()
            .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
            .replaceAll(RegExp(r'//.*'), '');
        for (final d in _dead) {
          if (src.contains(d)) offenders.add('$path -> $d');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'still referenced: $offenders');
  });

  // ---- BEHAVIOURAL, not a source grep. The spec's verification table asks for
  // "a seeded box at the old version -> re-seed -> field present", and rule 21
  // says a source grep counts for PRESENCE only. This is the real chain. ----
  group('the version bump actually delivers the field', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('plate_seed');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      await HiveService.instance.init();
    });

    tearDownAll(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        try { tempDir.deleteSync(recursive: true); } catch (_) {}
      }
    });

    test('a box seeded at the OLD version gains demo_slug after re-seed', () async {
      final box = HiveService.instance.exerciseBox;
      await box.clear();
      // Read through a typed Map, never `box.get(id)['k']`. exerciseBox is an
      // untyped `Box` (hive_service.dart:211), so a dynamic index trips
      // avoid_dynamic_calls -- analysis_options.yaml:22 sets it to WARNING, and
      // --no-fatal-infos suppresses infos, not warnings, so the push would be
      // refused with only `error: failed to push some refs` to go on.
      Map<String, dynamic> read(String k) =>
          Map<String, dynamic>.from(box.get(k) as Map);
      // Simulate a v10 install: rows present, but WITHOUT the new fields.
      final stale = Map<String, dynamic>.from(
          lib.firstWhere((e) => e['demo_slug'] != null));
      final id = stale['id'] as String;
      stale.remove('demo_slug');
      stale.remove('demo_pair');
      await box.put(id, stale);
      expect(read(id)['demo_slug'], isNull, reason: 'precondition');

      // The re-seed writes the bundled row over it. This is what putAll does at
      // seed_service.dart:190 -- assert the OUTCOME, not the call.
      final fresh = lib.firstWhere((e) => e['id'] == id);
      await box.putAll({id: fresh});

      expect(read(id)['demo_slug'], isNotNull,
          reason: 'the re-seed did not deliver demo_slug');
      expect(read(id)['demo_pair'], isA<bool>());
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_library_data_test.dart`
Expected: FAIL on the version test, the mapping test, the 165/127 test, the neither-key test, both dead-field tests, and the behavioural test. The "still 292 rows" test PASSES today — that is correct; it is a *guard against the split being undone*, not a change this task makes.

- [ ] **Step 3: Apply the mapping and strip the dead fields**

```bash
python - <<'EOF'
import json, io
LIB = "assets/data/exercise_library.json"
lib = json.load(io.open(LIB, encoding="utf-8"))
mapping = json.load(io.open("docs/plans/exercise-plates-mapping.json", encoding="utf-8"))
by_id = {m["id"]: m for m in mapping}

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
    # else: emit NEITHER key. An explicit `demo_slug: None` would make 127 rows
    # carry a key the schema test treats as present.

json.dump(lib, io.open(LIB, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("rows %d (unchanged), artwork on %d, monogram on %d"
      % (len(lib), art, len(lib) - art))
EOF
```

Expected: `rows 292 (unchanged), artwork on 165, monogram on 127`.

- [ ] **Step 4: Update the schema contract — the literal diff**

`test/contracts/exercise_library_schema_contract_test.dart` has **five** tests (`:31, :35, :49, :60, :68`). `:35-47` asserts an exact per-row key match:

```dart
final missing = _canonicalKeys.difference(keys);
final extra   = keys.difference(_canonicalKeys);
```

All 292 rows currently carry the identical 38 keys. After Step 3, 165 rows carry 37 and **127 carry 35**. The two new keys therefore cannot join `_canonicalKeys` — `missing` would fire on 127 rows. Counted from the literal at `:14-24`: 38 keys, minus the three dead ones, is **35 required**.

Replace `:14-24` and `:31-47` with exactly this:

```dart
// 38 - 3 dead image URL fields = 35 keys required on EVERY row.
const _canonicalKeys = <String>{
  'id', 'name', 'category', 'movement_pattern', 'exercise_type', 'primary_muscles',
  'secondary_muscles', 'equipment_needed', 'logging_type', 'difficulty_level',
  'suitable_for', 'default_sets', 'default_reps', 'default_rest_secs', 'tempo',
  'met_value', 'cal_per_set_est', 'breathing_cue', 'coaching_cues', 'common_mistakes',
  'warmup_protocol', 'pro_tip', 'is_indian_context', 'indian_alternative', 'source',
  'is_active', 'is_foundational',
  'injury_contraindications', 'is_bilateral', 'cns_demand', 'target_focus',
  'equipment_tier', 'standard_swap', 'priority_tier', 'rep_range',
};

// Exercise plates (v11): present on the 165 rows with a drawing, absent on the
// other 127. They CANNOT be canonical — `missing` would fire on every
// artwork-less row — and they cannot be ignored either, or a typo'd key would
// slip through `extra`. Hence a second set, and a union on the `extra` side.
const _optionalKeys = <String>{'demo_slug', 'demo_pair'};
```

```dart
    test('the canonical schema is 35 required keys plus 2 optional', () {
      expect(_canonicalKeys.length, 35);
      expect(_optionalKeys.length, 2);
    });

    test('every row carries EXACTLY the 35 required keys and nothing outside '
        'the union with the optional two (blocks stub-shaped rows)', () {
      final offenders = <String>[];
      final allowed = _canonicalKeys.union(_optionalKeys);
      for (final r in rows) {
        final keys = r.keys.toSet();
        final missing = _canonicalKeys.difference(keys);
        final extra = keys.difference(allowed);
        if (missing.isNotEmpty || extra.isNotEmpty) {
          offenders.add('${r['id']}: missing=$missing extra=$extra');
        }
      }
      expect(offenders, isEmpty,
          reason: 'Rows deviating from the 35-key canonical schema:\n'
              '${offenders.join('\n')}');
    });
```

**Leave `:49-88` untouched** — the `injury_contraindications`, `primary_muscles` and `292 rows, ids unique` tests all still hold, because this batch removes no row. Round 2 caught an earlier version of this plan changing the key set, miscounting the file as four tests, and never noticing the row-count assertion.

- [ ] **Step 5: Bump the version and delete the copy-through**

In `seed_service.dart`, above line 95:

```dart
  // v11 (exercise plates): demo_slug + demo_pair on 165 rows; the three dead
  // image URL fields removed. Re-seed rewrites every row in place via putAll.
  static const int _exerciseLibraryVersion = 11;
```

In `swap_service.dart`, delete lines 294-297 — the four lines copying `image_start_url`/`image_end_url` through a swap. A swapped exercise resolves its plate by name like any other.

- [ ] **Step 6: Run both files**

Run: `flutter test test/contracts/exercise_plate_library_data_test.dart test/contracts/exercise_library_schema_contract_test.dart`
Expected: all green — 8 new plus the schema contract's **5**.

- [ ] **Step 7: Commit**

```bash
git add assets/data/exercise_library.json test/contracts/ lib/core/services/seed_service.dart lib/core/services/swap_service.dart
sh scripts/safe_commit.sh "feat(plates): demo_slug + demo_pair on 165 rows, seed version 10 -> 11

The version bump is what delivers the fields: seed_service.dart:127-128 re-seeds
only when stored < constant, so adding them without it would be a silent no-op
and no existing install would receive them. Proven behaviourally -- a box seeded
without the fields, re-seeded, then read back -- not by grepping the constant,
which rule 21 says counts for presence only.

demo_pair carries the plate SHAPE in the data rather than a Dart constant, so
the Python asset pipeline and the Dart renderer read one field instead of
duplicating a rule across a language boundary.

An artwork-less row carries NEITHER key rather than a null one: the schema
contract asserts an exact per-row key match, so a null would read as present on
127 rows. That test's required set goes 38 -> 35 with a separate 2-key optional
set; its 292-row assertion is untouched because this batch removes no row.

Removes the three dead image URL fields, whose only reader was a copy-through in
swap_service that nothing then rendered."
```

---

### Task 2: Vendor the artwork, crop it, ship 292 SVGs

**Files:** `scripts/build_exercise_plates.py`, `assets/exercise_plates/*`, `docs/plans/exercise-plates-manifest.json`, `pubspec.yaml`, `.gitignore`, `scripts/retire_worktree_lib.dart`; test `test/contracts/exercise_plate_assets_present_test.dart`

**Interfaces:** Consumes `demo_slug` + `demo_pair`. Produces `<slug>-1.svg` (always) and `<slug>-3.svg` (pair slugs only).

> **Assets are FLAT.** Flutter does not recurse, so directory-per-slug needs one `pubspec.yaml` line **each** — and `pubspec.yaml` is `platform`-tier, which would make every future photograph batch a platform-tier change requiring a ×2 review, contradicting the spec's "data change plus a version bump, no code" plan for the 127 photographs. Verified collision-free: all 153 slugs match `^[a-z0-9]+(-[a-z0-9]+)*$`, none ends in `-1`/`-3`, 292 filenames all unique.

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
  final conflicts = <String>[];
  for (final e in lib) {
    final s = e['demo_slug'];
    if (s is! String || s.isEmpty) continue;
    final pair = e['demo_pair'] == true;
    if (slugs.containsKey(s) && slugs[s] != pair) conflicts.add(s);
    slugs[s] = pair;
  }

  test('no slug is claimed as both pair and single', () {
    // The pipeline hard-fails on this; assert it here too, because a
    // last-write-wins map would otherwise hide it on the Dart side.
    expect(conflicts, isEmpty);
  });

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
      if (entry.value && !three.existsSync()) wrong.add('${entry.key}-3.svg missing (pair)');
      if (!entry.value && three.existsSync()) {
        wrong.add('${entry.key}-3.svg present but the exercise is a hold');
      }
    }
    expect(wrong, isEmpty, reason: 'asset shape drift: $wrong');
  });

  test('exactly 292 SVGs ship — no orphans left by a rename', () {
    final dir = Directory('assets/exercise_plates');
    expect(dir.existsSync(), isTrue, reason: 'run the pipeline first');
    final files = dir.listSync().whereType<File>()
        .where((f) => f.path.endsWith('.svg')).toList();
    expect(files.length, 292);
  });

  test('paired frames share one viewBox', () {
    final vb = RegExp(r'viewBox="([^"]+)"');
    final drift = <String>[];
    for (final entry in slugs.entries.where((e) => e.value)) {
      final a = File('assets/exercise_plates/${entry.key}-1.svg').readAsStringSync();
      final b = File('assets/exercise_plates/${entry.key}-3.svg').readAsStringSync();
      final va = vb.firstMatch(a)?.group(1);
      if (va != vb.firstMatch(b)?.group(1)) drift.add(entry.key);
    }
    expect(drift, isEmpty, reason: 'frames would jump size: $drift');
  });

  test('every frame is tintable and unsized', () {
    for (final entry in slugs.entries) {
      final names = ['${entry.key}-1.svg', if (entry.value) '${entry.key}-3.svg'];
      for (final n in names) {
        final t = File('assets/exercise_plates/$n').readAsStringSync();
        expect(t.contains('fill="currentColor"'), isTrue, reason: '$n not tintable');
        expect(RegExp(r'<svg[^>]*\s(width|height)=').hasMatch(t), isFalse,
            reason: '$n pins a size and will not scale');
      }
    }
  });

  test('every shipped slug exists in the upstream manifest', () {
    final f = File('docs/plans/exercise-plates-manifest.json');
    expect(f.existsSync(), isTrue, reason: 'copy the manifest in Step 3 first');
    final man = (jsonDecode(f.readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final upstream = man.map((e) => e['slug'] as String).toSet();
    expect(slugs.keys.toSet().difference(upstream), isEmpty,
        reason: 'demo_slug values with no upstream drawing');
  });
}
```

> Two of these tests **error rather than fail** before Step 3/5 (no directory, no manifest). That is why each opens with an `existsSync` expectation naming the step that creates it — an error with a useful message beats a stack trace.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_assets_present_test.dart`
Expected: the two slug-set tests PASS (Task 1 landed the data); the five file/manifest tests FAIL with the "run the pipeline first" / "copy the manifest first" reasons.

- [ ] **Step 3: Vendor the upstream catalogue**

[workout-guide](https://github.com/bryllim/workout-guide) by Bryl Lim, CC BY-SA 4.0, traced from [Everkinetic](https://github.com/everkinetic/data). 302 exercises × 3 frames = 906 SVGs.

```bash
mkdir -p vendor
git clone --depth 1 https://github.com/bryllim/workout-guide vendor/workout-guide
git -C vendor/workout-guide rev-parse HEAD              # RECORD this sha
find vendor/workout-guide -name manifest.json           # note the path
find vendor/workout-guide -name 'frame-1.svg' | head -1 # note the assets root
```

The spec records `packages/workout-guide/assets/<slug>/frame-N.svg` with `manifest.json` one level **above** the assets. Confirm against `find`; do not assume.

Add to `.gitignore`:

```
# Upstream plate artwork — cloned by scripts/build_exercise_plates.py.
# Only the cropped output under assets/exercise_plates/ is committed.
/vendor/
```

**Register `vendor/` as regenerable** in `scripts/retire_worktree_lib.dart`'s `regenerableIgnoredPaths` (`:236-270`):

```dart
  'vendor/',   // .gitignore: cloned upstream plate artwork, re-clonable
```

> ⚠ Without this the worktree is **permanently unretirable**: leg 3 keeps any worktree holding a non-regenerable ignored file, and `:281-284` treats anything not on the list as precious. Exactly the recurrence §5 warns about (diagnose `b4d7e9`, OI-128). Verified: `git status --porcelain --ignored=matching` emits a wholly-ignored directory as one collapsed `vendor/` entry, which is what this exact-match list compares against.

Copy the manifest in and verify its shape — **the plan assumes a top-level array of objects with a `frames` list and a `slug`, and nothing has ever verified that**, because the catalogue has never been cloned here:

```bash
cp <manifest-path> docs/plans/exercise-plates-manifest.json
python -c "
import json, io
m = json.load(io.open('docs/plans/exercise-plates-manifest.json', encoding='utf-8'))
assert isinstance(m, list) and isinstance(m[0], dict), 'not a top-level array of objects'
assert all('slug' in e and isinstance(e.get('frames'), list) for e in m), 'shape drift'
print('entries:', len(m))
print('frames :', sum(len(e['frames']) for e in m))
print('formats:', {f['format'] for e in m for f in e['frames']})
"
```

Expected: `entries: 302`, `frames: 906`, `formats: {'svg'}`. **If the shape or counts differ, STOP** — the mapping was adjudicated against a 302-entry catalogue.

**All of this was RUN on 2026-08-29** against upstream `aac599224bb9780305239607ef98540b7e0ce389`, so what follows is measurement, not hope. Confirmed: the manifest is a top-level array of 302 objects each carrying `slug` and a `frames` list; 906 frames, every one `format: "svg"`; the layout is exactly `packages/workout-guide/assets/<slug>/frame-N.svg`; **all 153 of our slugs exist**, and every pair slug has its `frame-3.svg`.

Across the 292 files we actually read: **every viewBox is `0 0 512 512`**, there are **zero** `transform=` attributes, **zero** non-`<path>` primitives, exactly **one `<path>` per file**, and every file carries a convertible white fill. So none of `ink_bbox`'s structural guards fires on today's catalogue — they exist for the day upstream changes, which is what Step 1's manifest test is also for.

⚠ **One thing the recon overturned, and it was a blocker.** An earlier draft hard-failed on path commands `A`/`S`/`T` on the theory they were exotic. They are not: **all 292 files use them**, and `s` alone appears **20,917 times**. That version would have processed zero drawings while reading as a careful, well-guarded tool. The pipeline below implements them — which is the difference between a guard and a refusal. Arcs needed the W3C endpoint→centre conversion; bounding one by its chord box expanded by its radii was tried first and is worthless, because a near-straight arc carries an enormous radius (bench-press came out **59637×59602** on a 512 canvas, and 199 of 292 files landed off the artboard).

Validated against the rasters from the founder review: bench-press frame 1 gives `(30.0, 38.0, 419.3, 482.9)` against the raster's `(30, 38, 420, 482)` — **0.9 units of slack**. Generating for real produced **292 files, 6.64 MB raw / 2.83 MB deflated**, no paired viewBox drift, and a median crop of **47% of the canvas → the figure renders ~1.45× larger** in the same box.

- [ ] **Step 4: Write the pipeline**

```python
# scripts/build_exercise_plates.py
"""Crop the vendored workout-guide SVGs into app plate assets.

Run once after vendoring; the OUTPUT is committed, the vendored source is not.
Reads demo_slug + demo_pair from the exercise library and emits
assets/exercise_plates/<slug>-1.svg (always) and -3.svg (pairs only).

VALIDATED against the real catalogue 2026-08-29 (upstream
aac599224bb9780305239607ef98540b7e0ce389): 292 files for 153 slugs, 0 errors,
6.64 MB raw / 2.83 MB deflated, no paired viewBox drift.

WHY the bbox comes from PATH DATA and not a raster: upstream ships SVG only --
all 906 frames in its manifest are format "svg" -- and no rasterizer is
installed here. Pure stdlib, no native Cairo dependency, reproducible in CI.

WHY THE FULL COMMAND SET IS IMPLEMENTED rather than hard-failed: an earlier
draft raised on A/S/T on the theory they were rare. Measured against the 292
files we actually ship, EVERY ONE uses them -- 's' alone appears 20,917 times --
so that version could not have processed a single file.

  C/Q/S/T are EXACT. A bezier lies inside the convex hull of its control points,
  so collecting on-curve AND control points yields a superset of the true ink
  bbox: loose at worst, never clipping. S and T reconstruct the implied control
  point by reflection, which is arithmetic, not approximation.

  A (arc) is converted from SVG endpoint parameterisation to centre
  parameterisation (W3C implementation notes F.6.5) and sampled across its real
  sweep. Bounding an arc by its chord box expanded by (rx, ry) was tried and is
  WORTHLESS in practice -- a nearly-straight arc is encoded with an enormous
  radius, which blew bench-press up to 59637x59602 on a 512 canvas and put 199
  of 292 files outside the artboard. Do not re-propose it.

  GROUND TRUTH: against the rasters used for the founder review, bench-press
  frame 1 gives (30.0, 38.0, 419.3, 482.9) vs the raster's (30, 38, 420, 482) --
  worst-edge slack 0.9 units on a 512 canvas -- and frame 3 gives 0.5.

WHY a PAIR is cropped to the UNION and a SINGLE to its own bounds: cropping each
frame of a pair separately makes the body change size between START and END
(bench press is 390x444 then 431x397). But a HOLD renders frame 1 alone, so
unioning it with an unrendered frame 3 pollutes the viewBox -- for Wall Sit,
frame 3 is the athlete standing up, and the union would shrink the seated pose
to a fraction of the plate. demo_pair tells them apart.

WHY no stroke: at matched display size a stroke closes the interior gaps --
median gap 17 -> 13 units at width 4, 6% closed outright. The crop is the fix.
Over all 292 shipping files the cropped viewBox is a median 47% of the canvas
area, so the figure renders about 1.45x larger in the same box.
"""
import io, os, re, json, math, sys

ARC_SAMPLES = 24
PAD = 10
CANVAS = 512
EXPECTED_VIEWBOX = "0 0 512 512"
SRC = sys.argv[1] if len(sys.argv) > 1 else "vendor/workout-guide/packages/workout-guide/assets"
OUT = "assets/exercise_plates"

NUM = re.compile(r"[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?")
CMD = re.compile(r"([MmZzLlHhVvCcSsQqTtAa])")
NON_PATH = re.compile(r"<(circle|rect|ellipse|polygon|polyline|use|image|text)\b")


def _arc_points(x1, y1, rx, ry, phi_deg, fa, fs, x2, y2):
    """W3C F.6.5 endpoint -> centre parameterisation, then sample the sweep."""
    if rx == 0 or ry == 0 or (x1 == x2 and y1 == y2):
        return [(x2, y2)]
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(phi_deg % 360.0)
    cp, sp = math.cos(phi), math.sin(phi)

    dx2, dy2 = (x1 - x2) / 2.0, (y1 - y2) / 2.0
    x1p = cp * dx2 + sp * dy2
    y1p = -sp * dx2 + cp * dy2

    # F.6.6 -- scale the radii up if they cannot span the chord
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:
        s = math.sqrt(lam)
        rx *= s
        ry *= s

    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    co = 0.0 if den == 0 else math.sqrt(max(0.0, num / den))
    if fa == fs:
        co = -co
    cxp = co * rx * y1p / ry
    cyp = -co * ry * x1p / rx

    cx = cp * cxp - sp * cyp + (x1 + x2) / 2.0
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2.0

    def ang(ux, uy, vx, vy):
        d = math.hypot(ux, uy) * math.hypot(vx, vy)
        if d == 0:
            return 0.0
        c = max(-1.0, min(1.0, (ux * vx + uy * vy) / d))
        a = math.acos(c)
        return -a if (ux * vy - uy * vx) < 0 else a

    ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
    vx, vy = (-x1p - cxp) / rx, (-y1p - cyp) / ry
    th1 = ang(1.0, 0.0, ux, uy)
    dth = ang(ux, uy, vx, vy)
    if not fs and dth > 0:
        dth -= 2 * math.pi
    elif fs and dth < 0:
        dth += 2 * math.pi

    out = []
    for i in range(ARC_SAMPLES + 1):
        th = th1 + dth * (i / float(ARC_SAMPLES))
        ct, st = math.cos(th), math.sin(th)
        out.append((cx + rx * ct * cp - ry * st * sp,
                    cy + rx * ct * sp + ry * st * cp))
    return out


def path_points(d, where):
    """Every on-curve point, every control point, and sampled arc points."""
    toks = [t for t in CMD.split(d) if t.strip()]
    pts = []
    cx = cy = sx = sy = 0.0
    pc2 = None   # previous cubic control-2, for S reflection
    pq = None    # previous quadratic control, for T reflection
    cmd = None
    i = 0
    while i < len(toks):
        t = toks[i]
        if CMD.fullmatch(t):
            cmd = t
            i += 1
            if cmd in "Zz":
                cx, cy = sx, sy
                pc2 = pq = None
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
                pts.append((cx, cy)); pc2 = pq = None
                c = "l" if rel else "L"          # implicit lineto after moveto
            elif C == "L":
                x, y = nums[j:j + 2]; j += 2
                cx, cy = (cx + x, cy + y) if rel else (x, y)
                pts.append((cx, cy)); pc2 = pq = None
            elif C == "H":
                x = nums[j]; j += 1
                cx = cx + x if rel else x
                pts.append((cx, cy)); pc2 = pq = None
            elif C == "V":
                y = nums[j]; j += 1
                cy = cy + y if rel else y
                pts.append((cx, cy)); pc2 = pq = None
            elif C == "C":
                a = nums[j:j + 6]; j += 6
                p = [(cx + a[k], cy + a[k + 1]) if rel else (a[k], a[k + 1])
                     for k in (0, 2, 4)]
                pts.extend(p); pc2 = p[1]; cx, cy = p[2]; pq = None
            elif C == "S":
                a = nums[j:j + 4]; j += 4
                # implied control 1 = reflection of the previous cubic's control
                # 2 about the current point; the current point itself when the
                # previous command was not C/S.
                r = (2 * cx - pc2[0], 2 * cy - pc2[1]) if pc2 else (cx, cy)
                p2 = (cx + a[0], cy + a[1]) if rel else (a[0], a[1])
                e = (cx + a[2], cy + a[3]) if rel else (a[2], a[3])
                pts.extend([r, p2, e]); pc2 = p2; cx, cy = e; pq = None
            elif C == "Q":
                a = nums[j:j + 4]; j += 4
                p = [(cx + a[k], cy + a[k + 1]) if rel else (a[k], a[k + 1])
                     for k in (0, 2)]
                pts.extend(p); pq = p[0]; cx, cy = p[1]; pc2 = None
            elif C == "T":
                a = nums[j:j + 2]; j += 2
                r = (2 * cx - pq[0], 2 * cy - pq[1]) if pq else (cx, cy)
                e = (cx + a[0], cy + a[1]) if rel else (a[0], a[1])
                pts.extend([r, e]); pq = r; cx, cy = e; pc2 = None
            elif C == "A":
                a = nums[j:j + 7]; j += 7
                ex, ey = (cx + a[5], cy + a[6]) if rel else (a[5], a[6])
                pts.extend(_arc_points(cx, cy, a[0], a[1], a[2],
                                       a[3] != 0, a[4] != 0, ex, ey))
                cx, cy = ex, ey; pc2 = pq = None
            else:
                raise ValueError("%s: unhandled command %r" % (where, c))
        i += 1
    return pts


def ink_bbox(p):
    """Ink bounds, with the structural guards. Anything the parser cannot see
    HARD-FAILS rather than silently cropping through the drawing."""
    t = io.open(p, encoding="utf-8").read()

    vb = re.search(r'viewBox="([^"]*)"', t)
    if not vb:
        raise ValueError("%s: no viewBox" % p)
    if " ".join(vb.group(1).split()) != EXPECTED_VIEWBOX:
        raise ValueError("%s: viewBox is %r, expected %r -- union() clamps to "
                         "CANVAS=%d and would truncate this frame"
                         % (p, vb.group(1), EXPECTED_VIEWBOX, CANVAS))
    if re.search(r"\stransform=", t):
        raise ValueError("%s: has a transform=; the bbox would be computed in "
                         "the wrong coordinate space" % p)
    m = NON_PATH.search(t)
    if m:
        raise ValueError("%s: contains <%s>, whose geometry the path parser "
                         "cannot see; the crop would cut through it silently"
                         % (p, m.group(1)))

    pts = []
    for d in re.findall(r'\sd="([^"]+)"', t):
        pts += path_points(d, p)
    if not pts:
        raise ValueError("no path data: %s" % p)
    xs = [q[0] for q in pts]
    ys = [q[1] for q in pts]
    return min(xs), min(ys), max(xs), max(ys)


def union(boxes):
    x0 = max(0, min(b[0] for b in boxes) - PAD)
    y0 = max(0, min(b[1] for b in boxes) - PAD)
    x1 = min(CANVAS, max(b[2] for b in boxes) + PAD)
    y1 = min(CANVAS, max(b[3] for b in boxes) + PAD)
    return round(x0), round(y0), round(x1 - x0), round(y1 - y0)


def crop_svg(text, view_box, where):
    t = re.sub(r"<\?xml[^>]*\?>", "", text)
    # [^"]* not \d+ -- "512.0" or "512px" would survive a digits-only strip and
    # then fail the assets test with no repair step.
    t = re.sub(r'\swidth="[^"]*"', "", t, count=1)
    t = re.sub(r'\sheight="[^"]*"', "", t, count=1)
    t, n = re.subn(r'viewBox="[^"]*"', 'viewBox="%d %d %d %d"' % view_box, t, count=1)
    if n != 1:
        raise ValueError("%s: no viewBox to rewrite" % where)
    for lit in ('fill="#fff"', 'fill="#FFF"', 'fill="#ffffff"', 'fill="#FFFFFF"',
                'fill="white"', 'fill="WHITE"'):
        t = t.replace(lit, 'fill="currentColor"')
    if 'fill="currentColor"' not in t:
        raise ValueError("%s: no white fill found to convert (a style= or an "
                         "inherited fill is not handled)" % where)
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
    written = set()
    for slug, pair in sorted(slugs.items()):
        frames = ["1", "3"] if pair else ["1"]
        srcs = [os.path.join(SRC, slug, "frame-%s.svg" % f) for f in frames]
        for f in srcs:
            if not os.path.exists(f):
                raise SystemExit("missing upstream frame: %s" % f)
        vb = union([ink_bbox(f) for f in srcs])
        for src, f in zip(srcs, frames):
            name = "%s-%s.svg" % (slug, f)
            io.open(os.path.join(OUT, name), "w", encoding="utf-8").write(
                crop_svg(io.open(src, encoding="utf-8").read(), vb, name))
            written.add(name)

    # A renamed slug leaves an orphan the 292-file test would catch later; say
    # so HERE, where the fix is obvious.
    stale = {f for f in os.listdir(OUT) if f.endswith(".svg")} - written
    if stale:
        raise SystemExit("stale SVGs from an earlier run: %s\n"
                         "delete them -- the asset test counts files"
                         % sorted(stale)[:5])

    print("wrote %d files for %d slugs (%d pair, %d single)"
          % (len(written), len(slugs),
             sum(1 for v in slugs.values() if v),
             sum(1 for v in slugs.values() if not v)))


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Generate and declare**

Run: `python scripts/build_exercise_plates.py`
Expected: `wrote 292 files for 153 slugs (139 pair, 14 single)`.

In `pubspec.yaml`, under `assets:` (line 129), add **one** line:

```yaml
    - assets/exercise_plates/
```

Create `assets/exercise_plates/ATTRIBUTION.md` with the Step 3 sha:

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

Redistributed under the same licence. Per-frame creator and Everkinetic source for
every drawing is preserved in `docs/plans/exercise-plates-manifest.json`.

⚠ This file documents the obligation; it does not DISCHARGE it. It ships inside the
APK (the flat asset line bundles the whole directory) but no user will ever open it.
**Task 8 is what puts the attribution in front of a person.**
```

- [ ] **Step 6: Run the test**

Run: `flutter test test/contracts/exercise_plate_assets_present_test.dart`
Expected: all 7 PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/build_exercise_plates.py scripts/retire_worktree_lib.dart assets/exercise_plates pubspec.yaml .gitignore docs/plans/exercise-plates-manifest.json test/contracts/exercise_plate_assets_present_test.dart
sh scripts/safe_commit.sh "feat(plates): vendor the artwork and ship 292 cropped plate SVGs

A PAIR is cropped to the union of both frames so the figure cannot change size
between START and END. A HOLD is cropped to frame 1's own bounds, because it
renders frame 1 alone and unioning it with an unrendered frame 3 pollutes the
viewBox -- for Wall Sit frame 3 is the athlete standing up. demo_pair tells them
apart, in the data, so Python and Dart read one field.

The bbox comes from path data, not a raster: upstream ships SVG only and no
rasterizer is installed. A bezier lies inside the hull of its control points, so
the bbox over on-curve plus control points is a superset -- loose at worst,
never clipping. Checked against the review rasters: 389x445 vs 390x444, 430x397
vs 431x397.

That guarantee is conditional and every exclusion HARD-FAILS rather than
miscropping: arcs, smooth curves, transforms, a non-512 source viewBox, and
non-<path> primitives -- ink_bbox reads only d= attributes, so a <circle> would
contribute nothing and the crop would cut straight through it with no error.

Assets are FLAT, one pubspec line, because pubspec.yaml is platform-tier and a
line per slug would make every future photograph batch a platform-tier change.

vendor/ is registered regenerable in retire_worktree_lib, or leg 3 of the
retirement predicate would keep this worktree forever (diagnose b4d7e9)."
```

---

### Task 3: The plate resolver

**Files:** `lib/shared/widgets/exercise_plate/plate_resolver.dart`; test `test/contracts/exercise_plate_resolver_test.dart`

**Interfaces:** Consumes `ExerciseRepository.instance.getByExactName`. Produces `ExercisePlate`, `resolvePlate(String)`, `monogramFor(String)`.

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
    // REQUIRED: HiveService.init() calls Hive.initFlutter(), which resolves via
    // path_provider and IGNORES Hive.init()'s path. Without this the file
    // throws MissingPluginException in setUpAll -- an error, not a failure.
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

  // ---- ENUMERATED, not sampled. ----
  test('every row with artwork resolves to the frames demo_pair declares', () {
    final bad = <String>[];
    for (final e in lib) {
      final slug = e['demo_slug'];
      if (slug is! String || slug.isEmpty) continue;
      final p = resolvePlate(e['name'] as String);
      if (!p.hasArtwork) { bad.add('${e['name']}: no artwork'); continue; }
      if (p.slug != slug) bad.add('${e['name']}: slug ${p.slug} != $slug');
      if (p.isPair != (e['demo_pair'] == true)) bad.add('${e['name']}: pair drift');
      if (p.assetPaths.length != (e['demo_pair'] == true ? 2 : 1)) {
        bad.add('${e['name']}: ${p.assetPaths.length} paths');
      }
      if (p.assetPaths.first != 'assets/exercise_plates/$slug-1.svg') {
        bad.add('${e['name']}: bad path ${p.assetPaths.first}');
      }
    }
    expect(bad, isEmpty, reason: 'shape drift on ${bad.length} rows: ${bad.take(5)}');
  });

  test('every row WITHOUT artwork resolves to a monogram and no paths', () {
    var checked = 0;
    for (final e in lib) {
      if (e.containsKey('demo_slug')) continue;
      checked++;
      final p = resolvePlate(e['name'] as String);
      expect(p.hasArtwork, isFalse, reason: '${e['name']} claims artwork');
      expect(p.assetPaths, isEmpty);
      expect(p.monogram, isNotEmpty);
    }
    expect(checked, 127, reason: 'the artwork-less set is 127 rows');
  });

  test('an unknown name never throws and never claims artwork', () {
    final p = resolvePlate('Totally Invented Exercise');
    expect(p.hasArtwork, isFalse);
    expect(p.monogram, 'TIE');
  });

  test('lookup is EXACT, never substring', () {
    // Both rows must exist or this passes vacuously on null == null.
    expect(lib.map((e) => e['name']).toSet(),
        containsAll(<String>['Push Up', 'Pike Push Up']));
    expect(resolvePlate('Push Up').slug,
        isNot(equals(resolvePlate('Pike Push Up').slug)));
  });

  test('a non-String demo_slug is ignored, not cast', () {
    // Community rows are written verbatim from Postgres
    // (lib/core/services/sync/sync_community.dart:499) and carry any JSON type.
    HiveService.instance.exerciseBox.put('ZTEST', {
      'id': 'ZTEST', 'name': 'Ztest Bogus Row', 'demo_slug': 42, 'demo_pair': 'yes',
    });
    expect(resolvePlate('Ztest Bogus Row').hasArtwork, isFalse);
  });

  group('monogramFor', () {
    test('takes the initial of up to three significant words', () {
      expect(monogramFor('Barbell Bench Press'), 'BBP');
      expect(monogramFor('Push Up'), 'PU');
    });

    test('strips the POSSESSIVE, and nothing else', () {
      // The bug was "Captain's" -> [Captain, s] contributing a bare S.
      expect(monogramFor("Captain's Chair Leg Raise"), 'CCL');
      expect(monogramFor("Child's Pose"), 'CP');
      expect(monogramFor("World's Greatest Stretch"), 'WGS');
    });

    test('KEEPS genuine one-letter words', () {
      // A length filter "fixed" the 3 possessives and broke 9 real names --
      // V-Up -> U, Z Press -> P, T-Bar Row -> BR, and Prone Y/T/W Raise all
      // collapsing to PR. The possessive is the signal, not the length.
      expect(monogramFor('V-Up'), 'VU');
      expect(monogramFor('V-Ups'), 'VU');
      expect(monogramFor('Z Press'), 'ZP');
      expect(monogramFor('T-Bar Row'), 'TBR');
      expect(monogramFor('L-Sit Hold'), 'LSH');
      expect(monogramFor('B-Stance RDL'), 'BSR');
      expect(monogramFor('Prone Y Raise'), 'PYR');
      expect(monogramFor('Prone T Raise'), 'PTR');
      expect(monogramFor('Prone W Raise'), 'PWR');
    });

    test('drops punctuation and stop words', () {
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
// Name -> plate. No Flutter imports, so the logic is separable from any widget
// harness -- but note resolvePlate DOES read Hive, so its tests still need the
// binding and the path_provider mock. Only monogramFor is genuinely pure.
//
// Plate SHAPE comes from the library's `demo_pair` field, NOT a constant here.
// It used to be a logging_type rule plus a hand-curated exception list, so the
// asset pipeline (Python) and the renderer (Dart) each held half of one
// decision with nothing keeping them in sync.
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

const Set<String> _monogramStopWords = {'the', 'a', 'of', 'with', 'to', 'and'};

/// Trailing possessive, straight or curly. Removed BEFORE punctuation becomes
/// whitespace, so it never survives as a bare "s" token.
final RegExp _possessive = RegExp(r"['\u2019]s\b", caseSensitive: false);

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
/// It does NOT identify — three letters collide across the library ('SS' is
/// shared by five exercises). Its only job is to make an artwork-less slot look
/// deliberate; the exercise name renders beside it.
String monogramFor(String name) {
  // Strip the possessive FIRST. Doing it by word length instead — which is the
  // obvious-looking fix — silently breaks every genuine one-letter word:
  // V-Up -> U, Z Press -> P, T-Bar Row -> BR, and Prone Y/T/W Raise all
  // collapsing to the same PR. Measured over all 292 names: the length filter
  // changes 12 -- the 3 possessives it gets right, and 9 one-letter words it
  // gets wrong. The possessive regex changes exactly those 3.
  final words = name
      .replaceAll(_possessive, '')
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
Expected: all 10 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/exercise_plate/plate_resolver.dart test/contracts/exercise_plate_resolver_test.dart
sh scripts/safe_commit.sh "feat(plates): the plate resolver — name to assets and shape

Shape comes from the library's demo_pair field, not a constant here, so the
Python pipeline and the Dart renderer read one field instead of each holding
half a rule.

monogramFor strips the POSSESSIVE, not short words. The apostrophe in
Captain's leaves a bare 's' token; filtering by word length fixes that and
silently breaks every genuine one-letter word -- measured over all 292 names,
9 worse against 3 fixed, with Prone Y/T/W Raise all collapsing to PR and
V-Up reduced to U. Regression tests pin all nine.

Lookup is getByExactName, never search. Fields are read with 'is String' rather
than cast: the same box holds community rows written verbatim from Postgres."
```

---

### Task 4: The monogram and the thumbnail

One task, one test file — splitting them left a test file importing a widget that did not exist yet.

**Files:** `exercise_monogram.dart`, `exercise_plate_thumb.dart`; test `test/contracts/exercise_plate_widgets_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/exercise_plate_widgets_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

  testWidgets('the thumb RE-RESOLVES when the exercise name changes', (t) async {
    // The names must sit on OPPOSITE sides of hasArtwork. Two artwork-less
    // names would both render ExerciseMonogram(name: widget.exerciseName),
    // which reads the WIDGET not the resolved plate -- so deleting
    // didUpdateWidget entirely would still pass. Round 2 caught exactly that.
    await t.pumpWidget(_host(
        const ExercisePlateThumb(exerciseName: 'Wall Sit', size: 44)));
    await t.pumpAndSettle();
    expect(find.byType(SvgPicture), findsOneWidget, reason: 'Wall Sit has art');

    await t.pumpWidget(_host(const ExercisePlateThumb(
        exerciseName: 'Totally Invented Exercise', size: 44)));
    await t.pumpAndSettle();
    expect(find.byType(SvgPicture), findsNothing,
        reason: 'a swap reuses the State; didUpdateWidget must re-resolve');
    expect(find.byType(ExerciseMonogram), findsOneWidget);
  });

  testWidgets('a slug with no bundled asset degrades to the monogram', (t) async {
    // await: Box.put returns a Future and this body is async, so an
    // un-awaited call trips unawaited_futures (analysis_options.yaml:21,
    // WARNING). Task 3's identical put sits in a SYNC test body where the lint
    // does not fire -- same statement, two different verdicts.
    await HiveService.instance.exerciseBox.put('ZGHOST', {
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
Expected: FAIL — neither widget exists.

- [ ] **Step 3: Write the monogram**

```dart
// lib/shared/widgets/exercise_plate/exercise_monogram.dart
//
// Shown wherever an exercise has no artwork. Three populations reach it: user
// custom exercises, community exercises synced from user_custom_exercises, and
// the 127 library rows awaiting a photograph.
//
// It reads as "a plate not yet issued" rather than a failure. Rejected: falling
// back to the index number (a column mixing engravings and bare numerals reads
// as "some of these are missing"), a category glyph (nine glyphs to design, and
// a triangle beside an engraving is two visual languages), and an empty frame
// (reads as a loading state that never resolves).
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_resolver.dart';

/// The plate corner radius scales with the plate, so a 44 px thumb and a 96 px
/// empty state read as the same object at two sizes. Deliberately NOT an
/// `AppRadius` member: those are fixed Wardroom radii (2 / 4 / 6) and this is
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
// stays neutral). The badges are 24/24/28 px today; 44 is also the minimum
// touch target, so one change fixes two things — but it IS a +16..20 px bump in
// a header Row, so check the card height on a real device.
//
// WHY initState and not build(): the Active Workout card rebuilds ~1x/second off
// the workout timer, so resolving in build() would re-read Hive sixty times a
// minute. coaching_content_panel.dart:40-58 learned this first.
//
// The parsed picture is cached by the SVG layer itself
// (vector_graphics/lib/src/vector_graphics.dart, _livePictureCache), so six to
// eight thumbs on one screen parse once, not once per frame.
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

  Widget _monogram() =>
      ExerciseMonogram(name: widget.exerciseName, size: widget.size);

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
                // render an error box. Reachable via community rows.
                //
                // The fallback is sized to the PADDED box (size * 0.88), not
                // size, so the one frame before setState lands does not jump.
                errorBuilder: (_, __, ___) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _assetFailed = true);
                  });
                  return ExerciseMonogram(
                      name: widget.exerciseName, size: widget.size * 0.88);
                },
              ),
            ),
          )
        : _monogram();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: SizedBox(width: widget.size, height: widget.size, child: face),
    );
  }
}
```

> `errorBuilder` is confirmed present — **`flutter_svg-2.3.0/lib/svg.dart:539`**, constructor parameter at `:200`, typedef `SvgErrorWidgetBuilder = Widget Function(BuildContext, Object, StackTrace)` at `:21`, which matches the 3-arg `(_, __, ___)` above. `pubspec.lock:606-613` resolves to **2.3.0**; a stale `flutter_svg-2.2.4` also sits in the pub cache and is not what builds.

- [ ] **Step 5: Run the test**

Run: `flutter test test/contracts/exercise_plate_widgets_test.dart`
Expected: all 6 PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/shared/widgets/exercise_plate/ test/contracts/exercise_plate_widgets_test.dart
sh scripts/safe_commit.sh "feat(plates): the monogram and the 44 px thumbnail

Zero new elements in a header row already at five, because the badge it replaces
carried almost nothing. The badges are 24/24/28 px today and 44 is the minimum
touch target, so one change fixes two things -- but it is a +16..20 px bump in a
header Row and the card height wants checking on a device.

Resolves in initState and didUpdateWidget, never in build: the Active Workout
card rebuilds about once a second off the workout timer.

The re-resolve test uses names on OPPOSITE sides of hasArtwork. Two artwork-less
names both render the monogram from widget.exerciseName rather than the resolved
plate, so deleting didUpdateWidget outright would still have passed."
```

---

### Task 5: The plate sheet

**Files:** `exercise_plate_sheet.dart`; test `test/contracts/exercise_plate_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/exercise_plate_sheet_test.dart
//
// The shape rule asserted through the RENDERED widget — a resolver unit test
// passes even if the sheet ignores isPair.
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
  late List<Map<String, dynamic>> lib;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('plate_sheet');
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

  Future<void> open(WidgetTester t, String name, {Size? surface}) async {
    if (surface != null) {
      await t.binding.setSurfaceSize(surface);
      // teardown, not a trailing statement — an earlier failure would otherwise
      // leak the surface into the next test.
      addTearDown(() => t.binding.setSurfaceSize(null));
    }
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
    expect(find.text('NO DRAWING YET'), findsOneWidget);
  });

  testWidgets('a REAL breathing cue renders', (t) async {
    // Barbell Bench Press carries "Inhale down, exhale on press" (verified).
    // Without this positive half, the suppression test below would pass on a
    // sheet that never renders BREATHING at all.
    await open(t, 'Barbell Bench Press');
    expect(find.text('BREATHING'), findsOneWidget);
  });

  testWidgets('a NUMERIC breathing_cue is suppressed', (t) async {
    // Surya Namaskar's breathing_cue is the string "12" -- one of the 136 rows
    // where a spreadsheet column shift put met_value into the field.
    await open(t, 'Surya Namaskar');
    expect(find.text('BREATHING'), findsNothing);
  });

  testWidgets('the sheet scrolls rather than overflowing at 320x480', (t) async {
    // The genuine worst case: an exercise WITH two plates (each AspectRatio 1)
    // AND the most cue lines. Picked from the data rather than by hand.
    final worst = lib
        .where((e) => e['demo_pair'] == true && e['coaching_cues'] is List)
        .reduce((a, b) => _cueLines(a) >= _cueLines(b) ? a : b);
    await open(t, worst['name'] as String, surface: const Size(320, 480));
    expect(t.takeException(), isNull, reason: 'RenderFlex overflow');
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });
}

int _cueLines(Map<String, dynamic> e) => (e['coaching_cues'] as List)
    .expand((c) => c.toString().split(';'))
    .where((c) => c.trim().isNotEmpty)
    .length;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/exercise_plate_sheet_test.dart`
Expected: FAIL — the sheet does not exist.

- [ ] **Step 3: Write the sheet**

```dart
// lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart
//
// The plate. Two images for a movement that cycles, one for a hold. Free to
// every tier, matching the FORM & CUES panel it sits beside.
//
// NOTE on the "never resolve library data in build()" constraint: this widget
// DOES, deliberately. That rule exists for the Active Workout card, which
// rebuilds ~1x/second off the workout timer. A modal sheet builds once when it
// opens; paying two linear scans of exerciseBox there is the simpler trade.
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

  /// Cues arrive in three shapes across the 292 rows, counted 2026-08-29: a
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
    // coaching_content_panel applies the identical guard; the data repair is on
    // the OI board.
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

The shape rule is asserted through the rendered widget, not just the resolver.

The overflow test picks its own worst case from the data -- the paired exercise
with the most cue lines -- rather than naming one by hand. The first attempt
named an exercise with no artwork at all, so it rendered one monogram instead of
two square plates and tested nothing.

breathing_cue is a falsifiable PAIR: BREATHING must render for a real cue
(Barbell Bench Press) and must not for a numeric one (Surya Namaskar, '12').
Asserting only the absence would pass on a sheet that never renders it."
```

---

### Task 6: Wire the three badge sites, the second door, and the breathing guard

Merged from two tasks. Separating them left Task 6 knowingly committing a red test — the same rule Task 1 invokes to justify its own atomicity, waived one task later.

**Files:** `exercise_card.dart`, `screen.dart`, `expandable_day_card.dart`, `day_detail_sheet.dart`, `coaching_content_panel.dart`; tests `exercise_plate_badge_sites_test.dart`, `breathing_cue_numeric_suppressed_test.dart`

- [ ] **Step 1: Write the failing tests**

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
  test('all three badge sites render the thumb and open the sheet', () {
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
      expect(
          RegExp(r"\$\{\s*(widget\.)?(exerciseIndex|index)\s*\+\s*1\s*\}")
              .hasMatch(src),
          isFalse,
          reason: '$p still renders the numeric badge');
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

```dart
// test/contracts/breathing_cue_numeric_suppressed_test.dart
//
// 136 of 292 rows carry a bare number in breathing_cue — a spreadsheet column
// shift that put met_value into the field, live in the shipped app. BOTH
// surfaces that render it must suppress a numeric value; guarding only the new
// sheet leaves two surfaces disagreeing about one field.
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
Expected: FAIL on all four.

- [ ] **Step 3: Active Workout card**

`exercise_card.dart` is `part of 'screen.dart'` — add the imports to **`screen.dart`**:

```dart
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_sheet.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_plate_thumb.dart';
```

Replace the number-badge `Container` (its `Text` is at `:447` — grep for `exerciseIndex + 1` rather than trusting the line) with:

```dart
                              ExercisePlateThumb(
                                exerciseName: widget.exercise.name,
                                size: 44,
                                onTap: () => ExercisePlateSheet.show(
                                    context, widget.exercise.name),
                              ),
```

Keep the `const SizedBox(width: 10)` after it.

> The exercise NAME is unavailable as a tap target: `:429-433` wraps the header row in a `GestureDetector` whose `onTap` is `widget.onFocus` (expand/collapse, Bug #15b) and `onLongPress` is `widget.onLongPressHeader` (superset grouping). Both load-bearing. The thumb's own detector sits inside and wins the tap arena for its 44 px; long-press still reaches the outer one.
>
> ⚠ **The badge carried the active-card gold signal** (`:440` fill, `:449` text colour, both on `widget.isActive`). The card border keeps a gold tint at 0.35 alpha (`:398-399`), so the signal weakens rather than vanishes. Check on a device; if the active card is not obviously marked, tint the thumb border on `isActive`.

- [ ] **Step 4: Train day card**

`expandable_day_card.dart:236` is the badge `Text`, inside `Consumer(builder: (context, ref, _) {` at `:215-216`, so `context` resolves. Read `:207-250` — the variable is `exercise`, not `name`:

```dart
              ExercisePlateThumb(
                exerciseName: exercise.name,
                size: 44,
                onTap: () => ExercisePlateSheet.show(context, exercise.name),
              ),
```

Add both `package:` imports.

- [ ] **Step 5: Home day-detail sheet — thread the context first**

`day_detail_sheet.dart:256` is the badge `Text`, but **`context` is not in scope**: `StatelessWidget` (`:16`), `_buildWorkoutBody()` takes no `BuildContext` (`:193`), `itemBuilder: (_, index)` discards it (`:216`). Using `context` is a compile error.

Change `:216` to `itemBuilder: (ctx, index) {`, then:

```dart
              ExercisePlateThumb(
                exerciseName: name,
                size: 44,
                onTap: () => ExercisePlateSheet.show(ctx, name),
              ),
```

(`:225` defines `name` in this file.) Add both imports.

- [ ] **Step 6: The second door and the breathing guard**

In `coaching_content_panel.dart`, at the end of the header `Row` rendering the `FORM & CUES` label:

```dart
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ExercisePlateSheet.show(context, widget.exerciseName),
          child: Text('VIEW PLATE',
              style: AppTypography.monoXs
                  .copyWith(color: AppColors.accent, letterSpacing: 2)),
        ),
```

The import already reaches this file via `screen.dart` (Step 3). Confirm the field holding the name (per `:40-58`) before using it.

Then, where `_breathing` is assigned in `_resolve()` (`:51-59`) — **the local there is `map`, not `raw`**:

```dart
    final b = _cleanString(map['breathing_cue']);
    // 136 of the library rows carry a bare number here — a spreadsheet column
    // shift that put met_value into breathing_cue. Suppress rather than render
    // "BREATHING / 5". Mirrored in exercise_plate_sheet.dart; the data repair
    // is tracked on the OI board.
    _breathing = (b != null && RegExp(r'^\d+(\.\d+)?$').hasMatch(b)) ? null : b;
```

> §4.2, not scope creep: the batch already edits this file, it renders the same field as the new sheet, and guarding one of two surfaces is the drift class this repo has hit 15+ times.

- [ ] **Step 7: Analyze and test**

Run: `flutter analyze lib/features/train/screens/active_workout/ lib/features/train/widgets/expandable_day_card.dart lib/features/home/widgets/day_detail_sheet.dart lib/shared/widgets/exercise_plate/`
Expected: **zero warnings.** `--no-fatal-infos` suppresses infos, not warnings, and one warning fails the push with no useful message from git.

Run: `flutter test test/contracts/exercise_plate_badge_sites_test.dart test/contracts/breathing_cue_numeric_suppressed_test.dart`
Expected: all 4 PASS — no red intermediate state.

- [ ] **Step 8: Commit**

```bash
git add lib/features/ test/contracts/
sh scripts/safe_commit.sh "feat(plates): the badge becomes the plate at all three sites, plus the second door

Merged with the FORM & CUES door so no commit lands with a red test: splitting
them left this commit knowingly shipping a failing assertion, which is the rule
Task 1 invokes to justify its own atomicity.

Tapping the exercise NAME was unavailable -- exercise_card.dart:429-433 already
owns both the tap (expand/collapse, Bug #15b) and the long-press (superset
grouping). The thumb's own detector sits inside that row.

day_detail_sheet needed BuildContext threaded first: _buildWorkoutBody takes
none and its itemBuilder discarded it, so the obvious edit would not compile.

The numeric-breathing_cue guard lands in coaching_content_panel too. 136 of 292
rows carry a bare number there, live in the shipped app, and guarding one of two
surfaces rendering the same field is the drift class this repo keeps hitting."
```

---

### Task 7: The attribution surface

CC BY-SA 4.0 requires attribution to reach the recipient. `grep -rn "showLicensePage\|LicenseRegistry\|AboutDialog\|showAboutDialog" lib/` returns **zero hits** — the app has no credit surface at all.

**Files:** `lib/main.dart`, a Profile screen, `assets/exercise_plates/LICENSE-CC-BY-SA-4.0.txt`; test `test/contracts/plate_attribution_surface_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/contracts/plate_attribution_surface_test.dart
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
    expect(hits, isNotEmpty, reason: 'the licence page exists but nothing opens it');
  });
}
```

- [ ] **Step 2: Run to verify failure** — FAIL on all three.

- [ ] **Step 3: Ship the licence text and register it**

Save the full CC BY-SA 4.0 legal text to `assets/exercise_plates/LICENSE-CC-BY-SA-4.0.txt` (covered by Task 2's single pubspec line).

In `lib/main.dart`, before `runApp(` (`:122`); `package:flutter/foundation.dart` is already imported at `:5`, so only `package:flutter/services.dart` for `rootBundle` needs adding:

```dart
  // CC BY-SA 4.0 requires attribution to reach the recipient. The plate artwork
  // is adapted from workout-guide (Bryl Lim), itself traced from Everkinetic.
  // Registering here feeds Flutter's own showLicensePage.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Exercise plate artwork'],
      await rootBundle
          .loadString('assets/exercise_plates/LICENSE-CC-BY-SA-4.0.txt'),
    );
  });
```

- [ ] **Step 4: Add the Profile row**

Use the existing `ProfileRow` widget — the pattern is at `profile_content.dart:541-561`: `ProfileRow({icon, title, subtitle, trailing: ProfileRowChevron(), onTap, showBorder})`. Label it `CREDITS & LICENCES` (Wardroom register, not "Open source licenses"):

```dart
onTap: () => showLicensePage(
  context: context,
  applicationName: 'ICANBEFITTER',
  applicationLegalese: 'Exercise artwork CC BY-SA 4.0 — workout-guide (Bryl Lim), '
      'traced from Everkinetic.',
),
```

`showLicensePage` captures inherited themes (`material/about.dart:303-306`) and `AppTheme.dark` sets `brightness: Brightness.dark` plus a dark `ColorScheme`, so it renders legibly without extra work.

- [ ] **Step 5: Run the test** — all 3 PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/features/profile/ assets/exercise_plates/LICENSE-CC-BY-SA-4.0.txt test/contracts/plate_attribution_surface_test.dart
sh scripts/safe_commit.sh "feat(plates): ship the CC BY-SA attribution to the user

292 CC BY-SA 4.0 assets were about to ship inside a paid app with no attribution
reaching anyone. An earlier draft claimed the repo-side ATTRIBUTION.md covered
it; a markdown file in the tree is not distributed and discharges nothing, and
the app had no credit surface at all -- zero hits for showLicensePage,
LicenseRegistry or AboutDialog across lib/.

Registers the licence with Flutter's own registry at startup and adds a Profile
row that opens showLicensePage, so the credit travels with the artwork."
```

---

### Task 8: Correct the spec, register the SoT, close the ledger

> **OI-147, OI-148 and OI-149 are already filed on this branch** (2026-08-29): the Donkey Calf Raise removal split out after round 2, the 23 equipment-variant exercises the spec had misrouted to OI-145, and the `breathing_cue` data defect. The ledger below cites all three; nothing here mints a number.

**Files:** `docs/plans/exercise-plates-spec.md`, `docs/sot_registry.yaml`, `docs/naming_conventions.md`, `docs/audit/exercise-plates.closure.yaml`, `docs/audit/open_issues.md`

- [ ] **Step 1: Write the failing test**

Append to `test/contracts/exercise_plate_badge_sites_test.dart`:

```dart
  test('the SoT registry carries the plate read path with a behavioural test', () {
    final y = File('docs/sot_registry.yaml').readAsStringSync();
    expect(y.contains('concept: exercise_plate_read_path'), isTrue);
    final i = y.indexOf('concept: exercise_plate_read_path');
    final w = y.substring(i, (i + 900).clamp(0, y.length));
    expect(w.contains('behavioral_test_path:'), isTrue,
        reason: 'rule 21 is strict — a bare registry entry blocks the commit');
    expect(w.contains('line_range:'), isTrue,
        reason: 'without line_range both registry gates skip this entry entirely');
  });

  test('demo_slug and demo_pair are in the naming glossary (§4.7)', () {
    final n = File('docs/naming_conventions.md').readAsStringSync();
    expect(n.contains('demo_slug'), isTrue);
    expect(n.contains('demo_pair'), isTrue);
  });

  test('the spec no longer contradicts the implementation', () {
    final s = File('docs/plans/exercise-plates-spec.md').readAsStringSync();
    expect(s.contains('demo_pair'), isTrue,
        reason: 'the Data contract still omits the field that carries the shape');
    expect(s.contains('293'), isFalse,
        reason: 'the stale per-exercise file count is still in the spec');
  });

  test('sync_community cannot strip demo_slug — the guard is pinned', () {
    final src = _strip(
        File('lib/core/services/sync/sync_community.dart').readAsStringSync());
    expect(src.contains('exerciseBox.get(id) == null'), isTrue,
        reason: 'the add-only guard was relaxed; community sync can now '
            'overwrite a library row and strip demo_slug');
  });

  test('the batch closure ledger exists and is terminal', () {
    final f = File('docs/audit/exercise-plates.closure.yaml');
    expect(f.existsSync(), isTrue, reason: '§4.2 requires one for a ≥4-unit batch');
    expect(f.readAsStringSync().contains('deferred:'), isFalse,
        reason: 'the schema has no deferred key');
  });
```

- [ ] **Step 2: Run to verify failure** — **four of the five fail.**

> The `sync_community` test passes TODAY: `lib/core/services/sync/sync_community.dart:502` already reads `if (id != null && id.isNotEmpty && exerciseBox.get(id) == null)`. It is a **pin against future relaxation**, not a red-first test, and an implementer seeing 4/5 should not go hunting for a break. Said out loud because asserting a red state without running it is the class that produced round 2's unfalsifiable `didUpdateWidget` test.

- [ ] **Step 3: Correct the spec (three contradictions)**

1. **`spec:113-137`** says the shape rule *"lives in Dart beside the rule, not in the library JSON, because it is a rendering decision rather than exercise data."* That is now backwards — rewrite it to describe `demo_pair`, and say why: the Python pipeline must read the same decision to choose union-crop vs own-bounds.
2. **`spec:139-150`** documents only `demo_slug`. Add `demo_pair` to the Data contract.
3. **`spec:348-368`** says *"293 plate files"* and *"128 two-image and 37 single-image plates"*. Correct to **165 exercises (148 pair + 17 single) over 153 slugs → 292 files**, and note the per-exercise/per-slug distinction.

**Four more lines carry SPLIT residue** — the batch no longer removes a row, so anything assuming 291 rows or 126 monogram exercises is now false:

| line | text | correction |
|---|---|---|
| `:359` | `at full coverage, all 291 / 291 / 507` | 292 rows, not 291 |
| `:428` | `removed at founder request / 1 - Donkey Calf Raise` | nothing is removed — point at **OI-147** |
| `:434` | `exercises awaiting a founder photograph / 126` | **127** |
| `:452` | `- **126 photographs** - the founder's camera.` | **127** |
| `:453` | `- **23 new exercises** ... **OI-145**` | **OI-148** — OI-145 scopes 34 *different* drawings |

Also record: `Barbell Curl` keeps its name and its `ez-bar-curl` drawing (founder, 2026-08-29 — renaming orphans `exlog_*` history, which hashes the name).

Also record: `Barbell Curl` keeps its name and its `ez-bar-curl` drawing (founder, 2026-08-29 — renaming orphans `exlog_*` history, which hashes the name); the Donkey Calf Raise removal is **OI-147**; and the 23 split-rule exercises are **not** OI-145 (that issue scopes 34 different drawings) — file them as OI-148.

- [ ] **Step 4: Register the SoT concept**

Append to `docs/sot_registry.yaml`. **`line_range:` on every writer and reader is mandatory** — both `check_sot_registry_completeness.dart:117-119` and `check_sot_registry_parity.dart:140-141` match `file:\s*…\n\s*line_range:\s*(\d+)-(\d+)`, so an entry without it passes Gate 42 while being invisible to both validators:

```yaml
  - concept: exercise_plate_read_path
    domain: workout
    behavioral_test_path: test/contracts/exercise_plate_resolver_test.dart
    contract_test_path: test/contracts/exercise_plate_assets_present_test.dart
    description: |
      Exercise plates. WRITER: `assets/data/exercise_library.json` — `demo_slug`
      (nullable, 165 populated) and `demo_pair` (nullable bool, the plate SHAPE),
      both from `docs/plans/exercise-plates-mapping.json`. Delivered to existing
      installs ONLY by `_exerciseLibraryVersion`: `seed_service.dart:127-128`
      re-seeds iff stored < constant.

      READER: `resolvePlate()` in `plate_resolver.dart`, the SOLE entry point.
      EXACT name (`getByExactName` — never `search`, which is substring). Reads
      both fields with `is String` / `== true`, never a cast, because this box
      also holds community rows written verbatim from Postgres.

      ⚠ `demo_pair` is in the DATA deliberately: it is read by BOTH the Dart
      renderer and the Python pipeline (`scripts/build_exercise_plates.py`),
      which crops a pair to the union of both frames and a hold to frame 1's own
      bounds. Moving it into a Dart constant re-creates a cross-language drift
      with no gate.

      ⚠ 165 exercises share 153 slugs — a per-exercise count and a per-slug
      count are different numbers.

      ⚠ An artwork-less row carries NEITHER key. A `demo_slug: null` would read
      as present to the schema contract's exact key match.

      ⚠ `equipment_tier` is NOT consulted anywhere in this path.
    writers:
      - file: assets/data/exercise_library.json
        line_range: 1-2
        method: demo_slug + demo_pair fields
      - file: lib/core/services/seed_service.dart
        line_range: 95-95
        method: _exerciseLibraryVersion
    readers:
      - file: lib/shared/widgets/exercise_plate/plate_resolver.dart
        line_range: 60-90
        method: resolvePlate
      - file: lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart
        line_range: 100-140
        method: build
```

Fix the `line_range` values to the real ones after the files land.

Append `demo_slug` and `demo_pair` to the reserved-domain glossary (`docs/naming_conventions.md` §8) — §4.7.

- [ ] **Step 5: Write the closure ledger**

`docs/audit/exercise-plates.closure.yaml` — §4.2's structural closed==N invariant, required for any ≥4-unit batch.

⚠ **Gate 40 requires per-STATE fields a plain table cannot carry** (`scripts/validate_audit_closure.dart:18-40`): `upstream_blocked` needs **both** `blocker:` and `reopen_when:`; `blocked_on_user` needs `reason:`; `verified_clean` needs `evidence:` or `notes:`; `closed_in_commit` needs a real SHA or a labelled branch state **and** a verification path. `total_findings` must equal the `findings:` length, and `closed_count` the terminal count. Model it on `docs/audit/ci-speedup.closure.yaml`. Write the YAML, not a summary of it:

```yaml
# Closure ledger — exercise plates. Gate 40 (validate_audit_closure.dart).
# One terminal_state per item; no `deferred:` key. 15 items, over the §4.2 >=4
# threshold. Branch: exercise-plates.
#
# No diagnose-doc: this is a feature, not a bug fix. No commit subject matches
# rule 22's ^(fix|bug|regression) pattern.

batch: exercise-plates
total_findings: 15
closed_count: 15

findings:
  # --- the nine build tasks; fill each SHA in as it lands ---
  - id: T1
    title: demo_slug + demo_pair on 165 rows, seed version 10 -> 11
    terminal_state: closed_in_commit
    commit: "<sha>"
    verification: flutter test test/contracts/exercise_plate_library_data_test.dart
  - id: T2
    title: vendor the artwork, crop it, ship 292 SVGs
    terminal_state: closed_in_commit
    commit: "<sha>"
    verification: flutter test test/contracts/exercise_plate_assets_present_test.dart
  - id: T3
    title: the plate resolver
    terminal_state: closed_in_commit
    commit: "<sha>"
    verification: flutter test test/contracts/exercise_plate_resolver_test.dart
  - id: T4
    title: monogram and 44 px thumbnail
    terminal_state: closed_in_commit
    commit: "<sha>"
    verification: flutter test test/contracts/exercise_plate_widgets_test.dart
  - id: T5
    title: the plate sheet
    terminal_state: closed_in_commit
    commit: "<sha>"
    verification: flutter test test/contracts/exercise_plate_sheet_test.dart
  - id: T6
    title: wire three badge sites, second door, breathing guard
    terminal_state: closed_in_commit
    commit: "<sha>"
    verification: flutter test test/contracts/exercise_plate_badge_sites_test.dart
  - id: T7
    title: CC BY-SA attribution surface
    terminal_state: closed_in_commit
    commit: "<sha>"
    verification: flutter test test/contracts/plate_attribution_surface_test.dart
  - id: T8
    title: spec corrections, SoT registry, closure ledger
    terminal_state: closed_in_commit
    commit: "<sha>"
    verification: dart run scripts/check_sot_behavioral_test_paths.dart
  - id: T9
    title: full suite, B-pass, review record, merge
    terminal_state: closed_in_commit
    commit: "<sha>"
    verification: flutter test && flutter analyze --no-fatal-infos

  # --- parked, each terminal, each pointing at something that EXISTS ---
  - id: P1
    title: 127 photographs for the exercises with no drawing
    terminal_state: blocked_on_user
    reason: >
      Requires the founder's camera. The monogram covers these rows from day
      one; the photographs arrive later as a data change plus an
      _exerciseLibraryVersion bump, no code. Shooting guidance is in the spec.
  - id: P2
    title: 23 equipment-variant exercises from the split rule
    terminal_state: blocked_on_user
    reason: >
      OI-148. Blocked on a product decision, not on artwork - a dumbbell user
      would see both rows of every split pair, doubling that movement's slot
      probability. Every drawing is already identified.
  - id: P3
    title: breathing_cue holds a bare number on 136 of 292 rows
    terminal_state: blocked_on_user
    reason: >
      OI-149. 136 replacement cues must be AUTHORED; the original text is
      unrecoverable. Verified dead - the field is absent from all 20 columns of
      both seed migrations, and all 19 git revisions of the library carry the
      numeric value. Both render surfaces in this batch suppress it, pinned by
      test/contracts/breathing_cue_numeric_suppressed_test.dart.
  - id: P4
    title: remove Donkey Calf Raise
    terminal_state: blocked_on_user
    reason: >
      OI-147. Split out of this batch after review round 2. Needs the
      606-persona generator matrix run first - it is the library's only
      bodyweight-tier calf isolation row - then a seed-migration re-mint, a
      ledger pair, and a live prod apply needing its own founder authorization.
  - id: P5
    title: the three dead image URL fields in migrations 074/125 and two seed scripts
    terminal_state: verified_clean
    evidence: >
      backups/live_schema_columns.json holds no exercise_library key at all, so
      nothing server-side reads them. The generators re-emit only when next run,
      which OI-147's re-mint will do. Removed from the bundled JSON and from
      swap_service in T1.
  - id: P6
    title: stale swap_service entries in backups/gate19_drift_baseline.txt
    terminal_state: verified_clean
    notes: >
      Gate 19 flags NEW drift only and has no stale-entry check, so the two
      entries for the deleted swap_service lines cannot fail anything. Its
      header asks for a refresh after closing a true drift; this is a deletion,
      not a drift closure.
```


- [ ] **Step 6: Run the tests** — all green. Then `dart run scripts/check_sot_behavioral_test_paths.dart` and `dart run scripts/validate_audit_closure.dart`.

- [ ] **Step 7: Commit**

```bash
git add docs/
sh scripts/safe_commit.sh "docs(plates): correct the spec, register the SoT path, close the ledger

The spec had drifted into contradicting the implementation in three places: it
still said the shape rule lives in Dart 'because it is a rendering decision
rather than exercise data' (demo_pair now puts it in the data, precisely so the
Python pipeline can read it), it documented only demo_slug, and its delivery
table said 293 files from a 128/37 split that is off by 20 exercises.

The SoT entry carries line_range on every writer and reader: both registry
validators match on a file/line_range pair, so an entry without it passes rule
21's gate while being invisible to the checks that verify its citations.

Adds the closure ledger §4.2 requires for a batch this size. Its absence would
have passed every gate -- validate_audit_closure only validates ledgers that
exist -- which is why the rule states it in prose."
```

---

### Task 9: Full suite, review, merge

- [ ] **Step 1: Full suite** — `flutter test`. Green. Rule 20 makes a red `main` a P0 and bans "pre-existing failure".

> A targeted run is a DIFFERENT input set from the suite, not a subset. None of these files spawn subprocesses, so none needs a file-level `@Timeout`.

- [ ] **Step 2: Analyze** — `flutter analyze --no-fatal-infos`. Zero warnings.

- [ ] **Step 3: B-pass** — `/code-review`. Self-initiated at ≥`account`; this is `platform` (§4.3). **The commit carrying its output needs a same-dated Tuning history bullet in `.claude/skills/code-review/SKILL.md`** — `check_skill_tuning_history.dart` blocks any commit adding `docs/reviews/**.md` without one.

- [ ] **Step 4: The plan-review record**

`docs/plan-reviews/exercise-plates.md`, `---` frontmatter (the gate parses `^key:` line-anchored):

```markdown
---
branch: exercise-plates
date: <YYYY-MM-DD>
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/exercise-plates-bpass.md
---
```

> ⚠ **`bpass_review:` is mandatory.** `check_plan_review_record_exists.dart:840-866` requires `bpass: accepted` to name a file under `docs/reviews/` that exists **at the merge rev** (`git show <rev>:<path>`) and matches `^verdict:\s*accepted\s*$`.

- [ ] **Step 5: §5 close-out — every row, out loud**

Diagnose-doc (n/a) · contract tests · SoT registry (Task 8) · `applied_migrations.json` (n/a, no migration) · root CLAUDE.md · `lib/features/train/CLAUDE.md` · `docs/architecture/` · feedback memory · project retrospective · harness `MEMORY.md` · **worktree retirement** (dry-run first, from the PRIMARY worktree) · **skill self-evolution** (§5.1).

- [ ] **Step 6: Merge and push**

```bash
cd "C:/Upendra/Claude Code/Fitness App"       # PRIMARY — integration only
sh scripts/safe_merge.sh exercise-plates
sh scripts/safe_push.sh
```

`safe_push.sh` has THREE outcomes: `0` LANDED, `1` FAILED, **`2` UNVERIFIED**.

---

## What the reviews changed

**Round 1** — 7 BLOCKER / 15 MAJOR / 16 MINOR. All 7 blockers verified real. The mapping existed nowhere and was recovered; `Hive.initFlutter` needs a `path_provider` mock; the schema contract pins a closed key set; `day_detail_sheet` has no `BuildContext`; the pipeline's file count was wrong; `monogramFor` returned `CSC`; the review record needs `bpass_review:`. Two design changes came out of it — `demo_pair` into the data, and flat asset paths.

**Round 2** — 5 BLOCKER / 11 MAJOR / 17 MINOR, verdict **not converged**, with four of five blockers *inside round 1's own fixes*:

- Widening the dead-field scan to `test/` made it **scan itself** and fail forever. Now skips its own path.
- Repairing the schema contract fixed the key set and missed that the file has **five** tests, one asserting `rows.length == 292` — and the "38 → 37" instruction contradicted the optional-key instruction below it. The right shape is **35 required + 2 optional**, with `extra` computed against the union.
- The `monogramFor` fix **degraded 9 names to fix 3** — `V-Up`→`U`, `Z Press`→`P`, and `Prone Y/T/W Raise` all collapsing to `PR`. The signal is the **possessive**, not word length. Nine regression tests pin it.
- The `didUpdateWidget` test was **unfalsifiable** — both fixtures were artwork-less, so the monogram read `widget.exerciseName` and deleting the method entirely still passed.
- Two blockers came from removing Donkey Calf Raise, which **is no longer in this batch** (OI-147).

Also from round 2: `ink_bbox` was silently blind to `<circle>`/`<rect>`/etc. and to a non-512 canvas (both now hard-fail); Task 6 knowingly committed a red test (merged with Task 7); no closure ledger existed (Task 8); the spec contradicted the implementation in three places (Task 8); the version-delivery test was a source grep where the spec asks for a behavioural one (Task 1); the `sync_community` guard was asserted in prose rather than pinned (Task 8); and the `flutter_svg` citation named 2.2.4 when the lock resolves **2.3.0**.

## Self-Review

**Spec coverage.** Source and licence → Tasks 2, 7. Frames 1 and 3 → Task 2. Crop rules → Task 2. Shape rule → Tasks 1, 3, 5. Delivery → Task 1 (behavioural). `sync_community` guard → Task 8 (pinned, not prose). Placement → Task 6. Performance → Task 4 (resolve site + the SVG layer's picture cache). Monogram → Task 4. Licence → Task 7. Removals → Task 1. Spec corrections + closure → Task 8.

**Parked, each terminal in the Task 8 ledger:** 127 photographs, the 23 split-rule exercises (OI-148), the `breathing_cue` data repair, the Donkey Calf Raise removal (**OI-147**), and the dead-field references in the seed generators — the last `verified_clean` because `live_schema_columns.json` carries no `exercise_library` key, so nothing server-side reads them.

**Type consistency.** `resolvePlate → ExercisePlate` (Tasks 3, 4, 5); `monogramFor` (3, 4); `plateRadiusFor` (4, both widgets); `ExercisePlateThumb({exerciseName, size, onTap})` (4, 6); `ExercisePlateSheet.show(BuildContext, String)` (5, 6); asset paths `assets/exercise_plates/<slug>-{1,3}.svg` throughout.

**What a round-3 reviewer should attack first**, in order:
1. **Task 1 Step 4** — the schema contract change is described but not written out as a diff, and it is the single instruction two rounds have now got wrong. Read `:5-47` and confirm 35 + 2 is achievable in that file's actual shape.
2. **The manifest's structure** (Task 2 Step 3) — still unverified by anyone, because the catalogue has never been cloned in this repo. Both the Python probe and the Dart test assume a top-level array with `slug` and a `frames` list.
3. **The `line_range` values** in the Task 8 SoT entry are placeholders to be filled after the files exist — check they were.
