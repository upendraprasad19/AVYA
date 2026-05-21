---
scope: lib
parent: ../CLAUDE.md
created: 2026-05-18
updated: 2026-05-21
status: active
---

# Library Cross-Feature Rules

> This file is auto-loaded by Claude Code when working under `lib/`.
> Root CLAUDE.md (../CLAUDE.md) contains process invariants and a pointer index.

## What lives here

`lib/` is the Flutter client. The architecture is **offline-first**: every read and
write hits Hive on the local device. Supabase is a backup/projection layer that
catches up via the `SyncService` fan-out. Cross-feature rules below apply
everywhere under `lib/`; per-feature nested CLAUDE.md files refine them.

Sub-trees:

- `lib/core/` — services, theme, router, utils, models. See `lib/core/services/CLAUDE.md`.
- `lib/features/` — 7 feature directories matching the 5 tab screens + onboarding + auth.
- `lib/shared/` — reusable widgets (`wardroom/`), repositories (`plan_engine/`, `user_repository`, `exercise_repository`).

## Cross-feature non-negotiables (mirrors root CLAUDE.md §4.4)

These apply EVERY interaction inside `lib/`:

1. **Hive-first for ALL reads/writes.** Never block UI on Supabase response.
2. **Repository pattern.** Widgets never call Supabase or Hive directly — go through a Repository or a WriteService.
3. **Riverpod for shared state.** No `setState` for anything cross-widget.
4. **`subscription.gate()` for PRO features.** Never inline `isPro` checks in build methods.
5. **WardSet primitives + DM Sans + Wardroom palette only.** No raw `setState`-driven colors, no system fonts. Palette source-of-truth: `lib/shared/widgets/wardroom/CLAUDE.md`.
6. **All screens handle loading / error / empty.** No bare `CircularProgressIndicator` without a skeleton design.
7. **Relative imports within a feature, `package:` for `shared/` + `core/`.**

## Single-source-of-truth contracts

Every concept owned by code under `lib/` has a registered writer + reader set in
`docs/sot_registry.yaml`. Concepts are grouped by domain (workout / nutrition /
health / subscription / auth_profile / cross_domain). When you touch a writer
or reader of a registered concept, update the registry entry in the same commit
and add (or extend) a `*_writer_to_reader_test.dart` under `test/contracts/`
that pins the field name and semantic.

The recurring class of bug under `lib/` is **writer/reader drift** — 9+ instances
since APK Test #6. The fix is always: NAME writer + reader by file:line FIRST,
then propose. See `feedback_writer_reader_field_drift_recurring.md` and root
CLAUDE.md §4.1.

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Calling `Hive.box(...)` directly from a widget | Always go through a Repository or WriteService. Raw `Hive.box` bypasses the cross-account `wrapUserScopedBox` guard. | `feedback_writer_reader_field_drift_recurring.md` + `auth_hive_owner_agreement` SoT |
| Reading `configBox.get('isPro')` from a widget | Use `ref.watch(subscriptionInfoProvider).isPro` or wrap the feature in `subscription.gate(feature: ...)`. Root CLAUDE.md §4.4 rules 5+19. | `subscription_state` SoT concept |
| `setState` for state that two widgets share | Promote to a Riverpod provider. `StatefulWidget` is for purely-local widget state (animations, focus, input controllers). | Root CLAUDE.md §4.4 rule 2 |
| Force-unwrap `!` on map keys or `.first` on possibly-empty list | Null-safe the read (`(m['k'] as num?)?.toDouble() ?? 0.0`); guard `.first` with `isNotEmpty`. PR-FIX-2 (2026-04-24) swept 6 instances. | `lib/core/services/CLAUDE.md` (relocated) |
| Date-key built with `DateTime.now().toIso8601String()` instead of IST helper | Always `istDateStr(date)` from `lib/core/utils/ist_date.dart`. Hive keys + cloud `date` columns + counter resets are IST. `feedback_use_ist_throughout.md`. | Root CLAUDE.md §4.5 |
| New feature added without a regression test | Every fix and every contract-bearing write MUST have a `test/contracts/<concept>_writer_to_reader_test.dart` that fails when the field name drifts. Source-grep tests count for presence only — also need a behavioral test (`feedback_source_grep_false_confidence.md`). | Root CLAUDE.md §4.4 rule 21 |

## Tests pinning the rules here

- `test/contracts/` — 100+ writer→reader pinning tests, one per SoT concept.
- `test/lints/` — analyzer-driven checks (no raw `Hive.box(`, no `setState` of
  shared keys, no hard-coded colors outside Wardroom palette).
- `scripts/check_*.dart` — pre-commit gates (`check_writer_reader_drift.dart`,
  `check_subscription_gate.dart`, `check_nested_claude_md_content.dart` — Gate 44).
- `integration_test/flows/` — end-to-end golden flows that exercise every WriteService.

## See also

- `lib/core/services/CLAUDE.md` — WriteService / sync fan-out / Hive contracts.
- `lib/features/<feature>/CLAUDE.md` — per-feature rules.
- `lib/shared/widgets/wardroom/CLAUDE.md` — palette + primitives.
- `docs/architecture/sync.md` — sync schedule + restore-completeness.
- `docs/sot_registry.yaml` — machine-readable concept registry.
