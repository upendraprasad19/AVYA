---
reviewed_at: 2026-08-10T21:40:00+05:30
staged_against: 065a91fc
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 3
verdict: accepted
---

# Code Review — 065a91fc (B-pass, branch `google-signin-misroute`)

Fresh context-blind Sonnet reviewer, dispatched per `.claude/skills/code-review/SKILL.md`.
All three findings were independently verified against the code before acceptance
(`feedback_audit_verifier_cannot_trust_own_subagent`: subagents quote reliably and reason
unreliably — every claim below was re-read at its cited file:line first).

**All three fixed in the same batch** (§4.2 no-deferrals).

## Finding 1 — P0 — guard_without_its_mirror — FIXED

- **file:line:** `lib/features/auth/screens/restoring/state.dart` `_onContinueAnyway`
  (was `restoring_screen.dart:605-628` at review time), interacting with
  `lib/core/router/app_router.dart:706-718` `postSessionRedirect`
- **claim:** The `DestinationUnknown` no-evidence path leaves `_committedToGoHome == false`.
  The 30s CONTINUE CTA is wall-clock and fires regardless, and `_onContinueAnyway` navigated to
  `/home` **unconditionally** while skipping the `setOnboarded()` stamp (which is gated on
  `_committedToGoHome`). `_authRedirect` then reads the unstamped flag and bounces to bare
  `/onboarding` — **re-opening this batch's own misroute through the escape hatch.**
  It reopens it for precisely the cohort the diagnose names as worst-case: a returning user on a
  fresh reinstall (Hive genuinely empty, so local evidence correctly reports "none") whose read
  keeps failing for the full 30s. And the `completeOnboarding` guard cannot backstop it — that
  guard re-runs the **same** `user_profile` SELECT under the **same** broken token and is
  documented to **fail OPEN**, so a persistent instance of this exact failure defeats every layer
  in the batch and a real overwrite lands.
- **verification:** `grep -n "_committedToGoHome = true" lib/features/auth/screens/restoring/state.dart`
  — set on every branch except the `DestinationUnknown`-no-evidence fallthrough.
- **why the existing test missed it:** `local_onboarding_evidence_behavioral_test.dart`'s
  "DestinationUnknown branch never routes to onboarding" only source-greps the `case` **body**
  for a literal `context.go('/onboarding`. The route here is *indirect*
  (`_onContinueAnyway` → GoRouter → `_authRedirect`), so the test stayed green.
  **Third instance of guard-without-its-mirror in this batch** — the first two were caught by
  mutation testing, this one only by an independent reader.
- **fix applied:** `_onContinueAnyway` now re-resolves when `!_committedToGoHome`: local evidence
  first, then one live `resolveDestination`. `GoHome` → stamp + `/home`; `ResumeOnboarding` /
  `StartMissionBrief` → their correct destinations (unchanged for genuine new users); still
  `DestinationUnknown` → **stay put**, CTA left live so a tap retries. A wall-clock timer is not
  evidence that `/home` is safe.
- **tests:** two added in `local_onboarding_evidence_behavioral_test.dart` — the re-resolve must
  gate the navigation, and the still-unknown case must not navigate at all.
- **status:** fixed

## Finding 2 — P1 — raw internal sentinel rendered to the user — FIXED

- **file:line:** `onboarding_provider.dart` sets `error: 'already_onboarded'` →
  `plan_screen.dart:543` reads it → `plan_screen.dart:297` `_errorBanner` renders
  `Text(message)` **verbatim**.
- **claim:** a user tripping the new overwrite guard would see the literal token
  `already_onboarded` in a red banner. No mapping layer exists between the provider's `error`
  and the rendered text.
- **verification:** `grep -n "onboardingProvider).error" lib/features/onboarding/screens/plan_screen.dart`
  → 543; `grep -n "_errorBanner(" …` → 70 (render) / 297 (definition). Confirmed by reading both.
- **fix applied:** `plan_screen` intercepts the sentinel and routes home (or `/coach/induction`
  if not yet inducted) instead of showing a banner. This state isn't an error from the user's
  side — the account is already set up, so the correct response is to take them where they
  belong, not to show them a red box.
- **status:** fixed

## Finding 3 — P2 — stale SoT line-range citation — FIXED

- **file:line:** `docs/sot_registry.yaml`, `resolveDestination` writer entry, `line_range: 150-230`
- **claim:** the method spans 150-208; the range overran into `_selectProfileRow` and `_shortId`.
  The parity gate passed because it only checks the named method falls inside the range, not that
  the range is tight — so this class of drift can pass a green gate.
- **verification:** `grep -n "Future<PostSignInDestination> resolveDestination" lib/core/services/auth_session_bootstrapper.dart`
  → 150; matching close brace at 208.
- **fix applied:** corrected to `150-208`.
- **status:** fixed

## Lenses that returned clean

- **function_exception_swallow** — `git diff HEAD~1..HEAD | grep -n "functions.invoke("` → 0 matches.
  No Edge Function invocations added or touched, so the lens has no surface here.
- **secrets_in_tree** — `git diff HEAD~1..HEAD | grep -nE "sk-[A-Za-z0-9]|rzp_live_|AKIA[0-9A-Z]{16}|-----BEGIN"`
  → 0 matches across code, docs, diagnose-doc and plan-review record.
- **unawaited_no_error_sink** — `git diff HEAD~1..HEAD | grep -n "^\+.*unawaited("` → 17 additions,
  every one wrapping `ErrorTelemetry.recordNonFatal` or `ErrorTelemetry.logEvent`, the declared
  sinks. The `bg_heal_*` ones are a verbatim `part`-file relocation, confirmed byte-identical to
  the block deleted from `restoring_screen.dart` in the same commit.
- **blast_radius_mismatch** — `lib/features/auth/**` and `lib/features/onboarding/**` are
  registered `account` (`docs/blast_radius.yaml:188,197`), with `lib/**` defaulting to `account`
  (:270), covering the touched `lib/core/services/*`. Matches the record's declared tier.
- **writer_reader_drift** — the one new writer/reader pair (`requiredOnboardingProfileFields` vs
  the prior inline 9-field list) is a verbatim extraction; same 9 names moved, not retyped, and
  both the module doc and the registry entry cross-reference migration 112's server-side gate.
  Reviewer noted it did not re-verify migration 112's own column list against live schema — that
  predates this diff and is out of scope.

## Founder triage notes

All three accepted and fixed in-batch rather than logged. Finding 1 is the one that matters: it
is the same defect this batch exists to close, reachable by a second route, and the batch's own
backstop could not have caught it because that backstop fails open under identical conditions.

⚠ **`restoring_screen.dart` now sits at exactly 800/800 against Gate 43 — zero margin.** The next
change to that file trips the gate.

I attempted the structural remedy in this batch (move `_RestoringScreenState` into
`restoring/state.dart` as a part — the split the gate's own failure message prescribes) and
**reverted it**. It is not a small move: it broke 5 `line_range` citations in
`docs/sot_registry.yaml`, `check_reader_manifest_complete`, and
`restoring_screen_timeout_test.dart`, because a dozen registry entries and several source-grep
tests point at line numbers inside that file. Finishing it properly means re-anchoring all of
them — real work that deserves its own batch rather than being bolted onto a green bug-fix at the
end. Landing a half-migrated registry to save one refactor would trade a contained hygiene debt
for a live correctness risk.

So: the fixes are in and green at 800 lines; the split is the top follow-on and should be the
first thing done to this file. OI-88's *extraction* half did land here (`heal_after_restore.dart`
+ `animated_dots.dart`); the state-class split is what remains.
