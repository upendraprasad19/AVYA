---
bug_id: 2026-05-16-rank-widget-migration
date: 2026-05-16
batch: APK Test #16.2 / Phase E (audit 2026-05-16) — E.11
status: fixed
regression_test: test/contracts/rank_widget_migration_test.dart
symptom: >-
  CLAUDE.md §9 "Wardroom primitives" Legacy section documented `RankChip` +
  `RankInsignia` as "slated for removal — do not introduce new usages", but 5
  active callsites remained for 3 weeks after the canonical `WardRankPill` /
  `WardRankInsignia` shipped (APK Test #6):
---

## Symptom

CLAUDE.md §9 "Wardroom primitives" Legacy section documented `RankChip` + `RankInsignia` as "slated for removal — do not introduce new usages", but 5 active callsites remained for 3 weeks after the canonical `WardRankPill` / `WardRankInsignia` shipped (APK Test #6):

1. `lib/features/profile/widgets/rank_chip_full_width.dart:55` — small 18 dp insignia in the full-width rank strip.
2. `lib/features/profile/widgets/service_record_section.dart:129` — 32 dp current-rank in expanded service record.
3. `lib/features/profile/widgets/service_record_section.dart:232` — 28 dp ladder entry (with `dimmed: dim` variant for past ranks).
4. `lib/features/train/screens/phase_roadmap_screen.dart:365` — 24/32 dp in phase-roadmap detail.
5. `lib/features/train/screens/phase_roadmap_screen.dart:426` — 56 dp in promotion-marker.

`RankChip` widget itself had ZERO active callers — only the legacy widget's own implementation referenced it.

## Root cause

When `WardRankInsignia` (CustomPaint-based, 11 painters dispatched by rankCode) shipped in APK Test #6, the migration of existing callsites was deferred with the "slated for removal" tag. The legacy `RankInsignia` (text-fallback widget with a `dimmed: bool` parameter) and `RankChip` (compact composite of `RankInsignia` + name text) stayed in the barrel for back-compat. Three weeks of feature work added MORE callsites instead of fewer — the migration never got the dedicated batch attention to drive it to zero.

## Fix

Founder approved Phase D NEEDS_DECISION 1 Option A — migrate + delete in this batch.

**5 callsite migrations** (each replaces `RankInsignia(rankCode, size, [dimmed])` with `WardRankInsignia(rankCode, size, [color])`):
1. `rank_chip_full_width.dart:55` — direct swap, no dimmed parameter.
2. `service_record_section.dart:129` — `dimmed: false` → omit `color` (defaults to `AppColors.accent` gold).
3. `service_record_section.dart:232` — `dimmed: dim` → `color: dim ? AppColors.textMute : null`. The legacy `dimmed: true` set `ringColor = AppColors.textMute.withValues(alpha: 0.45)` and `textColor = AppColors.textMute`; closest semantic match in the canonical palette is `AppColors.textMute`.
4. `phase_roadmap_screen.dart:365` — direct swap.
5. `phase_roadmap_screen.dart:426` — direct swap.

**2 file deletions:**
- `lib/shared/widgets/wardroom/rank_chip.dart` (had 0 callers; only referenced `RankInsignia` internally — cascade-cleaned).
- `lib/shared/widgets/wardroom/rank_insignia.dart` (no remaining external callers post-migration).

**Barrel pruned:** `lib/shared/widgets/wardroom/wardroom.dart` lost the `export 'rank_chip.dart'` + `export 'rank_insignia.dart'` lines. Replaced with an audit comment marking the deletion + canonical replacement reference.

**Import updates:** `rank_chip_full_width.dart` + `phase_roadmap_screen.dart` switched from `wardroom/rank_insignia.dart` to `wardroom/ward_rank_insignia.dart`. `service_record_section.dart` already imported the wardroom barrel, no change needed.

## Verification

- New contract test: `test/contracts/rank_widget_migration_test.dart` (5 sub-tests).
  - `legacy rank_chip.dart file no longer exists` ✓
  - `legacy rank_insignia.dart file no longer exists` ✓
  - `wardroom barrel does not re-export the deleted files` ✓
  - `previously-known callsites have migrated to WardRankInsignia` ✓
  - `no remaining import of the deleted files` (full lib/ tree walk) ✓
- All 5/5 PASS via `flutter test`.
- `flutter analyze` on the 4 edited files → 0 issues.

## Follow-ups

- CLAUDE.md §9 "Wardroom primitives" Legacy section must drop the rank_chip/rank_insignia rows. Folded into E.15 doc updates batch.
- The 3 audit comments at migration sites can be reduced to short references after one APK ship cycle (currently `// audit-2026-05-16 E.11 — migrated from legacy RankInsignia.` — useful for the next reviewer, removable later).

## Class lesson

"Slated for removal" without an explicit batch assignment is a deferral pretext. Every legacy-marker should carry a hard deadline (e.g. "delete by APK Test #N") and the responsible batch's todo list. Otherwise it accumulates. Codified in Phase E's discipline: when introducing a new canonical replacement for an existing widget/method/file, the migration batch ships in the SAME APK as the replacement (not a "future cleanup batch").
