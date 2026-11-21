---
branch: workout-equipment-community-seam
scope: ⑥ slice B2 — community-download equipment_needed write-normalize (consistency, ship-live default-ON, platform)
blast_radius: platform
reviewer: context-blind adversarial B-pass (self-initiated, §4.3)
verdict: accepted
---

# B-pass — ⑥ slice B2 community-download equipment_needed write-normalize

Context-blind adversarial review of the implemented diff (4 code/test files + SoT, platform tier). Every
load-bearing claim verified by reading the actual code (`equipment_vocab.dart`, `sync_community.dart`,
`exercise_selector.dart`, `exercise_repository.dart`, `sync_service.dart`, the test). **No P0/P1 defects.**

## Verified-clean (by bug class)
- **Crash / null-safety — CLEAN.** `normalizedEquipmentRow → fromProfile` (`equipment_vocab.dart:201-205`)
  traced on every cloud shape: null/absent → `[]`; bare/empty String → `normalize([raw])`/`[]`; List with
  non-String/Map/int elements → `.map(toString)` + unmappable-drop; a bare Map value → `[]`. No `as List`
  cast (the e9d1c7 class is avoided by design). The call-site `map` is always a fresh `Map.from(row)`
  (`sync_community.dart:500`); `configBox.get(...)` cannot throw. No throwing input exists.
- **Kill-switch sense — CORRECT + idiom-consistent.** `enabled: _hive.configBox.get('disable_community_
  equipment_normalize') != true` (`:512-514`): absent → normalize ON; flag `true` → verbatim raw. Mirrors the
  house `!= true` "enabled" idiom (`sync_nutrition.dart:211/591`); the `== true` `_isDisabled` getters are the
  opposite polarity, correctly so.
- **Mutation aliasing — SAFE.** Mutates + returns the same map, but the map is a per-row fresh
  `Map.from(row)`; `normalize` only READS the source (`.map` allocates), so the PostgREST `row` is untouched.
- **Wrong-loop / missed-seam — CORRECT.** Exercises-only is right — `user_custom_foods` has no
  `equipment_needed`, so the food loop must not normalize. The only `exerciseBox` community writer is
  `:508`; `seed_service.dart:177` writes slice-A-normalized seed rows; no other `source='community'` writer.
- **Idempotence — CLEAN.** Canonical in → canonical out; rows are stored once (`get(id)==null` dedup `:502`).
- **Consistency-only claim — VERIFIED TRUE (the crux), two ways.** (1) `query()` reads `equipment_needed` RAW
  (`exercise_repository.dart:130`) but is reached only via `_selectForSpecs`/`_broadenSelection`/
  `_appendBodyFocusIsolation`, all inside `ExerciseSelector.pick()` (`:81-143`) — and `pick()` has ZERO
  callers (`.pick(` grep empty; sole live entry `plan_generator.dart:124 → pickV4 → queryV4`). (2) queryV4
  rejects community rows BEFORE any equipment read — the movement-pattern filter (`:251`) is false for the
  pattern-less community rows — and its only `equipment_needed` read (the B1 exclusions block `:283`) uses
  idempotent `fromProfile`. Every other reader is display/copy/AI-payload + shape-tolerant; the L2/L6 custom
  paths read `customBox` (disjoint from exerciseBox community rows). No live reader exact-matches the raw value.
- **Import — CORRECT.** Added to the library root `sync_service.dart:34` (single, used at `:510`); a `part`
  cannot carry imports.
- **Test — REAL, not vacuous.** Both flag branches + every shape; expected canonical values match the
  alias/precedence logic (`'Cable Machine'→'cables'`, `'Barbell or Dumbbells'→'dumbbells'`, unmappable→`[]`);
  seam-wiring grep strips comments first + is paired with the transform test (rule 21 satisfied).

## P2 / informational (non-blocking; NOT bundled into this consistency slice)
- **P2 — latent dead-code revival trap.** The whole safety argument rests on `pick()`/`query()` being dead;
  the dead code still reads `equipment_needed` RAW (`exercise_repository.dart:130`). If `pick()` were ever
  revived, community rows would be subject to raw-vs-canonical selection skew. Already SoT-documented
  ("correct IF ever revived"). B2 does NOT introduce or worsen it — canonical stored data makes a revived
  lowercase `query()` MORE likely to match, not less. Removing the dead V3 `pick()`/`query()` path is a
  separate plan-engine concern (its own blast-radius + review), unrelated to this consistency slice; it is
  not a B2 defect and nothing in B2 depends on it changing.
- **Nit — kill-switch is first-write-only** (inherent to the pre-existing `get(id)==null` download-once
  dedup; the flag governs new downloads, not a migrator). Benign.
- **Nit — line-ref drift** (SoT `:503`→ the call is `:510`/put `:508`; slice-A docstring `:270`→ tier block
  `:287`). BOTH corrected in this commit.

**Layers checked:** client code (selector cascade, query/queryV4, sync_community loop), Hive write shape
(exerciseBox community rows), test. No schema/EF/cron/RLS surface touched.
