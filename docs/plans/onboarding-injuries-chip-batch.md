# Ship 3 — U5 onboarding injuries chip (Option B: pre-selected default)

Branch `onboarding-injuries-chip`, off main WITH Ships 1+2 (InjuryVocab + the
injury filters are all live). Ship 3 (last) of the workout-generator injury
batch. Blast radius **account** (onboarding UI + plan-screen read-side).

## Problem
Onboarding never collects injuries: `plan_screen.dart:525` hardcodes
`notifier.setAnswer('injuries', <String>['none'])`. So the injury filters
shipped in Ships 1+2 (main cascade, universal pool, warmup/cooldown) have NO
onboarding-collected data to act on — a user's injuries only reach the engine if
they later open Edit Profile or the AI-coach muster. New users get no injury
protection on their FIRST plan.

## Founder decision (2026-07-12): Option B — pre-selected "No injuries" default
Frictionless, matches the Details screen's other 4 pre-selected chip rows
(CONTINUE always works). The injuries question is now VISIBLE at onboarding, so
`['none']` is a genuine "saw it, none" answer. Accepted tradeoff: a silent-
injured user (leaves the default) still gets `['none']` and isn't nagged by the
home completeness nudge — that's the frictionless choice. (Option A = mandatory
tap, rejected for funnel friction.)

## Scope (writer → reader, named)
1. **details_screen.dart** — add a MULTI-select injuries chip row (the other 4
   rows are single-select `_ChipSection`, so injuries needs its own multi-select
   row — duplicate Edit-Profile's `_buildInjuriesChips` pattern: canonical
   `InjuryVocab.canonicalTokens` + a `none`-toggle where tapping a real injury
   clears `none` and vice-versa). State `_injuries` DEFAULT `['none']` (pre-
   selected "No injuries"). Add `'injuries': _injuries` to the `enriched` route-
   extras map (built :121-127) → passed to `/onboarding/plan`.
   **⚑ CORRECTION (×2 review, verified):** `initState` MUST ALSO seed `_injuries`
   from `widget.data['injuries']` (GROWABLE list, fallback `['none']`) — like the
   4 sibling chips at :112-115 — or the existing "ADJUST PLAN" back-nav
   (`plan_screen.dart:367` → `/onboarding/details`) resets the selection to
   `['none']` on the plan→details→plan round-trip, silently dropping it before
   generation. Use a GROWABLE list (`[...]`/`List<String>.from`), since the
   none-toggle calls `.remove`/`.add`.
2. **plan_screen.dart:525** — read `widget.data['injuries']` (crash-safe:
   `(widget.data['injuries'] as List?)?.cast<String>() ?? const ['none']`)
   instead of the hardcoded `['none']`. PRESERVE the `['none']` sentinel (do NOT
   InjuryVocab-normalize here — the profile convention is `['none']` for "no
   injuries", which the home nudge + Edit-Profile reader expect; the GENERATOR
   normalizes centrally when it reads, Ship 1). The `_onReportForDuty` inference
   fallback (legacy chat users, missing `widget.data`) keeps `['none']`.
3. Vocabulary: the chip tokens MUST be the canonical set (lower_back not back,
   incl. elbow/neck/hamstring) — reuse `InjuryVocab.canonicalTokens` so
   onboarding matches Edit Profile (Ship 1) exactly. Label "Lower Back" etc.

## NOT in scope (verified, not deferred)
- Nudge change: NONE needed. The visible pre-selected chip makes `['none']` a
  genuine answer; `profile_completeness_provider` already treats a non-empty
  injuries list as answered (the 2026-04-17 convention). Option B accepts that a
  default-`['none']` user isn't nagged — that's the frictionless choice, not a bug.
- Edit-Profile chip widget: private screen method → DUPLICATE the pattern in
  details_screen (per plan guidance), do NOT import a private method.

## Verification
`test/contracts/onboarding_injuries_chip_*_test.dart`: (a) details_screen's
`enriched` extras carry the selected injuries (pure widget/logic test of the
chip state → extras map); (b) end-to-end — onboarding with a knee selection →
completeOnboarding writes `profile['injuries']` containing `knee` (Hive), and a
default (untouched) onboarding writes `['none']` (byte-identical to today). The
plan_screen read-side no longer emits a hardcoded `['none']` when the user
selected an injury.

## ⚑ HARDENED after ×2 review (2026-07-12) — verdict: harden-then-implement (converged, no split)

Both reviewers converged; I verified the round-trip bug against code. Resolutions:
1. **P1-A (BLOCKING, folded above):** seed `_injuries` from `widget.data['injuries']`
   in `details_screen.initState` — the ADJUST-PLAN round-trip drops it otherwise
   (ships the very bug the batch fixes).
2. **P1-B (BLOCKING):** seed as a FRESH GROWABLE list (`List<String>.from(...)`),
   NEVER a `.cast<String>()` view — a `CastList`'s `.add`/`.remove` delegate to
   the underlying SHARED `widget.data` list (mutates shared state + throws on a
   fixed-length source).
3. **P1-C (BLOCKING — test):** the behavioral test must prove the batch's point
   END-TO-END: onboarding with `['knee']` → `completeOnboarding` → the GENERATED
   schedule contains ZERO knee-contraindicated exercises (not merely
   `profile['injuries']` contains knee). Plus toggle-INVARIANT assertions:
   `['none', X]` never producible; deselect-all → `['none']`; select-X clears `none`.
4. **P2-A (fold in — structural anti-drift):** two unpinned hardcoded chip lists
   (Edit-Profile + onboarding) reopen Ship-1's vocab-drift guarantee. FIX: add a
   SINGLE shared source `InjuryVocab.chipTokens` (curated UI order = `['none']` +
   the 9 canonical) + `InjuryVocab.chipLabel(token)`, consumed by BOTH
   details_screen AND edit_profile (mechanical refactor of the hardcoded list).
   Pin with a contract test: `chipTokens.toSet() == {'none'} ∪ canonicalTokens`.
5. **P2-B:** chip ORDER = the curated Edit-Profile order (knee, lower_back, …),
   NOT alphabetical `canonicalTokens` iteration — `chipTokens` carries that order.
6. **P2-C:** plan_screen read uses the type-check form (`v is List ? v.cast… :
   const ['none']`), NOT `as List?` (throws on a legacy String) and NOT
   `InjuryVocab.normalize` (strips the `['none']` sentinel).

Confirmed sound by both: toggle logic, nudge non-impact, sentinel preservation,
write→read chain, default byte-identity.

## Discipline
- [x] Own worktree (onboarding-injuries-chip), own focused plan (this doc).
- [x] ×2 context-blind review DONE + converged (ground-truth + design); record → `docs/plan-reviews/onboarding-injuries-chip.md`.
- [ ] ×2 context-blind review of THIS plan (§4.12) → `docs/plan-reviews/onboarding-injuries-chip.md`.
- [ ] Behavioral test + diagnose-doc (onboarding injury-drop) + SoT (extends
  injury_vocabulary_contract with the onboarding writer); self B-pass (account-
  tier) before merge; commit/merge/push autonomously.
