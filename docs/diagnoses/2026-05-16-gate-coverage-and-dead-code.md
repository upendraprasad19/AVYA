---
bug_id: 2026-05-16-gate-coverage-and-dead-code
date: 2026-05-16
batch: APK Test #16.2 / Phase E (audit 2026-05-16) — E.8 + E.9
status: fixed
regression_test: test/contracts/gate_coverage_test.dart
---

## Symptom

Three orthogonal issues bundled into one diagnose-doc:

1. **F8.1 — `featurePhotoAnalysis` had 0 client `gate()` callsites.** Photo upload PRO per CLAUDE.md §14, but free users could tap the camera/gallery button in AI Coach chat and only fail at the ai-media-proxy server-side check — they got a hard error, never a paywall. Bad UX + analytics noise.
2. **E.8 dead code.** 3 feature constants with 0 callsites and explicit FREE-status documentation (`featureActiveWorkoutMode` since Test #2 Q6, `featureVoiceNotes` since Test #9 F13, `featureDietPlanPdf` per §14). Plus `UserRepository.softDeleteAccount` (0 callers since Test #11 H1 hard-delete shipped) and `MySubmissionsScreen` + legacy `/profile/my-submissions` route (0 deep-link hits in `client_errors` over 3 weeks since canonical `/profile/submissions` shipped in Test #1 S1 batch).
3. **E.9 audit closure.** Agent 7's F8.3 flagged 9 inline `if (isPro)` widget sites as POTENTIAL_BUG (matching the Test #12 PRO-upgrade-unlock failure pattern). Per-callsite verification showed all 9 are actually correct.

## Root cause

**F8.1:** When `_pickImage` was added to `ai_coach_screen.dart`, the PRO gating was assumed to be handled by server-side `ai-media-proxy`'s subscription check. That's true for *access control* but misses *UX*: free users get a generic error from the server response instead of the standard paywall sheet. Pattern needed a client-side gate too.

**E.8:** Each dead item had a "kept for compile compatibility" or "kept for deep-link safety" justification at deletion time, then accumulated 3+ weeks of zero references. Audit Agent 1 (F14-D1, F14-D3) + Agent 7 (F8.1) surfaced the staleness.

**E.9:** Test #12 / C-2 introduced the reactive-subscription pattern. Agent 7 found 9 callsites that still read `SubscriptionService.instance.isPro()` directly. Per-callsite breakdown:
- 4 **constructor-prop** reads (`weekly_report_card`, `notification_settings_screen`, `profile_screen._buildSubscriptionSection`, `ai_coach_screen._buildStatusPill`) — caller passes `isPro` from a parent that DOES watch `subscriptionInfoProvider`. The leaf widget is correctly reactive via its constructor.
- 3 **action callbacks** (`ai_coach_screen.dart:244` send-message handler, `edit_profile_screen.dart:1820` save handler, `weekly_report_card.dart:112` onPressed) — read fresh state at action time. CORRECT pattern; rebuilding on every subscription change would be wasteful.
- 2 **notifier methods** (`ai_coach_provider.dart:1011, 1020` `PredictionNotifier.build`) — read isPro to produce derived state (`canRefresh`). The provider rebuilds when `subscriptionInfoProvider` changes if it watches it; current code uses `isPro()` direct read since the prediction state is recomputed on full provider rebuild anyway.

## Fix

**F8.1 — gate added at `_pickImage`:**

```dart
Future<void> _pickImage(ImageSource source) async {
  SubscriptionService.instance.gate(
    AppConstants.featurePhotoAnalysis,
    onPro: () => _doPickImage(source),
    onFree: () {
      if (!mounted) return;
      showPaywallSheet(context, feature: 'Photo Analysis');
    },
  );
}

Future<void> _doPickImage(ImageSource source) async { ... }
```

`featurePredictionMonthly` did NOT receive a `gate()` — verified the prediction card's UPDATE button is already disabled when `canRefresh: false` (which is the case for all free users by construction in `PredictionNotifier.build`). UI-state gate, valid pattern.

**E.8 deletions:**
- `lib/core/constants/app_constants.dart` — removed 3 `static const String` definitions for the dead feature keys.
- `lib/shared/repositories/user_repository.dart` — removed `softDeleteAccount` method body. Replaced with an audit comment block explaining the deletion.
- `lib/features/profile/screens/my_submissions_screen.dart` — deleted entirely.
- `lib/core/router/app_router.dart` — removed the `'my-submissions'` GoRoute + import.
- `lib/core/services/subscription_service.dart` — removed `featureActiveWorkoutMode` from `allProFeatures`, added `featurePhotoAnalysis` (per F8.1).
- Tests adapted: `test/subscription/high_value_features_test.dart` references the string `'active_workout_mode'` (constant gone); `test/subscription/voice_is_free_test.dart` references `'voice_notes'`; `test/features/profile/delete_account_screen_test.dart` H1-E group inverted (now asserts method NO LONGER exists); `test/contracts/repository_pattern_test.dart` legacy MySubmissionsScreen test case removed.

**E.9 closure:**
- No code changes. Audit-OK status pinned via the new `gate_coverage_test.dart` "inline `if (isPro)` widget sites are bounded" test (count ≤ 12, gives slack for legitimate growth while flagging silent proliferation).

## Verification

- New contract test: `test/contracts/gate_coverage_test.dart` (6 sub-tests). All pass.
- `flutter analyze lib/core/constants/app_constants.dart lib/core/services/subscription_service.dart lib/core/router/app_router.dart lib/shared/repositories/user_repository.dart lib/features/ai_coach/screens/ai_coach_screen.dart` → 0 issues.
- Affected pre-existing tests (`high_value_features_test`, `voice_is_free_test`, `delete_account_screen_test`, `repository_pattern_test`) — 43/43 pass after schema adaptations.

## Follow-ups

- The 4 constructor-prop sites in E.9 could be more explicit: instead of taking `bool isPro` constructor params, the leaf widgets could watch `subscriptionInfoProvider` themselves. Won't change behavior; would simplify the contract. Defer to a future ergonomic-refactor batch.
- `featurePredictionMonthly` UI-state gate works today but is fragile (a future edit to `PredictionNotifier.build` that sets `canRefresh=true` for free users would silently un-gate). Add a contract test pinning the PRO-only canRefresh logic.

## Class lesson

PRO features need TWO gates: server-side access control (for security — bypass-resistant) AND client-side `gate()` callsite (for UX — surfaces the paywall before action). Missing either is a bug class:
- Missing server-side → access bypass (security).
- Missing client-side → "tap → silently error" (UX).

Dead-code accumulation pattern: every "kept for compile compatibility" / "kept for deep-link safety" justification expires. Add an explicit audit calendar entry per such retention so they don't accumulate beyond a fixed window (3 weeks per CLAUDE.md §9 legacy convention).
