---
branch: oi494-food-search-date
scope: OI-494 (diagnose 4f9b2e). istNow() is UTC-flagged, so passing it into istDateStr or a WriteService date shifts the IST day twice. A food-search or coach-food-card meal logged from 18:30 IST landed on tomorrow, on every device. The coach snapshot's week window and step history ran a day ahead in the evening. Fix: pass the wall instant (nowWall()) at three sites, move the last istNow() timestamp stamps to the UTC instant, correct the istNow() doc comment, and add a behavioural regression file whose guard bans any istNow token in lib/ outside ist_date.dart.
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/a138ffb4ec21-review.md
---

# Plan-review record: OI-494 istNow() double shift

Plan: `docs/plans/oi494-ist-double-shift.md`. Diagnose doc: `docs/diagnoses/2026-11-11-ist-now-double-shift-food-search-4f9b2e.md`. Tier M (touches `ai_coach` and `core/utils`, recurrence class). Each round used one context-blind Sonnet reviewer with `docs/agent_brief_preamble.md` prepended and an exhaustive read-only command list (it could run only the new test file). Every round ran on the staged diff after the full gate loop: whole-project `flutter analyze --no-fatal-infos`, the full `TZ=Asia/Kolkata flutter test test/ --exclude-tags golden`, and the pre-commit gate loop.

## Round 1 (plan rev 1, staged diff)
Verdict: converged, no P0 or P1. The reviewer re-derived the root cause from `ist_date.dart`, reasoned through the IST boundaries (Sunday 22:30, Monday 03:00 IST), traced every `istNow` token in `lib/` (including a local variable of that name in `workout_repository.dart:641`) and every other `logMeal` caller, ran the new file under both zones, and checked `supabase/functions/` cheaply (the server helper reads `getUTC*` on the shifted value, which is the correct pattern).
- P2-1: the `tool_dispatcher.dart:1713` local-midnight date parse lived only in the plan's prose. Fixed: written into the OI-493 entry in `docs/audit/open_issues.md` in this commit.
- P2-2: test D's comment strip cut each line at its first `//`, so `'http://...'; istNow()` hid a call, block comments were not stripped, and a tear-off `istNow;` slipped past the `\bistNow\(\)` regex. Fixed: a string-aware comment stripper (strings, raw, triple quotes, nested interpolations, nested block comments) and an `istNow` token regex. D0 pins the stripper with 11 cases. The local variable in `workout_repository.dart` is allowlisted with its reason. Mutants MD1 (strings not recognised) and MD2 (old call-only regex) both go red in both zones (diagnose doc table).
- P3-1: plan table line numbers are pre-fix. Labelled "on main, before the fix".
- P3-2: claimed `sync_profile.dart:838/893` were off by about 2. Rejected: line 838 holds the "server-set and never pushed" comment and 893/895 hold the two `..remove('updated_at')` calls (checked with `sed -n`).
- P3-3, P3-4: the live query and the mutants were not re-run by the reviewer (UNVERIFIED on its side). Both were run by the coordinator and are recorded in the diagnose doc.

## Round 2 (plan rev 2, staged diff after round 1's fixes)
Verdict: converged, no P0 or P1. This seat focused on design and failure modes: it traced an evening log end to end (key, `date`, `logged_at`/`created_at` from the real UTC instant at `nutrition_write_service.dart:112-113`), checked the week window for all 7 IST weekdays including 00:00-05:30 IST on a UTC host, searched every date helper use in `lib/features/ai_coach/` (no other shifted value), read the comment stripper for termination and quoting, and confirmed the clock seam does not leak and the repointed tests are tighter, not looser.
- P2-1: the `DeleteNutritionLogNotifier.delete` range moved by a mechanical +3 from a range that was already stale on main. Fixed: re-anchored.
- P2-2: other registry ranges for the changed files were stale (most already on main; the parity gate checks bounds only). Fixed: all 19 `line_range` entries citing `nutrition_provider.dart` and `ai_snapshot_builder.dart` recomputed from each method's own start and end (class line included where the gate keys on it), and the water `ist_sites` line 409 (a blank line) corrected to 412, the `build()` declaration (the convention of the sibling `setWaterMl` entry; a first try at 417, the `istDateStr` call, was refused by the gate, which wants the class within 5 lines). Parity gate green.
- P3-1: B2 is green on main too, so it pins the M4 mutant (host-zone weekday), not the original bug. Accepted: the plan and the diagnose doc now say so; A, B and C are the tests that fail on main.
- P3-2: whole-day `Duration` arithmetic could be a day off near a host DST change. Rejected: the arithmetic is on an instant and `istDateStr` converts to UTC before adding 5:30, so the host zone (and its DST) never enters; IST has no DST.
- P3-3: a stray wrong-day row can be replaced by a real log of the same food and slot on that day (same `computeLogKey`). Accepted as a documented edge (testers only); noted in the diagnose doc's Data section.

Both rounds converged with no P0 or P1, so the plan was not split.

## B-pass (code review, two seats, `docs/reviews/a138ffb4ec21-review.md`)
Both seats were context-blind Sonnet reviewers with the preamble and an exhaustive read-only command list, each dispatched after a green full gate loop. Neither found a P0, P1 or P2.
- Seat 1 (whole diff): 3 P3. The water `ist_sites` line was rejected as a false alarm (the gate's 5-line window refuses the suggested line). The per-file allowlist in guard D could not tell a safe use from an unsafe one in the same file, so every remaining `istNow` use in `lib/` was moved (profile `updated_at` and snapshot photo `taken_at` now write the UTC instant; a local variable was renamed) and D became zero-tolerance. New test E pins the profile stamp with a LOCAL clock; mutants M5-M7 are red. The comment edit in `sync_profile.dart` this needed makes the diff `platform` by path, and the frontmatter says so.
- Seat 2 (that delta): 3 P3. A stale "IST ISO-8601" class doc was fixed, and M7 was labelled presence-only. The onboarding `updated_at` format predates the diff and nothing reads it, so it needed no change.
Verdict accepted; the code landed as `05d96854`.
