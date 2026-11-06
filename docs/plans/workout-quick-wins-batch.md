# Batch 2 — Quick wins (W3.6 coaching-content panel + W2.6 bodyweight-trend nudge)

Workout-generator overhaul Batch 2 (per `~/.claude/plans/ok-lock-1a-and-atomic-balloon.md`).
Two independent, additive, low-risk items — no engine change, no hard deps. Blast radius:
**account** (W2.6 touches `lib/features/ai_coach/**`; W3.6 alone is feature). Own worktree
`workout-quick-wins` off `64b9e04b`.

## Ground truth (self-verified against code, rule 11 — file:line)

**W3.6 fields** (`assets/data/exercise_library.json`): `coaching_cues` 258/258, `common_mistakes`
258/258, `breathing_cue` 258/258 populated; `warmup_protocol` 213/258 (45 empty). Zero references
under `lib/features/train/`. Active Workout renders each exercise via `_ExerciseCard`
(`lib/features/train/screens/active_workout/exercise_card.dart`) from the `ExerciseData` model
(`lib/features/train/providers/train_provider.dart`) which carries **`name` but NO exercise id**.
The coaching fields live only in the seeded library map (`exerciseBox`), reachable at render time
via `ExerciseRepository` — but the only name lookup today is `search()` which is **pure substring**
(Ship-1 learning: "Push Up" → "Pike Push Up"), so a naive lookup would show the WRONG exercise's
cues. No exact-name getter exists.

**W2.6 lever** (`lib/shared/repositories/plan_engine/training_history_analyzer.dart:162`
`bodyweightTrendSignal()`): DEAD — zero external callers (grep). Computes a robust **28d-vs-prior-28d
mean** bodyweight delta (signed kg, `0.0` when either window empty), reading `healthBox` `weight_*`
rows. `demotedExercises()` (`:107`) is already LIVE (`exercise_selector.dart:535`) — correctly OUT
of scope. **Overlap found:** `PatternDetector._weightTrendAlert()`
(`lib/features/ai_coach/services/pattern_detector.dart:~200`) ALREADY surfaces a weight insight —
but 14-day oldest-vs-newest (2-point, noisy), high-severity, and ONLY on goal-CONFLICT
(`lose_fat`+gain>1kg OR `build_muscle`+loss>1kg). It fires for nobody else and never confirms a
right-direction or neutral trend. Insights surface: `PatternDetector.analyze()` builds a
`CoachingInsight` list → cached in `userBox['pattern_insights']` → read by home
`insight_card.dart` + fed to `ai_snapshot_builder.dart:909` (coach context) + `coach_memory_service`
+ PRO `deep_analysis_card`. No existing `pattern_detector` unit test.

## W3.6 — collapsible per-exercise coaching-content panel (Active Workout)

**Writer:** the seeded library (`exerciseBox`, from `exercise_library.json`). **Reader (NEW):** a
collapsible panel in `_ExerciseCard`.

1. **`ExerciseRepository.getByExactName(String name) → Map<String,dynamic>?`** — case-insensitive
   EXACT match on `name` (NOT substring; guards against the Pike-Push-Up class). Returns the full
   library map or null. (`lib/shared/repositories/exercise_repository.dart`.)
2. **New widget `CoachingContentPanel`** (`active_workout/coaching_content_panel.dart`, authored as
   a `part of 'screen.dart'` — R1-P3b: `exercise_card.dart` and all its siblings are parts of
   `screen.dart`, which already imports exercise_repository / wardroom / theme / spacing / typography;
   a part cannot carry its own imports, so add `part 'coaching_content_panel.dart';` to `screen.dart`).
   A `StatefulWidget` that resolves the library map **in `initState` + re-resolves in `didUpdateWidget`
   only when `exercise.name` changes** and caches it — **NEVER in `build()`** (R1-P3a: the card list
   rebuilds ~1×/sec from the workout timer writing `elapsedSeconds`, and `getByExactName` scans all 258
   maps per call; a build()-time lookup re-scans every second). Renders up to 4 labelled sections,
   **hiding any empty/missing section**, with **per-type reads (R1-P2, crash-avoider)**:
   - `coaching_cues` + `common_mistakes` are JSON **arrays** → read as
     `(map['coaching_cues'] as List?)?.map((e) => e.toString()).toList()` (NEVER `as List<String>` —
     Hive gives `List<dynamic>`, the cast red-screens the focused card mid-workout); render as a
     bulleted list; hide when null/empty.
   - `breathing_cue` + `warmup_protocol` are **strings** → read as `map['breathing_cue'] as String?`;
     render as a single line; hide when `null` OR `.trim().isEmpty` (the 45 empty `warmup_protocol`
     are empty STRINGS `""`, not null — a null-only check would render a bare "WARM-UP" heading, the
     exact thing we're avoiding).
   **Collapsed by default** (a "FORM & CUES" disclosure row), Wardroom palette + DM Sans, mirrors the
   card's existing section styling. FREE (basic form education, not the PRO `deep_analysis_card`).
3. **Insert** into `_ExerciseCard`'s expanded body (`exercise_card.dart`), keyed on
   `widget.exercise.name`.

Risk: name mismatch for swapped/custom exercises → panel shows nothing (graceful). No PII, no
network, no engine change. Feature-tier surface.

## W2.6 — informational bodyweight-trend nudge (dedup vs the existing alert)

**Writer/computed:** `bodyweightTrendSignal()` (existing, now given a caller). **Reader (NEW):** a
new `PatternDetector` detector → `CoachingInsight` → the existing insight surface.

1. **New detector `_bodyweightTrendNudge()`** in `PatternDetector`, added to `analyze()`'s list.
   Uses `TrainingHistoryAnalyzer.bodyweightTrendSignal()` (the 28d-vs-28d mean, signed kg).
2. **Dedup ON THE OUTCOME, not a re-derived predicate (R1-F2·P2, the crux).** `_weightTrendAlert`
   fires off a 14-day 2-point delta while the nudge uses a 28d-vs-28d mean — re-deriving the alert's
   `>1.0` condition on the nudge's different metric provably diverges BOTH ways (a `+0.9`-mean /
   `+1.2`-14d user gets two cards; a `+1.3`-mean / `+0.3`-14d user gets none). So the nudge calls
   `_weightTrendAlert()` and **returns null if it is non-null** (drift-proof; removes the two-threshold
   coupling entirely). It still returns null when `|signal| < 0.8` (no meaningful monthly trend) or
   `signal == 0.0` (insufficient data — either 28d window empty).
3. **Goal-aware copy across ALL 5 canonical `FitnessGoals.tokens` × {up, down} + a goal-neutral
   fallback (R1-F2·P2, load-bearing).** Verified set (`lib/core/constants/fitness_goals.dart:65-112`):
   `build_muscle`(+1.0), `lose_fat`(−1.0), `strength`(+0.5), `general_fitness`(0.0), `recompose`(−0.5)
   — there is **no `maintain`** token, and `_weightTrendAlert` only fires for `lose_fat`/`build_muscle`,
   so **the nudge is the ONLY weight signal for `strength`/`general_fitness`/`recompose`** → every
   token needs real copy. Up on a surplus goal (build_muscle/strength) → confirming; down on a deficit
   goal (lose_fat/recompose) → confirming; a trend AGAINST the goal or on neutral `general_fitness` →
   gentle "weight moved ~Xkg this month — worth a look at calories?" (never shame). Empty/unknown goal
   → goal-neutral factual "weight moved ~Xkg this month." Read the goal from
   **`profile['primary_goal']` via the SAME `_user.getProfile()` read `_weightTrendAlert` uses
   (`:255`)** — reuse it, don't add a new profile read (R2-P3, repo #1 writer/reader-drift class).
   A test asserts a non-empty sensible message for every `FitnessGoals.tokens` entry (each seeded via
   `primary_goal`) + the empty-goal fallback.
4. **`severity: InsightSeverity.low` is LOAD-BEARING (R1-F4·P3).** `_getCoachNotices`
   (`ai_snapshot_builder.dart:911`) filters `severity != low` BEFORE building the coach notices, so a
   low nudge NEVER reaches the AI prompt — this, not the kill-switch, is why there's no AI-snapshot
   pollution. Add a code comment pinning that `low` keeps it out of the snapshot (so a future bump to
   `medium` is a conscious decision). Keep **kill-switch `disable_bodyweight_trend_nudge`**
   (`configBox`, default-ON = missing flag ⇒ enabled, matching the `disable_*` pattern) as cheap
   insurance — reason corrected: it is NOT for AI-adjacency (the severity filter handles that), just a
   standard behavior-change off-switch.

Risk / non-issues (R1-verified): **not** a spam vector — insights are pull-only passive cards,
`CoachingInsight.pushWorthy` has ZERO readers in `lib/` (no notification consumer exists), and the
nudge is `pushWorthy:false`; `analyze()` recomputes each call (it writes but never reads
`pattern_insights` to gate) but that's a passive read, not a re-notify (R1-F3 corrected the plan's
false "cached per-day" claim). Home shows `insights.first` (highest severity) so a low nudge can
never bury a real high/medium alert; among multiple `low` insights Dart's non-stable sort makes which
one shows nondeterministic — PRE-EXISTING (milestone_countdown + weekend_nutrition are already low),
accepted, not introduced here (R1-F5). IST: uses the existing healthBox date parsing (unchanged).
Account-tier (ai_coach).

## Tests (rule 21 — behavioral, not source-grep)

- **W3.6 `coaching_content_test.dart`:** (a) `getByExactName('Barbell Bench Press')` returns a map
  with non-empty `coaching_cues`/`common_mistakes`/`breathing_cue`; (b) exact-name does NOT substring-
  match ("Push Up" ≠ "Pike Push Up"); (c) a non-existent name → null (hide path). Plus a library
  contract assertion: all 258 rows carry non-empty `coaching_cues`/`common_mistakes`/`breathing_cue`
  (catches a library regression that would blank the panel).
- **W2.6 `bodyweight_trend_nudge_test.dart`:** Hive-seeded `healthBox` weight_* rows →
  `PatternDetector.instance.analyze()` — (a) a clear +1.2kg/28d trend on `general_fitness` yields the
  nudge insight (low severity); (b) DEDUP-ON-OUTCOME: a `lose_fat`+14d-gaining user gets the EXISTING
  `weight_trend_up` alert and NOT the nudge; (c) flat/insufficient data → no nudge; (d) kill-switch ON
  → no nudge; (e) GOAL COVERAGE: iterate every `FitnessGoals.tokens` entry (+ an empty-goal profile)
  and assert the nudge's `userMessage` is non-empty and sensible for both an up and a down trend (the
  nudge is the sole weight signal for strength/general_fitness/recompose).

## NOT in scope (explicit)

- `demotedExercises()` — already wired (out of scope, verified).
- Changing `_weightTrendAlert`'s existing logic/thresholds — left verbatim; the nudge is additive +
  deduped around it.
- PRO-gating the coaching panel — it's free basic education.
- W2.6 does not modify any plan-engine behavior — purely an insight surface.

## Discipline

Account tier → ×2 context-blind plan review (this doc) → `docs/plan-reviews/workout-quick-wins.md`
(converged) → self-B-pass before `--no-ff` merge (§4.3). SoT: W3.6 read-only display (contract test
pins field presence + exact-name lookup); W2.6 add a `bodyweight_trend_nudge` writer/reader entry.
Both items reach terminal state in THIS batch (§4.2). `feat` commits — no diagnose-doc (no bug).
