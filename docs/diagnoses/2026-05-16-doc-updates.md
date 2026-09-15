---
bug_id: 2026-05-16-doc-updates
date: 2026-05-16
batch: APK Test #16.2 / Phase E (audit 2026-05-16) — E.15
status: fixed
regression_test: test/contracts/sot_registry_completeness_test.dart
symptom: >-
  CLAUDE.md and `docs/sot_registry.yaml` need to track the audit-2026-05-16
  architectural changes so the next contributor sees the canonical patterns:
---

## Symptom

CLAUDE.md and `docs/sot_registry.yaml` need to track the audit-2026-05-16 architectural changes so the next contributor sees the canonical patterns:

- §11 still listed 20 AI tools / 6 FREE / 20 PRO (actually 24 tools / 11 FREE / 13 PRO — closed in E.5.4).
- §9 Legacy section still listed `RankChip` / `RankInsignia` as "slated for removal" (E.11 deleted them).
- §15 SoT Rules didn't reference 5 new canonical concepts introduced in this batch (coach_notes upward sync, logPR through WriteService, WorkoutScheduleService routing, HealthWriteService, ai-proxy placeholder resolution).
- §19 fix-table had no entry for the audit-2026-05-16 batch itself.
- `docs/sot_registry.yaml` had 36 concepts; the new SoT surfaces from this batch needed entries.

## Root cause

Documentation lag is a known recurring class. Every major batch since Test #6 has shipped with at least one doc gap that surfaced in the NEXT audit. Closing the doc updates in the SAME batch as the architectural change is the only way to keep CLAUDE.md / SoT registry trustworthy.

## Fix

**CLAUDE.md §9** — replaced the 2-line legacy RankChip/RankInsignia entries with a single deletion notice referencing the regression test that pins the deletion.

**CLAUDE.md §11** — already updated in E.5.4 (24 tools / 5 families / 11-FREE-13-PRO).

**CLAUDE.md §15 SoT Rules** — added 5 new bullets:
- AI coach memory upward sync (F3-1.1 — `coach_notes` cloud column ↔ `coaching_notes` Hive key asymmetry, must stay aligned).
- AI coach `logPR` tool (F6-2 — canonical WorkoutWriteService routing, NOT legacy logSetWithPrRescan).
- WorkoutScheduleService (E.6 — 9 mutations through upsertScheduled, 3 non-schedule writes with explicit fan-out, 1 internal backup direct).
- HealthWriteService (E.7 — new canonical writer mirroring Workout/Nutrition WriteServices; IST baked in; 9 UI-layer callsites migrated).

**CLAUDE.md §19** — added one comprehensive row at the bottom of the fix-table summarizing the entire audit-2026-05-16 batch with cross-references to all 11 new diagnose-docs.

**`docs/sot_registry.yaml`** — appended 5 new concepts:
1. `coach_memory_coach_notes_upward_sync` (E.1)
2. `ai_coach_tool_dispatcher_log_pr` (E.5.1)
3. `workout_schedule_service_routes_through_write_service` (E.6)
4. `health_write_service` (E.7)
5. `ai_proxy_placeholder_resolution` (E.5.2)

Each entry follows the canonical shape: `concept`, `domain`, `description`, `writers` (file:line), `readers`, `regression_test`, `class_constraints` (the "never do X" invariant the contract test pins).

Registry grew from 36 → 41 concepts (matches the audit plan's "concept count > 33" goal).

## Verification

- `flutter test test/contracts/sot_registry_completeness_test.dart` — 2/2 pass after extension. Gate 7 mirror still resolves every `file:line_range` to a real file within bounds.
- All 13 audit-2026-05-16 contract test files run clean (68/68 sub-tests pass).
- `flutter analyze` clean on every file the batch touched.

## Follow-ups

- The 5 new SoT registry entries have placeholder `line_range` values for some methods — should be tightened as code stabilizes after this batch. Tracking under the next audit's framework parity sweep.
- Some §15 bullets reference both Hive prefix names (e.g. `sleep_log_`, `weight_`, `measurement_`) but the Hive field-name contract sub-section doesn't yet enumerate them with the same detail it gives `exlog_*` / `nlog_*`. Defer to next batch — these prefixes are NOT writer/reader drift candidates today (single writer = `HealthWriteService`), so the gap is documentation-only.

## Class lesson

Doc updates ship with the code change, not in a follow-up batch. The Legacy-section drift on RankChip/RankInsignia is a canonical example: 3 weeks of "slated for removal" tagging with no actual removal accumulated 5 active callsites. Codified: every batch that introduces a canonical replacement for an existing widget/method/file MUST close the migration in the same batch + update the docs reference in the same commit set.
