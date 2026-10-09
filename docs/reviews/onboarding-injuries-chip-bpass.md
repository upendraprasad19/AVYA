---
branch: onboarding-injuries-chip
review_type: b-pass
blast_radius: account
verdict: accepted
---

# B-Pass Review — `onboarding-injuries-chip` (Ship 3 / U5)

Context-blind adversarial B-pass on the implemented diff (self-initiated before the
`--no-ff` merge, §4.3). Reviewer traced the full writer→reader chain against source
(not prose), ran `flutter analyze` on the changed files, and executed the new tests.

## Verification summary
- **Writer:** `details_screen.dart:145` writes `'injuries': _injuries` into `enriched`
  (which spreads `...widget.data`, `:140`) → `context.go('/onboarding/plan')` (`:147`).
  Details → Plan is **direct** (no intermediate screen), so nothing between them can
  drop the key.
- **Reader:** `plan_screen.dart:531` reads `widget.data['injuries']` →
  `setAnswer('injuries', …)` (`:532–537`).
- **Persistence (load-bearing link):** `onboarding_provider.dart:338` reads
  `a['injuries']` → written into the profile map (`:376`) **and** threaded into
  `generateAndSchedule(injuries: injuries)` (`:460`, normalized centrally in generateV4).
  The chip value genuinely reaches the injury filter — the feature is not inert.
- **Round-trip:** `plan_screen.dart:367–369` "ADJUST PLAN" →
  `context.go('/onboarding/details', extra: widget.data)`; `details_screen.dart:123–127`
  `initState` seeds a **fresh copy** from `widget.data['injuries']`. A real selection
  survives the round-trip.

Confirmed crash-safety / integrity:
- Both reads use `is List` guards (not `as List`) → null / legacy-String / non-List
  fall back to `['none']` without throwing (`details_screen.dart:124`, `plan_screen.dart:534`).
- `toggleChip` (`injury_vocab.dart:81–90`): `.where(...).toList()` growable, list literals
  growable, never empty, `'none'` never co-present with a real injury — pinned behaviorally.
- `chipTokens.toSet() − {none} == canonicalTokens` (both 9) — pinned by the vocab test.
- `_injuries` initState builds a fresh list, so chip mutations don't mutate the incoming
  extras map; plan's `.map(...).toList()` is also fresh — no shared-map mutation either side.
- `edit_profile_screen.dart:1236` refactor is behavior-preserving vs the old inline toggle
  (none-tap, toggle-off-to-empty, add — all equivalent case-by-case).

Brand / rules:
- `_InjuryChip` mirrors `_Chip` exactly: `AppColors.accent` = Campaign Gold `#D4B270`,
  real Wardroom tokens, DM Sans via `AppTypography`, 150 ms cross-fade, `AppRadius.sharp`.
  Content-sized padding for the `Wrap` (intentional). Color inside `BoxDecoration` — no
  `Container(color:+decoration:)` violation. Section header/description identical to the
  other 4 chip rows.
- Onboarding state stays in GoRouter `state.extra` — no premature provider commit; local
  `setState` is compliant. No raw `Hive.box`.
- `flutter analyze` on all 4 changed files: **No issues found**. New tests: **pass**.
  Downstream `injury_filter_behavioral_test.dart` exists (coverage claim valid).

## Findings

### P3 — Re-hardcode guard regex is form-specific → HARDENED IN-BATCH
The wiring test's negative literal check only caught the exact `<String>['none']` shape.
**Resolved in this batch** (not deferred, §4.2): added a POSITIVE guard asserting the
injuries `setAnswer` is fed from the extras-derived `selectedInjuries`
(`= widget.data['injuries']`), so an exotically-reformatted re-hardcode that leaves the
`widget.data` read as dead code now also fails. See
`onboarding_injuries_chip_wiring_test.dart` ("no re-hardcode to [none]", positive guard).

### P3 — Wiring test is source-grep only (by design, disclosed)
Comment-stripped source-grep (correctly strips, per `feedback_source_grep_strip_comments_first`).
Presence-only per rule 21; the runtime path is proven by `injury_filter_behavioral_test`
(downstream filter) + the vocab test's behavioral toggle asserts, and the full onboarding
runtime (auth/sync) is legitimately an integration-test concern. No action required.

No P0 or P1 defects survive verification. Sentinel integrity, crash-safety, writer/reader
wiring, round-trip seeding, vocab-drift pinning, and brand parity all hold against the code.

verdict: accepted
