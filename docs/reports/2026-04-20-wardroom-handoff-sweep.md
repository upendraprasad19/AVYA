# Wardroom Handoff Enforcement — Sweep Report

**Branch:** `feat/wardroom-handoff-enforcement`
**Base:** `ba0a754` (main before merge)
**Merge commit:** `e3d5aaf` (`feat: Wardroom design handoff enforcement — 14-screen sweep (PRs R–AF)`)
**Merged to:** `main` on 2026-04-20

---

## 1. Scope & Timeline

- **Start:** 2026-04-18
- **End:** 2026-04-20
- **Commits on branch:** 17 (16 PRs R–AF + 1 post-PR nav fix)
- **Screens touched:** 14

| Screen | Route | Token changes | New primitives used | Structural changes |
|---|---|---|---|---|
| Daily (Home) | `/home` (tab 0) | accent cyan→gold across header + cards | WardDispatchHeader, WardInsightQuote, WardBar w/ trailingLabel | Dispatch eyebrow replaces old title; insight quote block slots between streak and quick actions |
| Train | `/train` (tab 1) | gold week chips, gold phase badge | WardPhaseDots, WardPhaseBlock, WardLetterhead (double divider) | Week chip format `W1/W2/W3/W4` (was `WK 01/…`); phase block header replaces stacked title+subtitle |
| Active Workout | `/train/active` | bgRaise rest-timer card, gold CTA | WardSessionRow, WardSessionTable, WardUnitToggle | Set rows unified into table shell; KG/LBS pill moved into row |
| Nutrition (Galley) | `/nutrition` (tab 2) | gold accents, parchment text on bgDeep sidebar | WardCategorySidebar, WardStatTile | Rotated category sidebar replaces top pill row; stat tiles for kcal/P/C/F |
| AI Coach | `/coach` (tab 3) | dispatch header, italic-gold emphasis spans | WardDispatchHeader | Dispatch eyebrow above chat; context line shows today's date |
| Onboarding — Welcome | `/onboarding` | full Wardroom palette | WardFrame, WardLetterhead, WardButton | NEW screen — entry to stepped flow |
| Onboarding — Goal | `/onboarding/goal` | gold radio border | WardRadioRow | NEW screen — primary_goal selection |
| Onboarding — Stats | `/onboarding/stats` | gold inputs, unit pill | WardUnitToggle | NEW screen — weight/height/age/sex |
| Onboarding — Plan | `/onboarding/plan` | gold phase dots + START chip | WardPhaseDots, WardPhaseBlock, WardSealBadge | NEW screen — "REPORT FOR DUTY" CTA |
| Profile banner | `/profile` (tab 4) | none (layout only) | — | Banner height bump + identity widget |
| Settings | `/profile/settings` | gold accents | WardLetterhead, WardKvRow, WardToggle | Section headers use letterhead; toggles use WardToggle |
| Edit Profile | `/profile/edit` | dispatch header | WardDispatchHeader | Header replaced with dispatch variant |
| Weekly Reports | `/profile/reports` | dispatch header + parchment | WardDispatchHeader, WardSealBadge | Report cards use dispatch eyebrow; seal badge on cover |
| Notifications Inbox | `/profile/notifications` | full Wardroom | WardLetterhead, WardCard, WardChip | NEW screen — sample-data inbox list |

---

## 2. What Shipped — PR Table

All commits on the `feat/wardroom-handoff-enforcement` branch between `ba0a754` (base) and `e3d5aaf` (merge):

| PR / Fix | Commit | Summary | Screen(s) |
|---|---|---|---|
| R | `174ff21` | primitive reconciliation + wardroom copy constants | (foundation — `colors.dart`, `wardroom_copy.dart`) |
| S | `d5df10b` | wardroom daily screen structural redo | Daily (Home) |
| T | `9eea0be` | wardroom train plan structural redo | Train (incl. `W1/W2/W3/W4` week chips) |
| U | `717f078` | wardroom active workout visual polish | Active Workout |
| V | `ace3669` | wardroom nutrition (galley) structural redo | Nutrition |
| W | `07d7a01` | wardroom ai coach dispatch eyebrow | AI Coach |
| X | `0edca78` | wardroom profile banner height | Profile banner |
| Y | `f0c82e0` | wardroom onboarding welcome screen | Onboarding — Welcome (NEW) |
| Z | `9d24160` | wardroom onboarding goal screen | Onboarding — Goal (NEW) |
| AA | `57b1320` | wardroom onboarding stats screen | Onboarding — Stats (NEW) |
| AB | `5d658a1` | wardroom onboarding plan screen + 12-week campaign | Onboarding — Plan (NEW) |
| AC | `80f8a6d` | wardroom settings screen | Settings |
| AD | `c46f6e6` | wardroom edit profile header | Edit Profile |
| AE | `4628f04` | wardroom weekly report dispatch header | Weekly Reports |
| AF | `d13ce74` | wardroom notifications inbox | Notifications Inbox (NEW) |
| Nav fix | `17faa86` | stepped-flow navigation was being blocked by auth redirect | `GoRouter._authRedirect` (touches all stepped onboarding routes) |
| Merge | `e3d5aaf` | merge to main | — |

---

## 3. New Primitives (13 added, 15 → 28 total)

| Name | File | Purpose | Where used |
|---|---|---|---|
| WardSealBadge / WardSealVariant | `ward_seal_badge.dart` | Seal glyph in 4 variants (report / subscription / phase / founder) | Weekly Reports, Onboarding Plan |
| WardDispatchHeader | `ward_dispatch_header.dart` | Double gold rule + eyebrow + italic-gold emphasis + context line | AI Coach, Edit Profile, Weekly Reports |
| WardInsightQuote + InsightSegment | `ward_insight_quote.dart` | Gradient card with gold quote watermark + segmented body | Daily (Home) |
| WardGlassGrid | `ward_glass_grid.dart` | 8-cell hydration tracker grid | Daily (Home), Nutrition |
| WardAchievementStrip | `ward_achievement_strip.dart` | Horizontal earned/locked circles | Profile (deferred wiring — PR AG) |
| WardPhaseDots | `ward_phase_dots.dart` | 12-phase progress row | Train, Onboarding Plan |
| WardPhaseBlock | `ward_phase_block.dart` | Roman numeral circle + title/weeks/description + START chip | Train, Onboarding Plan |
| WardStatTile | `ward_stat_tile.dart` | Mono label + Fraunces numeric + unit | Nutrition stat tiles, Daily snapshot |
| WardRadioRow | `ward_radio_row.dart` | 44px tap row with gold left-border when selected | Onboarding Goal, Settings |
| WardToggle | `ward_toggle.dart` | 36×20 pill toggle, 150ms crossfade | Settings |
| WardUnitToggle | `ward_unit_toggle.dart` | KG/LBS 2-position inline pill | Onboarding Stats, Active Workout |
| WardSessionRow / WardSessionTable | `ward_session_row.dart` | Set-log row + table shell | Active Workout |
| WardCategorySidebar | `ward_category_sidebar.dart` | Vertical 46px `bgDeep` with rotated mono label | Nutrition (Galley) |

Additionally, existing primitives were extended in PR R:
- `WardBar` gained `trailingLabel` slot for gold "25%" mono numeral
- `WardLetterhead` gained `dividerStyle: WardDivider` enum (none / single / double); legacy `divider: bool` retained for backward-compat

---

## 4. Copy Catalogue (`lib/core/copy/wardroom_copy.dart`)

Single source for all literal handoff strings. Never inline a Wardroom string in a widget — reference this file. Categories:

- **Eyebrows** — section mono labels (`"DAILY DISPATCH"`, `"CAMPAIGN PLAN"`, `"MESS GALLEY"`, etc.)
- **Feature ticks** — bullet items on Welcome / Plan screens
- **CTA labels** — `"REPORT FOR DUTY"`, `"START CAMPAIGN"`, `"LOG SET"`, etc.
- **Onboarding copy** — stepped flow prompts, placeholders, helper text
- **Notification sample data** — seed entries for Notifications Inbox (placeholder until OneSignal wiring ships in PR AG)

Extending the copy: add a new `static const` to the appropriate section in `wardroom_copy.dart`. Grouping is by screen/surface, not alphabetical.

---

## 5. Known Gaps (PR AG Candidates)

Grouped by screen, each with rationale for deferral:

### Nutrition
- **Meal-slot cards** — Galley structural redo (PR V) landed the sidebar + stat tiles but the actual meal-slot content cards (Breakfast / Lunch / Dinner / Snacks with per-meal macros and food chips) kept the old pre-Wardroom layout. Rationale: content cards are the bulk of the screen and warranted a focused PR to avoid a 500-line diff inside PR V.

### AI Coach
- **Today's Insight** section — dispatch header (PR W) landed; the insight card sequence (3-tier insight: data-driven / motivational / plan-reminder) was left on the old layout.
- **Suggested Actions** — 3-chip action row (tap to prefill chat) deferred.
- **Patterns** — weekly pattern detector card (e.g. "You train 80 % of Tuesdays") deferred.
- Rationale: these three sit below the dispatch header as distinct surfaces; each maps to a separate coach_memory signal and deserves its own PR.

### Profile
- **Journey card** — 12-phase overview with current phase highlighted; blocked on finalised copy for phase names.
- **Body Stats** — weight / BF% / measurements stacked card (currently lives as separate rows).
- **Achievements** — `WardAchievementStrip` was shipped (PR R) but isn't wired to real `user_achievements` data yet.
- **Subscription Seal** — `WardSealBadge` variant (`subscription`) exists; Profile needs the surrounding card layout.

### Onboarding
- **Stepped-flow field coverage** — these fields are still defaulted server-side because the stepped flow doesn't collect them: `fitness_experience`, `days_per_week`, `equipment_access`, `lifestyle_activity`, `pace_preference`, `diet_preference`, `injuries`, target weight. Plan generator currently uses sensible defaults, but users can't personalize until they re-enter Settings post-onboarding.

### Notifications Inbox
- **Real-data wiring** — currently shows sample data from `wardroom_copy.dart`. Needs an inbox Hive box reader + OneSignal payload persistence so in-app messages show alongside push history. Deferred because the persistence layer didn't exist yet.

---

## 6. Business-Logic Preservation Audit

Files intentionally **NOT** touched during the 14-screen sweep — this was a design-only branch:

- `lib/shared/repositories/plan_generator.dart` and everything under `lib/shared/repositories/plan_engine/` — CLAUDE rule #14 (never modify without approval)
- `supabase/functions/**` — no Edge Function changes
- `android/`, `ios/` — no platform code changes
- `pubspec.yaml`, `pubspec.lock` — no new dependencies added (all primitives use existing `google_fonts`, `flutter_svg`, core Flutter)
- `.env`, `google-services.json`, any secrets — untouched
- `memory/feedback_*.md` — all existing feedback memory preserved
- Existing `project_*.md` memory files (bug_batch_3, plan_generator_v3, qa_environment, etc.) — untouched
- `assets/data/exercise_library.json`, `assets/data/food_database.json` — no seed changes

Verified by diffing `ba0a754..e3d5aaf --stat`: all changes are under `lib/` (UI), `lib/core/copy/wardroom_copy.dart` (new copy file), and the router glue fix in `lib/core/router/`. No business-logic directories were modified.

---

## 7. Verification Performed

### `flutter analyze` (main worktree, post-merge)
```
4 issues found. (ran in 41.1s)
  warning - unused_local_variable — test/plan_engine_v3_test.dart:1750 (phase1Weeks)
  warning - unused_local_variable — test/plan_engine_v3_test.dart:1756 (phase5Weeks)
  warning - unnecessary_null_comparison — test/plan_generator/v4_diagnostic/cascade_tracer.dart:107
     info - unintended_html_in_doc_comment — test/plan_generator/v4_diagnostic/library_integrity.dart:23
```
All 4 are **pre-existing** and live in test files only. 0 new issues introduced by the sweep. 0 errors in `lib/`.

### On-device smoke test (prod APK, pre-merge)
- Launched from fresh install (Hive boxes empty)
- Flow: Welcome → Goal → Stats → Plan → "REPORT FOR DUTY" — all 4 transitions advanced correctly
- Confirmed the post-PR-AF `_authRedirect` fix (commit `17faa86`) — before this fix, every tap past Welcome was silently redirected back to `/onboarding`. Post-fix, sub-routes navigate cleanly.
- Hot-restart from `/onboarding/plan` stays on Plan (doesn't bounce).

### APK artifact
- Path: `.claude/worktrees/wardroom-handoff-enforcement/build/app/outputs/flutter-apk/app-prod-release.apk`
- Flavor: `prod`
- Build mode: `release`
- Built with `--dart-define-from-file=.env`

---

## 8. Branch & APK Locations

| Thing | Path |
|---|---|
| Merged branch tip | `e3d5aaf` on `main` |
| Branch (not yet deleted) | `feat/wardroom-handoff-enforcement` |
| Branch worktree | `C:\Upendra\Claude Code\Fitness App\.claude\worktrees\wardroom-handoff-enforcement\` |
| Main worktree | `C:\Upendra\Claude Code\Fitness App\` |
| Pre-merge rollback tag | *(not tagged — rely on reflog: `git reflog show main` shows `ba0a754` as the pre-merge tip)* |
| Prod APK | `.claude/worktrees/wardroom-handoff-enforcement/build/app/outputs/flutter-apk/app-prod-release.apk` |
| APK SHA1 | `.claude/worktrees/wardroom-handoff-enforcement/build/app/outputs/flutter-apk/app-prod-release.apk.sha1` |

---

## 9. Recommended Next Steps

PR AG prioritisation (highest user-visible impact first):

1. **Nutrition meal-slot cards** — the most-used surface still carrying pre-Wardroom layout. Users tap into it 3–5× per day. Expected diff size: ~400 LOC.
2. **Coach Today's Insight + Suggested Actions** — raises perceived intelligence of the AI coach the moment a user opens the tab. Maps cleanly to existing `coach_memory` signals; no new server plumbing needed.
3. **Profile Journey card + Body Stats + Subscription Seal** — the Profile tab currently looks the least "done" of all 5 tabs; banner height fix (PR X) made the mismatch more visible.
4. **Onboarding stepped-flow field coverage** — add `fitness_experience`, `days_per_week`, `equipment_access`, `lifestyle_activity`, `pace_preference`, `diet_preference`, `injuries`, and target weight as dedicated steps (or a single "refine your plan" post-welcome step). Unblocks server-side personalization.
5. **Notifications real-data wiring** — create an `inbox` Hive box, persist OneSignal payloads, read in Notifications screen. Swap sample data out of `wardroom_copy.dart`.

After PR AG ships, delete the legacy `/onboarding/chat` route and `onboarding_chat_screen.dart` per CLAUDE §13a (retained only for rollback).
