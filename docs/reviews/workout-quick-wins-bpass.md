---
branch: workout-quick-wins
review_type: b-pass
blast_radius: account
verdict: accepted
---

# B-Pass Review — workout-quick-wins (Batch 2: W3.6 + W2.6)

Context-blind adversarial B-pass on the implemented diff (self-initiated before the
`--no-ff` merge, §4.3). Every claim verified against source + the real
`assets/data/exercise_library.json` (258 rows).

## Verified (against ground truth)

- **W3.6 panel crash-safety — SAFE.** `_stringList` guards `is! List` then coerces each
  element via `.toString().trim()` (never `as List<String>`, which would red-screen on Hive's
  `List<dynamic>`). `_cleanString` handles null/non-String/empty. Real JSON: coaching_cues 258/258
  arrays, common_mistakes 258/258, breathing_cue 258/258 strings, warmup_protocol 213 + 45 empty
  strings (suppressed), 0 non-string array elements. `getByExactName` returns a growable
  `Map.from(raw)`; no null-deref path (`map?[...]` throughout).
- **W3.6 lifecycle — CORRECT.** `_resolve()` in `initState`; the card is keyed
  `ValueKey('coaching_<name>')` so a swap mints fresh State → re-resolve. `didUpdateWidget` branch
  is dead-but-harmless (documented). Never resolves in `build()` (the card rebuilds ~1×/s off the
  workout timer). `_expanded` is purely-local UI `setState` (allowed).
- **W3.6 placement/wiring — CORRECT.** Inside `if (widget.isExpanded)`; superset bar unaffected;
  `part` + imports correct; no-match → `SizedBox.shrink()` with no wrapping padding (zero layout gap
  for swap/custom).
- **W2.6 dedup — CORRECT & SAFE.** `_weightTrendAlert()` is pure-read, so the extra call is
  side-effect-free; when it fires (lose_fat-up / build_muscle-down) the nudge returns null → never
  two weight cards.
- **W2.6 copy/goals/severity — CORRECT.** All 5 `FitnessGoals` tokens + empty/default handled with
  distinct non-empty copy; reads `primary_goal`; `severity: low` filtered by `_getCoachNotices`
  (`ai_snapshot_builder.dart:911`) so it never reaches the AI prompt; home `getTopInsight()` does not
  filter low, so it surfaces when highest. Kill-switch default-ON.
- **Tests — NON-VACUOUS.** Dedup test forces `weight_trend_up` (14-day +1.5) while the 28-day signal
  would otherwise fire the nudge → fails without the dedup line. Goal-coverage seeds recent all-equal
  (14-day delta 0) so the alert can't mask the nudge. `getByExactName` exact-not-substring test is
  robust. (Hardened post-review: the goal-coverage test now asserts `build_muscle` ≠ `lose_fat` copy
  on the same trend — proving goal-awareness, not just non-empty — P3-4.)
- **Brand/rules — CLEAN.** `AppColors.accent = 0xFFD4B270` (Campaign Gold); DM Sans via
  `AppTypography`; `Container` uses `decoration:` only; no new IST date-keys.

## Findings

**P0/P1/P2: none.**

**P3 (non-blocking):**
1. W3.6 not in `sot_registry.yaml` (only nested train/CLAUDE.md). Reviewer: "arguably out of registry
   scope (read-only display of static seed data, no Hive-write drift risk); `coaching_content_test`
   pins both the exact-match semantic and library-field population — an asymmetry note, not a drift
   gap." **Resolution:** kept documented in the nested CLAUDE.md (the right home for a read-only
   seed-display contract) + pinned by the contract test — not a deferral, a scope judgment.
2. `pattern_detector.dart` redundant `signal == 0.0` guard (subsumed by `< 0.8`). **Kept** — documents
   the "insufficient data ⇒ 0.0" intent (reviewer: harmless).
3. `_weightTrendAlert()` runs twice per `analyze()` (dedup-on-outcome). **Kept** — intentional +
   negligible on a small box.
4. Goal-coverage test asserted only non-empty. **FIXED in-batch** (§4.2): added the goal-aware
   `build_muscle` ≠ `lose_fat` assertion.
5. Pre-existing stale `analyze()` "once per day" doc. The stale CLASS-level copy was **removed in this
   batch**; the remaining method-level "cached … with today's date" is accurate (out of scope).

VERDICT: accepted
