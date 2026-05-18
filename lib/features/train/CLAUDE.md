---
scope: train
parent: ../../../CLAUDE.md
created: 2026-05-18
status: scaffold
---

# Train (Active Workout + Templates) — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/features/train/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

<!-- MIGRATION IN PROGRESS — content from CLAUDE.md will be moved here in Milestone 2 -->

## Single-source-of-truth contracts

### Logging types (drives Active Workout UI)

| logging_type | UI Shows |
|---|---|
| `weight_reps` | Weight (kg) + Reps + Sets |
| `bodyweight_reps` | Reps + Sets (no weight input) |
| `weighted_bodyweight` | Added Weight + Reps + Sets |
| `timed` | Sets + Duration (seconds) + rest timer |
| `cardio` | Duration (min) + Distance (km) |
| `distance` | Distance + load |

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Warm-up sets counted in completedSets | `completedSets` getter filters out `warmUpSets` keys. Exercise name matching uses exact-first, fuzzy only for names >= 6 chars. | CLAUDE.md §19 entry 31 (relocated 2026-05-18) |
| WarmupCooldownSection RangeError | `didUpdateWidget` resets `_checked` list when `widget.exercises.length` changes. Always guard list length on rebuild. | CLAUDE.md §19 entry 32 (relocated 2026-05-18) |
| Phase 2-12 invisible to free users | Train screen previously capped the week selector at 4 weeks — free users couldn't see what they were paying for. APK Test #2 / Q7 extends the selector to 12 weeks (3 phases) with PHASE I / II (PRO) / III (PRO) headers + lock glyph on weeks 5–12 for free users. Tap any locked week → `/train/preview?phase=II&week=5&day=1` renders a real workout via `previewPlanProvider` (calls `PlanGenerator.instance.generateV4()` with the user's actual profile — goal/equipment/days/experience). State-aware banner: "Complete Phase I to unlock Phase II — your AI coach generates the next 4 weeks the moment you finish." Free users see UPGRADE TO PRO bottom CTA + cross-link to `/train/roadmap`. | CLAUDE.md §19 entry 99 (relocated 2026-05-18) |

## Tests pinning the rules here

(populated in Milestone 6)
