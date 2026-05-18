---
scope: ai_coach
parent: ../../../CLAUDE.md
created: 2026-05-18
status: scaffold
---

# AI Coach — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/features/ai_coach/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

<!-- MIGRATION IN PROGRESS — content from CLAUDE.md will be moved here in Milestone 2 -->

## Single-source-of-truth contracts

(populated in Milestone 2)

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Mic stops after 2-3 seconds | `pauseFor: 5s`, `listenFor: 60s`, `ListenMode.dictation`, `partialResults: true` via `SpeechListenOptions`. | CLAUDE.md §19 entry 22 (relocated 2026-05-18) |
| "Restart the app" error copy | Never use. Map server errors to actionable user messages in `ai_coach_provider.dart`: `Message too long` → "shorten it", `Snapshot too large` → "try a shorter question", `Image too large` → "max 5 MB", `502/503/504` → "model temporarily unavailable, try in a minute". | CLAUDE.md §19 entry 40 (relocated 2026-05-18) |
| AI breakdown card "didn't log" but data was saved | Test #11 L1 (founder-reported). Data WAS saved correctly to Hive + cloud with `items[]`. Bug was UI: no snackbar / haptic / toast on save → card just disappeared → user assumed failure. Fixed: `AiBreakdownNotifier.saveMeal` now returns `Future<WriteResult>`, card pops `Meal saved ✓` snackbar with `HapticFeedback.lightImpact()`. Plus `_saving` guard prevents double-tap race. **Pattern lesson:** every save action that mutates data MUST give the user a confirmation signal, even if the success is "just" a card vanishing. Compare canonical patterns at `scan_meal_section.dart:445-465` and `food_search_sheet.dart:519`. | CLAUDE.md §19 entry 122 (relocated 2026-05-18) |

## Tests pinning the rules here

(populated in Milestone 6)
