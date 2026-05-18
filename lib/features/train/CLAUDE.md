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

(populated in Milestones 2 + 5)

## Tests pinning the rules here

(populated in Milestone 6)
